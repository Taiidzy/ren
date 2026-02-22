use axum::{
    Router,
    extract::State,
    extract::ws::{Message as WsMessage, WebSocket, WebSocketUpgrade},
    response::IntoResponse,
    routing::get,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;
use std::collections::{HashMap, HashSet};
use tokio::{
    sync::{broadcast, mpsc},
    task::JoinHandle,
};

use crate::AppState;
use crate::middleware::{CurrentUser, ensure_can_send_message, ensure_member};
use crate::models::auth::UserResponse;
use crate::models::chats::{FileMetadata, Message};

pub fn router() -> Router<AppState> {
    Router::new().route("/ws", get(ws_handler))
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    CurrentUser { id: user_id, .. }: CurrentUser,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state, user_id))
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ClientEvent {
    Init {
        contacts: Vec<i32>,
    },
    JoinChat {
        chat_id: i32,
    },
    LeaveChat {
        chat_id: i32,
    },
    SendMessage {
        chat_id: i32,
        message: String,                     // зашифрованное сообщение
        message_type: Option<String>,        // 'text' | 'file' | 'image' и т.д.
        envelopes: Option<Value>,            // JSON объект с конвертами для каждого участника
        metadata: Option<Vec<FileMetadata>>, // метаданные файлов
        reply_to_message_id: Option<i64>,
    },
    VoiceMessage {
        chat_id: i32,
        message: String,
        message_type: Option<String>,
        envelopes: Option<Value>,
        metadata: Option<Vec<FileMetadata>>,
        reply_to_message_id: Option<i64>,
    },
    VideoMessage {
        chat_id: i32,
        message: String,
        message_type: Option<String>,
        envelopes: Option<Value>,
        metadata: Option<Vec<FileMetadata>>,
        reply_to_message_id: Option<i64>,
    },
    EditMessage {
        chat_id: i32,
        message_id: i64,
        message: String,
        message_type: Option<String>,
        envelopes: Option<Value>,
        metadata: Option<Vec<FileMetadata>>,
    },
    DeleteMessage {
        chat_id: i32,
        message_id: i64,
    },
    ForwardMessage {
        from_chat_id: i32,
        message_id: i64,
        to_chat_id: i32,
        message: String,
        message_type: Option<String>,
        envelopes: Option<Value>,
        metadata: Option<Vec<FileMetadata>>,
    },
    Typing {
        chat_id: i32,
        is_typing: bool,
    },
}

#[derive(Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ServerEvent<'a> {
    Ok,
    Error {
        error: &'a str,
    },
    MessageNew {
        chat_id: i32,
        message: OutMessage,
    },
    MessageUpdated {
        chat_id: i32,
        message: OutMessage,
    },
    MessageDeleted {
        chat_id: i32,
        message_id: i64,
        deleted_at: String,
        deleted_by: i64,
    },
    Typing {
        chat_id: i32,
        user_id: i32,
        is_typing: bool,
    },
    Presence {
        user_id: i32,
        status: &'a str,
    }, // online/offline (глобальная)
    ProfileUpdated {
        user: UserResponse,
    },
}

// OutMessage теперь использует структуру Message из models
type OutMessage = Message;

struct Subscriptions {
    joined: HashSet<i32>,
    forwarders: HashMap<i32, JoinHandle<()>>, // chat_id -> task handle
    // Глобальная подписка на личный канал пользователя
    user_forwarder: Option<JoinHandle<()>>,
    contacts: HashSet<i32>,
}

