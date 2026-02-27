use axum::{
    Json, Router,
    extract::{Multipart as MultipartExtractor, Path, Query, State},
    http::StatusCode,
    routing::{get, patch, post},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use serde_json::json;
use sqlx::{Postgres, Row, Transaction};
use std::path::Path as StdPath;
use tokio::fs;
use tokio::io::AsyncWriteExt;

use crate::AppState;
use crate::middleware::CurrentUser; // экстрактор текущего пользователя
use crate::middleware::ensure_member;
use crate::models::chats::{Chat, CreateChatRequest, FileMetadata, Message};
use crate::route::ws::{
    publish_chat_created, publish_chat_updated, publish_member_added, publish_member_removed,
    publish_member_role_changed, publish_message_delivered, publish_message_read,
    publish_payload_to_users,
};

// Модели вынесены в crate::models::chats

// Экстракция пользователя теперь делается через CurrentUser

// ---------------------------
// Конструктор роутера
// ---------------------------
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/chats", post(create_chat).get(list_chats))
        .route("/chats/:chat_id/messages", get(get_messages))
        .route("/chats/:id/read", post(mark_chat_read))
        .route("/chats/:id/delivered", post(mark_chat_delivered))
        .route(
            "/chats/:id/avatar",
            post(update_chat_avatar).patch(update_chat_avatar),
        )
        .route("/chats/:id/members", get(list_members).post(add_member))
        .route(
            "/chats/:id/members/:user_id",
            patch(update_member_role).delete(remove_member),
        )
        .route(
            "/chats/:id/favorite",
            post(add_favorite).delete(remove_favorite),
        )
        .route(
            "/chats/:id",
            patch(update_chat_info).delete(delete_or_leave_chat),
        )
}

#[derive(Deserialize)]
struct GetMessagesQuery {
    limit: Option<i64>,
    before_id: Option<i64>,
    after_id: Option<i64>,
}

#[derive(Serialize)]
struct ChatMember {
    user_id: i32,
    username: String,
    nickname: Option<String>,
    avatar: Option<String>,
    role: String,
    joined_at: String,
}

#[derive(Deserialize)]
struct AddMemberRequest {
    user_id: i32,
    role: Option<String>,
}

#[derive(Deserialize)]
struct UpdateMemberRoleRequest {
    role: String,
}

#[derive(Deserialize)]
struct MarkReadRequest {
    message_id: Option<i64>,
}

#[derive(Serialize)]
struct MarkReadResponse {
    last_read_message_id: i64,
}

#[derive(Deserialize)]
struct MarkDeliveredRequest {
    message_id: Option<i64>,
}

#[derive(Serialize)]
struct MarkDeliveredResponse {
    last_delivered_message_id: i64,
}

#[derive(Deserialize)]
struct UpdateChatInfoRequest {
    title: Option<String>,
    avatar: Option<String>,
}

fn normalize_member_role(kind: &str, role: Option<&str>) -> Result<String, (StatusCode, String)> {
    let normalized = role.unwrap_or("member").trim().to_lowercase();
    if normalized.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "Роль не может быть пустой".into()));
    }

    match kind {
        "group" => {
            if normalized == "member" || normalized == "admin" {
                Ok(normalized)
            } else {
                Err((
                    StatusCode::BAD_REQUEST,
                    "Для group допустимы роли: member, admin".into(),
                ))
            }
        }
        "channel" => {
            if normalized == "member" || normalized == "admin" {
                Ok(normalized)
            } else {
                Err((
                    StatusCode::BAD_REQUEST,
                    "Для channel допустимы роли: member, admin".into(),
                ))
            }
        }
        _ => Err((StatusCode::BAD_REQUEST, "Операция недоступна".into())),
    }
}

