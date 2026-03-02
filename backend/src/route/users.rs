use axum::{
    Json, Router,
    extract::{Path as PathExtractor, Query, State},
    http::{StatusCode, header},
    response::Response,
    routing::{get, patch},
};
use base64::Engine;
use ring::signature::{ED25519, UnparsedPublicKey};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::Row;

use crate::AppState;
use crate::middleware::CurrentUser; // экстрактор текущего пользователя
use crate::models::auth::UserResponse; // используем общую модель пользователя
use crate::route::ws::publish_profile_updated_for_user;
use axum::extract::Multipart as MultipartExtractor;
use std::path::Component;
use std::path::Path;
use tokio::fs;
use tokio::io::AsyncWriteExt;

// Конструктор роутера для users: подключаем маршруты профиля
// - GET /users/me       — вернуть текущего пользователя
// - PATCH /users/username — сменить имя пользователя
// - PATCH /users/nickname — сменить отображаемое имя (nickname)
// - PATCH /users/avatar   — обновить аватар (можно null)
// - DELETE /users/me      — удалить аккаунт
// - GET /users/{id}/public-key — получить публичный ключ пользователя (для E2EE)
// - GET /avatars/{path}  — получить файл аватара
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/users/me", get(me).delete(delete_me))
        .route("/users/username", patch(update_username))
        .route("/users/nickname", patch(update_nickname))
        .route("/users/avatar", patch(update_avatar).post(update_avatar))
        .route("/users/search", get(search_users))
        .route("/users/signal-bundle", patch(update_signal_bundle))
        .route("/users/:id/public-key", get(get_public_key))
        .route("/avatars/*path", get(get_avatar))
}

#[derive(Deserialize)]
struct SearchUsersQuery {
    q: String,
    limit: Option<i64>,
}

async fn search_users(
    State(state): State<AppState>,
    CurrentUser { id: my_id, .. }: CurrentUser,
    Query(params): Query<SearchUsersQuery>,
) -> Result<Json<Vec<UserResponse>>, (StatusCode, String)> {
    let q = params.q.trim();
    if q.is_empty() {
        return Ok(Json(vec![]));
    }

    let limit = params.limit.unwrap_or(15).clamp(1, 50);

    let id_q: Option<i32> = q.parse::<i32>().ok();
    let like = format!("%{}%", q);

    let rows = sqlx::query(
        r#"
        SELECT id, login, username, nickname, avatar
        FROM users
        WHERE id <> $3
          AND (
            ($1::int IS NOT NULL AND id = $1::int)
            OR username ILIKE $2
          )
        ORDER BY
          CASE WHEN ($1::int IS NOT NULL AND id = $1::int) THEN 0 ELSE 1 END,
          username ASC
        LIMIT $4
        "#,
    )
    .bind(id_q)
    .bind(like)
    .bind(my_id)
    .bind(limit)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        out.push(UserResponse {
            id: row.try_get("id").unwrap_or_default(),
            login: row.try_get("login").unwrap_or_default(),
            username: row.try_get("username").unwrap_or_default(),
            nickname: row.try_get("nickname").ok(),
            avatar: row.try_get("avatar").ok(),
        });
    }

    Ok(Json(out))
}

// Хендлер GET /me
// 1) Достаём заголовок Authorization: Bearer <JWT>
// 2) Валидируем токен (подпись и срок годности)
// 3) По id из токена читаем пользователя из БД и возвращаем его данные
async fn me(
    State(state): State<AppState>,
    CurrentUser { id, .. }: CurrentUser,
) -> Result<Json<UserResponse>, (StatusCode, String)> {
    // Загружаем пользователя из БД по id (берём из JWT через CurrentUser)
    let row = sqlx::query(
        r#"
        SELECT id, login, username, nickname, avatar
        FROM users
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
        // Пользователь мог быть удалён — токен валиден, но пользователя в БД нет
        return Err((StatusCode::NOT_FOUND, "Пользователь не найден".into()));
    };

    let user = UserResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        nickname: row.try_get("nickname").ok(),
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
    CurrentUser { id, .. }: CurrentUser,
    Json(payload): Json<UpdateUsernameRequest>,
) -> Result<Json<UserResponse>, (StatusCode, String)> {
    // Простая валидация
    if payload.username.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Имя пользователя не может быть пустым".into(),
        ));
    }

    // Обновляем username; ловим конфликт уникальности (PG 23505)
    let row = sqlx::query(
        r#"
        UPDATE users
        SET username = $1
        WHERE id = $2
        RETURNING id, login, username, nickname, avatar
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
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка БД: {}", db_err),
                )
            }
        }
        other => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка: {}", other),
        ),
    })?;

    let user = UserResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        nickname: row.try_get("nickname").ok(),
        avatar: row.try_get("avatar").ok(),
    };

    let _ = publish_profile_updated_for_user(&state, id).await;

    Ok(Json(user))
}

