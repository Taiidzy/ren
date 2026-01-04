use axum::{
    body::Body,
    extract::{State, Path as PathExtractor},
    http::{StatusCode, header, HeaderMap},
    response::Response,
    routing::{get, patch},
    Json, Router,
};
use futures_util::StreamExt;
use multer::Multipart;
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::{AppState};
use crate::models::auth::UserResponse; // используем общую модель пользователя
use crate::middleware::CurrentUser; // экстрактор текущего пользователя
use std::path::Path;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use std::path::Component;
use axum::extract::Multipart as MultipartExtractor;

// Конструктор роутера для users: подключаем маршруты профиля
// - GET /users/me       — вернуть текущего пользователя
// - PATCH /users/username — сменить имя пользователя
// - PATCH /users/avatar   — обновить аватар (можно null)
// - DELETE /users/me      — удалить аккаунт
// - GET /users/{id}/public-key — получить публичный ключ пользователя (для E2EE)
// - GET /avatars/{path}  — получить файл аватара
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/users/me", get(me).delete(delete_me))
        .route("/users/username", patch(update_username))
        .route("/users/avatar", patch(update_avatar).post(update_avatar))
        .route("/users/:id/public-key", get(get_public_key))
        .route("/avatars/*path", get(get_avatar))
}

// Хендлер GET /me
// 1) Достаём заголовок Authorization: Bearer <JWT>
// 2) Валидируем токен (подпись и срок годности)
// 3) По id из токена читаем пользователя из БД и возвращаем его данные
async fn me(
    State(state): State<AppState>,
    CurrentUser { id }: CurrentUser,
) -> Result<Json<UserResponse>, (StatusCode, String)> {
    // Загружаем пользователя из БД по id (берём из JWT через CurrentUser)
    let row = sqlx::query(
        r#"
        SELECT id, login, username, avatar
        FROM users
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(row) = row else {
        // Пользователь мог быть удалён — токен валиден, но пользователя в БД нет
        return Err((StatusCode::NOT_FOUND, "Пользователь не найден".into()));
    };

    let user = UserResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        avatar: row.try_get("avatar").ok(),
    };

    Ok(Json(user))
}

// Тело запроса для смены имени пользователя
#[derive(Deserialize)]
struct UpdateUsernameRequest {
    username: String,
}

async fn update_username(
    State(state): State<AppState>,
    CurrentUser { id }: CurrentUser,
    Json(payload): Json<UpdateUsernameRequest>,
) -> Result<Json<UserResponse>, (StatusCode, String)> {
    // Простая валидация
    if payload.username.trim().is_empty() {
        return Err((StatusCode::BAD_REQUEST, "Имя пользователя не может быть пустым".into()));
    }

    // Обновляем username; ловим конфликт уникальности (PG 23505)
    let row = sqlx::query(
        r#"
        UPDATE users
        SET username = $1
        WHERE id = $2
        RETURNING id, login, username, avatar
        "#,
    )
    .bind(&payload.username)
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| match e {
        sqlx::Error::Database(db_err) => {
            if db_err.code().as_deref() == Some("23505") {
                (StatusCode::CONFLICT, "Имя пользователя уже занято".into())
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", db_err))
            }
        }
        other => (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка: {}", other)),
    })?;

    let user = UserResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        avatar: row.try_get("avatar").ok(),
    };

    Ok(Json(user))
}

