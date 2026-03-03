use axum::extract::DefaultBodyLimit;
use axum::extract::Multipart;
use axum::{
    Json, Router,
    body::{Body, Bytes as AxumBytes},
    extract::{Path, State},
    http::{HeaderMap, StatusCode, header},
    response::Response,
    routing::{get, post, put},
};
use bytes::Bytes;
use futures_util::TryStreamExt;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::{Arc, OnceLock};
use tokio::fs;
use tokio::io::AsyncWriteExt;
use tokio::sync::Mutex;
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

#[derive(Deserialize)]
struct InitChunkUploadRequest {
    chat_id: i32,
    filename: String,
    mimetype: String,
    total_size: i64,
    total_chunks: i32,
    chunk_size: i64,
}

#[derive(Serialize)]
struct InitChunkUploadResponse {
    upload_id: String,
    next_chunk_index: i32,
}

#[derive(Serialize)]
struct ChunkUploadStatusResponse {
    upload_id: String,
    next_chunk_index: i32,
    total_chunks: i32,
    received_size: i64,
    total_size: i64,
}

#[derive(Clone)]
struct ChunkUploadSession {
    upload_id: String,
    owner_id: i32,
    chat_id: i32,
    filename: String,
    mimetype: String,
    total_size: i64,
    total_chunks: i32,
    chunk_size: i64,
    next_chunk_index: i32,
    received_size: i64,
    rel_path: String,
    full_path: String,
}

static CHUNK_UPLOADS: OnceLock<dashmap::DashMap<String, Arc<Mutex<ChunkUploadSession>>>> =
    OnceLock::new();

fn uploads() -> &'static dashmap::DashMap<String, Arc<Mutex<ChunkUploadSession>>> {
    CHUNK_UPLOADS.get_or_init(dashmap::DashMap::new)
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/media", post(upload_media))
        .route("/media/:id", get(download_media))
        .route("/media/upload/init", post(init_chunked_upload))
        .route(
            "/media/upload/:upload_id/status",
            get(chunked_upload_status),
        )
        .route(
            "/media/upload/:upload_id/chunk/:chunk_index",
            put(upload_media_chunk),
        )
        .route(
            "/media/upload/:upload_id/finalize",
            post(finalize_chunked_upload),
        )
        .layer(DefaultBodyLimit::max(50 * 1024 * 1024))
}

async fn init_chunked_upload(
    State(state): State<AppState>,
    CurrentUser { id: user_id, .. }: CurrentUser,
    Json(body): Json<InitChunkUploadRequest>,
) -> Result<Json<InitChunkUploadResponse>, (StatusCode, String)> {
    if body.chat_id <= 0 {
        return Err((StatusCode::BAD_REQUEST, "chat_id обязателен".into()));
    }
    if body.total_size <= 0 || body.total_size > 500 * 1024 * 1024 {
        return Err((StatusCode::BAD_REQUEST, "Некорректный total_size".into()));
    }
    if body.total_chunks <= 0 || body.total_chunks > 100_000 {
        return Err((StatusCode::BAD_REQUEST, "Некорректный total_chunks".into()));
    }
    if body.chunk_size <= 0 || body.chunk_size > 10 * 1024 * 1024 {
        return Err((StatusCode::BAD_REQUEST, "Некорректный chunk_size".into()));
    }
    ensure_member(&state, body.chat_id, user_id).await?;

    fs::create_dir_all("uploads/media").await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Не удалось создать директорию: {}", e),
        )
    })?;

    let upload_id = Uuid::new_v4().to_string();
    let rel_path = format!("media/chunk_{}_{}", user_id, upload_id);
    let full_path = format!("uploads/{}", &rel_path);
    let _ = fs::File::create(&full_path).await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Не удалось создать файл upload: {}", e),
        )
    })?;

    let session = ChunkUploadSession {
        upload_id: upload_id.clone(),
        owner_id: user_id,
        chat_id: body.chat_id,
        filename: body.filename.trim().to_string(),
        mimetype: body.mimetype.trim().to_string(),
        total_size: body.total_size,
        total_chunks: body.total_chunks,
        chunk_size: body.chunk_size,
        next_chunk_index: 0,
        received_size: 0,
        rel_path,
        full_path,
    };
    uploads().insert(upload_id.clone(), Arc::new(Mutex::new(session)));

    Ok(Json(InitChunkUploadResponse {
        upload_id,
        next_chunk_index: 0,
    }))
}

