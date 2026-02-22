use serde::{Deserialize, Serialize};
use serde_json::Value;

// Модели для чатов

#[derive(Serialize, Clone)]
pub struct Chat {
    pub id: i32,
    pub kind: String,
    pub title: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub is_archived: Option<bool>,
    pub is_favorite: Option<bool>,
    pub peer_id: Option<i32>,
    pub peer_username: Option<String>,
    pub peer_avatar: Option<String>,
    pub unread_count: Option<i64>,
    pub my_role: Option<String>,
    pub last_message_id: Option<i64>,
    pub last_message: Option<String>,
    pub last_message_type: Option<String>,
    pub last_message_created_at: Option<String>,
    pub last_message_is_outgoing: Option<bool>,
    pub last_message_is_delivered: Option<bool>,
    pub last_message_is_read: Option<bool>,
}

// Конверт для E2EE (зашифрованный ключ для конкретного пользователя)
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Envelope {
    pub key: String,           // зашифрованный ключ (base64)
    pub ephem_pub_key: String, // эфемерный публичный ключ (base64)
    pub iv: String,            // вектор инициализации (base64)
}

// Метаданные файла
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct FileMetadata {
    pub file_id: Option<i64>,
    pub filename: String,
    pub mimetype: String,
    pub size: i64,
    pub enc_file: Option<String>, // зашифрованный файл (base64) или null
    pub nonce: Option<String>,    // nonce для файла (base64) или null
    pub file_creation_date: Option<String>,
    // Для chunked файлов:
    pub nonces: Option<Vec<String>>,
    pub chunk_size: Option<i64>,
    pub chunk_count: Option<i32>,
}

#[derive(Serialize, Clone)]
pub struct Message {
    pub id: i64,
    pub chat_id: i64,
    pub sender_id: i64,
    pub message: String,      // зашифрованное сообщение
    pub message_type: String, // 'text' | 'file' | 'image' и т.д.
    pub created_at: String,
    pub edited_at: Option<String>,
    pub reply_to_message_id: Option<i64>,
    pub forwarded_from_message_id: Option<i64>,
    pub forwarded_from_chat_id: Option<i64>,
    pub forwarded_from_sender_id: Option<i64>,
    pub deleted_at: Option<String>,
    pub deleted_by: Option<i64>,
    pub is_read: bool,
    pub is_delivered: bool,
    pub has_files: Option<bool>, // опционально, для обратной совместимости
    pub metadata: Option<Vec<FileMetadata>>, // метаданные файлов
    pub envelopes: Option<Value>, // JSON объект: {"userId": Envelope}
    pub status: Option<String>,  // "pending" | "sent" (для клиента)
}

// Для обратной совместимости: body теперь алиас для message
impl Message {
    pub fn body(&self) -> Option<&String> {
        Some(&self.message)
    }
}

#[derive(Deserialize, Clone)]
pub struct CreateChatRequest {
    pub kind: String,          // 'private' | 'group' | 'channel'
    pub title: Option<String>, // только для групп
    pub user_ids: Vec<i32>,    // участники (включая текущего пользователя)
}
