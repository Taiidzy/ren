use axum::body::{Body, Bytes, to_bytes};
use axum::extract::FromRef;
use axum::{
    async_trait,
    extract::{ConnectInfo, FromRequestParts, MatchedPath, Request, State},
    http::{StatusCode, header, request::Parts},
    middleware::Next,
    response::Response,
};
use jsonwebtoken::{DecodingKey, Validation, decode};
use sqlx::Row;
use uuid::Uuid;

use crate::AppState;
use crate::models::auth::Claims;
use chrono::Local;
use std::net::SocketAddr;
use std::time::Instant;

// Rate limiting module
pub mod rate_limit;
pub use rate_limit::{RateLimiter, AuthRateLimiter, rate_limit_middleware, auth_rate_limit_middleware};

// Экстрактор текущего пользователя из заголовка Authorization: Bearer <JWT>
// Пример использования: fn handler(State(state): State<AppState>, CurrentUser { id, .. }: CurrentUser) { ... }

// Утилита: убедиться, что пользователь является участником чата
pub async fn ensure_member(
    state: &AppState,
    chat_id: i32,
    user_id: i32,
) -> Result<(), (StatusCode, String)> {
    let exists: Option<i32> = sqlx::query_scalar(
        r#"SELECT 1 FROM chat_participants WHERE chat_id = $1 AND user_id = $2 LIMIT 1"#,
    )
    .bind(chat_id)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    if exists.is_none() {
        return Err((
            StatusCode::FORBIDDEN,
            "Нет доступа: вы не являетесь участником чата".into(),
        ));
    }
    Ok(())
}

// Утилита: убедиться, что пользователь может отправлять сообщения в чат.
// Для channel писать могут только owner/admin.
pub async fn ensure_can_send_message(
    state: &AppState,
    chat_id: i32,
    user_id: i32,
) -> Result<(), (StatusCode, String)> {
    let row = sqlx::query(
        r#"
        SELECT c.kind, COALESCE(cp.role, 'member') AS role
        FROM chats c
        JOIN chat_participants cp ON cp.chat_id = c.id
        WHERE c.id = $1 AND cp.user_id = $2
        LIMIT 1
        "#,
    )
    .bind(chat_id)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let Some(row) = row else {
        return Err((
            StatusCode::FORBIDDEN,
            "Нет доступа: вы не являетесь участником чата".into(),
        ));
    };

    let kind: String = row.try_get("kind").unwrap_or_default();
    let role: String = row.try_get("role").unwrap_or_else(|_| "member".to_string());
    if kind == "channel" && role != "owner" && role != "admin" {
        return Err((
            StatusCode::FORBIDDEN,
            "Недостаточно прав: в channel писать могут только owner/admin".into(),
        ));
    }

    Ok(())
}
#[derive(Clone, Copy, Debug)]
pub struct CurrentUser {
    pub id: i32,
    pub session_id: Uuid,
}