// Тело запроса для смены nickname
#[derive(Deserialize)]
struct UpdateNicknameRequest {
    nickname: String,
}

async fn update_nickname(
    State(state): State<AppState>,
    CurrentUser { id, .. }: CurrentUser,
    Json(payload): Json<UpdateNicknameRequest>,
) -> Result<Json<UserResponse>, (StatusCode, String)> {
    // Валидация: nickname не должен быть длиннее 32 символов
    if payload.nickname.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Nickname не может быть пустым".into(),
        ));
    }

    if payload.nickname.len() > 32 {
        return Err((
            StatusCode::BAD_REQUEST,
            "Nickname не может быть длиннее 32 символов".into(),
        ));
    }

    // Обновляем nickname; nickname не уникален, поэтому конфликтов не будет
    let row = sqlx::query(
        r#"
        UPDATE users
        SET nickname = $1
        WHERE id = $2
        RETURNING id, login, username, nickname, avatar
        "#,
    )
    .bind(&payload.nickname)
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let user = UserResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        nickname: row.try_get("nickname").ok(),
        avatar: row.try_get("avatar").ok(),
    };

    let _ = publish_profile_updated_for_user(&state, id).await;

    Ok(Json(user))
}

async fn update_avatar(
    State(state): State<AppState>,
    CurrentUser { id, .. }: CurrentUser,
    mut multipart: MultipartExtractor,
) -> Result<Json<UserResponse>, (StatusCode, String)> {
    // Получаем текущий путь к аватару для возможного удаления
    let current_avatar_row = sqlx::query("SELECT avatar FROM users WHERE id = $1")
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;

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

    while let Some(field) = multipart.next_field().await.map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            format!("Ошибка чтения multipart: {}", e),
        )
    })? {
        let name = field.name().unwrap_or("").to_string();

        match name.as_str() {
            "avatar" => {
                avatar_filename = field.file_name().map(|s| s.to_string());
                let data = field.bytes().await.map_err(|e| {
                    (
                        StatusCode::BAD_REQUEST,
                        format!("Ошибка чтения файла avatar: {}", e),
                    )
                })?;
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
            return Err((
                StatusCode::BAD_REQUEST,
                "Слишком большой файл аватара".into(),
            ));
        }

        // Создаем директорию для аватаров, если её нет
        let avatars_dir = Path::new("uploads/avatars");
        fs::create_dir_all(avatars_dir).await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Не удалось создать директорию для аватаров: {}", e),
            )
        })?;

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
        let mut file = fs::File::create(&new_path).await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Не удалось создать файл аватара: {}", e),
            )
        })?;
        file.write_all(&data).await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Не удалось записать файл аватара: {}", e),
            )
        })?;
        file.sync_all().await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Не удалось синхронизировать файл аватара: {}", e),
            )
        })?;

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
        RETURNING id, login, username, nickname, avatar
        "#,
    )
    .bind(&new_avatar_path)
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let user = UserResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        nickname: row.try_get("nickname").ok(),
        avatar: row.try_get("avatar").ok(),
    };

    let _ = publish_profile_updated_for_user(&state, id).await;

    Ok(Json(user))
}

async fn delete_me(
    State(state): State<AppState>,
    CurrentUser { id, .. }: CurrentUser,
) -> Result<StatusCode, (StatusCode, String)> {
    // Получаем путь к аватару перед удалением пользователя
    let avatar_row = sqlx::query("SELECT avatar FROM users WHERE id = $1")
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;

    // Удаляем текущего пользователя
    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;

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
    signature: String,
    key_version: u32,
    signed_at: String,
    identity_key: String,
    signed_pre_key_id: Option<i32>,
    signed_pre_key: Option<String>,
    signed_pre_key_signature: Option<String>,
    kyber_pre_key_id: Option<i32>,
    kyber_pre_key: Option<String>,
    kyber_pre_key_signature: Option<String>,
    one_time_pre_keys: Option<Value>,
}

#[derive(Deserialize)]
struct UpdateSignalBundleRequest {
    public_key: String,
    identity_key: Option<String>,
    signature: Option<String>,
    key_version: Option<i32>,
    signed_at: Option<String>,
    signed_pre_key_id: Option<i32>,
    signed_pre_key: Option<String>,
    signed_pre_key_signature: Option<String>,
    kyber_pre_key_id: Option<i32>,
    kyber_pre_key: Option<String>,
    kyber_pre_key_signature: Option<String>,
    one_time_pre_keys: Option<Value>,
}