async fn chunked_upload_status(
    CurrentUser { id: user_id, .. }: CurrentUser,
    Path(upload_id): Path<String>,
) -> Result<Json<ChunkUploadStatusResponse>, (StatusCode, String)> {
    let Some(entry) = uploads().get(&upload_id) else {
        return Err((StatusCode::NOT_FOUND, "Upload не найден".into()));
    };
    let arc = entry.value().clone();
    drop(entry);
    let session = arc.lock().await;
    if session.owner_id != user_id {
        return Err((StatusCode::FORBIDDEN, "Нет доступа".into()));
    }
    Ok(Json(ChunkUploadStatusResponse {
        upload_id: session.upload_id.clone(),
        next_chunk_index: session.next_chunk_index,
        total_chunks: session.total_chunks,
        received_size: session.received_size,
        total_size: session.total_size,
    }))
}

async fn upload_media_chunk(
    CurrentUser { id: user_id, .. }: CurrentUser,
    Path((upload_id, chunk_index)): Path<(String, i32)>,
    body: AxumBytes,
) -> Result<Json<ChunkUploadStatusResponse>, (StatusCode, String)> {
    let Some(entry) = uploads().get(&upload_id) else {
        return Err((StatusCode::NOT_FOUND, "Upload не найден".into()));
    };
    let arc = entry.value().clone();
    drop(entry);

    let mut session = arc.lock().await;
    if session.owner_id != user_id {
        return Err((StatusCode::FORBIDDEN, "Нет доступа".into()));
    }
    if chunk_index < 0 || chunk_index >= session.total_chunks {
        return Err((StatusCode::BAD_REQUEST, "Некорректный chunk_index".into()));
    }
    if chunk_index < session.next_chunk_index {
        return Ok(Json(ChunkUploadStatusResponse {
            upload_id: session.upload_id.clone(),
            next_chunk_index: session.next_chunk_index,
            total_chunks: session.total_chunks,
            received_size: session.received_size,
            total_size: session.total_size,
        }));
    }
    if chunk_index > session.next_chunk_index {
        return Err((
            StatusCode::CONFLICT,
            format!("Ожидается chunk {}", session.next_chunk_index),
        ));
    }

    let expected_plain_size = if chunk_index == session.total_chunks - 1 {
        session.total_size - (session.chunk_size * (session.total_chunks as i64 - 1))
    } else {
        session.chunk_size
    };
    let max_encrypted_chunk = expected_plain_size + 64;
    if body.len() as i64 > max_encrypted_chunk || body.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "Некорректный размер чанка".into()));
    }

    let mut f = fs::OpenOptions::new()
        .append(true)
        .open(&session.full_path)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Не удалось открыть upload файл: {}", e),
            )
        })?;
    f.write_all(&body).await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Не удалось записать чанк: {}", e),
        )
    })?;

    session.received_size += body.len() as i64;
    session.next_chunk_index += 1;

    Ok(Json(ChunkUploadStatusResponse {
        upload_id: session.upload_id.clone(),
        next_chunk_index: session.next_chunk_index,
        total_chunks: session.total_chunks,
        received_size: session.received_size,
        total_size: session.total_size,
    }))
}

async fn finalize_chunked_upload(
    State(state): State<AppState>,
    CurrentUser { id: user_id, .. }: CurrentUser,
    Path(upload_id): Path<String>,
) -> Result<Json<UploadMediaResponse>, (StatusCode, String)> {
    let Some(entry) = uploads().get(&upload_id) else {
        return Err((StatusCode::NOT_FOUND, "Upload не найден".into()));
    };
    let arc = entry.value().clone();
    drop(entry);
    let session = arc.lock().await.clone();
    if session.owner_id != user_id {
        return Err((StatusCode::FORBIDDEN, "Нет доступа".into()));
    }
    if session.next_chunk_index != session.total_chunks {
        return Err((StatusCode::BAD_REQUEST, "Upload не завершён".into()));
    }
    ensure_member(&state, session.chat_id, user_id).await?;

    let meta = fs::metadata(&session.full_path).await.map_err(|_| {
        (
            StatusCode::BAD_REQUEST,
            "Upload файл не найден для финализации".into(),
        )
    })?;
    let size = meta.len() as i64;
    if size <= 0 {
        return Err((StatusCode::BAD_REQUEST, "Пустой upload файл".into()));
    }

    let filename = if session.filename.trim().is_empty() {
        "file".to_string()
    } else {
        session.filename.clone()
    };
    let mimetype = if session.mimetype.trim().is_empty() {
        "application/octet-stream".to_string()
    } else {
        session.mimetype.clone()
    };

    let row = sqlx::query(
        r#"
        INSERT INTO media_files (owner_id, chat_id, path, filename, mimetype, size)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id::INT8 AS id
        "#,
    )
    .bind(user_id)
    .bind(session.chat_id)
    .bind(&session.rel_path)
    .bind(&filename)
    .bind(&mimetype)
    .bind(size)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let file_id: i64 = row.try_get("id").unwrap_or_default();
    uploads().remove(&upload_id);

    Ok(Json(UploadMediaResponse {
        file_id,
        filename,
        mimetype,
        size,
    }))
}