pub async fn publish_profile_updated_for_user(
    state: &AppState,
    user_id: i32,
) -> Result<(), (axum::http::StatusCode, String)> {
    let row = sqlx::query(
        r#"
        SELECT id, login, username, avatar
        FROM users
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let Some(row) = row else {
        return Err((
            axum::http::StatusCode::NOT_FOUND,
            "Пользователь не найден".into(),
        ));
    };

    let user = UserResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        avatar: row.try_get("avatar").ok(),
    };

    let payload = serde_json::to_string(&ServerEvent::ProfileUpdated { user }).map_err(|_| {
        (
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            "Ошибка сериализации".to_string(),
        )
    })?;

    let mut recipients = HashSet::<i32>::new();
    recipients.insert(user_id);
    let rows = sqlx::query(
        r#"
        SELECT DISTINCT cp2.user_id
        FROM chat_participants cp1
        JOIN chat_participants cp2 ON cp2.chat_id = cp1.chat_id
        WHERE cp1.user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        (
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    for r in rows {
        let uid: i32 = r.try_get("user_id").unwrap_or_default();
        if uid > 0 {
            recipients.insert(uid);
        }
    }

    for uid in recipients {
        if state.user_hub.get(&uid).is_none() {
            let (txc, _rx) = broadcast::channel::<String>(200);
            state.user_hub.insert(uid, txc);
        }
        if let Some(entry) = state.user_hub.get(&uid) {
            let _ = entry.send(payload.clone());
        }
    }

    Ok(())
}

async fn handle_socket(socket: WebSocket, state: AppState, user_id: i32) {
    // Канал для записи в websocket из разных задач
    let (out_tx, mut out_rx) = mpsc::unbounded_channel::<WsMessage>();

    // Разделяем ws на writer/reader
    let (mut ws_sender, mut ws_receiver) = socket.split();

    // Задача writer: отправляет всё, что приходит в out_rx, в сокет
    let writer = tokio::spawn(async move {
        while let Some(msg) = out_rx.recv().await {
            if ws_sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    let mut subs = Subscriptions {
        joined: HashSet::new(),
        forwarders: HashMap::new(),
        user_forwarder: None,
        contacts: HashSet::new(),
    };

    // Отмечаем онлайн-состояние c поддержкой нескольких активных сокетов одного пользователя.
    let was_offline = match state.online_connections.get_mut(&user_id) {
        Some(mut cnt) => {
            *cnt += 1;
            false
        }
        None => {
            state.online_connections.insert(user_id, 1);
            true
        }
    };
    let mut should_announce_online = was_offline;

    // Хелпер: публикация события в конкретный чат
    let publish = |state: &AppState, chat_id: i32, payload: String| {
        if let Some(entry) = state.ws_hub.get(&chat_id) {
            let _ = entry.send(payload);
        }
    };

    // Хелпер: публикация события в личный канал пользователя
    let publish_user = |state: &AppState, target_user_id: i32, payload: String| {
        if let Some(entry) = state.user_hub.get(&target_user_id) {
            let _ = entry.send(payload);
        }
    };

    let ensure_user_channel = |state: &AppState, target_user_id: i32| {
        if state.user_hub.get(&target_user_id).is_none() {
            let (tx, _rx) = broadcast::channel::<String>(200);
            state.user_hub.insert(target_user_id, tx);
        }
    };

    let is_user_online = |state: &AppState, target_user_id: i32| -> bool {
        state
            .online_connections
            .get(&target_user_id)
            .map(|c| *c > 0)
            .unwrap_or(false)
    };

    // Подписываем каждое соединение на личный канал пользователя сразу после апгрейда.
    ensure_user_channel(&state, user_id);
    let tx = state.user_hub.get(&user_id).unwrap().clone();
    let mut rx = tx.subscribe();
    let out_tx_clone = out_tx.clone();
    subs.user_forwarder = Some(tokio::spawn(async move {
        while let Ok(msg) = rx.recv().await {
            let _ = out_tx_clone.send(WsMessage::Text(msg));
        }
    }));

    // Обработка входящих сообщений клиента
    while let Some(Ok(msg)) = ws_receiver.next().await {
        match msg {
            WsMessage::Text(text) => {
                let parsed: Result<ClientEvent, _> = serde_json::from_str(&text);
                match parsed {
                    Ok(ClientEvent::Init { contacts }) => {
                        let next_contacts: HashSet<i32> = contacts.into_iter().collect();
                        let old_contacts = std::mem::replace(&mut subs.contacts, next_contacts);

                        // Отправляем снимок online/offline по текущим контактам инициатору.
                        for cid in &subs.contacts {
                            let status = if is_user_online(&state, *cid) {
                                "online"
                            } else {
                                "offline"
                            };
                            if let Ok(evt) = serde_json::to_string(&ServerEvent::Presence {
                                user_id: *cid,
                                status,
                            }) {
                                let _ = out_tx.send(WsMessage::Text(evt));
                            }
                        }

                        // Оповещаем контакты о нашем online:
                        // 1) при первом онлайн сокете — всех старых/новых контактов;
                        // 2) при обновлении списка — только новых.
                        let contacts_to_notify = if should_announce_online {
                            subs.contacts
                                .union(&old_contacts)
                                .copied()
                                .collect::<HashSet<_>>()
                        } else {
                            subs.contacts
                                .difference(&old_contacts)
                                .copied()
                                .collect::<HashSet<_>>()
                        };

                        if !contacts_to_notify.is_empty() {
                            let presence_evt = match serde_json::to_string(&ServerEvent::Presence {
                                user_id,
                                status: "online",
                            }) {
                                Ok(s) => s,
                                Err(_) => {
                                    let _ = out_tx.send(WsMessage::Text(
                                            serde_json::to_string(&ServerEvent::Error {
                                                error: "Ошибка сериализации",
                                            })
                                            .unwrap_or_else(|_| {
                                                "{\"type\":\"error\",\"error\":\"Ошибка сериализации\"}"
                                                    .to_string()
                                            }),
                                        ));
                                    continue;
                                }
                            };

                            for cid in contacts_to_notify {
                                ensure_user_channel(&state, cid);
                                publish_user(&state, cid, presence_evt.clone());
                            }
                            should_announce_online = false;
                        }

                        let ok_msg = serde_json::to_string(&ServerEvent::Ok)
                            .unwrap_or_else(|_| "{\"type\":\"ok\"}".to_string());
                        let _ = out_tx.send(WsMessage::Text(ok_msg));
                    }
                    Ok(ClientEvent::JoinChat { chat_id }) => {
                        if let Err(e) = ensure_member(&state, chat_id, user_id).await {
                            let err_msg =
                                serde_json::to_string(&ServerEvent::Error { error: &e.1 })
                                    .unwrap_or_else(|_| {
                                        format!(
                                            "{{\"type\":\"error\",\"error\":{}}}",
                                            serde_json::to_string(&e.1)
                                                .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                        )
                                    });
                            let _ = out_tx.send(WsMessage::Text(err_msg));
                            continue;
                        }
                        // Получаем или создаём broadcaster для чата
                        let tx = match state.ws_hub.get(&chat_id) {
                            Some(existing) => existing.clone(),
                            None => {
                                let (tx, _rx) = broadcast::channel::<String>(200);
                                state.ws_hub.insert(chat_id, tx);
                                state.ws_hub.get(&chat_id).unwrap().clone()
                            }
                        };
                        // Подписываемся и создаём форвардер в out_tx
                        let mut rx = tx.subscribe();
                        let out_tx_clone = out_tx.clone();
                        let handle = tokio::spawn(async move {
                            while let Ok(msg) = rx.recv().await {
                                let _ = out_tx_clone.send(WsMessage::Text(msg));
                            }
                        });
                        subs.joined.insert(chat_id);
                        subs.forwarders.insert(chat_id, handle);
                        let ok_msg = serde_json::to_string(&ServerEvent::Ok)
                            .unwrap_or_else(|_| "{\"type\":\"ok\"}".to_string());
                        let _ = out_tx.send(WsMessage::Text(ok_msg));
                    }
                    Ok(ClientEvent::LeaveChat { chat_id }) => {
                        if subs.joined.remove(&chat_id) {
                            if let Some(h) = subs.forwarders.remove(&chat_id) {
                                h.abort();
                            }
                        }
                        let ok_msg = serde_json::to_string(&ServerEvent::Ok)
                            .unwrap_or_else(|_| "{\"type\":\"ok\"}".to_string());
                        let _ = out_tx.send(WsMessage::Text(ok_msg));
                    }
                    Ok(ClientEvent::Typing { chat_id, is_typing }) => {
                        if subs.joined.contains(&chat_id) {
                            if let Ok(evt) = serde_json::to_string(&ServerEvent::Typing {
                                chat_id,
                                user_id,
                                is_typing,
                            }) {
                                publish(&state, chat_id, evt);
                            }
                        }
                    }
                    Ok(ClientEvent::SendMessage {
                        chat_id,
                        message,
                        message_type,
                        envelopes,
                        metadata,
                        reply_to_message_id,
                    })
                    | Ok(ClientEvent::VoiceMessage {
                        chat_id,
                        message,
                        message_type,
                        envelopes,
                        metadata,
                        reply_to_message_id,
                    })
                    | Ok(ClientEvent::VideoMessage {
                        chat_id,
                        message,
                        message_type,
                        envelopes,
                        metadata,
                        reply_to_message_id,
                    }) => {
                        if let Err(e) = ensure_can_send_message(&state, chat_id, user_id).await {
                            let err_msg =
                                serde_json::to_string(&ServerEvent::Error { error: &e.1 })
                                    .unwrap_or_else(|_| {
                                        format!(
                                            "{{\"type\":\"error\",\"error\":{}}}",
                                            serde_json::to_string(&e.1)
                                                .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                        )
                                    });
                            let _ = out_tx.send(WsMessage::Text(err_msg));
                            continue;
                        }

                        let msg_type = message_type.unwrap_or_else(|| "text".to_string());
                        let has_files = metadata.as_ref().map(|m| !m.is_empty());

                        // Сериализуем envelopes и metadata в JSON
                        let envelopes_json =
                            envelopes.map(|v| serde_json::to_value(v).ok()).flatten();
                        let metadata_json = metadata
                            .as_ref()
                            .map(|m| serde_json::to_value(m).ok())
                            .flatten();

                        // Сохраняем сообщение в БД
                        let row = match sqlx::query(
                            r#"
                            INSERT INTO messages (chat_id, sender_id, message, message_type, envelopes, metadata, reply_to_message_id)
                            VALUES ($1, $2, $3, $4, $5, $6, $7)
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
                                envelopes,
                                metadata
                            "#,
                        )
                        .bind(chat_id)
                        .bind(user_id)
                        .bind(&message)
                        .bind(&msg_type)
                        .bind(&envelopes_json)
                        .bind(&metadata_json)
                        .bind(reply_to_message_id.map(|v| v as i32))
                        .fetch_one(&state.pool)
                        .await {
                            Ok(r) => r,
                            Err(e) => {
                                let err_txt = format!("Ошибка БД: {}", e);
                                let err_msg = serde_json::to_string(&ServerEvent::Error { error: &err_txt })
                                    .unwrap_or_else(|_| format!("{{\"type\":\"error\",\"error\":{}}}", serde_json::to_string(&err_txt).unwrap_or_else(|_| "\"Ошибка\"".to_string())));
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                        };

                        // Десериализуем envelopes и metadata обратно
                        let envelopes_value: Option<Value> =
                            row.try_get("envelopes").ok().flatten();
                        let metadata_value: Option<Value> = row.try_get("metadata").ok().flatten();
                        let metadata_vec: Option<Vec<FileMetadata>> =
                            metadata_value.and_then(|v| serde_json::from_value(v).ok());

                        let msg = OutMessage {
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
                            forwarded_from_message_id: row
                                .try_get("forwarded_from_message_id")
                                .ok(),
                            forwarded_from_chat_id: row.try_get("forwarded_from_chat_id").ok(),
                            forwarded_from_sender_id: row.try_get("forwarded_from_sender_id").ok(),
                            deleted_at: row
                                .try_get::<chrono::DateTime<chrono::Utc>, _>("deleted_at")
                                .ok()
                                .map(|t| t.to_rfc3339()),
                            deleted_by: row.try_get("deleted_by").ok(),
                            is_read: row.try_get("is_read").unwrap_or(false),
                            has_files,
                            metadata: metadata_vec,
                            envelopes: envelopes_value,
                            status: Some("sent".to_string()),
                        };
                        // Полная синхронизация идёт через личные user-каналы:
                        // все онлайн-устройства всех участников получают message_new.
                        let evt_message_new = serde_json::to_string(&ServerEvent::MessageNew {
                            chat_id,
                            message: msg.clone(),
                        })
                        .ok();

                        let rows = sqlx::query(
                            r#"SELECT user_id FROM chat_participants WHERE chat_id = $1"#,
                        )
                        .bind(chat_id)
                        .fetch_all(&state.pool)
                        .await;

                        if let Ok(participants) = rows {
                            for r in participants {
                                let uid: i32 = r.try_get("user_id").unwrap_or_default();
                                if uid <= 0 {
                                    continue;
                                }

                                if !is_user_online(&state, uid) {
                                    continue;
                                }

                                ensure_user_channel(&state, uid);

                                if let Some(evt) = &evt_message_new {
                                    publish_user(&state, uid, evt.clone());
                                }
                            }
                        }
                    }
                    Ok(ClientEvent::EditMessage {
                        chat_id,
                        message_id,
                        message,
                        message_type,
                        envelopes,
                        metadata,
                    }) => {
                        if !subs.joined.contains(&chat_id) {
                            if let Err(e) = ensure_member(&state, chat_id, user_id).await {
                                let err_msg =
                                    serde_json::to_string(&ServerEvent::Error { error: &e.1 })
                                        .unwrap_or_else(|_| {
                                            format!(
                                                "{{\"type\":\"error\",\"error\":{}}}",
                                                serde_json::to_string(&e.1)
                                                    .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                            )
                                        });
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                        }

                        // Только автор может редактировать. Нельзя редактировать удалённое.
                        let envelopes_value = envelopes.clone();
                        let metadata_json = match metadata {
                            Some(ref v) => serde_json::to_value(v).ok(),
                            None => None,
                        };
                        let has_files = metadata.as_ref().map(|v| !v.is_empty()).unwrap_or(false);

                        let updated = sqlx::query(
                            r#"
                            UPDATE messages
                            SET message = $1,
                                message_type = $2,
                                envelopes = $3,
                                metadata = $4,
                                edited_at = now()
                            WHERE id = $5
                              AND chat_id = $6
                              AND sender_id = $7
                              AND deleted_at IS NULL
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
                                envelopes,
                                metadata
                            "#,
                        )
                        .bind(&message)
                        .bind(&message_type)
                        .bind(&envelopes_value)
                        .bind(&metadata_json)
                        .bind(message_id)
                        .bind(chat_id)
                        .bind(user_id)
                        .fetch_optional(&state.pool)
                        .await;

                        let row = match updated {
                            Ok(Some(r)) => r,
                            Ok(None) => {
                                let err_msg = serde_json::to_string(&ServerEvent::Error {
                                    error: "Сообщение не найдено",
                                })
                                .unwrap_or_else(|_| {
                                    "{\"type\":\"error\",\"error\":\"Сообщение не найдено\"}"
                                        .to_string()
                                });
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                            Err(e) => {
                                let err_txt = format!("Ошибка БД: {}", e);
                                let err_msg =
                                    serde_json::to_string(&ServerEvent::Error { error: &err_txt })
                                        .unwrap_or_else(|_| {
                                            format!(
                                                "{{\"type\":\"error\",\"error\":{}}}",
                                                serde_json::to_string(&err_txt)
                                                    .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                            )
                                        });
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                        };

                        let envelopes_value: Option<Value> =
                            row.try_get("envelopes").ok().flatten();
                        let metadata_value: Option<Value> = row.try_get("metadata").ok().flatten();
                        let metadata_vec: Option<Vec<FileMetadata>> =
                            metadata_value.and_then(|v| serde_json::from_value(v).ok());

                        let msg = OutMessage {
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
                            is_read: row.try_get("is_read").unwrap_or(false),
                            reply_to_message_id: row.try_get("reply_to_message_id").ok(),
                            forwarded_from_message_id: row
                                .try_get("forwarded_from_message_id")
                                .ok(),
                            forwarded_from_chat_id: row.try_get("forwarded_from_chat_id").ok(),
                            forwarded_from_sender_id: row.try_get("forwarded_from_sender_id").ok(),
                            deleted_at: row
                                .try_get::<chrono::DateTime<chrono::Utc>, _>("deleted_at")
                                .ok()
                                .map(|t| t.to_rfc3339()),
                            deleted_by: row.try_get("deleted_by").ok(),
                            has_files: Some(has_files),
                            metadata: metadata_vec,
                            envelopes: envelopes_value,
                            status: Some("sent".to_string()),
                        };

                        let evt = match serde_json::to_string(&ServerEvent::MessageUpdated {
                            chat_id,
                            message: msg,
                        }) {
                            Ok(s) => s,
                            Err(_) => {
                                let err_msg = serde_json::to_string(&ServerEvent::Error {
                                    error: "Ошибка сериализации",
                                })
                                .unwrap_or_else(|_| {
                                    "{\"type\":\"error\",\"error\":\"Ошибка сериализации\"}"
                                        .to_string()
                                });
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                        };

                        let participants = sqlx::query(
                            r#"
                            SELECT user_id
                            FROM chat_participants
                            WHERE chat_id = $1
                            "#,
                        )
                        .bind(chat_id)
                        .fetch_all(&state.pool)
                        .await;

                        if let Ok(rows) = participants {
                            for r in rows {
                                let uid: i32 = r.try_get("user_id").unwrap_or_default();
                                if uid <= 0 {
                                    continue;
                                }
                                if !is_user_online(&state, uid) {
                                    continue;
                                }
                                ensure_user_channel(&state, uid);
                                publish_user(&state, uid, evt.clone());
                            }
                        }
                    }
                    Ok(ClientEvent::DeleteMessage {
                        chat_id,
                        message_id,
                    }) => {
                        if !subs.joined.contains(&chat_id) {
                            if let Err(e) = ensure_member(&state, chat_id, user_id).await {
                                let err_msg =
                                    serde_json::to_string(&ServerEvent::Error { error: &e.1 })
                                        .unwrap_or_else(|_| {
                                            format!(
                                                "{{\"type\":\"error\",\"error\":{}}}",
                                                serde_json::to_string(&e.1)
                                                    .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                            )
                                        });
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                        }

                        let updated = sqlx::query(
                            r#"
                            UPDATE messages
                            SET deleted_at = now(), deleted_by = $3
                            WHERE id = $1 AND chat_id = $2
                            RETURNING deleted_at
                            "#,
                        )
                        .bind(message_id as i32)
                        .bind(chat_id)
                        .bind(user_id)
                        .fetch_optional(&state.pool)
                        .await;

                        let row = match updated {
                            Ok(r) => r,
                            Err(e) => {
                                let err_txt = format!("Ошибка БД: {}", e);
                                let err_msg =
                                    serde_json::to_string(&ServerEvent::Error { error: &err_txt })
                                        .unwrap_or_else(|_| {
                                            format!(
                                                "{{\"type\":\"error\",\"error\":{}}}",
                                                serde_json::to_string(&err_txt)
                                                    .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                            )
                                        });
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                        };

                        let Some(row) = row else {
                            let err_msg = serde_json::to_string(&ServerEvent::Error {
                                error: "Сообщение не найдено",
                            })
                            .unwrap_or_else(|_| {
                                "{\"type\":\"error\",\"error\":\"Сообщение не найдено\"}"
                                    .to_string()
                            });
                            let _ = out_tx.send(WsMessage::Text(err_msg));
                            continue;
                        };

                        let deleted_at = row
                            .try_get::<chrono::DateTime<chrono::Utc>, _>("deleted_at")
                            .map(|t| t.to_rfc3339())
                            .unwrap_or_default();

                        let evt = match serde_json::to_string(&ServerEvent::MessageDeleted {
                            chat_id,
                            message_id,
                            deleted_at,
                            deleted_by: user_id as i64,
                        }) {
                            Ok(s) => s,
                            Err(_) => {
                                let err_msg = serde_json::to_string(&ServerEvent::Error {
                                    error: "Ошибка сериализации",
                                })
                                .unwrap_or_else(|_| {
                                    "{\"type\":\"error\",\"error\":\"Ошибка сериализации\"}"
                                        .to_string()
                                });
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                        };

                        // Realtime всем онлайн-участникам через личные каналы.
                        let participants = sqlx::query(
                            r#"
                            SELECT user_id
                            FROM chat_participants
                            WHERE chat_id = $1
                            "#,
                        )
                        .bind(chat_id)
                        .fetch_all(&state.pool)
                        .await;

                        if let Ok(rows) = participants {
                            for r in rows {
                                let uid: i32 = r.try_get("user_id").unwrap_or_default();
                                if uid <= 0 {
                                    continue;
                                }
                                if !is_user_online(&state, uid) {
                                    continue;
                                }
                                ensure_user_channel(&state, uid);
                                publish_user(&state, uid, evt.clone());
                            }
                        }
                    }
                    Ok(ClientEvent::ForwardMessage {
                        from_chat_id,
                        message_id,
                        to_chat_id,
                        message,
                        message_type,
                        envelopes,
                        metadata,
                    }) => {
                        // Должен быть участником и исходного, и целевого чата
                        if let Err(e) = ensure_member(&state, from_chat_id, user_id).await {
                            let err_msg =
                                serde_json::to_string(&ServerEvent::Error { error: &e.1 })
                                    .unwrap_or_else(|_| {
                                        format!(
                                            "{{\"type\":\"error\",\"error\":{}}}",
                                            serde_json::to_string(&e.1)
                                                .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                        )
                                    });
                            let _ = out_tx.send(WsMessage::Text(err_msg));
                            continue;
                        }
                        if let Err(e) = ensure_can_send_message(&state, to_chat_id, user_id).await
                        {
                            let err_msg =
                                serde_json::to_string(&ServerEvent::Error { error: &e.1 })
                                    .unwrap_or_else(|_| {
                                        format!(
                                            "{{\"type\":\"error\",\"error\":{}}}",
                                            serde_json::to_string(&e.1)
                                                .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                        )
                                    });
                            let _ = out_tx.send(WsMessage::Text(err_msg));
                            continue;
                        }

                        // Получаем автора исходного сообщения
                        let src = sqlx::query(
                            r#"
                            SELECT sender_id::INT8 AS sender_id
                            FROM messages
                            WHERE id = $1 AND chat_id = $2
                            LIMIT 1
                            "#,
                        )
                        .bind(message_id as i32)
                        .bind(from_chat_id)
                        .fetch_optional(&state.pool)
                        .await;

                        let src = match src {
                            Ok(r) => r,
                            Err(e) => {
                                let err_txt = format!("Ошибка БД: {}", e);
                                let err_msg =
                                    serde_json::to_string(&ServerEvent::Error { error: &err_txt })
                                        .unwrap_or_else(|_| {
                                            format!(
                                                "{{\"type\":\"error\",\"error\":{}}}",
                                                serde_json::to_string(&err_txt)
                                                    .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                            )
                                        });
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                        };

                        let Some(src_row) = src else {
                            let err_msg = serde_json::to_string(&ServerEvent::Error {
                                error: "Исходное сообщение не найдено",
                            })
                            .unwrap_or_else(|_| {
                                "{\"type\":\"error\",\"error\":\"Исходное сообщение не найдено\"}"
                                    .to_string()
                            });
                            let _ = out_tx.send(WsMessage::Text(err_msg));
                            continue;
                        };

                        let original_sender_id: i64 =
                            src_row.try_get("sender_id").unwrap_or_default();

                        let msg_type = message_type.unwrap_or_else(|| "text".to_string());
                        let has_files = metadata.as_ref().map(|m| !m.is_empty());
                        let envelopes_json =
                            envelopes.map(|v| serde_json::to_value(v).ok()).flatten();
                        let metadata_json = metadata
                            .as_ref()
                            .map(|m| serde_json::to_value(m).ok())
                            .flatten();

                        let row = match sqlx::query(
                            r#"
                            INSERT INTO messages (
                                chat_id,
                                sender_id,
                                message,
                                message_type,
                                envelopes,
                                metadata,
                                forwarded_from_message_id,
                                forwarded_from_chat_id,
                                forwarded_from_sender_id
                            )
                            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
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
                                envelopes,
                                metadata
                            "#,
                        )
                        .bind(to_chat_id)
                        .bind(user_id)
                        .bind(&message)
                        .bind(&msg_type)
                        .bind(&envelopes_json)
                        .bind(&metadata_json)
                        .bind(message_id as i32)
                        .bind(from_chat_id)
                        .bind(original_sender_id as i32)
                        .fetch_one(&state.pool)
                        .await
                        {
                            Ok(r) => r,
                            Err(e) => {
                                let err_txt = format!("Ошибка БД: {}", e);
                                let err_msg =
                                    serde_json::to_string(&ServerEvent::Error { error: &err_txt })
                                        .unwrap_or_else(|_| {
                                            format!(
                                                "{{\"type\":\"error\",\"error\":{}}}",
                                                serde_json::to_string(&err_txt)
                                                    .unwrap_or_else(|_| "\"Ошибка\"".to_string())
                                            )
                                        });
                                let _ = out_tx.send(WsMessage::Text(err_msg));
                                continue;
                            }
                        };

                        let envelopes_value: Option<Value> =
                            row.try_get("envelopes").ok().flatten();
                        let metadata_value: Option<Value> = row.try_get("metadata").ok().flatten();
                        let metadata_vec: Option<Vec<FileMetadata>> =
                            metadata_value.and_then(|v| serde_json::from_value(v).ok());

                        let msg = OutMessage {
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
                            forwarded_from_message_id: row
                                .try_get("forwarded_from_message_id")
                                .ok(),
                            forwarded_from_chat_id: row.try_get("forwarded_from_chat_id").ok(),
                            forwarded_from_sender_id: row.try_get("forwarded_from_sender_id").ok(),
                            deleted_at: row
                                .try_get::<chrono::DateTime<chrono::Utc>, _>("deleted_at")
                                .ok()
                                .map(|t| t.to_rfc3339()),
                            deleted_by: row.try_get("deleted_by").ok(),
                            is_read: row.try_get("is_read").unwrap_or(false),
                            has_files,
                            metadata: metadata_vec,
                            envelopes: envelopes_value,
                            status: Some("sent".to_string()),
                        };

                        if let Ok(evt) = serde_json::to_string(&ServerEvent::MessageNew {
                            chat_id: to_chat_id,
                            message: msg,
                        }) {
                            let participants = sqlx::query(
                                r#"
                                SELECT user_id
                                FROM chat_participants
                                WHERE chat_id = $1
                                "#,
                            )
                            .bind(to_chat_id)
                            .fetch_all(&state.pool)
                            .await;

                            if let Ok(rows) = participants {
                                for r in rows {
                                    let uid: i32 = r.try_get("user_id").unwrap_or_default();
                                    if uid <= 0 {
                                        continue;
                                    }
                                    if !is_user_online(&state, uid) {
                                        continue;
                                    }
                                    ensure_user_channel(&state, uid);
                                    publish_user(&state, uid, evt.clone());
                                }
                            }
                        }
                    }
                    Err(_) => {
                        let err_msg = serde_json::to_string(&ServerEvent::Error {
                            error: "Некорректный формат сообщения",
                        })
                        .unwrap_or_else(|_| {
                            "{\"type\":\"error\",\"error\":\"Некорректный формат сообщения\"}"
                                .to_string()
                        });
                        let _ = out_tx.send(WsMessage::Text(err_msg));
                    }
                }
            }
            WsMessage::Close(_) => {
                break;
            }
            WsMessage::Ping(p) => {
                let _ = out_tx.send(WsMessage::Pong(p));
            }
            _ => {}
        }
    }

    // Закрытие: отписываемся от всех каналов и шлём offline глобально
    for (_chat_id, handle) in subs.forwarders.drain() {
        handle.abort();
    }
    subs.joined.clear();
    if let Some(h) = subs.user_forwarder.take() {
        h.abort();
    }

    // Снимаем одно активное соединение; offline отправляем только когда сокетов больше не осталось.
    let became_offline = match state.online_connections.get_mut(&user_id) {
        Some(mut cnt) => {
            if *cnt > 1 {
                *cnt -= 1;
                false
            } else {
                state.online_connections.remove(&user_id);
                true
            }
        }
        None => true,
    };

    if became_offline {
        let presence_evt = match serde_json::to_string(&ServerEvent::Presence {
            user_id,
            status: "offline",
        }) {
            Ok(s) => s,
            Err(_) => "{\"type\":\"presence\",\"user_id\":0,\"status\":\"offline\"}".to_string(),
        };
        for cid in subs.contacts.drain() {
            ensure_user_channel(&state, cid);
            if let Some(entry) = state.user_hub.get(&cid) {
                let _ = entry.send(presence_evt.clone());
            }
        }
    }

    let _ = writer.abort();
}
