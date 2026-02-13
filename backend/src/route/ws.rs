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
use crate::middleware::{CurrentUser, ensure_member};
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
    NotificationNew {
        chat_id: i32,
        message: OutMessage,
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

    // Отмечаем, что пользователь онлайн (сразу после апгрейда)
    state.online_users.insert(user_id);

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

    // Обработка входящих сообщений клиента
    while let Some(Ok(msg)) = ws_receiver.next().await {
        match msg {
            WsMessage::Text(text) => {
                let parsed: Result<ClientEvent, _> = serde_json::from_str(&text);
                match parsed {
                    Ok(ClientEvent::Init { contacts }) => {
                        // Подписываемся на собственный личный канал, чтобы получать presence от других
                        let tx = match state.user_hub.get(&user_id) {
                            Some(existing) => existing.clone(),
                            None => {
                                let (tx, _rx) = broadcast::channel::<String>(200);
                                state.user_hub.insert(user_id, tx);
                                state.user_hub.get(&user_id).unwrap().clone()
                            }
                        };
                        // Если уже был форвардер, перезапустим
                        if let Some(h) = subs.user_forwarder.take() {
                            h.abort();
                        }
                        let mut rx = tx.subscribe();
                        let out_tx_clone = out_tx.clone();
                        subs.user_forwarder = Some(tokio::spawn(async move {
                            while let Ok(msg) = rx.recv().await {
                                let _ = out_tx_clone.send(WsMessage::Text(msg));
                            }
                        }));

                        // Сохраняем список контактов и рассылаем им, что мы онлайн
                        subs.contacts = contacts.into_iter().collect();
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
                        for cid in &subs.contacts {
                            // создаём входящий канал для контакта при необходимости
                            if state.user_hub.get(cid).is_none() {
                                let (txc, _rx) = broadcast::channel::<String>(200);
                                state.user_hub.insert(*cid, txc);
                            }
                            publish_user(&state, *cid, presence_evt.clone());
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
                        // Отмечаем, что пользователь находится в этом чате
                        state.in_chat.insert((chat_id, user_id));
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
                        state.in_chat.remove(&(chat_id, user_id));
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
                        if !subs.joined.contains(&chat_id) {
                            // safety: проверка членства
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
                        // Реальные получатели: участники чата кроме отправителя.
                        // Если пользователь онлайн и находится в этом чате -> отправляем message_new (через ws_hub).
                        // Если онлайн, но не в чате -> отправляем notification_new (через user_hub).
                        let rows = sqlx::query(
                            r#"SELECT user_id FROM chat_participants WHERE chat_id = $1"#,
                        )
                        .bind(chat_id)
                        .fetch_all(&state.pool)
                        .await;

                        if let Ok(participants) = rows {
                            for r in participants {
                                let uid: i32 = r.try_get("user_id").unwrap_or_default();
                                if uid <= 0 || uid == user_id {
                                    continue;
                                }

                                if !state.online_users.contains(&uid) {
                                    continue;
                                }

                                // Обеспечим наличие личного канала, иначе publish_user будет no-op
                                if state.user_hub.get(&uid).is_none() {
                                    let (txc, _rx) = broadcast::channel::<String>(200);
                                    state.user_hub.insert(uid, txc);
                                }

                                if state.in_chat.contains(&(chat_id, uid)) {
                                    if let Ok(evt) =
                                        serde_json::to_string(&ServerEvent::MessageNew {
                                            chat_id,
                                            message: msg.clone(),
                                        })
                                    {
                                        publish(&state, chat_id, evt);
                                    }
                                } else {
                                    if let Ok(evt) =
                                        serde_json::to_string(&ServerEvent::NotificationNew {
                                            chat_id,
                                            message: msg.clone(),
                                        })
                                    {
                                        publish_user(&state, uid, evt);
                                    }
                                }
                            }
                        }

                        // Эхо отправителю: только если он подписан на чат.
                        if subs.joined.contains(&chat_id) {
                            if let Ok(evt) = serde_json::to_string(&ServerEvent::MessageNew {
                                chat_id,
                                message: msg,
                            }) {
                                publish(&state, chat_id, evt);
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

                        publish(&state, chat_id, evt.clone());

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
                                if state.user_hub.get(&uid).is_none() {
                                    let (txc, _rx) = broadcast::channel::<String>(200);
                                    state.user_hub.insert(uid, txc);
                                }
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

                        // 1) realtime для тех, кто подписан на чат
                        publish(&state, chat_id, evt.clone());

                        // 2) realtime всем участникам чата через личные каналы (на случай отсутствия join_chat)
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
                                if state.user_hub.get(&uid).is_none() {
                                    let (txc, _rx) = broadcast::channel::<String>(200);
                                    state.user_hub.insert(uid, txc);
                                }
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
                        if let Err(e) = ensure_member(&state, to_chat_id, user_id).await {
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
                            publish(&state, to_chat_id, evt);
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
    for chat_id in subs.joined.drain() {
        state.in_chat.remove(&(chat_id, user_id));
    }
    if let Some(h) = subs.user_forwarder.take() {
        h.abort();
    }

    // Удаляем из онлайна
    state.online_users.remove(&user_id);
    let presence_evt = match serde_json::to_string(&ServerEvent::Presence {
        user_id,
        status: "offline",
    }) {
        Ok(s) => s,
        Err(_) => "{\"type\":\"presence\",\"user_id\":0,\"status\":\"offline\"}".to_string(),
    };
    for cid in subs.contacts.drain() {
        if state.user_hub.get(&cid).is_none() {
            let (txc, _rx) = broadcast::channel::<String>(200);
            state.user_hub.insert(cid, txc);
        }
        if let Some(entry) = state.user_hub.get(&cid) {
            let _ = entry.send(presence_evt.clone());
        }
    }
    let _ = writer.abort();
}