async fn upload_media(
    State(state): State<AppState>,
    CurrentUser { id: user_id, .. }: CurrentUser,
    mut multipart: Multipart,
) -> Result<Json<UploadMediaResponse>, (StatusCode, String)> {
    let mut filename: Option<String> = None;
    let mut mimetype: Option<String> = None;
    let mut chat_id: Option<i32> = None;

    // Stream file straight to disk to avoid buffering large ciphertext in RAM.
    let mut tmp_full_path: Option<String> = None;
    let mut rel_path: Option<String> = None;
    let mut written: i64 = 0;

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            format!("Ошибка чтения multipart: {}", e),
        )
    })? {
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

                fs::create_dir_all("uploads/media").await.map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        format!("Не удалось создать директорию: {}", e),
                    )
                })?;

                let uuid = Uuid::new_v4().to_string();
                let rp = format!("media/{}_{}", user_id, uuid);
                let fp = format!("uploads/{}", &rp);
                rel_path = Some(rp);
                tmp_full_path = Some(fp.clone());

                let mut f = fs::File::create(&fp).await.map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        format!("Не удалось создать файл: {}", e),
                    )
                })?;

                const MAX_BYTES: i64 = 50 * 1024 * 1024;

                let mut stream = field;
                while let Some(chunk) = stream.chunk().await.map_err(|e| {
                    (
                        StatusCode::BAD_REQUEST,
                        format!("Ошибка чтения файла: {}", e),
                    )
                })? {
                    if chunk.is_empty() {
                        continue;
                    }
                    written += chunk.len() as i64;
                    if written > MAX_BYTES {
                        let _ = fs::remove_file(&fp).await;
                        return Err((StatusCode::BAD_REQUEST, "Слишком большой файл".into()));
                    }
                    f.write_all(&chunk).await.map_err(|e| {
                        (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            format!("Не удалось записать файл: {}", e),
                        )
                    })?;
                }

                f.sync_all().await.map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        format!("Не удалось синхронизировать файл: {}", e),
                    )
                })?;
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
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

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
    CurrentUser { id: user_id, .. }: CurrentUser,
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
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let Some(row) = row else {
        return Err((StatusCode::NOT_FOUND, "Файл не найден".into()));
    };

    let owner_id: i64 = row.try_get("owner_id").unwrap_or_default();
    let chat_id: Option<i32> = row.try_get("chat_id").ok().flatten();
    let rel_path: String = row.try_get("path").unwrap_or_default();
    let mimetype: String = row
        .try_get("mimetype")
        .unwrap_or_else(|_| "application/octet-stream".to_string());

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

    if let Some(if_none_match) = headers
        .get(header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok())
    {
        if if_none_match.trim() == etag {
            return Ok(Response::builder()
                .status(StatusCode::NOT_MODIFIED)
                .header(header::ETAG, etag)
                .header(header::CACHE_CONTROL, "private, max-age=31536000")
                .body(Body::empty())
                .map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        format!("Ошибка создания ответа: {}", e),
                    )
                })?);
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
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка создания ответа: {}", e),
            )
        })?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::TryStreamExt;

    #[tokio::test]
    async fn reader_stream_keeps_binary_payload_unchanged() {
        let path = std::env::temp_dir().join(format!("ren_media_test_{}.bin", Uuid::new_v4()));
        let source = vec![0_u8, 1, 2, 3, 254, 255, 0, 200, 17, 99];
        fs::write(&path, &source).await.expect("write temp file");

        let file = fs::File::open(&path).await.expect("open temp file");
        let stream = ReaderStream::new(file).map_ok(Bytes::from);
        let chunks: Vec<Bytes> = stream.try_collect().await.expect("collect stream");
        let restored = chunks.into_iter().flatten().collect::<Vec<u8>>();

        assert_eq!(restored, source);
        let _ = fs::remove_file(&path).await;
    }
}
