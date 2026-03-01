use axum::{
    Json, Router,
    extract::{ConnectInfo, Path, State},
    http::{HeaderMap, StatusCode},
    routing::{delete, get, post},
};
use serde::Deserialize;
use sqlx::Row;
use std::net::SocketAddr;
use std::time::Duration;

use crate::AppState;
use crate::middleware::CurrentUser;
use crate::models::auth::{
    Claims, LoginRequest, LoginResponse, RefreshRequest, RefreshResponse, SessionResponse,
    UserAuthResponse, UserRegisterRequest,
};

use argon2::Argon2;
use password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use rand_core::{OsRng, RngCore};

use chrono::{Duration as ChronoDuration, Utc};
use jsonwebtoken::{EncodingKey, Header, encode};
use sha2::{Digest, Sha256};
use uuid::Uuid;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/refresh", post(refresh))
        .route("/auth/logout", post(logout))
        .route(
            "/auth/sessions",
            get(list_sessions).delete(delete_other_sessions),
        )
        .route("/auth/sessions/:id", delete(delete_session))
}

async fn register(
    State(state): State<AppState>,
    Json(payload): Json<UserRegisterRequest>,
) -> Result<Json<UserAuthResponse>, (StatusCode, String)> {
    let UserRegisterRequest {
        mut login,
        mut username,
        nickname,
        password,
        pkebymk,
        pkebyrk,
        pubk,
        salt,
    } = payload;

    login = login.trim().to_string();
    username = username.trim().to_string();
    // Если nickname не передан, устанавливаем его равным username
    let nickname = nickname
        .map(|n| n.trim().to_string())
        .filter(|n| !n.is_empty())
        .unwrap_or_else(|| username.clone());

    // Валидация длины nickname (макс. 32 символа)
    if nickname.len() > 32 {
        return Err((
            StatusCode::BAD_REQUEST,
            "Nickname не может быть длиннее 32 символов".into(),
        ));
    }

    if login.is_empty() || username.is_empty() || password.len() < 6 {
        return Err((
            StatusCode::BAD_REQUEST,
            "Некорректные данные (минимум: пароль >= 6 символов)".into(),
        ));
    }

    let password_salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let password_hash = argon2
        .hash_password(password.as_bytes(), &password_salt)
        .map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Не удалось захешировать пароль".into(),
            )
        })?
        .to_string();

    let row = sqlx::query(
        r#"
        INSERT INTO users (login, username, nickname, password, pkebymk, pkebyrk, pubk, salt)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id
        "#,
    )
    .bind(&login)
    .bind(&username)
    .bind(&nickname)
    .bind(&password_hash)
    .bind(&pkebymk)
    .bind(&pkebyrk)
    .bind(&pubk)
    .bind(&salt)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| match e {
        sqlx::Error::Database(db_err) => {
            if db_err.code().as_deref() == Some("23505") {
                (
                    StatusCode::CONFLICT,
                    "Логин или имя пользователя уже занято".into(),
                )
            } else {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Ошибка БД: {}", db_err),
                )
            }
        }
        other => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка: {}", other),
        ),
    })?;

    let user_id: i32 = row.try_get("id").map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Ошибка чтения id пользователя".into(),
        )
    })?;

    let rec = sqlx::query_as::<_, UserAuthResponse>(
        r#"
        SELECT id, login, username, nickname, avatar, pkebymk, pkebyrk, salt, pubk
        FROM users
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    Ok(Json(rec))
}

