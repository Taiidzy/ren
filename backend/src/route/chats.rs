use axum::{
    extract::{Path, State, Query},
    http::StatusCode,
    routing::{delete, get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{Value, json};
use sqlx::{Postgres, Row, Transaction};

use crate::{AppState};
use crate::models::chats::{Chat, Message, CreateChatRequest, FileMetadata};
use crate::middleware::CurrentUser; // экстрактор текущего пользователя
use crate::middleware::{ensure_member};
use crate::route::ws::{publish_chat, publish_user};

// Модели вынесены в crate::models::chats

// Экстракция пользователя теперь делается через CurrentUser

// ---------------------------
// Конструктор роутера
// ---------------------------
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/chats", post(create_chat).get(list_chats))
        .route("/chats/search", get(search_chats))
        .route("/chats/:chat_id/messages", get(get_messages))
        .route("/chats/:chat_id/participants", get(get_participants))
        .route("/chats/:chat_id/participants", post(add_participant))
        .route(
            "/chats/:chat_id/participants/:user_id",
            delete(remove_participant),
        )
        .route("/chats/:chat_id/leave", post(leave_chat))
        .route("/chats/:chat_id/keys/latest", get(get_latest_key))
        .route("/chats/:chat_id/keys/rotate", post(rotate_key))
        .route("/chats/:id/favorite", post(add_favorite).delete(remove_favorite))
        .route("/chats/:id", delete(delete_or_leave_chat))
}

#[derive(Deserialize)]
struct RotateKeyRequest {
    envelopes: Value,
}

#[derive(serde::Serialize)]
struct ParticipantItem {
    user_id: i32,
    role: String,
    username: String,
    avatar: Option<String>,
    pubk: Option<String>,
}

#[derive(serde::Serialize)]
struct LatestKeyResponse {
    chat_id: i32,
    key_version: i32,
    envelope: Option<Value>,
}

#[derive(serde::Serialize)]
struct ParticipantChangeResponse {
    chat_id: i32,
    rotation_required: bool,
}

#[derive(Deserialize)]
struct AddParticipantRequest {
    user_id: i32,
}

#[derive(Deserialize)]
struct GetMessagesQuery {
    limit: Option<i64>,
    before_id: Option<i64>,
    after_id: Option<i64>,
}

#[derive(Deserialize)]
struct SearchChatsQuery {
    q: String,
    kind: Option<String>,
    limit: Option<i64>,
}

// ---------------------------
// POST /chats — создать чат
// ---------------------------
async fn create_chat(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
    Json(body): Json<CreateChatRequest>,
) -> Result<Json<Chat>, (StatusCode, String)> {
    // Простые проверки
    if body.kind == "private" {
        if body.user_ids.len() != 2 || !body.user_ids.contains(&current_user_id) {
            return Err((StatusCode::BAD_REQUEST, "Для private-чата нужно ровно 2 участника, включая текущего пользователя".into()));
        }
    }

    let mut tx: Transaction<'_, Postgres> = state.pool.begin().await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось начать транзакцию: {}", e)))?;

    // Для private-чата сначала проверим, существует ли уже чат с этой парой (каноническая пара user_a<=user_b)
    if body.kind == "private" {
        let mut a = body.user_ids[0];
        let mut b = body.user_ids[1];
        if a > b { std::mem::swap(&mut a, &mut b); }
        // Сначала пробуем найти по canonical-паре user_a/user_b (новая схема)
        let existing = sqlx::query(
            r#"
            SELECT id, kind, title, created_at, updated_at, is_archived, key_version
            FROM chats
            WHERE kind = 'private' AND user_a = $1 AND user_b = $2
            LIMIT 1
            "#,
        )
        .bind(a)
        .bind(b)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

        if let Some(row) = existing {
            let chat = Chat {
                id: row.try_get("id").unwrap_or_default(),
                kind: row.try_get::<String,_>("kind").unwrap_or_default(),
                title: row.try_get("title").ok(),
                created_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("created_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
                updated_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("updated_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
                is_archived: row.try_get("is_archived").ok(),
                is_favorite: Some(false),
                peer_id: None,
                peer_username: None,
                peer_avatar: None,
                key_version: row.try_get("key_version").ok(),
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
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка добавления участника: {}", e)))?;

            tx.commit().await.ok();
            return Ok(Json(chat));
        }

        // Fallback: если в старых данных user_a/user_b ещё не заполнены, найдём по участникам
        let existing_old = sqlx::query(
            r#"
            SELECT c.id, c.kind, c.title, c.created_at, c.updated_at, c.is_archived, c.key_version
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
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

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
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка добавления участника: {}", e)))?;

            let chat = Chat {
                id: chat_id,
                kind: row.try_get::<String,_>("kind").unwrap_or_default(),
                title: row.try_get("title").ok(),
                created_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("created_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
                updated_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("updated_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
                is_archived: row.try_get("is_archived").ok(),
                is_favorite: Some(false),
                peer_id: None,
                peer_username: None,
                peer_avatar: None,
                key_version: row.try_get("key_version").ok(),
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
        if a > b { std::mem::swap(&mut a, &mut b); }
        sqlx::query(
            r#"
            INSERT INTO chats (kind, title, user_a, user_b)
            VALUES ($1, $2, $3, $4)
            RETURNING id, kind, title, created_at, updated_at, is_archived, key_version
            "#,
        )
        .bind(&body.kind)
        .bind(&body.title)
        .bind(a)
        .bind(b)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка создания чата: {}", e)))?
    } else {
        sqlx::query(
            r#"
            INSERT INTO chats (kind, title)
            VALUES ($1, $2)
            RETURNING id, kind, title, created_at, updated_at, is_archived, key_version
            "#,
        )
        .bind(&body.kind)
        .bind(&body.title)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка создания чата: {}", e)))?
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
            .bind(if (body.kind == "group" || body.kind == "channel") && uid == current_user_id {
                "admin"
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
            r#"INSERT INTO chat_participants (chat_id, user_id, role) VALUES ($1, $2, 'member') ON CONFLICT DO NOTHING"#,
        )
        .bind(chat_id)
        .bind(current_user_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка добавления текущего пользователя: {}", e)))?;
    }

    tx.commit().await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось зафиксировать транзакцию: {}", e)))?;

    let chat = Chat {
        id: chat_id,
        kind: row.try_get::<String,_>("kind").unwrap_or_default(),
        title: row.try_get("title").ok(),
        created_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("created_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
        updated_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("updated_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
        is_archived: row.try_get("is_archived").ok(),
        is_favorite: Some(false),
        peer_id: None,
        peer_username: None,
        peer_avatar: None,
        key_version: row.try_get("key_version").ok(),
    };

    Ok(Json(chat))
}

// ---------------------------
// GET /chats — список чатов текущего пользователя
// ---------------------------
async fn list_chats(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
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
            c.key_version,
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
            u.avatar   AS peer_avatar
        FROM chats c
        JOIN chat_participants p ON p.chat_id = c.id
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
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let items = rows
        .into_iter()
        .map(|row| Chat {
            id: row.try_get("id").unwrap_or_default(),
            kind: row.try_get::<String,_>("kind").unwrap_or_default(),
            title: row.try_get("title").ok(),
            created_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("created_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
            updated_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("updated_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
            is_archived: row.try_get("is_archived").ok(),
            is_favorite: row.try_get::<bool,_>("is_favorite").ok().map(Some).unwrap_or(Some(false)),
            peer_id: row.try_get("peer_id").ok(),
            peer_username: row.try_get("peer_username").ok(),
            peer_avatar: row.try_get("peer_avatar").ok(),
            key_version: row.try_get("key_version").ok(),
        })
        .collect();

    Ok(Json(items))
}

// ---------------------------
// GET /chats/search — глобальный поиск групп/каналов по названию
// ---------------------------
async fn search_chats(
    State(state): State<AppState>,
    CurrentUser { id: _my_id }: CurrentUser,
    Query(params): Query<SearchChatsQuery>,
) -> Result<Json<Vec<Chat>>, (StatusCode, String)> {
    let q = params.q.trim();
    if q.is_empty() {
        return Ok(Json(vec![]));
    }

    let limit = params.limit.unwrap_or(15).clamp(1, 50);
    let like = format!("%{}%", q);

    let kind = params.kind.unwrap_or_else(|| "".to_string()).to_lowercase();
    let kind_filter: Option<&str> = match kind.as_str() {
        "group" => Some("group"),
        "channel" => Some("channel"),
        _ => None,
    };

    let rows = sqlx::query(
        r#"
        SELECT id, kind, title, created_at, updated_at, is_archived, key_version
        FROM chats
        WHERE kind IN ('group', 'channel')
          AND ($2::text IS NULL OR kind = $2::text)
          AND COALESCE(title, '') ILIKE $1
        ORDER BY updated_at DESC
        LIMIT $3
        "#,
    )
    .bind(like)
    .bind(kind_filter)
    .bind(limit)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        out.push(Chat {
            id: row.try_get("id").unwrap_or_default(),
            kind: row.try_get::<String,_>("kind").unwrap_or_default(),
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
            peer_avatar: None,
            key_version: row.try_get("key_version").ok(),
        });
    }

    Ok(Json(out))
}

// ---------------------------
// GET /chats/{chat_id}/participants — участники чата (для E2EE key distribution)
// ---------------------------
async fn get_participants(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
    Path(chat_id): Path<i32>,
) -> Result<Json<Vec<ParticipantItem>>, (StatusCode, String)> {
    ensure_member(&state, chat_id, current_user_id).await?;

    let rows = sqlx::query(
        r#"
        SELECT
            p.user_id,
            COALESCE(p.role, 'member') AS role,
            COALESCE(u.username, u.login) AS username,
            u.avatar,
            u.pubk
        FROM chat_participants p
        JOIN users u ON u.id = p.user_id
        WHERE p.chat_id = $1
        ORDER BY
          CASE WHEN p.role = 'admin' THEN 0 ELSE 1 END,
          u.username ASC
        "#,
    )
    .bind(chat_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        out.push(ParticipantItem {
            user_id: row.try_get("user_id").unwrap_or_default(),
            role: row.try_get::<String,_>("role").unwrap_or_else(|_| "member".to_string()),
            username: row.try_get::<String,_>("username").unwrap_or_default(),
            avatar: row.try_get("avatar").ok(),
            pubk: row.try_get("pubk").ok(),
        });
    }

    Ok(Json(out))
}

// ---------------------------
// POST /chats/{chat_id}/participants — добавить участника (group/channel: только admin)
// body: { user_id }
// ---------------------------
async fn add_participant(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
    Path(chat_id): Path<i32>,
    Json(body): Json<AddParticipantRequest>,
) -> Result<Json<ParticipantChangeResponse>, (StatusCode, String)> {
    // Определяем тип чата
    let kind: Option<String> = sqlx::query_scalar("SELECT kind FROM chats WHERE id = $1")
        .bind(chat_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(kind) = kind else {
        return Err((StatusCode::NOT_FOUND, "Чат не найден".into()));
    };

    // Добавлять участников можно только в group/channel и только админом
    if kind != "group" && kind != "channel" {
        return Err((StatusCode::BAD_REQUEST, "Добавление участников поддерживается только для group/channel".into()));
    }
    crate::middleware::ensure_admin(&state, chat_id, current_user_id).await?;

    // Убедимся, что пользователь существует (иначе внешний ключ даст 500)
    let exists: Option<i32> = sqlx::query_scalar("SELECT id FROM users WHERE id = $1")
        .bind(body.user_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;
    if exists.is_none() {
        return Err((StatusCode::NOT_FOUND, "Пользователь не найден".into()));
    }

    sqlx::query(
        r#"INSERT INTO chat_participants (chat_id, user_id, role)
           VALUES ($1, $2, 'member')
           ON CONFLICT DO NOTHING"#,
    )
    .bind(chat_id)
    .bind(body.user_id)
    .execute(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка добавления участника: {}", e)))?;

    let evt = json!({
        "type": "participants_changed",
        "chat_id": chat_id,
        "action": "added",
        "user_id": body.user_id,
        "rotation_required": kind == "group",
    })
    .to_string();
    publish_chat(&state, chat_id, evt.clone());
    publish_user(&state, body.user_id, evt);

    Ok(Json(ParticipantChangeResponse {
        chat_id,
        rotation_required: kind == "group",
    }))
}

// ---------------------------
// DELETE /chats/{chat_id}/participants/{user_id} — удалить участника (group/channel: только admin)
// ---------------------------
async fn remove_participant(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
    Path((chat_id, user_id)): Path<(i32, i32)>,
) -> Result<Json<ParticipantChangeResponse>, (StatusCode, String)> {
    let kind: Option<String> = sqlx::query_scalar("SELECT kind FROM chats WHERE id = $1")
        .bind(chat_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(kind) = kind else {
        return Err((StatusCode::NOT_FOUND, "Чат не найден".into()));
    };

    if kind != "group" && kind != "channel" {
        return Err((StatusCode::BAD_REQUEST, "Удаление участников поддерживается только для group/channel".into()));
    }
    crate::middleware::ensure_admin(&state, chat_id, current_user_id).await?;

    // Нельзя удалить последнего админа
    let role: Option<String> = sqlx::query_scalar(
        "SELECT role FROM chat_participants WHERE chat_id = $1 AND user_id = $2",
    )
    .bind(chat_id)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(role) = role else {
        return Ok(Json(ParticipantChangeResponse {
            chat_id,
            rotation_required: false,
        }));
    };

    if role == "admin" {
        let admin_cnt: i64 = sqlx::query_scalar(
            "SELECT COUNT(*)::INT8 FROM chat_participants WHERE chat_id = $1 AND role = 'admin'",
        )
        .bind(chat_id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;
        if admin_cnt <= 1 {
            return Err((StatusCode::BAD_REQUEST, "Нельзя удалить последнего admin".into()));
        }
    }

    sqlx::query("DELETE FROM chat_participants WHERE chat_id = $1 AND user_id = $2")
        .bind(chat_id)
        .bind(user_id)
        .execute(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка удаления участника: {}", e)))?;

    let evt = json!({
        "type": "participants_changed",
        "chat_id": chat_id,
        "action": "removed",
        "user_id": user_id,
        "rotation_required": kind == "group",
    })
    .to_string();
    publish_chat(&state, chat_id, evt.clone());
    publish_user(&state, user_id, evt);

    Ok(Json(ParticipantChangeResponse {
        chat_id,
        rotation_required: kind == "group",
    }))
}

// ---------------------------
// POST /chats/{chat_id}/leave — покинуть чат (group/channel)
// ---------------------------
async fn leave_chat(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
    Path(chat_id): Path<i32>,
) -> Result<Json<ParticipantChangeResponse>, (StatusCode, String)> {
    ensure_member(&state, chat_id, current_user_id).await?;

    let kind: Option<String> = sqlx::query_scalar("SELECT kind FROM chats WHERE id = $1")
        .bind(chat_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(kind) = kind else {
        return Err((StatusCode::NOT_FOUND, "Чат не найден".into()));
    };
    if kind != "group" && kind != "channel" {
        return Err((StatusCode::BAD_REQUEST, "leave поддерживается только для group/channel".into()));
    }

    // Если админов больше нет — запрещаем уход последнего админа
    let my_role: Option<String> = sqlx::query_scalar(
        "SELECT role FROM chat_participants WHERE chat_id = $1 AND user_id = $2",
    )
    .bind(chat_id)
    .bind(current_user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    if my_role.as_deref() == Some("admin") {
        let admin_cnt: i64 = sqlx::query_scalar(
            "SELECT COUNT(*)::INT8 FROM chat_participants WHERE chat_id = $1 AND role = 'admin'",
        )
        .bind(chat_id)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;
        if admin_cnt <= 1 {
            return Err((StatusCode::BAD_REQUEST, "Нельзя покинуть чат: вы последний admin".into()));
        }
    }

    sqlx::query("DELETE FROM chat_participants WHERE chat_id = $1 AND user_id = $2")
        .bind(chat_id)
        .bind(current_user_id)
        .execute(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка выхода из чата: {}", e)))?;

    let evt = json!({
        "type": "participants_changed",
        "chat_id": chat_id,
        "action": "left",
        "user_id": current_user_id,
        "rotation_required": kind == "group",
    })
    .to_string();
    publish_chat(&state, chat_id, evt);

    Ok(Json(ParticipantChangeResponse {
        chat_id,
        rotation_required: kind == "group",
    }))
}

// ---------------------------
// GET /chats/{chat_id}/keys/latest — получить конверт текущего ключа для себя
// ---------------------------
async fn get_latest_key(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
    Path(chat_id): Path<i32>,
) -> Result<Json<LatestKeyResponse>, (StatusCode, String)> {
    ensure_member(&state, chat_id, current_user_id).await?;

    let row = sqlx::query(
        r#"
        SELECT ck.key_version, ck.envelopes
        FROM chat_keys ck
        WHERE ck.chat_id = $1
        ORDER BY ck.key_version DESC
        LIMIT 1
        "#,
    )
    .bind(chat_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(row) = row else {
        return Ok(Json(LatestKeyResponse { chat_id, key_version: 0, envelope: None }));
    };

    let key_version: i32 = row.try_get("key_version").unwrap_or(0);
    let envelopes: Value = row.try_get("envelopes").unwrap_or(Value::Null);

    let envelope = envelopes
        .get(current_user_id.to_string())
        .cloned();

    Ok(Json(LatestKeyResponse { chat_id, key_version, envelope }))
}

// ---------------------------
// POST /chats/{chat_id}/keys/rotate — ротация ключа (только admin, group only)
// body: { envelopes: {"userId": {key, ephem_pub_key, iv}, ...} }
// ---------------------------
async fn rotate_key(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
    Path(chat_id): Path<i32>,
    Json(body): Json<RotateKeyRequest>,
) -> Result<Json<LatestKeyResponse>, (StatusCode, String)> {
    crate::middleware::ensure_admin(&state, chat_id, current_user_id).await?;

    // Only group chats require rotation; channels are static.
    let kind: Option<String> = sqlx::query_scalar("SELECT kind FROM chats WHERE id = $1")
        .bind(chat_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(kind) = kind else {
        return Err((StatusCode::NOT_FOUND, "Чат не найден".into()));
    };
    if kind != "group" {
        return Err((StatusCode::BAD_REQUEST, "Ротация ключа поддерживается только для group-чата".into()));
    }

    if !body.envelopes.is_object() {
        return Err((StatusCode::BAD_REQUEST, "envelopes должен быть JSON-объектом".into()));
    }

    let mut tx: Transaction<'_, Postgres> = state.pool.begin().await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось начать транзакцию: {}", e)))?;

    let new_version: i32 = sqlx::query_scalar(
        "UPDATE chats SET key_version = key_version + 1 WHERE id = $1 RETURNING key_version",
    )
    .bind(chat_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    sqlx::query(
        r#"INSERT INTO chat_keys (chat_id, key_version, envelopes) VALUES ($1, $2, $3)"#,
    )
    .bind(chat_id)
    .bind(new_version)
    .bind(&body.envelopes)
    .execute(&mut *tx)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    tx.commit().await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось зафиксировать транзакцию: {}", e)))?;

    let evt = json!({
        "type": "chat_key_rotated",
        "chat_id": chat_id,
        "key_version": new_version,
    })
    .to_string();
    publish_chat(&state, chat_id, evt);

    let envelope = body.envelopes.get(current_user_id.to_string()).cloned();
    Ok(Json(LatestKeyResponse { chat_id, key_version: new_version, envelope }))
}

// ---------------------------
// GET /chats/{chat_id}/messages — сообщения чата (только для участников)
// ---------------------------
async fn get_messages(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
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
                COALESCE(key_version, 0) AS key_version,
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
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let items: Vec<Message> = rows
        .into_iter()
        .map(|row| {
            let metadata_value: Option<Value> = row.try_get("metadata").ok().flatten();
            let metadata_vec: Option<Vec<FileMetadata>> = metadata_value
                .and_then(|v| serde_json::from_value(v).ok());
            
            let has_files = metadata_vec.as_ref().map(|m| !m.is_empty());
            
            Message {
                id: row.try_get("id").unwrap_or_default(),
                chat_id: row.try_get("chat_id").unwrap_or_default(),
                sender_id: row.try_get("sender_id").unwrap_or_default(),
                message: row.try_get("message").unwrap_or_default(),
                message_type: row.try_get("message_type").unwrap_or_else(|_| "text".to_string()),
                created_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("created_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
                edited_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("edited_at").ok().map(|t| t.to_rfc3339()),
                reply_to_message_id: row.try_get("reply_to_message_id").ok(),
                forwarded_from_message_id: row.try_get("forwarded_from_message_id").ok(),
                forwarded_from_chat_id: row.try_get("forwarded_from_chat_id").ok(),
                forwarded_from_sender_id: row.try_get("forwarded_from_sender_id").ok(),
                deleted_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>,_>("deleted_at")
                    .ok()
                    .map(|t| t.to_rfc3339()),
                deleted_by: row.try_get("deleted_by").ok(),
                is_read: row.try_get("is_read").unwrap_or(false),
                has_files,
                metadata: metadata_vec,
                envelopes: row.try_get("envelopes").ok().flatten(),
                status: None,
                key_version: row.try_get::<i32,_>("key_version").ok(),
            }
        })
        .collect();

    Ok(Json(items))
}

// ---------------------------
// DELETE /chats/{id}
// Группы: только admin может удалить чат (полностью). Private: выходим из чата (удаляем участника).
// ---------------------------
async fn delete_or_leave_chat(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
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
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(row) = row else { return Err((StatusCode::NOT_FOUND, "Чат не найден".into())); };
    let kind: String = row.try_get("kind").unwrap_or_default();
    let _role: String = row.try_get("role").unwrap_or_else(|_| "member".to_string());

    if kind == "group" || kind == "channel" {
        // Удалять весь чат может только администратор — проверяем через общую утилиту
        crate::middleware::ensure_admin(&state, id, current_user_id).await?;
        sqlx::query("DELETE FROM chats WHERE id = $1")
            .bind(id)
            .execute(&state.pool)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка удаления чата: {}", e)))?;
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
                .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка удаления приватного чата: {}", e)))?;
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
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка выхода из чата: {}", e)))?;

        // Если участников больше нет — удаляем сам чат (упрощённо, вместо фонового джоба)
        let participants_left: Option<i64> = sqlx::query_scalar(
            "SELECT COUNT(*) FROM chat_participants WHERE chat_id = $1",
        )
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

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
    CurrentUser { id: current_user_id }: CurrentUser,
    Path(id): Path<i32>,
) -> Result<StatusCode, (StatusCode, String)> {
    // Только участник чата может добавлять в избранное
    ensure_member(&state, id, current_user_id).await?;

    let cnt: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)::INT8 FROM chat_favorites WHERE user_id = $1",
    )
    .bind(current_user_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

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
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------
// DELETE /chats/{id}/favorite — убрать чат из избранного
// ---------------------------
async fn remove_favorite(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
    Path(id): Path<i32>,
) -> Result<StatusCode, (StatusCode, String)> {
    // Только участник чата может менять избранное
    ensure_member(&state, id, current_user_id).await?;

    sqlx::query("DELETE FROM chat_favorites WHERE user_id = $1 AND chat_id = $2")
        .bind(current_user_id)
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    Ok(StatusCode::NO_CONTENT)
}

// Параметры удаления чата через query string
#[derive(Deserialize)]
struct DeleteOptions {
    for_all: Option<bool>,
}
