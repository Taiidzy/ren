pub mod auth;
pub mod chats;
pub mod media;
pub mod users;
pub mod ws;

use crate::AppState;
use axum::Router;

// Общий роутер для модуля route (если позже появятся другие подмодули)
pub fn router() -> Router<AppState> {
    Router::new()
        .merge(auth::router())
        .merge(users::router())
        .merge(chats::router())
        .merge(media::router())
        .merge(ws::router())
}