async fn load_chat_recipients(
    state: &AppState,
    chat_id: i32,
) -> Result<Vec<i32>, (StatusCode, String)> {
    let rows = sqlx::query("SELECT user_id FROM chat_participants WHERE chat_id = $1")
        .bind(chat_id)
        .fetch_all(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;

    Ok(rows
        .into_iter()
        .map(|row| row.try_get::<i32, _>("user_id").unwrap_or_default())
        .collect::<Vec<_>>())
}

async fn resolve_user_name(state: &AppState, user_id: i32) -> String {
    if user_id <= 0 {
        return "пользователь".to_string();
    }

    let row = sqlx::query("SELECT COALESCE(username, login) AS name FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(&state.pool)
        .await
        .ok()
        .flatten();

    if let Some(row) = row {
        let name = row.try_get::<String, _>("name").unwrap_or_default();
        let trimmed = name.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    format!("user #{}", user_id)
}

async fn create_system_message_and_publish(
    state: &AppState,
    chat_id: i32,
    actor_user_id: i32,
    text: String,
    recipients: &[i32],
) -> Result<(), (StatusCode, String)> {
    let row = sqlx::query(
        r#"
        INSERT INTO messages (chat_id, sender_id, message, message_type, envelopes, metadata)
        VALUES ($1, $2, $3, 'system', NULL, NULL)
        RETURNING
            id::INT8 AS id,
            chat_id::INT8 AS chat_id,
            sender_id::INT8 AS sender_id,
            message,
            message_type,
            created_at,
            edited_at,
            reply_to_message_id::INT8 AS reply_to_message_id,
            forwarded_from_message_id::INT8 AS forwarded_from_message_id,
            forwarded_from_chat_id::INT8 AS forwarded_from_chat_id,
            forwarded_from_sender_id::INT8 AS forwarded_from_sender_id,
            deleted_at,
            deleted_by::INT8 AS deleted_by,
            is_read,
            is_delivered,
            envelopes,
            metadata
        "#,
    )
    .bind(chat_id)
    .bind(actor_user_id)
    .bind(text)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let msg = Message {
        id: row.try_get("id").unwrap_or_default(),
        chat_id: row.try_get("chat_id").unwrap_or_default(),
        sender_id: row.try_get("sender_id").unwrap_or_default(),
        message: row.try_get("message").unwrap_or_default(),
        message_type: row
            .try_get("message_type")
            .unwrap_or_else(|_| "system".to_string()),
        created_at: row
            .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
            .map(|t| t.to_rfc3339())
            .unwrap_or_default(),
        edited_at: row
            .try_get::<chrono::DateTime<chrono::Utc>, _>("edited_at")
            .ok()
            .map(|t| t.to_rfc3339()),
        reply_to_message_id: row.try_get("reply_to_message_id").ok(),
        forwarded_from_message_id: row.try_get("forwarded_from_message_id").ok(),
        forwarded_from_chat_id: row.try_get("forwarded_from_chat_id").ok(),
        forwarded_from_sender_id: row.try_get("forwarded_from_sender_id").ok(),
        deleted_at: row
            .try_get::<chrono::DateTime<chrono::Utc>, _>("deleted_at")
            .ok()
            .map(|t| t.to_rfc3339()),
        deleted_by: row.try_get("deleted_by").ok(),
        is_read: row.try_get("is_read").unwrap_or(false),
        is_delivered: row.try_get("is_delivered").unwrap_or(false),
        has_files: Some(false),
        metadata: None,
        envelopes: None,
        protocol_version: Some(1),
        sender_identity_key: None,
        status: Some("sent".to_string()),
    };

    let payload = json!({
        "type": "message_new",
        "chat_id": chat_id,
        "message": msg
    })
    .to_string();
    publish_payload_to_users(state, recipients, payload);
    Ok(())
}

async fn load_chat_kind_role_and_title(
    state: &AppState,
    chat_id: i32,
    user_id: i32,
) -> Result<(String, String, Option<String>), (StatusCode, String)> {
    let row = sqlx::query(
        r#"
        SELECT c.kind, COALESCE(cp.role, 'member') AS role, c.title
        FROM chats c
        JOIN chat_participants cp ON cp.chat_id = c.id
        WHERE c.id = $1 AND cp.user_id = $2
        LIMIT 1
        "#,
    )
    .bind(chat_id)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let Some(row) = row else {
        return Err((StatusCode::NOT_FOUND, "Чат не найден".into()));
    };

    let kind = row
        .try_get::<String, _>("kind")
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    let role = row
        .try_get::<String, _>("role")
        .unwrap_or_else(|_| "member".to_string())
        .trim()
        .to_lowercase();
    let title: Option<String> = row.try_get("title").ok().flatten();
    Ok((kind, role, title))
}

async fn update_chat_info(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Json(body): Json<UpdateChatInfoRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    if body.title.is_none() && body.avatar.is_none() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Нет данных для обновления чата".into(),
        ));
    }

    let (kind, role, old_title) =
        load_chat_kind_role_and_title(&state, id, current_user_id).await?;
    if kind != "group" && kind != "channel" {
        return Err((
            StatusCode::BAD_REQUEST,
            "Обновление доступно только для группы/канала".into(),
        ));
    }
    if role != "owner" {
        return Err((
            StatusCode::FORBIDDEN,
            "Только owner может менять информацию о чате".into(),
        ));
    }

    let mut changed = false;
    let mut title_for_event = old_title.clone();
    let mut avatar_for_event: Option<String> = None;

    if let Some(raw_title) = body.title {
        let title = raw_title.trim();
        if title.is_empty() {
            return Err((
                StatusCode::BAD_REQUEST,
                "Название не может быть пустым".into(),
            ));
        }
        sqlx::query("UPDATE chats SET title = $1, updated_at = now() WHERE id = $2")
            .bind(title)
            .bind(id)
            .execute(&state.pool)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка БД: {}", e),
                )
            })?;
        changed = true;
        title_for_event = Some(title.to_string());
    }

    if let Some(raw_avatar) = body.avatar {
        let next_avatar = {
            let trimmed = raw_avatar.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        };
        sqlx::query("UPDATE chats SET avatar = $1, updated_at = now() WHERE id = $2")
            .bind(&next_avatar)
            .bind(id)
            .execute(&state.pool)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка БД: {}", e),
                )
            })?;
        changed = true;
        avatar_for_event = next_avatar;
    }

    if changed {
        let recipients = load_chat_recipients(&state, id).await?;
        publish_chat_updated(
            &state,
            &recipients,
            id,
            title_for_event.as_deref(),
            avatar_for_event.as_deref(),
            current_user_id,
        );
    }

    Ok(StatusCode::NO_CONTENT)
}

async fn update_chat_avatar(
    State(state): State<AppState>,
    Path(id): Path<i32>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    mut multipart: MultipartExtractor,
) -> Result<StatusCode, (StatusCode, String)> {
    let (kind, role, title_for_event) =
        load_chat_kind_role_and_title(&state, id, current_user_id).await?;
    if kind != "group" && kind != "channel" {
        return Err((
            StatusCode::BAD_REQUEST,
            "Обновление доступно только для группы/канала".into(),
        ));
    }
    if role != "owner" {
        return Err((
            StatusCode::FORBIDDEN,
            "Только owner может менять аватар чата".into(),
        ));
    }

    let current_avatar_row = sqlx::query("SELECT avatar FROM chats WHERE id = $1")
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

    let old_avatar_path = current_avatar_path.clone();
    let new_avatar_path = if remove_avatar {
        None
    } else if let Some(data) = avatar_data {
        const MAX_AVATAR_BYTES: usize = 5 * 1024 * 1024;
        if data.len() > MAX_AVATAR_BYTES {
            return Err((
                StatusCode::BAD_REQUEST,
                "Слишком большой файл аватара".into(),
            ));
        }

        let avatars_dir = StdPath::new("uploads/avatars");
        fs::create_dir_all(avatars_dir).await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Не удалось создать директорию для аватаров: {}", e),
            )
        })?;

        let extension_raw = avatar_filename
            .as_ref()
            .and_then(|f| StdPath::new(f).extension())
            .and_then(|ext| ext.to_str())
            .unwrap_or("jpg");
        let extension = extension_raw.to_ascii_lowercase();
        let extension = match extension.as_str() {
            "jpg" | "jpeg" | "png" | "gif" | "webp" => extension,
            _ => "jpg".to_string(),
        };

        let new_path = format!("uploads/avatars/chat_{}.{}", id, extension);
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
        Some(format!("avatars/chat_{}.{}", id, extension))
    } else {
        old_avatar_path.clone()
    };

    if let Some(ref old_path) = old_avatar_path {
        if new_avatar_path.as_ref() != Some(old_path) {
            let full_old_path = StdPath::new("uploads").join(old_path);
            if full_old_path.exists() {
                let _ = fs::remove_file(&full_old_path).await;
            }
        }
    }

    sqlx::query("UPDATE chats SET avatar = $1, updated_at = now() WHERE id = $2")
        .bind(&new_avatar_path)
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;

    let recipients = load_chat_recipients(&state, id).await?;
    publish_chat_updated(
        &state,
        &recipients,
        id,
        title_for_event.as_deref(),
        new_avatar_path.as_deref(),
        current_user_id,
    );

    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------
