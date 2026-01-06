use axum::{async_trait, extract::{FromRequestParts, State, MatchedPath, ConnectInfo, Request}, http::{request::Parts, StatusCode, header}, middleware::Next, response::Response};
use axum::body::{Body, Bytes, to_bytes};
use axum::extract::FromRef;
use jsonwebtoken::{decode, DecodingKey, Validation};
use sqlx::Row;

use crate::AppState;
use crate::models::auth::Claims;
use std::net::SocketAddr;
use std::time::Instant;
use chrono::Local;

// Экстрактор текущего пользователя из заголовка Authorization: Bearer <JWT>
// Пример использования: fn handler(State(state): State<AppState>, CurrentUser { id }: CurrentUser) { ... }

// Утилита: убедиться, что пользователь является участником чата
pub async fn ensure_member(state: &AppState, chat_id: i32, user_id: i32) -> Result<(), (StatusCode, String)> {
    let exists: Option<i32> = sqlx::query_scalar(
        r#"SELECT 1 FROM chat_participants WHERE chat_id = $1 AND user_id = $2 LIMIT 1"#,
    )
    .bind(chat_id)
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    if exists.is_none() {
        return Err((StatusCode::FORBIDDEN, "Нет доступа: вы не являетесь участником чата".into()));
    }
    Ok(())
}
#[derive(Clone, Copy, Debug)]
pub struct CurrentUser {
    pub id: i32,
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
        let State(app_state): State<AppState> = State::from_request_parts(parts, state)
            .await
            .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Не удалось получить состояние приложения".to_string()))?;

        // Достаём токен из заголовка Authorization: Bearer <JWT>.
        // Для WebSocket upgrade некоторые клиенты/прокси могут не прокидывать Authorization,
        // поэтому поддерживаем fallback через query параметр ?token=<JWT>.
        let token: String = if let Some(auth_header) = parts
            .headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
        {
            auth_header
                .strip_prefix("Bearer ")
                .or_else(|| auth_header.strip_prefix("bearer "))
                .ok_or((StatusCode::UNAUTHORIZED, "Некорректный формат заголовка Authorization".to_string()))?
                .to_string()
        } else {
            let query = parts.uri.query().unwrap_or("");
            let mut token_q: Option<&str> = None;
            for pair in query.split('&') {
                let mut it = pair.splitn(2, '=');
                let k = it.next().unwrap_or("");
                let v = it.next().unwrap_or("");
                if k == "token" && !v.is_empty() {
                    token_q = Some(v);
                    break;
                }
            }
            token_q
                .ok_or((StatusCode::UNAUTHORIZED, "Отсутствует заголовок Authorization или query token".to_string()))?
                .to_string()
        };

        // Валидируем токен
        let data = decode::<Claims>(
            &token,
            &DecodingKey::from_secret(app_state.jwt_secret.as_bytes()),
            &Validation::default(),
        )
        .map_err(|_| (StatusCode::UNAUTHORIZED, "Невалидный или просроченный токен".to_string()))?;

        Ok(CurrentUser { id: data.claims.sub })
    }
}

pub async fn logging(req: Request, next: Next) -> Response {
    let started = Instant::now();
    let now = Local::now().format("%Y-%m-%d %H:%M:%S%.3f").to_string();
    let method = req.method().clone();
    let uri = req.uri().clone();
    let query = uri.query().unwrap_or("").to_string();
    let path = req.extensions().get::<MatchedPath>().map(|p| p.as_str().to_string()).unwrap_or_else(|| uri.path().to_string());
    let from = req.extensions().get::<ConnectInfo<SocketAddr>>().map(|c| c.0.ip().to_string()).unwrap_or_else(|| "-".to_string());

    // IMPORTANT: do not consume request body for multipart uploads (it breaks parsing).
    // We also bypass body preview for /media endpoints.
    let (parts, body) = req.into_parts();

    let content_type = parts
        .headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    let should_skip_body = path.starts_with("/media")
        || content_type.to_ascii_lowercase().starts_with("multipart/");

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
    let bytes: Bytes = match to_bytes(body, 64 * 1024).await { // 64KB limit
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
                if snippet.contains("\"password\"") || snippet.contains("\"token\"") || snippet.contains("Bearer ") {
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

// Утилита: убедиться, что пользователь — admin в указанном чате
pub async fn ensure_admin(state: &AppState, chat_id: i32, user_id: i32) -> Result<(), (StatusCode, String)> {
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
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Ошибка БД: {}", e)))?;

    let Some(row) = row else {
        return Err((StatusCode::FORBIDDEN, "Вы не являетесь участником этого чата".into()));
    };

    let role: String = row.try_get("role").unwrap_or_else(|_| "member".to_string());
    if role != "admin" {
        return Err((StatusCode::FORBIDDEN, "Недостаточно прав (нужна роль admin)".into()));
    }
    Ok(())
}