fn normalize_identity_pubkey(identity_bytes: &[u8]) -> Result<[u8; 32], (StatusCode, String)> {
    if identity_bytes.len() == 32 {
        let mut out = [0u8; 32];
        out.copy_from_slice(identity_bytes);
        return Ok(out);
    }
    if identity_bytes.len() == 33 && identity_bytes[0] == 0x05 {
        let mut out = [0u8; 32];
        out.copy_from_slice(&identity_bytes[1..]);
        return Ok(out);
    }
    Err((
        StatusCode::BAD_REQUEST,
        "identity_key must be Ed25519 (32 bytes or 33 bytes with 0x05 prefix)".into(),
    ))
}

fn verify_key_signature(
    identity_key_b64: &str,
    public_key_b64: &str,
    signature_b64: &str,
    key_version: i32,
) -> Result<(), (StatusCode, String)> {
    if key_version <= 0 {
        return Err((StatusCode::BAD_REQUEST, "key_version must be > 0".into()));
    }

    let identity_raw = base64::engine::general_purpose::STANDARD
        .decode(identity_key_b64)
        .map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                "identity_key must be valid base64".into(),
            )
        })?;
    let verify_key_bytes = normalize_identity_pubkey(&identity_raw)?;

    let public_key_raw = base64::engine::general_purpose::STANDARD
        .decode(public_key_b64)
        .map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                "public_key must be valid base64".into(),
            )
        })?;

    let signature_raw = base64::engine::general_purpose::STANDARD
        .decode(signature_b64)
        .map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                "signature must be valid base64".into(),
            )
        })?;
    if signature_raw.len() != 64 {
        return Err((StatusCode::BAD_REQUEST, "signature must be 64 bytes".into()));
    }

    let mut payload = Vec::with_capacity(public_key_raw.len() + 4);
    payload.extend_from_slice(&public_key_raw);
    payload.extend_from_slice(&key_version.to_le_bytes());

    UnparsedPublicKey::new(&ED25519, verify_key_bytes)
        .verify(&payload, &signature_raw)
        .map_err(|_| (StatusCode::UNAUTHORIZED, "invalid signature".into()))
}

async fn update_signal_bundle(
    State(state): State<AppState>,
    CurrentUser { id, .. }: CurrentUser,
    Json(payload): Json<UpdateSignalBundleRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    let public_key = payload.public_key.trim();
    if public_key.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "public_key is required".into()));
    }
    let signature = payload
        .signature
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .ok_or((StatusCode::BAD_REQUEST, "signature is required".into()))?;

    let identity_key = payload
        .identity_key
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .unwrap_or(public_key);
    let key_version = payload.key_version.unwrap_or(1).max(1);
    verify_key_signature(identity_key, public_key, signature, key_version)?;

    let signed_at = payload
        .signed_at
        .unwrap_or_else(|| chrono::Utc::now().to_rfc3339());
    let signed_at_dt = chrono::DateTime::parse_from_rfc3339(&signed_at)
        .map(|d| d.with_timezone(&chrono::Utc))
        .unwrap_or_else(|_| chrono::Utc::now());

    sqlx::query(
        r#"
        UPDATE users
        SET
            pubk = $1,
            identity_pubk = $2,
            key_version = $3,
            key_signed_at = $4,
            key_signature = $5,
            signed_pre_key_id = $6,
            signed_pre_key = $7,
            signed_pre_key_signature = $8,
            kyber_pre_key_id = $9,
            kyber_pre_key = $10,
            kyber_pre_key_signature = $11,
            one_time_pre_keys = $12,
            one_time_pre_keys_updated_at = CASE WHEN $12::jsonb IS NULL THEN one_time_pre_keys_updated_at ELSE now() END
        WHERE id = $13
        "#,
    )
    .bind(public_key)
    .bind(identity_key)
    .bind(key_version)
    .bind(signed_at_dt)
    .bind(signature)
    .bind(payload.signed_pre_key_id)
    .bind(payload.signed_pre_key)
    .bind(payload.signed_pre_key_signature)
    .bind(payload.kyber_pre_key_id)
    .bind(payload.kyber_pre_key)
    .bind(payload.kyber_pre_key_signature)
    .bind(payload.one_time_pre_keys)
    .bind(id)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    Ok(StatusCode::NO_CONTENT)
}