// POST /chats — создать чат
// ---------------------------
async fn create_chat(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Json(body): Json<CreateChatRequest>,
) -> Result<Json<Chat>, (StatusCode, String)> {
    // Простые проверки
    match body.kind.as_str() {
        "private" => {
            if body.user_ids.len() != 2 || !body.user_ids.contains(&current_user_id) {
                return Err((
                    StatusCode::BAD_REQUEST,
                    "Для private-чата нужно ровно 2 участника, включая текущего пользователя"
                        .into(),
                ));
            }
        }
        "group" => {
            if body.title.as_deref().unwrap_or("").trim().is_empty() {
                return Err((StatusCode::BAD_REQUEST, "Для group обязателен title".into()));
            }
        }
        "channel" => {
            if body.title.as_deref().unwrap_or("").trim().is_empty() {
                return Err((
                    StatusCode::BAD_REQUEST,
                    "Для channel обязателен title".into(),
                ));
            }
        }
        _ => {
            return Err((
                StatusCode::BAD_REQUEST,
                "kind должен быть одним из: private, group, channel".into(),
            ));
        }
    }

    let mut tx: Transaction<'_, Postgres> = state.pool.begin().await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Не удалось начать транзакцию: {}", e),
        )
    })?;

    // Для private-чата сначала проверим, существует ли уже чат с этой парой (каноническая пара user_a<=user_b)
    if body.kind == "private" {
        let mut a = body.user_ids[0];
        let mut b = body.user_ids[1];
        if a > b {
            std::mem::swap(&mut a, &mut b);
        }
        // Сначала пробуем найти по canonical-паре user_a/user_b (новая схема)
        let existing = sqlx::query(
            r#"
            SELECT id, kind, title, created_at, updated_at, is_archived
            FROM chats
            WHERE kind = 'private' AND user_a = $1 AND user_b = $2
            LIMIT 1
            "#,
        )
        .bind(a)
        .bind(b)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;

        if let Some(row) = existing {
            let chat = Chat {
                id: row.try_get("id").unwrap_or_default(),
                kind: row.try_get::<String, _>("kind").unwrap_or_default(),
                title: row.try_get("title").ok(),
                created_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                    .map(|t| t.to_rfc3339())
                    .unwrap_or_default(),
                updated_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("updated_at")
                    .map(|t| t.to_rfc3339())
                    .unwrap_or_default(),
                is_archived: row.try_get("is_archived").ok(),
                is_favorite: Some(false),
                peer_id: None,
                peer_username: None,
                peer_nickname: None,
                peer_avatar: None,
                unread_count: Some(0),
                my_role: Some("member".to_string()),
                last_message_id: None,
                last_message: None,
                last_message_type: None,
                last_message_created_at: None,
                last_message_is_outgoing: None,
                last_message_is_delivered: None,
                last_message_is_read: None,
            };
            // Гарантируем, что текущий пользователь числится участником (если выходил ранее — вернём в чат)
            sqlx::query(
                r#"INSERT INTO chat_participants (chat_id, user_id, role)
                   VALUES ($1, $2, 'member') ON CONFLICT DO NOTHING"#,
            )
            .bind(chat.id)
            .bind(current_user_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка добавления участника: {}", e),
                )
            })?;

            tx.commit().await.ok();
            return Ok(Json(chat));
        }

        // Fallback: если в старых данных user_a/user_b ещё не заполнены, найдём по участникам
        let existing_old = sqlx::query(
            r#"
            SELECT c.id, c.kind, c.title, c.created_at, c.updated_at, c.is_archived
            FROM chats c
            JOIN chat_participants p1 ON p1.chat_id = c.id AND p1.user_id = $1
            JOIN chat_participants p2 ON p2.chat_id = c.id AND p2.user_id = $2
            WHERE c.kind = 'private'
            LIMIT 1
            "#,
        )
        .bind(a)
        .bind(b)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;

        if let Some(row) = existing_old {
            let chat_id: i32 = row.try_get("id").unwrap_or_default();
            // Попробуем обновить user_a/user_b для такого чата (однократно)
            let _ = sqlx::query("UPDATE chats SET user_a = $1, user_b = $2 WHERE id = $3 AND user_a IS NULL AND user_b IS NULL")
                .bind(a)
                .bind(b)
                .bind(chat_id)
                .execute(&mut *tx).await;

            // Гарантируем участие текущего пользователя
            sqlx::query(
                r#"INSERT INTO chat_participants (chat_id, user_id, role)
                   VALUES ($1, $2, 'member') ON CONFLICT DO NOTHING"#,
            )
            .bind(chat_id)
            .bind(current_user_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка добавления участника: {}", e),
                )
            })?;

            let chat = Chat {
                id: chat_id,
                kind: row.try_get::<String, _>("kind").unwrap_or_default(),
                title: row.try_get("title").ok(),
                created_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                    .map(|t| t.to_rfc3339())
                    .unwrap_or_default(),
                updated_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("updated_at")
                    .map(|t| t.to_rfc3339())
                    .unwrap_or_default(),
                is_archived: row.try_get("is_archived").ok(),
                is_favorite: Some(false),
                peer_id: None,
                peer_username: None,
                peer_nickname: None,
                peer_avatar: None,
                unread_count: Some(0),
                my_role: Some("member".to_string()),
                last_message_id: None,
                last_message: None,
                last_message_type: None,
                last_message_created_at: None,
                last_message_is_outgoing: None,
                last_message_is_delivered: None,
                last_message_is_read: None,
            };
            tx.commit().await.ok();
            return Ok(Json(chat));
        }
    }

    // Создаём новый чат
    let row = if body.kind == "private" {
        // Для private сохраняем каноническую пару
        let mut a = body.user_ids[0];
        let mut b = body.user_ids[1];
        if a > b {
            std::mem::swap(&mut a, &mut b);
        }
        sqlx::query(
            r#"
            INSERT INTO chats (kind, title, user_a, user_b)
            VALUES ($1, $2, $3, $4)
            RETURNING id, kind, title, created_at, updated_at, is_archived
            "#,
        )
        .bind(&body.kind)
        .bind(&body.title)
        .bind(a)
        .bind(b)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка создания чата: {}", e),
            )
        })?
    } else {
        sqlx::query(
            r#"
            INSERT INTO chats (kind, title)
            VALUES ($1, $2)
            RETURNING id, kind, title, created_at, updated_at, is_archived
            "#,
        )
        .bind(&body.kind)
        .bind(&body.title)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка создания чата: {}", e),
            )
        })?
    };
    let chat_id: i32 = row.try_get("id").unwrap_or_default();

    // Вставляем участников (без дубликатов)
    let mut inserted_users = std::collections::HashSet::new();
    for uid in body.user_ids.iter().copied() {
        if inserted_users.insert(uid) {
            sqlx::query(
                r#"INSERT INTO chat_participants (chat_id, user_id, role) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"#,
            )
            .bind(chat_id)
            .bind(uid)
            .bind(if uid == current_user_id {
                if body.kind == "group" {
                    "owner"
                } else if body.kind == "channel" {
                    "owner"
                } else {
                    "member"
                }
            } else {
                "member"
            })
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка добавления участника: {}", e)))?;
        }
    }

    // На всякий случай убеждаемся, что текущий пользователь участник
    if !inserted_users.contains(&current_user_id) {
        sqlx::query(
            r#"INSERT INTO chat_participants (chat_id, user_id, role) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"#,
        )
        .bind(chat_id)
        .bind(current_user_id)
        .bind(if body.kind == "group" {
            "owner"
        } else if body.kind == "channel" {
            "owner"
        } else {
            "member"
        })
        .execute(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка добавления текущего пользователя: {}", e)))?;
    }

    tx.commit().await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Не удалось зафиксировать транзакцию: {}", e),
        )
    })?;

    let chat_kind = row.try_get::<String, _>("kind").unwrap_or_default();
    let my_role = if chat_kind == "channel" || chat_kind == "group" {
        "owner".to_string()
    } else {
        "member".to_string()
    };

    let chat = Chat {
        id: chat_id,
        kind: chat_kind,
        title: row.try_get("title").ok(),
        created_at: row
            .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
            .map(|t| t.to_rfc3339())
            .unwrap_or_default(),
        updated_at: row
            .try_get::<chrono::DateTime<chrono::Utc>, _>("updated_at")
            .map(|t| t.to_rfc3339())
            .unwrap_or_default(),
        is_archived: row.try_get("is_archived").ok(),
        is_favorite: Some(false),
        peer_id: None,
        peer_username: None,
        peer_nickname: None,
        peer_avatar: None,
        unread_count: Some(0),
        my_role: Some(my_role),
        last_message_id: None,
        last_message: None,
        last_message_type: None,
        last_message_created_at: None,
        last_message_is_outgoing: None,
        last_message_is_delivered: None,
        last_message_is_read: None,
    };

    let recipients = inserted_users.into_iter().collect::<Vec<_>>();
    publish_chat_created(
        &state,
        &recipients,
        chat_id,
        &chat.kind,
        chat.title.as_deref(),
        current_user_id,
    );

    Ok(Json(chat))
}

