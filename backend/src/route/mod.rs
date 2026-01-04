pub mod auth;
pub mod users;
pub mod chats;
pub mod ws;
pub mod media;

use axum::Router;
use crate::AppState;

// Общий роутер для модуля route (если позже появятся другие подмодули)
pub fn router() -> Router<AppState> {
    Router::new()
        .merge(auth::router())
        .merge(users::router())
        .merge(chats::router())
        .merge(media::router())
        .merge(ws::router())
}
