use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

// Модели, связанные с авторизацией/аутентификацией

// Тело запроса на регистрацию пользователя
// Для регистрации используется multipart/form-data с полями:
// - login: string
// - username: string
// - nickname: string (опционально, по умолчанию = username)
// - password: string
// - pkebymk: string (публичный ключ, зашифрованный мастер-ключом)
// - pkebyrk: string (публичный ключ, зашифрованный ключом восстановления)
// - salt: string (соль для криптографии)
// - pk: string (публичный ключ)
// - avatar: file (опционально, файл аватара)

// Упрощённая модель пользователя для ответов API (без пароля)
#[derive(Serialize, FromRow, Clone)]
pub struct UserResponse {
    pub id: i32,
    pub login: String,
    pub username: String,
    pub nickname: Option<String>,
    pub avatar: Option<String>,
}

#[derive(Serialize, FromRow, Clone)]
pub struct UserAuthResponse {
    pub id: i32,
    pub login: String,
    pub username: String,
    pub nickname: Option<String>,
    pub avatar: Option<String>,
    pub pkebymk: String,
    pub pkebyrk: String,
    pub salt: String,
    pub pubk: String,
}

#[derive(Deserialize, Clone)]
pub struct UserRegisterRequest {
    pub login: String,
    pub username: String,
    pub nickname: Option<String>,
    pub password: String,
    pub pkebymk: String,
    pub pkebyrk: String,
    pub pubk: String,
    pub salt: String,
}

// Тело запроса на вход (аутентификацию)
#[derive(Deserialize)]
pub struct LoginRequest {
    pub login: String,
    pub password: String,
    // Если true — более длинная refresh-сессия
    pub remember_me: Option<bool>,
}

// Ответ при успешной аутентификации
#[derive(Serialize)]
pub struct LoginResponse {
    pub message: String,
    pub user: UserAuthResponse,
    pub token: String,
    pub refresh_token: String,
    pub session_id: String,
}

#[derive(Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Serialize)]
pub struct RefreshResponse {
    pub token: String,
    pub refresh_token: String,
    pub session_id: String,
}

#[derive(Serialize)]
pub struct SessionResponse {
    pub id: String,
    pub device_name: String,
    pub ip_address: String,
    pub city: String,
    pub app_version: String,
    pub sdk_fingerprint: Option<String>,
    pub login_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
    pub is_current: bool,
}

// Полезная нагрузка (claims) для JWT
#[derive(Serialize, Deserialize)]
pub struct Claims {
    pub sub: i32,
    pub sid: String,
    pub token_type: String,
    pub login: String,
    pub username: String,
    pub nickname: Option<String>,
    pub exp: i64,
}

// P0-2: Ответ API с подписанным публичным ключом
#[derive(Serialize)]
pub struct SignedPublicKeyResponse {
    pub user_id: i32,
    pub public_key: String,
    pub signature: String,
    pub key_version: u32,
    pub signed_at: String,
    pub identity_key: String, // Ed25519 public key for verification
}