// ---------------------------
// GET /chats — список чатов текущего пользователя
// ---------------------------
async fn list_chats(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
) -> Result<Json<Vec<Chat>>, (StatusCode, String)> {
    let rows = sqlx::query(
        r#"
        SELECT
            c.id,
            c.kind,
            c.title,
            c.created_at,
            c.updated_at,
            c.is_archived,
            COALESCE(p.role, 'member') AS my_role,
            EXISTS(
                SELECT 1
                FROM chat_favorites cf
                WHERE cf.user_id = $1 AND cf.chat_id = c.id
            ) AS is_favorite,
            COALESCE(
                CASE
                    WHEN c.kind = 'private' AND c.user_a = $1 THEN c.user_b
                    WHEN c.kind = 'private' AND c.user_b = $1 THEN c.user_a
                    ELSE NULL
                END,
                (
                    SELECT cp.user_id
                    FROM chat_participants cp
                    WHERE cp.chat_id = c.id AND cp.user_id <> $1
                    LIMIT 1
                )
            ) AS peer_id,
            COALESCE(u.username, u.login) AS peer_username,
            u.nickname AS peer_nickname,
            CASE
                WHEN c.kind = 'group' OR c.kind = 'channel' THEN c.avatar
                ELSE u.avatar
            END AS peer_avatar,
            lm.id AS last_message_id,
            lm.message AS last_message,
            lm.message_type AS last_message_type,
            lm.created_at AS last_message_created_at,
            CASE
                WHEN lm.sender_id IS NULL THEN NULL
                WHEN lm.sender_id = $1 THEN TRUE
                ELSE FALSE
            END AS last_message_is_outgoing,
            CASE
                WHEN lm.id IS NULL THEN NULL
                ELSE COALESCE(lm.is_delivered, FALSE)
            END AS last_message_is_delivered,
            CASE
                WHEN lm.id IS NULL THEN NULL
                ELSE COALESCE(lm.is_read, FALSE)
            END AS last_message_is_read,
            (
                SELECT COUNT(*)::INT8
                FROM messages m
                WHERE m.chat_id = c.id
                  AND m.deleted_at IS NULL
                  AND m.sender_id <> $1
                  AND m.id::INT8 > COALESCE(p.last_read_message_id::INT8, 0)
            ) AS unread_count
        FROM chats c
        JOIN chat_participants p ON p.chat_id = c.id
        LEFT JOIN LATERAL (
            SELECT
                m.id,
                m.sender_id,
                m.message,
                m.message_type,
                m.created_at,
                m.is_delivered,
                m.is_read
            FROM messages m
            WHERE m.chat_id = c.id
              AND m.deleted_at IS NULL
            ORDER BY m.id DESC
            LIMIT 1
        ) lm ON TRUE
        LEFT JOIN users u ON u.id = COALESCE(
            CASE
                WHEN c.kind = 'private' AND c.user_a = $1 THEN c.user_b
                WHEN c.kind = 'private' AND c.user_b = $1 THEN c.user_a
                ELSE NULL
            END,
            (
                SELECT cp.user_id
                FROM chat_participants cp
                WHERE cp.chat_id = c.id AND cp.user_id <> $1
                LIMIT 1
            )
        )
        WHERE p.user_id = $1
        ORDER BY c.updated_at DESC
        "#,
    )
    .bind(current_user_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let items = rows
        .into_iter()
        .map(|row| Chat {
            id: row.try_get("id").unwrap_or_default(),
            kind: row.try_get::<String, _>("kind").unwrap_or_default(),
            title: row.try_get("title").ok(),
            created_at: row
                .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                .map(|t| t.to_rfc3339())
                .unwrap_or_default(),
            updated_at: row
                .try_get::<chrono::DateTime<chrono::Utc>, _>("updated_at")
                .map(|t| t.to_rfc3339())
                .unwrap_or_default(),
            is_archived: row.try_get("is_archived").ok(),
            is_favorite: row
                .try_get::<bool, _>("is_favorite")
                .ok()
                .map(Some)
                .unwrap_or(Some(false)),
            peer_id: row.try_get("peer_id").ok(),
            peer_username: row.try_get("peer_username").ok(),
            peer_nickname: row.try_get("peer_nickname").ok(),
            peer_avatar: row.try_get("peer_avatar").ok(),
            unread_count: row.try_get("unread_count").ok().or(Some(0)),
            my_role: row.try_get("my_role").ok(),
            last_message_id: row.try_get("last_message_id").ok(),
            last_message: row.try_get("last_message").ok(),
            last_message_type: row.try_get("last_message_type").ok(),
            last_message_created_at: row
                .try_get::<chrono::DateTime<chrono::Utc>, _>("last_message_created_at")
                .map(|t| t.to_rfc3339())
                .ok(),
            last_message_is_outgoing: row.try_get("last_message_is_outgoing").ok(),
            last_message_is_delivered: row.try_get("last_message_is_delivered").ok(),
            last_message_is_read: row.try_get("last_message_is_read").ok(),
        })
        .collect();

    Ok(Json(items))
}

// ---------------------------
// GET /chats/{chat_id}/messages — сообщения чата (только для участников)
// ---------------------------
async fn get_messages(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path(chat_id): Path<i32>,
    Query(q): Query<GetMessagesQuery>,
) -> Result<Json<Vec<Message>>, (StatusCode, String)> {
    // Проверяем, что пользователь — участник чата (общая утилита)
    ensure_member(&state, chat_id, current_user_id).await?;

    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let before_id = q.before_id;
    let after_id = q.after_id;

    let rows = sqlx::query(
        r#"
        SELECT * FROM (
            SELECT 
                id::INT8 AS id, 
                chat_id::INT8 AS chat_id, 
                sender_id::INT8 AS sender_id, 
                COALESCE(message, body) AS message,
                COALESCE(message_type, 'text') AS message_type,
                created_at,
                edited_at,
                reply_to_message_id::INT8 AS reply_to_message_id,
                forwarded_from_message_id::INT8 AS forwarded_from_message_id,
                forwarded_from_chat_id::INT8 AS forwarded_from_chat_id,
                forwarded_from_sender_id::INT8 AS forwarded_from_sender_id,
                deleted_at,
                deleted_by::INT8 AS deleted_by,
                COALESCE(is_read, false) AS is_read,
                COALESCE(is_delivered, false) AS is_delivered,
                envelopes,
                metadata
            FROM messages
            WHERE chat_id = $1
              AND deleted_at IS NULL
              AND ($2::INT8 IS NULL OR id::INT8 < $2::INT8)
              AND ($3::INT8 IS NULL OR id::INT8 > $3::INT8)
            ORDER BY created_at DESC
            LIMIT $4
        ) t
        ORDER BY created_at ASC
        "#,
    )
    .bind(chat_id)
    .bind(before_id)
    .bind(after_id)
    .bind(limit)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let items: Vec<Message> = rows
        .into_iter()
        .map(|row| {
            let metadata_value: Option<Value> = row.try_get("metadata").ok().flatten();
            let metadata_vec: Option<Vec<FileMetadata>> =
                metadata_value.and_then(|v| serde_json::from_value(v).ok());

            let has_files = metadata_vec.as_ref().map(|m| !m.is_empty());

            Message {
                id: row.try_get("id").unwrap_or_default(),
                chat_id: row.try_get("chat_id").unwrap_or_default(),
                sender_id: row.try_get("sender_id").unwrap_or_default(),
                message: row.try_get("message").unwrap_or_default(),
                message_type: row
                    .try_get("message_type")
                    .unwrap_or_else(|_| "text".to_string()),
                created_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                    .map(|t| t.to_rfc3339())
                    .unwrap_or_default(),
                edited_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("edited_at")
                    .ok()
                    .map(|t| t.to_rfc3339()),
                reply_to_message_id: row.try_get("reply_to_message_id").ok(),
                forwarded_from_message_id: row.try_get("forwarded_from_message_id").ok(),
                forwarded_from_chat_id: row.try_get("forwarded_from_chat_id").ok(),
                forwarded_from_sender_id: row.try_get("forwarded_from_sender_id").ok(),
                deleted_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("deleted_at")
                    .ok()
                    .map(|t| t.to_rfc3339()),
                deleted_by: row.try_get("deleted_by").ok(),
                is_read: row.try_get("is_read").unwrap_or(false),
                is_delivered: row.try_get("is_delivered").unwrap_or(false),
                has_files,
                metadata: metadata_vec,
                envelopes: row.try_get("envelopes").ok().flatten(),
                protocol_version: row.try_get("protocol_version").ok(),
                sender_identity_key: row.try_get("sender_identity_key").ok(),
                status: None,
            }
        })
        .collect();

    Ok(Json(items))
}

// ---------------------------
// POST /chats/{id}/read — отметить сообщения как прочитанные до message_id (или до последнего)
// ---------------------------
async fn mark_chat_read(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path(id): Path<i32>,
    Json(body): Json<MarkReadRequest>,
) -> Result<Json<MarkReadResponse>, (StatusCode, String)> {
    ensure_member(&state, id, current_user_id).await?;

    let prev_last_read: i64 = sqlx::query_scalar(
        r#"
        SELECT COALESCE(last_read_message_id::INT8, 0)
        FROM chat_participants
        WHERE chat_id = $1 AND user_id = $2
        "#,
    )
    .bind(id)
    .bind(current_user_id)
    .fetch_one(&state.pool)
    .await
    .unwrap_or(0);

    let max_message_id: i64 = sqlx::query_scalar(
        r#"
        SELECT COALESCE(MAX(id)::INT8, 0)
        FROM messages
        WHERE chat_id = $1
          AND deleted_at IS NULL
        "#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let requested = body.message_id.unwrap_or(max_message_id).max(0);
    let target = requested.min(max_message_id);
    let target_i32 = target.min(i32::MAX as i64) as i32;
    let effective_target = target_i32 as i64;

    if effective_target <= prev_last_read {
        return Ok(Json(MarkReadResponse {
            last_read_message_id: prev_last_read,
        }));
    }

    sqlx::query(
        r#"
        UPDATE chat_participants
        SET last_read_message_id = $3
        WHERE chat_id = $1 AND user_id = $2
        "#,
    )
    .bind(id)
    .bind(current_user_id)
    .bind(target_i32)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let kind: String = sqlx::query_scalar("SELECT kind FROM chats WHERE id = $1")
        .bind(id)
        .fetch_one(&state.pool)
        .await
        .unwrap_or_else(|_| "private".to_string());

    if kind == "private" && effective_target > 0 {
        let _ = sqlx::query(
            r#"
            UPDATE messages
            SET is_read = TRUE,
                is_delivered = TRUE
            WHERE chat_id = $1
              AND sender_id <> $2
              AND id::INT8 <= $3
            "#,
        )
        .bind(id)
        .bind(current_user_id)
        .bind(effective_target)
        .execute(&state.pool)
        .await;
    }

    let recipients = load_chat_recipients(&state, id).await?;
    publish_message_read(&state, &recipients, id, current_user_id, effective_target);

    Ok(Json(MarkReadResponse {
        last_read_message_id: effective_target,
    }))
}

// ---------------------------
// POST /chats/{id}/delivered — отметить сообщения как доставленные до message_id (или до последнего)
// ---------------------------
async fn mark_chat_delivered(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path(id): Path<i32>,
    Json(body): Json<MarkDeliveredRequest>,
) -> Result<Json<MarkDeliveredResponse>, (StatusCode, String)> {
    ensure_member(&state, id, current_user_id).await?;

    let prev_last_delivered: i64 = sqlx::query_scalar(
        r#"
        SELECT COALESCE(MAX(id)::INT8, 0)
        FROM messages
        WHERE chat_id = $1
          AND sender_id <> $2
          AND deleted_at IS NULL
          AND is_delivered = TRUE
        "#,
    )
    .bind(id)
    .bind(current_user_id)
    .fetch_one(&state.pool)
    .await
    .unwrap_or(0);

    let max_message_id: i64 = sqlx::query_scalar(
        r#"
        SELECT COALESCE(MAX(id)::INT8, 0)
        FROM messages
        WHERE chat_id = $1
          AND deleted_at IS NULL
        "#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let requested = body.message_id.unwrap_or(max_message_id).max(0);
    let target = requested.min(max_message_id);

    if target <= prev_last_delivered {
        return Ok(Json(MarkDeliveredResponse {
            last_delivered_message_id: prev_last_delivered,
        }));
    }

    let _ = sqlx::query(
        r#"
        UPDATE messages
        SET is_delivered = TRUE
        WHERE chat_id = $1
          AND sender_id <> $2
          AND id::INT8 <= $3
          AND deleted_at IS NULL
          AND COALESCE(is_delivered, FALSE) = FALSE
        "#,
    )
    .bind(id)
    .bind(current_user_id)
    .bind(target)
    .execute(&state.pool)
    .await;

    let delivered_cursor: i64 = sqlx::query_scalar(
        r#"
        SELECT COALESCE(MAX(id)::INT8, 0)
        FROM messages
        WHERE chat_id = $1
          AND sender_id <> $2
          AND deleted_at IS NULL
          AND is_delivered = TRUE
        "#,
    )
    .bind(id)
    .bind(current_user_id)
    .fetch_one(&state.pool)
    .await
    .unwrap_or(prev_last_delivered);

    let recipients = load_chat_recipients(&state, id).await?;
    if delivered_cursor > prev_last_delivered {
        publish_message_delivered(&state, &recipients, id, current_user_id, delivered_cursor);
    }

    Ok(Json(MarkDeliveredResponse {
        last_delivered_message_id: delivered_cursor,
    }))
}

// ---------------------------
// GET /chats/{id}/members — список участников (для участников чата)
// ---------------------------
async fn list_members(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path(id): Path<i32>,
) -> Result<Json<Vec<ChatMember>>, (StatusCode, String)> {
    ensure_member(&state, id, current_user_id).await?;

    let rows = sqlx::query(
        r#"
        SELECT
            cp.user_id,
            COALESCE(u.username, u.login) AS username,
            u.nickname,
            u.avatar,
            COALESCE(cp.role, 'member') AS role,
            cp.joined_at
        FROM chat_participants cp
        JOIN users u ON u.id = cp.user_id
        WHERE cp.chat_id = $1
        ORDER BY cp.joined_at ASC, cp.user_id ASC
        "#,
    )
    .bind(id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let members = rows
        .into_iter()
        .map(|row| ChatMember {
            user_id: row.try_get("user_id").unwrap_or_default(),
            username: row.try_get("username").unwrap_or_default(),
            nickname: row.try_get("nickname").ok(),
            avatar: row.try_get("avatar").ok(),
            role: row
                .try_get::<String, _>("role")
                .unwrap_or_else(|_| "member".to_string()),
            joined_at: row
                .try_get::<chrono::DateTime<chrono::Utc>, _>("joined_at")
                .map(|t| t.to_rfc3339())
                .unwrap_or_default(),
        })
        .collect::<Vec<_>>();

    Ok(Json(members))
}

// ---------------------------
// POST /chats/{id}/members — добавить участника в group/channel (admin/owner)
// ---------------------------
async fn add_member(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path(id): Path<i32>,
    Json(body): Json<AddMemberRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    crate::middleware::ensure_admin(&state, id, current_user_id).await?;

    let chat_row = sqlx::query("SELECT kind FROM chats WHERE id = $1")
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;

    let Some(chat_row) = chat_row else {
        return Err((StatusCode::NOT_FOUND, "Чат не найден".into()));
    };
    let kind: String = chat_row.try_get("kind").unwrap_or_default();
    if kind == "private" {
        return Err((
            StatusCode::BAD_REQUEST,
            "Нельзя управлять участниками private-чата".into(),
        ));
    }

    let exists_user: Option<i32> = sqlx::query_scalar("SELECT 1 FROM users WHERE id = $1 LIMIT 1")
        .bind(body.user_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;
    if exists_user.is_none() {
        return Err((StatusCode::NOT_FOUND, "Пользователь не найден".into()));
    }
    if body.user_id == current_user_id {
        return Err((
            StatusCode::BAD_REQUEST,
            "Нельзя добавить самого себя через этот endpoint".into(),
        ));
    }

    let exists_member: Option<String> = sqlx::query_scalar(
        "SELECT role FROM chat_participants WHERE chat_id = $1 AND user_id = $2 LIMIT 1",
    )
    .bind(id)
    .bind(body.user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;
    if exists_member.is_some() {
        return Ok(StatusCode::NO_CONTENT);
    }

    let role = normalize_member_role(&kind, body.role.as_deref())?;
    let inserted = sqlx::query(
        r#"
        INSERT INTO chat_participants (chat_id, user_id, role)
        VALUES ($1, $2, $3)
        ON CONFLICT (chat_id, user_id) DO NOTHING
        "#,
    )
    .bind(id)
    .bind(body.user_id)
    .bind(&role)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;
    if inserted.rows_affected() == 0 {
        return Ok(StatusCode::NO_CONTENT);
    }

    let recipients = load_chat_recipients(&state, id).await?;
    publish_member_added(
        &state,
        &recipients,
        id,
        body.user_id,
        role.clone(),
        current_user_id,
    );
    let actor_name = resolve_user_name(&state, current_user_id).await;
    let target_name = resolve_user_name(&state, body.user_id).await;
    let text = format!(
        "{} добавил(а) {} в чат (роль: {}).",
        actor_name, target_name, role
    );
    create_system_message_and_publish(&state, id, current_user_id, text, &recipients).await?;

    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------
// PATCH /chats/{id}/members/{user_id} — смена роли участника (admin/owner)
// ---------------------------
async fn update_member_role(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path((id, user_id)): Path<(i32, i32)>,
    Json(body): Json<UpdateMemberRoleRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    crate::middleware::ensure_admin(&state, id, current_user_id).await?;

    let chat_row = sqlx::query("SELECT kind FROM chats WHERE id = $1")
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;
    let Some(chat_row) = chat_row else {
        return Err((StatusCode::NOT_FOUND, "Чат не найден".into()));
    };
    let kind: String = chat_row.try_get("kind").unwrap_or_default();
    if kind == "private" {
        return Err((
            StatusCode::BAD_REQUEST,
            "Нельзя менять роли в private-чате".into(),
        ));
    }

    let target_role: Option<String> = sqlx::query_scalar(
        "SELECT role FROM chat_participants WHERE chat_id = $1 AND user_id = $2 LIMIT 1",
    )
    .bind(id)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;
    let Some(target_role) = target_role else {
        return Err((StatusCode::NOT_FOUND, "Участник не найден".into()));
    };
    if target_role == "owner" {
        return Err((
            StatusCode::BAD_REQUEST,
            "Нельзя менять роль owner через этот endpoint".into(),
        ));
    }

    let role = normalize_member_role(&kind, Some(body.role.as_str()))?;
    if role == target_role {
        return Ok(StatusCode::NO_CONTENT);
    }
    let updated =
        sqlx::query("UPDATE chat_participants SET role = $1 WHERE chat_id = $2 AND user_id = $3")
            .bind(role.clone())
            .bind(id)
            .bind(user_id)
            .execute(&state.pool)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка БД: {}", e),
                )
            })?;

    if updated.rows_affected() == 0 {
        return Err((StatusCode::NOT_FOUND, "Участник не найден".into()));
    }

    let recipients = load_chat_recipients(&state, id).await?;
    publish_member_role_changed(
        &state,
        &recipients,
        id,
        user_id,
        role.clone(),
        current_user_id,
    );
    let actor_name = resolve_user_name(&state, current_user_id).await;
    let target_name = resolve_user_name(&state, user_id).await;
    let text = format!(
        "{} изменил(а) роль {} на {}.",
        actor_name, target_name, role
    );
    create_system_message_and_publish(&state, id, current_user_id, text, &recipients).await?;

    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------
// DELETE /chats/{id}/members/{user_id} — удалить участника из group/channel
// ---------------------------
async fn remove_member(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path((id, user_id)): Path<(i32, i32)>,
) -> Result<StatusCode, (StatusCode, String)> {
    crate::middleware::ensure_admin(&state, id, current_user_id).await?;

    let chat_row = sqlx::query("SELECT kind FROM chats WHERE id = $1")
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;
    let Some(chat_row) = chat_row else {
        return Err((StatusCode::NOT_FOUND, "Чат не найден".into()));
    };
    let kind: String = chat_row.try_get("kind").unwrap_or_default();
    if kind == "private" {
        return Err((
            StatusCode::BAD_REQUEST,
            "Нельзя удалять участников из private-чата".into(),
        ));
    }

    if user_id == current_user_id {
        return Err((
            StatusCode::BAD_REQUEST,
            "Нельзя удалить самого себя через этот endpoint".into(),
        ));
    }

    let target_role: Option<String> = sqlx::query_scalar(
        "SELECT role FROM chat_participants WHERE chat_id = $1 AND user_id = $2 LIMIT 1",
    )
    .bind(id)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;
    let Some(target_role) = target_role else {
        return Ok(StatusCode::NO_CONTENT);
    };
    if target_role == "owner" {
        return Err((StatusCode::BAD_REQUEST, "Нельзя удалить owner".into()));
    }

    let deleted = sqlx::query("DELETE FROM chat_participants WHERE chat_id = $1 AND user_id = $2")
        .bind(id)
        .bind(user_id)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Ошибка БД: {}", e),
            )
        })?;

    if deleted.rows_affected() == 0 {
        return Err((StatusCode::NOT_FOUND, "Участник не найден".into()));
    }

    let mut recipients = load_chat_recipients(&state, id).await?;
    recipients.push(user_id);
    publish_member_removed(&state, &recipients, id, user_id, current_user_id);
    let actor_name = resolve_user_name(&state, current_user_id).await;
    let target_name = resolve_user_name(&state, user_id).await;
    let text = format!("{} удалил(а) {} из чата.", actor_name, target_name);
    let system_recipients = recipients
        .into_iter()
        .filter(|uid| *uid != user_id)
        .collect::<Vec<_>>();
    create_system_message_and_publish(&state, id, current_user_id, text, &system_recipients)
        .await?;

    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------
// DELETE /chats/{id}
// Group/channel: только admin/owner может удалить чат (полностью). Private: выходим из чата.
// ---------------------------
async fn delete_or_leave_chat(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path(id): Path<i32>,
    Query(opts): Query<DeleteOptions>,
) -> Result<StatusCode, (StatusCode, String)> {
    // Узнаем тип чата и роль текущего пользователя
    let row = sqlx::query(
        r#"
        SELECT c.kind, coalesce(p.role, 'member') AS role
        FROM chats c
        LEFT JOIN chat_participants p ON p.chat_id = c.id AND p.user_id = $2
        WHERE c.id = $1
        "#,
    )
    .bind(id)
    .bind(current_user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let Some(row) = row else {
        return Err((StatusCode::NOT_FOUND, "Чат не найден".into()));
    };
    let kind: String = row.try_get("kind").unwrap_or_default();
    let role: String = row.try_get("role").unwrap_or_else(|_| "member".to_string());

    if kind == "group" || kind == "channel" {
        // group/channel:
        // - for_all=true => удаление всего чата (только admin/owner)
        // - иначе => выход текущего пользователя из чата
        if opts.for_all.unwrap_or(false) {
            if role.trim().to_lowercase() != "owner" {
                return Err((
                    StatusCode::FORBIDDEN,
                    "Только owner может удалить группу/канал для всех".into(),
                ));
            }
            sqlx::query("DELETE FROM chats WHERE id = $1")
                .bind(id)
                .execute(&state.pool)
                .await
                .map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        format!("Ошибка удаления чата: {}", e),
                    )
                })?;
            return Ok(StatusCode::NO_CONTENT);
        }

        ensure_member(&state, id, current_user_id).await?;
        let _ = sqlx::query("DELETE FROM chat_participants WHERE chat_id = $1 AND user_id = $2")
            .bind(id)
            .bind(current_user_id)
            .execute(&state.pool)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка выхода из чата: {}", e),
                )
            })?;

        // Если участников больше нет — удаляем сам чат.
        let participants_left: Option<i64> =
            sqlx::query_scalar("SELECT COUNT(*) FROM chat_participants WHERE chat_id = $1")
                .bind(id)
                .fetch_optional(&state.pool)
                .await
                .map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        format!("Ошибка БД: {}", e),
                    )
                })?;

        if participants_left.unwrap_or(0) == 0 {
            let _ = sqlx::query("DELETE FROM chats WHERE id = $1")
                .bind(id)
                .execute(&state.pool)
                .await;
        }
        return Ok(StatusCode::NO_CONTENT);
    } else {
        // private: если for_all=true — удаляем чат полностью
        if opts.for_all.unwrap_or(false) {
            // Должен быть участником
            ensure_member(&state, id, current_user_id).await?;
            sqlx::query("DELETE FROM chats WHERE id = $1")
                .bind(id)
                .execute(&state.pool)
                .await
                .map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        format!("Ошибка удаления приватного чата: {}", e),
                    )
                })?;
            return Ok(StatusCode::NO_CONTENT);
        }
        // private: удаляем только участие текущего пользователя
        // Сначала убеждаемся, что текущий пользователь является участником чата
        ensure_member(&state, id, current_user_id).await?;
        sqlx::query("DELETE FROM chat_participants WHERE chat_id = $1 AND user_id = $2")
            .bind(id)
            .bind(current_user_id)
            .execute(&state.pool)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка выхода из чата: {}", e),
                )
            })?;

        // Если участников больше нет — удаляем сам чат (упрощённо, вместо фонового джоба)
        let participants_left: Option<i64> =
            sqlx::query_scalar("SELECT COUNT(*) FROM chat_participants WHERE chat_id = $1")
                .bind(id)
                .fetch_optional(&state.pool)
                .await
                .map_err(|e| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        format!("Ошибка БД: {}", e),
                    )
                })?;

        if participants_left.unwrap_or(0) == 0 {
            sqlx::query("DELETE FROM chats WHERE id = $1")
                .bind(id)
                .execute(&state.pool)
                .await
                .ok();
        }

        return Ok(StatusCode::NO_CONTENT);
    }
}

