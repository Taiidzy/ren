use axum::{
    body::Body,
    extract::{Path, State},
    http::{StatusCode, header},
    response::Response,
    routing::{get, post},
    Json, Router,
};
use axum::extract::Multipart;
use axum::extract::DefaultBodyLimit;
use serde::Serialize;
use sqlx::Row;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use crate::AppState;
use crate::middleware::{CurrentUser, ensure_member};

#[derive(Serialize)]
struct UploadMediaResponse {
    file_id: i64,
    filename: String,
    mimetype: String,
    size: i64,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/media", post(upload_media))
        .route("/media/:id", get(download_media))
        .layer(DefaultBodyLimit::max(50 * 1024 * 1024))
}

async fn upload_media(
    State(state): State<AppState>,
    CurrentUser { id: user_id }: CurrentUser,
    mut multipart: Multipart,
) -> Result<Json<UploadMediaResponse>, (StatusCode, String)> {
    let mut data: Option<Vec<u8>> = None;
    let mut filename: Option<String> = None;
    let mut mimetype: Option<String> = None;
    let mut chat_id: Option<i32> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| (StatusCode::BAD_REQUEST, format!("Ошибка чтения multipart: {}", e)))?
    {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "file" => {
                filename = field.file_name().map(|s| s.to_string());
                mimetype = field.content_type().map(|s| s.to_string());
                let bytes = field
                    .bytes()
                    .await
                    .map_err(|e| (StatusCode::BAD_REQUEST, format!("Ошибка чтения файла: {}", e)))?;
                if !bytes.is_empty() {
                    data = Some(bytes.to_vec());
                }
            }
            "filename" => {
                let v = field.text().await.unwrap_or_default();
                if !v.trim().is_empty() {
                    filename = Some(v);
                }
            }
            "mimetype" => {
                let v = field.text().await.unwrap_or_default();
                if !v.trim().is_empty() {
                    mimetype = Some(v);
                }
            }
            "chat_id" => {
                let v = field.text().await.unwrap_or_default();
                chat_id = v.trim().parse::<i32>().ok();
            }
            _ => {}
        }
    }

    let chat_id = chat_id.ok_or((StatusCode::BAD_REQUEST, "chat_id обязателен".into()))?;
    ensure_member(&state, chat_id, user_id).await?;

    let bytes = data.ok_or((StatusCode::BAD_REQUEST, "file обязателен".into()))?;

    // Limit: 50MB ciphertext
    const MAX_BYTES: usize = 50 * 1024 * 1024;
    if bytes.len() > MAX_BYTES {
        return Err((StatusCode::BAD_REQUEST, "Слишком большой файл".into()));
    }

    let filename = filename.unwrap_or_else(|| "file".to_string());
    let mimetype = mimetype.unwrap_or_else(|| "application/octet-stream".to_string());

    fs::create_dir_all("uploads/media")
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось создать директорию: {}", e)))?;

    let uuid = Uuid::new_v4().to_string();
    let rel_path = format!("media/{}_{}", user_id, uuid);
    let full_path = format!("uploads/{}", rel_path);

    let mut f = fs::File::create(&full_path)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось создать файл: {}", e)))?;
    f.write_all(&bytes)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось записать файл: {}", e)))?;
    f.sync_all()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось синхронизировать файл: {}", e)))?;

    let row = sqlx::query(
        r#"
        INSERT INTO media_files (owner_id, chat_id, path, filename, mimetype, size)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id::INT8 AS id
        "#,
    )
    .bind(user_id)
    .bind(chat_id)
    .bind(&rel_path)
    .bind(&filename)
    .bind(&mimetype)
    .bind(bytes.len() as i64)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let file_id: i64 = row.try_get("id").unwrap_or_default();

    Ok(Json(UploadMediaResponse {
        file_id,
        filename,
        mimetype,
        size: bytes.len() as i64,
    }))
}

async fn download_media(
    State(state): State<AppState>,
    CurrentUser { id: user_id }: CurrentUser,
    Path(id): Path<i64>,
) -> Result<Response, (StatusCode, String)> {
    let row = sqlx::query(
        r#"
        SELECT id::INT8 AS id, owner_id::INT8 AS owner_id, chat_id, path, mimetype
        FROM media_files
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(row) = row else {
        return Err((StatusCode::NOT_FOUND, "Файл не найден".into()));
    };

    let owner_id: i64 = row.try_get("owner_id").unwrap_or_default();
    let chat_id: Option<i32> = row.try_get("chat_id").ok().flatten();
    let rel_path: String = row.try_get("path").unwrap_or_default();
    let mimetype: String = row.try_get("mimetype").unwrap_or_else(|_| "application/octet-stream".to_string());

    // Access policy: owner OR chat member
    if owner_id != user_id as i64 {
        let chat_id = chat_id.ok_or((StatusCode::FORBIDDEN, "Нет доступа".into()))?;
        ensure_member(&state, chat_id, user_id).await?;
    }

    let full_path = format!("uploads/{}", rel_path);
    let content = fs::read(&full_path)
        .await
        .map_err(|_| (StatusCode::NOT_FOUND, "Файл не найден".into()))?;

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, mimetype)
        .body(Body::from(content))
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка создания ответа: {}", e)))?)
}