async fn update_avatar(
    State(state): State<AppState>,
    CurrentUser { id }: CurrentUser,
    mut multipart: MultipartExtractor,
) -> Result<Json<UserResponse>, (StatusCode, String)> {
    // Получаем текущий путь к аватару для возможного удаления
    let current_avatar_row = sqlx::query("SELECT avatar FROM users WHERE id = $1")
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;
    
    let current_avatar_path = current_avatar_row
        .and_then(|row| row.try_get::<Option<String>, _>("avatar").ok())
        .flatten();

    // Извлекаем boundary из Content-Type.
    // Важно: Dio на iOS может присылать boundary с ведущими "--" (например "--dio-boundary-...").
    // Тело multipart в таком случае использует разделители вида "----dio-boundary-...".
    // Поэтому boundary НЕЛЬЗЯ триммить — иначе multer не найдёт финальный разделитель и вернёт
    // "incomplete multipart stream".


    // Извлекаем файл из multipart
    let mut avatar_data: Option<Vec<u8>> = None;
    let mut avatar_filename: Option<String> = None;
    let mut remove_avatar = false;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| (StatusCode::BAD_REQUEST, format!("Ошибка чтения multipart: {}", e)))?
    {
        let name = field.name().unwrap_or("").to_string();

        match name.as_str() {
            "avatar" => {
                avatar_filename = field.file_name().map(|s| s.to_string());
                let data = field.bytes().await
                    .map_err(|e| (StatusCode::BAD_REQUEST, format!("Ошибка чтения файла avatar: {}", e)))?;
                if !data.is_empty() {
                    avatar_data = Some(data.to_vec());
                }
            }
            "remove" => {
                let text = field.text().await.unwrap_or_default();
                remove_avatar = text == "true" || text == "1";
            }
            _ => {}
        }
    }


    // Сохраняем копию текущего пути для последующего удаления
    let old_avatar_path = current_avatar_path.clone();

    let new_avatar_path = if remove_avatar {
        // Удаляем аватар (устанавливаем в NULL)
        None
    } else if let Some(data) = avatar_data {
        // Лимит на размер аватара (защита от загрузки огромных файлов в память)
        // 5MB должно быть достаточно для большинства аватаров.
        const MAX_AVATAR_BYTES: usize = 5 * 1024 * 1024;
        if data.len() > MAX_AVATAR_BYTES {
            return Err((StatusCode::BAD_REQUEST, "Слишком большой файл аватара".into()));
        }

        // Создаем директорию для аватаров, если её нет
        let avatars_dir = Path::new("uploads/avatars");
        fs::create_dir_all(avatars_dir).await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось создать директорию для аватаров: {}", e)))?;

        // Определяем расширение файла
        let extension_raw = avatar_filename
            .as_ref()
            .and_then(|f| Path::new(f).extension())
            .and_then(|ext| ext.to_str())
            .unwrap_or("jpg");

        let extension = extension_raw.to_ascii_lowercase();
        let extension = match extension.as_str() {
            "jpg" | "jpeg" | "png" | "gif" | "webp" => extension,
            _ => "jpg".to_string(),
        };

        // Генерируем путь с использованием id пользователя
        let new_path = format!("uploads/avatars/user_{}.{}", id, extension);
        
        // Сохраняем файл
        let mut file = fs::File::create(&new_path).await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось создать файл аватара: {}", e)))?;
        file.write_all(&data).await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось записать файл аватара: {}", e)))?;
        file.sync_all().await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось синхронизировать файл аватара: {}", e)))?;

        Some(format!("avatars/user_{}.{}", id, extension))
    } else {
        // Если файл не передан и не запрошено удаление, оставляем текущий
        old_avatar_path.clone()
    };

    // Удаляем старый файл, если он был и мы его меняем
    if let Some(ref old_path) = old_avatar_path {
        if new_avatar_path.as_ref() != Some(old_path) {
            let full_old_path = Path::new("uploads").join(old_path);
            if full_old_path.exists() {
                let _ = fs::remove_file(&full_old_path).await; // Игнорируем ошибки удаления
            }
        }
    }

    // Обновляем путь в БД
    let row = sqlx::query(
        r#"
        UPDATE users
        SET avatar = $1
        WHERE id = $2
        RETURNING id, login, username, avatar
        "#,
    )
    .bind(&new_avatar_path)
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let user = UserResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        avatar: row.try_get("avatar").ok(),
    };

    Ok(Json(user))
}

async fn delete_me(
    State(state): State<AppState>,
    CurrentUser { id }: CurrentUser,
) -> Result<StatusCode, (StatusCode, String)> {
    // Получаем путь к аватару перед удалением пользователя
    let avatar_row = sqlx::query("SELECT avatar FROM users WHERE id = $1")
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;
    
    // Удаляем текущего пользователя
    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    // Удаляем файл аватара, если он был
    if let Some(row) = avatar_row {
        if let Ok(avatar_path) = row.try_get::<Option<String>, _>("avatar") {
            if let Some(path) = avatar_path {
                let full_path = Path::new("uploads").join(&path);
                if full_path.exists() {
                    let _ = fs::remove_file(&full_path).await; // Игнорируем ошибки
                }
            }
        }
    }

    Ok(StatusCode::NO_CONTENT)
}

// Модель для ответа с публичным ключом
#[derive(Serialize)]
struct PublicKeyResponse {
    user_id: i32,
    public_key: String,
}

// Хендлер для получения публичного ключа пользователя (для E2EE)
async fn get_public_key(
    State(state): State<AppState>,
    PathExtractor(user_id_str): PathExtractor<String>,
) -> Result<Json<PublicKeyResponse>, (StatusCode, String)> {
    let user_id: i32 = user_id_str.parse()
        .map_err(|_| (StatusCode::BAD_REQUEST, "Некорректный ID пользователя".into()))?;

    let row = sqlx::query(
        r#"
        SELECT id, pubk
        FROM users
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(row) = row else {
        return Err((StatusCode::NOT_FOUND, "Пользователь не найден".into()));
    };

    let pubk: Option<String> = row.try_get("pubk").ok().flatten();
    let pubk = pubk.ok_or((StatusCode::NOT_FOUND, "Публичный ключ не найден".into()))?;

    Ok(Json(PublicKeyResponse {
        user_id,
        public_key: pubk,
    }))
}

// Хендлер для получения файла аватара
async fn get_avatar(
    PathExtractor(path): PathExtractor<String>,
) -> Result<Response, (StatusCode, String)> {
    // Защита от path traversal: разрешаем только "нормальные" компоненты пути.
    // Запрещаем абсолютные пути, '..', '.' и префиксы диска.
    let rel = Path::new(&path);
    let mut has_component = false;
    for c in rel.components() {
        match c {
            Component::Normal(_) => {
                has_component = true;
            }
            _ => {
                return Err((StatusCode::BAD_REQUEST, "Некорректный путь".into()));
            }
        }
    }
    if !has_component {
        return Err((StatusCode::BAD_REQUEST, "Некорректный путь".into()));
    }

    let file_path = Path::new("uploads").join(rel);

    let content = fs::read(&file_path).await
        .map_err(|_| (StatusCode::NOT_FOUND, "Файл не найден".into()))?;

    // Определяем Content-Type по расширению
    let content_type = match file_path.extension().and_then(|ext| ext.to_str()) {
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("png") => "image/png",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        _ => "application/octet-stream",
    };

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .body(axum::body::Body::from(content))
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка создания ответа: {}", e)))?)
}