// ---------------------------
// POST /chats/{id}/favorite — добавить чат в избранное (макс 5 на пользователя)
// ---------------------------
async fn add_favorite(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path(id): Path<i32>,
) -> Result<StatusCode, (StatusCode, String)> {
    // Только участник чата может добавлять в избранное
    ensure_member(&state, id, current_user_id).await?;

    let cnt: i64 =
        sqlx::query_scalar("SELECT COUNT(*)::INT8 FROM chat_favorites WHERE user_id = $1")
            .bind(current_user_id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка БД: {}", e),
                )
            })?;

    if cnt >= 5 {
        return Err((StatusCode::BAD_REQUEST, "Лимит избранных чатов: 5".into()));
    }

    sqlx::query(
        "INSERT INTO chat_favorites (user_id, chat_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
    )
    .bind(current_user_id)
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

// ---------------------------
// DELETE /chats/{id}/favorite — убрать чат из избранного
// ---------------------------
async fn remove_favorite(
    State(state): State<AppState>,
    CurrentUser {
        id: current_user_id,
        ..
    }: CurrentUser,
    Path(id): Path<i32>,
) -> Result<StatusCode, (StatusCode, String)> {
    // Только участник чата может менять избранное
    ensure_member(&state, id, current_user_id).await?;

    sqlx::query("DELETE FROM chat_favorites WHERE user_id = $1 AND chat_id = $2")
        .bind(current_user_id)
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

// Параметры удаления чата через query string
#[derive(Deserialize)]
struct DeleteOptions {
    for_all: Option<bool>,
}

#[cfg(test)]
mod tests {
    use super::normalize_member_role;
    use axum::http::StatusCode;

    #[test]
    fn normalize_role_defaults_to_member() {
        let role = normalize_member_role("group", None).expect("role");
        assert_eq!(role, "member");
    }

    #[test]
    fn normalize_role_rejects_owner_for_group() {
        let err = normalize_member_role("group", Some("owner"))
            .expect_err("owner should be rejected for group");
        assert_eq!(err.0, StatusCode::BAD_REQUEST);
    }

    #[test]
    fn normalize_role_accepts_admin_for_channel() {
        let role = normalize_member_role("channel", Some("admin")).expect("role");
        assert_eq!(role, "admin");
    }

    #[test]
    fn normalize_role_trims_and_lowercases() {
        let role = normalize_member_role("channel", Some("  MEMBER  ")).expect("role");
        assert_eq!(role, "member");
    }
}