async fn login(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, (StatusCode, String)> {
    // P1-7: Check rate limit before processing
    let ip = addr.ip().to_string();
    if !state
        .auth_rate_limiter
        .is_allowed(&ip, Some(&payload.login))
    {
        return Err((
            StatusCode::TOO_MANY_REQUESTS,
            "Слишком много попыток входа. Повторите позже.".into(),
        ));
    }

    let row = sqlx::query(
        r#"
        SELECT id, login, username, nickname, avatar, password, pkebymk, pkebyrk, salt, pubk
        FROM users
        WHERE login = $1
        "#,
    )
    .bind(&payload.login)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let Some(row) = row else {
        // P1-7: Record failed attempt
        let (_allowed, _lockout_secs) = state
            .auth_rate_limiter
            .record_failure(&ip, Some(&payload.login));

        return Err((StatusCode::UNAUTHORIZED, "Неверный логин или пароль".into()));
    };

    let hashed: String = row.try_get("password").map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Ошибка чтения поля password".into(),
        )
    })?;
    let parsed_hash = PasswordHash::new(&hashed).map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Некорректный формат хеша пароля".into(),
        )
    })?;

    Argon2::default()
        .verify_password(payload.password.as_bytes(), &parsed_hash)
        .map_err(|_e| {
            // P1-7: Record failed attempt on password mismatch
            let (_allowed, _lockout_secs) = state
                .auth_rate_limiter
                .record_failure(&ip, Some(&payload.login));

            (StatusCode::UNAUTHORIZED, "Неверный логин или пароль".into())
        })?;

    // P1-7: Record successful login - reset counters
    state
        .auth_rate_limiter
        .record_success(&ip, Some(&payload.login));

    let user = UserAuthResponse {
        id: row.try_get("id").unwrap_or_default(),
        login: row.try_get("login").unwrap_or_default(),
        username: row.try_get("username").unwrap_or_default(),
        nickname: row.try_get("nickname").ok(),
        avatar: row.try_get("avatar").ok(),
        pkebymk: row.try_get("pkebymk").unwrap_or_default(),
        pkebyrk: row.try_get("pkebyrk").unwrap_or_default(),
        pubk: row.try_get("pubk").unwrap_or_default(),
        salt: row.try_get("salt").unwrap_or_default(),
    };

    let remember_me = payload.remember_me.unwrap_or(false);
    let ip_address = extract_ip(&headers, addr);
    let city = resolve_city(&headers, &ip_address).await;
    let app_version =
        extract_header(&headers, "x-app-version").unwrap_or_else(|| "unknown".to_string());
    let user_agent =
        extract_header(&headers, "user-agent").unwrap_or_else(|| "unknown".to_string());
    let device_name = extract_header(&headers, "x-device-name")
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| user_agent.clone());

    let refresh_ttl = if remember_me {
        ChronoDuration::days(365)
    } else {
        ChronoDuration::days(30)
    };
    let session_expires_at = Utc::now() + refresh_ttl;

    let session_id = Uuid::new_v4();
    let refresh_token = generate_refresh_token();
    let refresh_hash = hash_refresh_token(&state.jwt_secret, &refresh_token);

    sqlx::query(
        r#"
        INSERT INTO auth_sessions (
            id, user_id, refresh_token_hash, device_name, user_agent, ip_address,
            city, app_version, remember_me, expires_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        "#,
    )
    .bind(session_id)
    .bind(user.id)
    .bind(refresh_hash)
    .bind(device_name)
    .bind(user_agent)
    .bind(ip_address)
    .bind(city)
    .bind(app_version)
    .bind(remember_me)
    .bind(session_expires_at)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let token = issue_access_token(&state, &user, session_id)?;

    Ok(Json(LoginResponse {
        message: "Успешный вход".into(),
        user,
        token,
        refresh_token,
        session_id: session_id.to_string(),
    }))
}

async fn refresh(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(payload): Json<RefreshRequest>,
) -> Result<Json<RefreshResponse>, (StatusCode, String)> {
    if payload.refresh_token.trim().is_empty() {
        return Err((StatusCode::BAD_REQUEST, "refresh_token обязателен".into()));
    }

    let refresh_hash = hash_refresh_token(&state.jwt_secret, &payload.refresh_token);
    let row = sqlx::query(
        r#"
        SELECT
            s.id,
            s.user_id,
            s.remember_me,
            u.login,
            u.username,
            u.nickname
        FROM auth_sessions s
        JOIN users u ON u.id = s.user_id
        WHERE s.refresh_token_hash = $1
          AND s.revoked_at IS NULL
          AND s.expires_at > now()
        LIMIT 1
        "#,
    )
    .bind(refresh_hash)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let Some(row) = row else {
        return Err((StatusCode::UNAUTHORIZED, "Невалидный refresh_token".into()));
    };

    let session_id: Uuid = row.try_get("id").map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Ошибка чтения session id".into(),
        )
    })?;
    let user_id: i32 = row.try_get("user_id").map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Ошибка чтения user id".into(),
        )
    })?;
    let remember_me: bool = row.try_get("remember_me").unwrap_or(false);
    let login: String = row.try_get("login").unwrap_or_default();
    let username: String = row.try_get("username").unwrap_or_default();
    let nickname: Option<String> = row.try_get("nickname").ok();

    let new_refresh_token = generate_refresh_token();
    let new_refresh_hash = hash_refresh_token(&state.jwt_secret, &new_refresh_token);

    let refresh_ttl = if remember_me {
        ChronoDuration::days(365)
    } else {
        ChronoDuration::days(30)
    };
    let new_expires_at = Utc::now() + refresh_ttl;

    let ip_address = extract_ip(&headers, addr);
    let city = resolve_city(&headers, &ip_address).await;
    let app_version =
        extract_header(&headers, "x-app-version").unwrap_or_else(|| "unknown".to_string());
    let user_agent =
        extract_header(&headers, "user-agent").unwrap_or_else(|| "unknown".to_string());
    let device_name = extract_header(&headers, "x-device-name")
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| user_agent.clone());

    sqlx::query(
        r#"
        UPDATE auth_sessions
        SET
            refresh_token_hash = $1,
            device_name = $2,
            user_agent = $3,
            ip_address = $4,
            city = $5,
            app_version = $6,
            last_seen_at = now(),
            expires_at = $7
        WHERE id = $8
        "#,
    )
    .bind(new_refresh_hash)
    .bind(device_name)
    .bind(user_agent)
    .bind(ip_address)
    .bind(city)
    .bind(app_version)
    .bind(new_expires_at)
    .bind(session_id)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let claims_user = UserAuthResponse {
        id: user_id,
        login,
        username,
        nickname,
        avatar: None,
        pkebymk: String::new(),
        pkebyrk: String::new(),
        pubk: String::new(),
        salt: String::new(),
    };

    let token = issue_access_token(&state, &claims_user, session_id)?;

    Ok(Json(RefreshResponse {
        token,
        refresh_token: new_refresh_token,
        session_id: session_id.to_string(),
    }))
}

