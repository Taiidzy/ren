use serde::{Deserialize, Serialize};
use sqlx::FromRow;

/// One-Time PreKey
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct PreKey {
    pub id: i32,
    pub user_id: i32,
    pub prekey_id: i32,
    pub prekey_public: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub used_at: Option<chrono::DateTime<chrono::Utc>>,
}

/// Signed PreKey
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct SignedPreKey {
    pub id: i32,
    pub user_id: i32,
    pub prekey_public: String,
    pub signature: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub is_current: bool,
}

/// PreKey Bundle для ответа API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreKeyBundleResponse {
    pub user_id: i32,
    pub identity_key: String,
    pub signed_prekey: String,
    pub signed_prekey_signature: String,
    pub one_time_prekey: Option<String>,
    pub one_time_prekey_id: Option<i32>,
}

/// Запрос на загрузку One-Time PreKeys
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadPreKeysRequest {
    pub prekeys: Vec<PreKeyUpload>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreKeyUpload {
    pub prekey_id: i32,
    pub prekey: String,
}

/// Запрос на загрузку Signed PreKey
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadSignedPreKeyRequest {
    pub prekey: String,
    pub signature: String,
}

/// Ответ API с количеством One-Time PreKeys
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreKeyCountResponse {
    pub count: i32,
}
