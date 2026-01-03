use axum::{
    extract::{Path, State, Query},
    http::StatusCode,
    routing::{delete, get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::Value;
use sqlx::{Postgres, Row, Transaction};

use crate::{AppState};
use crate::models::chats::{Chat, Message, CreateChatRequest, FileMetadata};
use crate::middleware::CurrentUser; // экстрактор текущего пользователя
use crate::middleware::{ensure_member};

// Модели вынесены в crate::models::chats

// Экстракция пользователя теперь делается через CurrentUser

// ---------------------------
// Конструктор роутера
// ---------------------------
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/chats", post(create_chat).get(list_chats))
        .route("/chats/:chat_id/messages", get(get_messages))
        .route("/chats/:id", delete(delete_or_leave_chat))
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
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

        if let Some(row) = existing {
            let chat = Chat {
                id: row.try_get("id").unwrap_or_default(),
                kind: row.try_get::<String,_>("kind").unwrap_or_default(),
                title: row.try_get("title").ok(),
                created_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("created_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
                updated_at: row.try_get::<chrono::DateTime<chrono::Utc>,_>("updated_at").map(|t| t.to_rfc3339()).unwrap_or_default(),
                is_archived: row.try_get("is_archived").ok(),
                peer_id: None,
                peer_username: None,
                peer_avatar: None,
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
                peer_id: None,
                peer_username: None,
                peer_avatar: None,
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
            RETURNING id, kind, title, created_at, updated_at, is_archived
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
            RETURNING id, kind, title, created_at, updated_at, is_archived
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
            .bind(if body.kind == "group" && uid == current_user_id { "admin" } else { "member" })
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
        peer_id: None,
        peer_username: None,
        peer_avatar: None,
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
            peer_id: row.try_get("peer_id").ok(),
            peer_username: row.try_get("peer_username").ok(),
            peer_avatar: row.try_get("peer_avatar").ok(),
        })
        .collect();

    Ok(Json(items))
}

// ---------------------------
// GET /chats/{chat_id}/messages — сообщения чата (только для участников)
// ---------------------------
async fn get_messages(
    State(state): State<AppState>,
    CurrentUser { id: current_user_id }: CurrentUser,
    Path(chat_id): Path<i32>,
) -> Result<Json<Vec<Message>>, (StatusCode, String)> {
    // Проверяем, что пользователь — участник чата (общая утилита)
    ensure_member(&state, chat_id, current_user_id).await?;

    let rows = sqlx::query(
        r#"
        SELECT 
            id::INT8 AS id, 
            chat_id::INT8 AS chat_id, 
            sender_id::INT8 AS sender_id, 
            COALESCE(message, body) AS message,
            COALESCE(message_type, 'text') AS message_type,
            created_at,
            edited_at,
            COALESCE(is_read, false) AS is_read,
            envelopes,
            metadata
        FROM messages
        WHERE chat_id = $1
        ORDER BY created_at ASC
        "#,
    )
    .bind(chat_id)
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
                is_read: row.try_get("is_read").unwrap_or(false),
                has_files,
                metadata: metadata_vec,
                envelopes: row.try_get("envelopes").ok().flatten(),
                status: None,
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

    if kind == "group" {
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

// Параметры удаления чата через query string
#[derive(Deserialize)]
struct DeleteOptions {
    for_all: Option<bool>,
}