#[async_trait]
impl<S> FromRequestParts<S> for CurrentUser
where
    S: Send + Sync,
    AppState: FromRef<S>,
{
    type Rejection = (StatusCode, String);

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        // Получаем AppState через стандартный State-экстрактор
        let State(app_state): State<AppState> =
            State::from_request_parts(parts, state).await.map_err(|_| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Не удалось получить состояние приложения".to_string(),
                )
            })?;

        // Достаём токен только из заголовка Authorization: Bearer <JWT>.
        // Не принимаем query-token, чтобы исключить утечки секретов в URL/логах.
        let token: String = if let Some(auth_header) = parts
            .headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
        {
            auth_header
                .strip_prefix("Bearer ")
                .or_else(|| auth_header.strip_prefix("bearer "))
                .ok_or((
                    StatusCode::UNAUTHORIZED,
                    "Некорректный формат заголовка Authorization".to_string(),
                ))?
                .to_string()
        } else {
            return Err((
                StatusCode::UNAUTHORIZED,
                "Отсутствует заголовок Authorization".to_string(),
            ));
        };

        // Валидируем токен
        let data = decode::<Claims>(
            &token,
            &DecodingKey::from_secret(app_state.jwt_secret.as_bytes()),
            &Validation::default(),
        )
        .map_err(|_| {
            (
                StatusCode::UNAUTHORIZED,
                "Невалидный или просроченный токен".to_string(),
            )
        })?;

        if data.claims.token_type != "access" {
            return Err((StatusCode::UNAUTHORIZED, "Неверный тип токена".to_string()));
        }

        let session_id = Uuid::parse_str(&data.claims.sid).map_err(|_| {
            (
                StatusCode::UNAUTHORIZED,
                "Некорректный sid в токене".to_string(),
            )
        })?;

        let sdk_fingerprint = if app_state.sdk_fingerprint_allowlist.is_empty() {
            None
        } else {
            let v = parts
                .headers
                .get("x-sdk-fingerprint")
                .and_then(|x| x.to_str().ok())
                .map(|x| x.trim().to_string())
                .filter(|x| !x.is_empty())
                .ok_or((
                    StatusCode::UNAUTHORIZED,
                    "sdk fingerprint required".to_string(),
                ))?;
            let normalized = v.trim().to_lowercase();
            if normalized.is_empty() {
                return Err((
                    StatusCode::UNAUTHORIZED,
                    "sdk fingerprint required".to_string(),
                ));
            }
            if !app_state.sdk_fingerprint_allowlist.contains(&normalized) {
                return Err((
                    StatusCode::UNAUTHORIZED,
                    "sdk fingerprint is not allowed".to_string(),
                ));
            }
            Some(normalized)
        };

        let active: Option<i32> = if let Some(fp) = sdk_fingerprint.as_ref() {
            sqlx::query_scalar(
                r#"
                SELECT 1
                FROM auth_sessions
                WHERE id = $1
                  AND user_id = $2
                  AND revoked_at IS NULL
                  AND expires_at > now()
                  AND lower(coalesce(sdk_fingerprint, '')) = $3
                LIMIT 1
                "#,
            )
            .bind(session_id)
            .bind(data.claims.sub)
            .bind(fp)
            .fetch_optional(&app_state.pool)
            .await
            .map_err(|_| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Ошибка проверки сессии".to_string(),
                )
            })?
        } else {
            sqlx::query_scalar(
                r#"
                SELECT 1
                FROM auth_sessions
                WHERE id = $1
                  AND user_id = $2
                  AND revoked_at IS NULL
                  AND expires_at > now()
                LIMIT 1
                "#,
            )
            .bind(session_id)
            .bind(data.claims.sub)
            .fetch_optional(&app_state.pool)
            .await
            .map_err(|_| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Ошибка проверки сессии".to_string(),
                )
            })?
        };

        if active.is_none() {
            return Err((
                StatusCode::UNAUTHORIZED,
                "Сессия недействительна".to_string(),
            ));
        }

        let _ = sqlx::query(
            r#"
            UPDATE auth_sessions
            SET last_seen_at = now()
            WHERE id = $1
            "#,
        )
        .bind(session_id)
        .execute(&app_state.pool)
        .await;

        Ok(CurrentUser {
            id: data.claims.sub,
            session_id,
        })
    }
}

