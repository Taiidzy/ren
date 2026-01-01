use serde::{Deserialize, Serialize};
use sqlx::FromRow;

// Модели, связанные с авторизацией/аутентификацией

// Тело запроса на регистрацию пользователя
// Для регистрации используется multipart/form-data с полями:
// - login: string
// - username: string
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
    pub avatar: Option<String>,
}

#[derive(Serialize, FromRow, Clone)]
pub struct UserAuthResponse {
    pub id: i32,
    pub login: String,
    pub username: String,
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
    // Если true — выдаём долгоживущий токен ("запомнить меня")
    // Если не передан или false — токен на 24 часа
    pub remember_me: Option<bool>,
}

// Ответ при успешной аутентификации
#[derive(Serialize)]
pub struct LoginResponse {
    pub message: String,
    pub user: UserAuthResponse,
    // Сгенерированный JWT-токен, который клиент сохранит (например, в localStorage)
    pub token: String,
}

// Полезная нагрузка (claims) для JWT
#[derive(Serialize, Deserialize)]
pub struct Claims {
    pub sub: i32,
    pub login: String,
    pub username: String,
    pub exp: i64,
}