async fn list_sessions(
    State(state): State<AppState>,
    CurrentUser {
        id: user_id,
        session_id: current_session_id,
    }: CurrentUser,
) -> Result<Json<Vec<SessionResponse>>, (StatusCode, String)> {
    let rows = sqlx::query(
        r#"
        SELECT
            id,
            device_name,
            ip_address,
            city,
            app_version,
            created_at,
            last_seen_at
        FROM auth_sessions
        WHERE user_id = $1
          AND revoked_at IS NULL
          AND expires_at > now()
        ORDER BY created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let mut sessions = Vec::with_capacity(rows.len());
    for row in rows {
        let id: Uuid = row.try_get("id").map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Ошибка чтения session id".into(),
            )
        })?;

        sessions.push(SessionResponse {
            id: id.to_string(),
            device_name: row
                .try_get::<Option<String>, _>("device_name")
                .ok()
                .flatten()
                .unwrap_or_else(|| "Unknown device".to_string()),
            ip_address: row
                .try_get::<Option<String>, _>("ip_address")
                .ok()
                .flatten()
                .unwrap_or_else(|| "unknown".to_string()),
            city: row
                .try_get::<Option<String>, _>("city")
                .ok()
                .flatten()
                .unwrap_or_else(|| "Unknown".to_string()),
            app_version: row
                .try_get::<Option<String>, _>("app_version")
                .ok()
                .flatten()
                .unwrap_or_else(|| "unknown".to_string()),
            login_at: row.try_get("created_at").map_err(|_| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Ошибка чтения created_at".into(),
                )
            })?,
            last_seen_at: row.try_get("last_seen_at").map_err(|_| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Ошибка чтения last_seen_at".into(),
                )
            })?,
            is_current: id == current_session_id,
        });
    }

    Ok(Json(sessions))
}

async fn delete_session(
    State(state): State<AppState>,
    CurrentUser { id: user_id, .. }: CurrentUser,
    Path(session_id): Path<String>,
) -> Result<StatusCode, (StatusCode, String)> {
    let session_uuid = Uuid::parse_str(&session_id)
        .map_err(|_| (StatusCode::BAD_REQUEST, "Некорректный id сессии".into()))?;

    let result = sqlx::query(
        r#"
        UPDATE auth_sessions
        SET revoked_at = now()
        WHERE id = $1
          AND user_id = $2
          AND revoked_at IS NULL
        "#,
    )
    .bind(session_uuid)
    .bind(user_id)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    if result.rows_affected() == 0 {
        return Err((StatusCode::NOT_FOUND, "Сессия не найдена".into()));
    }

    Ok(StatusCode::NO_CONTENT)
}