pub async fn logging(req: Request, next: Next) -> Response {
    let started = Instant::now();
    let now = Local::now().format("%Y-%m-%d %H:%M:%S%.3f").to_string();
    let method = req.method().clone();
    let uri = req.uri().clone();
    let query = sanitize_query(uri.query().unwrap_or(""));
    let path = req
        .extensions()
        .get::<MatchedPath>()
        .map(|p| p.as_str().to_string())
        .unwrap_or_else(|| uri.path().to_string());
    let connect_ip = req
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|c| c.0.ip().to_string())
        .unwrap_or_else(|| "-".to_string());
    let forwarded_ip = req
        .headers()
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let from = forwarded_ip.unwrap_or(connect_ip);

    // IMPORTANT: do not consume request body for multipart uploads (it breaks parsing).
    // We also bypass body preview for /media endpoints.
    let (parts, body) = req.into_parts();

    let content_type = parts
        .headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    let should_skip_body =
        path.starts_with("/media") || content_type.to_ascii_lowercase().starts_with("multipart/");

    if should_skip_body {
        let req = Request::from_parts(parts, body);
        let res = next.run(req).await;

        let status = res.status();
        let elapsed = started.elapsed();
        println!(
            "{} | {} | {} {} | {} ms | {}",
            now,
            from,
            method,
            path,
            elapsed.as_millis(),
            status.as_u16()
        );
        if !query.is_empty() {
            println!("  query: {}", query);
        }
        if status.is_client_error() || status.is_server_error() {
            println!("Ошибка: статус {}", status.as_u16());
        }
        return res;
    }

    // Read and clone body with limit
    let bytes: Bytes = match to_bytes(body, 64 * 1024).await {
        // 64KB limit
        Ok(b) => b,
        Err(_) => Bytes::new(),
    };
    // Try to render body as UTF-8 text, truncate for safety
    // Redact sensitive payloads on auth routes.
    let body_preview = if path.starts_with("/auth/") {
        String::from("<redacted>")
    } else {
        match std::str::from_utf8(&bytes) {
            Ok(s) if !s.is_empty() => {
                let max = 2000.min(s.len());
                let snippet = &s[..max];
                // Quick heuristic: if body likely contains secrets, redact.
                if snippet.contains("\"password\"")
                    || snippet.contains("\"token\"")
                    || snippet.contains("Bearer ")
                {
                    String::from("<redacted>")
                } else {
                    snippet.to_string()
                }
            }
            _ => String::new(),
        }
    };
    // Rebuild request with the consumed body
    let req = Request::from_parts(parts, Body::from(bytes.clone()));

    let res = next.run(req).await;
    let status = res.status();
    let elapsed = started.elapsed();
    println!(
        "{} | {} | {} {} | {} ms | {}",
        now,
        from,
        method,
        path,
        elapsed.as_millis(),
        status.as_u16()
    );
    // extra line with query and body for tests
    if !query.is_empty() || !body_preview.is_empty() {
        println!("  query: {}\n  body: {}", query, body_preview);
    }
    if status.is_client_error() || status.is_server_error() {
        println!("Ошибка: статус {}", status.as_u16());
    }
    res
}

fn sanitize_query(raw: &str) -> String {
    if raw.is_empty() {
        return String::new();
    }

    raw.split('&')
        .map(|pair| {
            let mut it = pair.splitn(2, '=');
            let key = it.next().unwrap_or("");
            let value = it.next().unwrap_or("");
            if key.eq_ignore_ascii_case("token")
                || key.eq_ignore_ascii_case("access_token")
                || key.eq_ignore_ascii_case("refresh_token")
            {
                format!("{key}=<redacted>")
            } else {
                format!("{key}={value}")
            }
        })
        .collect::<Vec<_>>()
        .join("&")
}

// Утилита: убедиться, что пользователь — admin в указанном чате
pub async fn ensure_admin(
    state: &AppState,
    chat_id: i32,
    user_id: i32,
) -> Result<(), (StatusCode, String)> {
    let row = sqlx::query(
        r#"
        SELECT role
        FROM chat_participants
        WHERE chat_id = $1 AND user_id = $2
        "#,
    )
    .bind(chat_id)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Ошибка БД: {}", e),
        )
    })?;

    let Some(row) = row else {
        return Err((
            StatusCode::FORBIDDEN,
            "Вы не являетесь участником этого чата".into(),
        ));
    };

    let role: String = row.try_get("role").unwrap_or_else(|_| "member".to_string());
    if role != "admin" && role != "owner" {
        return Err((
            StatusCode::FORBIDDEN,
            "Недостаточно прав (нужна роль admin/owner)".into(),
        ));
    }
    Ok(())
}
