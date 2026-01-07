use axum::{
    body::Body,
    extract::{Path, State},
    http::{StatusCode, header, HeaderMap},
    response::Response,
    routing::{get, post},
    Json, Router,
};
use axum::extract::Multipart;
use axum::extract::DefaultBodyLimit;
use bytes::Bytes;
use futures_util::TryStreamExt;
use serde::Serialize;
use sqlx::Row;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use tokio_util::io::ReaderStream;
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
    let mut filename: Option<String> = None;
    let mut mimetype: Option<String> = None;
    let mut chat_id: Option<i32> = None;

    // Stream file straight to disk to avoid buffering large ciphertext in RAM.
    let mut tmp_full_path: Option<String> = None;
    let mut rel_path: Option<String> = None;
    let mut written: i64 = 0;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| (StatusCode::BAD_REQUEST, format!("Ошибка чтения multipart: {}", e)))?
    {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "file" => {
                if tmp_full_path.is_some() {
                    continue;
                }

                if filename.is_none() {
                    filename = field.file_name().map(|s| s.to_string());
                }
                if mimetype.is_none() {
                    mimetype = field.content_type().map(|s| s.to_string());
                }

                fs::create_dir_all("uploads/media")
                    .await
                    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось создать директорию: {}", e)))?;

                let uuid = Uuid::new_v4().to_string();
                let rp = format!("media/{}_{}", user_id, uuid);
                let fp = format!("uploads/{}", &rp);
                rel_path = Some(rp);
                tmp_full_path = Some(fp.clone());

                let mut f = fs::File::create(&fp)
                    .await
                    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось создать файл: {}", e)))?;

                const MAX_BYTES: i64 = 50 * 1024 * 1024;

                let mut stream = field;
                while let Some(chunk) = stream
                    .chunk()
                    .await
                    .map_err(|e| (StatusCode::BAD_REQUEST, format!("Ошибка чтения файла: {}", e)))?
                {
                    if chunk.is_empty() {
                        continue;
                    }
                    written += chunk.len() as i64;
                    if written > MAX_BYTES {
                        let _ = fs::remove_file(&fp).await;
                        return Err((StatusCode::BAD_REQUEST, "Слишком большой файл".into()));
                    }
                    f.write_all(&chunk)
                        .await
                        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось записать файл: {}", e)))?;
                }

                f.sync_all()
                    .await
                    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось синхронизировать файл: {}", e)))?;
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
    if let Err((sc, msg)) = ensure_member(&state, chat_id, user_id).await {
        if let Some(fp) = tmp_full_path.as_ref() {
            let _ = fs::remove_file(fp).await;
        }
        return Err((sc, msg));
    }

    if tmp_full_path.is_none() || rel_path.is_none() || written <= 0 {
        if let Some(fp) = tmp_full_path.as_ref() {
            let _ = fs::remove_file(fp).await;
        }
        return Err((StatusCode::BAD_REQUEST, "file обязателен".into()));
    }

    let filename = filename.unwrap_or_else(|| "file".to_string());
    let mimetype = mimetype.unwrap_or_else(|| "application/octet-stream".to_string());

    let rel_path = rel_path.unwrap_or_else(|| "".to_string());

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
    .bind(written)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let file_id: i64 = row.try_get("id").unwrap_or_default();

    Ok(Json(UploadMediaResponse {
        file_id,
        filename,
        mimetype,
        size: written,
    }))
}

async fn download_media(
    State(state): State<AppState>,
    CurrentUser { id: user_id }: CurrentUser,
    headers: HeaderMap,
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

    let meta = fs::metadata(&full_path)
        .await
        .map_err(|_| (StatusCode::NOT_FOUND, "Файл не найден".into()))?;
    let size = meta.len();
    let mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let etag = format!("W/\"{}-{}\"", size, mtime);

    if let Some(if_none_match) = headers.get(header::IF_NONE_MATCH).and_then(|v| v.to_str().ok()) {
        if if_none_match.trim() == etag {
            return Ok(Response::builder()
                .status(StatusCode::NOT_MODIFIED)
                .header(header::ETAG, etag)
                .header(header::CACHE_CONTROL, "private, max-age=31536000")
                .body(Body::empty())
                .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка создания ответа: {}", e)))?);
        }
    }

    let file = fs::File::open(&full_path)
        .await
        .map_err(|_| (StatusCode::NOT_FOUND, "Файл не найден".into()))?;

    let stream = ReaderStream::new(file).map_ok(Bytes::from);

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, mimetype)
        .header(header::ETAG, etag)
        .header(header::CACHE_CONTROL, "private, max-age=31536000")
        .body(Body::from_stream(stream))
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка создания ответа: {}", e)))?)
}