async fn delete_other_sessions(
    State(state): State<AppState>,
    CurrentUser {
        id: user_id,
        session_id: current_session_id,
    }: CurrentUser,
) -> Result<StatusCode, (StatusCode, String)> {
    sqlx::query(
        r#"
        UPDATE auth_sessions
        SET revoked_at = now()
        WHERE user_id = $1
          AND id <> $2
          AND revoked_at IS NULL
        "#,
    )
    .bind(user_id)
    .bind(current_session_id)
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

async fn logout(
    State(state): State<AppState>,
    CurrentUser {
        id: user_id,
        session_id,
    }: CurrentUser,
) -> Result<StatusCode, (StatusCode, String)> {
    let _ = sqlx::query(
        r#"
        UPDATE auth_sessions
        SET revoked_at = now()
        WHERE id = $1
          AND user_id = $2
          AND revoked_at IS NULL
        "#,
    )
    .bind(session_id)
    .bind(user_id)
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

fn issue_access_token(
    state: &AppState,
    user: &UserAuthResponse,
    session_id: Uuid,
) -> Result<String, (StatusCode, String)> {
    let expires_at = Utc::now() + ChronoDuration::minutes(15);
    let claims = Claims {
        sub: user.id,
        sid: session_id.to_string(),
        token_type: "access".to_string(),
        login: user.login.clone(),
        username: user.username.clone(),
        nickname: user.nickname.clone(),
        exp: expires_at.timestamp(),
    };

    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Не удалось сгенерировать JWT: {}", e),
        )
    })
}

fn hash_refresh_token(secret: &str, refresh_token: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(secret.as_bytes());
    hasher.update(refresh_token.as_bytes());
    format!("{:x}", hasher.finalize())
}

fn generate_refresh_token() -> String {
    let mut bytes = [0u8; 48];
    OsRng.fill_bytes(&mut bytes);
    let mut token = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        use std::fmt::Write;
        let _ = write!(&mut token, "{:02x}", b);
    }
    token
}

fn extract_ip(headers: &HeaderMap, addr: SocketAddr) -> String {
    if let Some(forwarded) = extract_header(headers, "x-forwarded-for") {
        let ip = forwarded.split(',').next().map(str::trim).unwrap_or("");
        if !ip.is_empty() {
            return ip.to_string();
        }
    }

    if let Some(real_ip) = extract_header(headers, "x-real-ip") {
        if !real_ip.trim().is_empty() {
            return real_ip;
        }
    }

    addr.ip().to_string()
}

fn extract_city_from_headers(headers: &HeaderMap) -> Option<String> {
    extract_header(headers, "x-geo-city")
        .or_else(|| extract_header(headers, "x-city"))
        .or_else(|| extract_header(headers, "cf-ipcity"))
        .filter(|v| !v.trim().is_empty())
}

fn extract_header(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|v| v.to_str().ok())
        .map(|v| v.trim().to_string())
}

async fn resolve_city(headers: &HeaderMap, ip_address: &str) -> String {
    // P2-12: Geo-Service Privacy - Check headers first (from trusted proxy)
    if let Some(city) = extract_city_from_headers(headers) {
        return city;
    }

    if ip_address.is_empty()
        || ip_address == "127.0.0.1"
        || ip_address == "::1"
        || ip_address.eq_ignore_ascii_case("unknown")
    {
        return "Unknown".to_string();
    }

    // P2-12: Geo-Service Privacy - External geo-requests disabled by default
    // Set ENABLE_EXTERNAL_GEO=1 to enable external lookups (not recommended for privacy)
    let enable_external = std::env::var("ENABLE_EXTERNAL_GEO")
        .unwrap_or_else(|_| "0".to_string())
        .trim()
        .eq("1");

    if !enable_external {
        // P2-12: Return "Unknown" instead of making external request
        return "Unknown".to_string();
    }

    // External geo lookup is disabled by default for privacy
    // If explicitly enabled, use local/offline geo-DB instead
    resolve_city_by_ipwhois(ip_address)
        .await
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| "Unknown".to_string())
}

#[derive(Deserialize)]
struct IpWhoisResponse {
    success: Option<bool>,
    city: Option<String>,
}

async fn resolve_city_by_ipwhois(ip_address: &str) -> Option<String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(3))
        .build()
        .ok()?;

    let template = std::env::var("IP_GEO_URL_TEMPLATE")
        .unwrap_or_else(|_| "https://ipwhois.app/json/{ip}".to_string());
    let url = template.replace("{ip}", ip_address);
    let response = client.get(url).send().await.ok()?;
    if !response.status().is_success() {
        return None;
    }

    let body = response.json::<IpWhoisResponse>().await.ok()?;
    if body.success == Some(false) {
        return None;
    }

    body.city.map(|v| v.trim().to_string())
}