// Хендлер для получения публичного ключа пользователя (для E2EE)
// P0-2: Возвращает подписанный публичный ключ с Ed25519 подписью
async fn get_public_key(
    State(state): State<AppState>,
    PathExtractor(user_id_str): PathExtractor<String>,
) -> Result<Json<PublicKeyResponse>, (StatusCode, String)> {
    let user_id: i32 = user_id_str.parse().map_err(|_| {
        (
            StatusCode::BAD_REQUEST,
            "Некорректный ID пользователя".into(),
        )
    })?;

    let mut tx = state.pool.begin().await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let row = sqlx::query(
        r#"
        SELECT
            id,
            pubk,
            identity_pubk,
            key_version,
            key_signed_at,
            key_signature,
            signed_pre_key_id,
            signed_pre_key,
            signed_pre_key_signature,
            kyber_pre_key_id,
            kyber_pre_key,
            kyber_pre_key_signature,
            one_time_pre_keys
        FROM users
        WHERE id = $1
        FOR UPDATE
        "#,
    )
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let Some(row) = row else {
        return Err((StatusCode::NOT_FOUND, "Пользователь не найден".into()));
    };

    let pubk: Option<String> = row.try_get("pubk").ok().flatten();
    let pubk = pubk.ok_or((StatusCode::NOT_FOUND, "Публичный ключ не найден".into()))?;

    let identity_pubk: Option<String> = row.try_get("identity_pubk").ok().flatten();
    let identity_pubk =
        identity_pubk.ok_or((StatusCode::NOT_FOUND, "Identity ключ не найден".into()))?;

    let key_version: i32 = row.try_get("key_version").unwrap_or(1);
    let key_signed_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("key_signed_at").ok().flatten();
    let key_signature: Option<String> = row.try_get("key_signature").ok().flatten();
    let signed_pre_key_id: Option<i32> = row.try_get("signed_pre_key_id").ok().flatten();
    let signed_pre_key: Option<String> = row.try_get("signed_pre_key").ok().flatten();
    let signed_pre_key_signature: Option<String> =
        row.try_get("signed_pre_key_signature").ok().flatten();
    let kyber_pre_key_id: Option<i32> = row.try_get("kyber_pre_key_id").ok().flatten();
    let kyber_pre_key: Option<String> = row.try_get("kyber_pre_key").ok().flatten();
    let kyber_pre_key_signature: Option<String> =
        row.try_get("kyber_pre_key_signature").ok().flatten();
    let one_time_pre_keys_raw: Option<Value> = row.try_get("one_time_pre_keys").ok().flatten();
    let mut served_one_time_pre_key: Option<Value> = None;
    if let Some(Value::Array(items)) = one_time_pre_keys_raw.clone() {
        let mut remaining = Vec::with_capacity(items.len().saturating_sub(1));
        for item in items {
            let is_valid = item
                .get("id")
                .and_then(|v| v.as_i64())
                .map(|id| id > 0)
                .unwrap_or(false)
                && item
                    .get("key")
                    .and_then(|v| v.as_str())
                    .map(|s| !s.trim().is_empty())
                    .unwrap_or(false);
            if served_one_time_pre_key.is_none() && is_valid {
                served_one_time_pre_key = Some(item);
                continue;
            }
            remaining.push(item);
        }
        if served_one_time_pre_key.is_some() {
            let remaining_value = Value::Array(remaining);
            sqlx::query(
                r#"
                UPDATE users
                SET one_time_pre_keys = $1, one_time_pre_keys_updated_at = now()
                WHERE id = $2
                "#,
            )
            .bind(remaining_value)
            .bind(user_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка БД: {}", e),
                )
            })?;
        }
    }
    tx.commit().await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;
    let one_time_pre_keys = served_one_time_pre_key.map(|item| json!([item]));
    let signed_at = key_signed_at
        .map(|t| t.to_rfc3339())
        .unwrap_or_else(|| "unknown".to_string());
    let signature = key_signature
        .filter(|s| !s.trim().is_empty())
        .ok_or((StatusCode::NOT_FOUND, "Подпись ключа не найдена".into()))?;

    Ok(Json(PublicKeyResponse {
        user_id,
        public_key: pubk,
        signature,
        key_version: key_version as u32,
        signed_at,
        identity_key: identity_pubk,
        signed_pre_key_id,
        signed_pre_key,
        signed_pre_key_signature,
        kyber_pre_key_id,
        kyber_pre_key,
        kyber_pre_key_signature,
        one_time_pre_keys,
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

    let content = fs::read(&file_path)
        .await
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
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка создания ответа: {}", e),
            )
        })?)
}
