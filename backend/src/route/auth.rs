use axum::{
    extract::{State},
    http::StatusCode,
    routing::post,
    Json, Router,
};
use sqlx::{Row};
use crate::AppState;
use crate::models::auth::{UserAuthResponse, LoginRequest, LoginResponse, Claims, UserRegisterRequest};

// Импорты для работы с хешированием пароля (argon2)
use argon2::{Argon2};
use password_hash::{PasswordHasher, PasswordVerifier, SaltString, PasswordHash};
use rand_core::OsRng; // генератор случайной соли
// Импорты для генерации JWT-токена
use jsonwebtoken::{encode, EncodingKey, Header};
use time::{Duration, OffsetDateTime};

// Модели вынесены в crate::models::auth

// ---------------------------
// Конструктор роутера модуля авторизации
// ---------------------------
pub fn router() -> Router<AppState> {
    Router::new()
        // POST /auth/register — регистрация нового пользователя
        .route("/auth/register", post(register))
        // POST /auth/login — вход пользователя по логину и паролю
        .route("/auth/login", post(login))
}

// ---------------------------
// Хендлер регистрации
// ---------------------------
async fn register(
    State(state): State<AppState>,
    Json(payload): Json<UserRegisterRequest>,
) -> Result<Json<UserAuthResponse>, (StatusCode, String)> {

    // Поля запроса (все обязательные по типам)
    let UserRegisterRequest { mut login, mut username, password, pkebymk, pkebyrk, pubk, salt } = payload;

    // Тримим строковые поля login/username для базовой валидации
    login = login.trim().to_string();
    username = username.trim().to_string();

    // Простейшие валидации длины
    if login.is_empty() || username.is_empty() || password.len() < 6 {
        return Err((StatusCode::BAD_REQUEST, "Некорректные данные (минимум: пароль >= 6 символов)".into()));
    }

    // Генерируем соль и хешируем пароль алгоритмом Argon2
    let password_salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let password_hash = argon2
        .hash_password(password.as_bytes(), &password_salt)
        .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Не удалось захешировать пароль".into()))?
        .to_string();

    // Вставляем запись в БД с E2EE полями
    let row = sqlx::query(
        r#"
        INSERT INTO users (login, username, password, pkebymk, pkebyrk, pubk, salt)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, login, username
        "#,
    )
    .bind(&login)
    .bind(&username)
    .bind(&password_hash)
    .bind(&pkebymk)
    .bind(&pkebyrk)
    .bind(&pubk)
    .bind(&salt)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| match e {
        sqlx::Error::Database(db_err) => {
            // Код ошибки уникальности в Postgres — 23505
            if db_err.code().as_deref() == Some("23505") {
                (StatusCode::CONFLICT, "Логин или имя пользователя уже занято".into())
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", db_err))
            }
        }
        other => (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка: {}", other)),
    })?;

    let user_id: i32 = row.try_get("id")
        .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Ошибка чтения id пользователя".into()))?;


    // Получаем обновленные данные пользователя
    let rec = sqlx::query_as::<_, UserAuthResponse>(
        r#"
        SELECT id, login, username, avatar, pkebymk, pkebyrk, salt, pubk
        FROM users
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    Ok(Json(rec))
}

// ---------------------------
// Хендлер входа (логина)
// ---------------------------
async fn login(
    State(state): State<AppState>,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, (StatusCode, String)> {
    // 1) Находим пользователя по логину
    let row = sqlx::query(
        r#"
        SELECT id, login, username, avatar, password, pkebymk, pkebyrk, salt, pubk
        FROM users
        WHERE login = $1
        "#,
    )
    .bind(&payload.login)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    // 2) Если пользователя с таким логином нет — возвращаем 401 (UNAUTHORIZED)
    let Some(row) = row else {
        return Err((StatusCode::UNAUTHORIZED, "Неверный логин или пароль".into()));
    };

    // 3) Получаем хеш пароля и проверяем его с введённым паролем
    let hashed: String = row.try_get("password").map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Ошибка чтения поля password".into()))?;
    let parsed_hash = PasswordHash::new(&hashed)
        .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Некорректный формат хеша пароля".into()))?;

    let argon2 = Argon2::default();
    argon2
        .verify_password(payload.password.as_bytes(), &parsed_hash)
        .map_err(|_| (StatusCode::UNAUTHORIZED, "Неверный логин или пароль".into()))?;

    // 4) Собираем данные пользователя для ответа (без пароля)
    let user = UserAuthResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        avatar: row.try_get("avatar").ok(),
        pkebymk: row.try_get("pkebymk").unwrap_or_default(),
        pkebyrk: row.try_get("pkebyrk").unwrap_or_default(),
        pubk: row.try_get("pubk").unwrap_or_default(),
        salt: row.try_get("salt").unwrap_or_default(),
    };

    // 5) Генерируем JWT-токен
    // Если remember_me = true — сделаем токен на 365 дней, иначе на 24 часа
    let ttl = if payload.remember_me.unwrap_or(false) {
        Duration::days(365)
    } else {
        Duration::hours(24)
    };
    let expires_at = OffsetDateTime::now_utc() + ttl;
    let claims = Claims {
        sub: user.id,
        login: user.login.clone(),
        username: user.username.clone(),
        exp: expires_at.unix_timestamp(),
    };

    // Формируем подпись токена секретом из состояния приложения
    let token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Не удалось сгенерировать JWT: {}", e)))?;

    Ok(Json(LoginResponse { message: "Успешный вход".into(), user, token }))
}
