// ---------------------------
// Импорты
// ---------------------------
use axum::{
    Router,
    http::{HeaderName, HeaderValue, Method, header},
    middleware::from_fn,
    routing::get,
};
use dashmap::DashMap;
use sqlx::{PgPool, postgres::PgPoolOptions};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::broadcast;
use tower_http::cors::{AllowOrigin, CorsLayer};

// Подключаем модуль с маршрутами
mod route;
// Подключаем модуль с моделями (auth/chats)
pub mod models;
// Подключаем модуль с экстракторами аутентификации
pub mod middleware;

use crate::middleware::rate_limit::{AuthRateLimiterConfig, RateLimiterConfig};

// Делаем состояние приложения доступным в остальных модулях (например, в маршрутах)
// чтобы в хендлерах был доступ к пулу соединений PostgreSQL.
#[derive(Clone)]
pub struct AppState {
    // Пул соединений с Postgres
    pub pool: PgPool,
    // Секрет для подписи JWT-токенов, читается из переменной окружения JWT_SECRET
    pub jwt_secret: String,
    // Хаб websocket-каналов по chat_id: широковещательная рассылка событий
    pub ws_hub: Arc<DashMap<i32, broadcast::Sender<String>>>,
    // Хаб пользовательских каналов по user_id: входящие уведомления (presence и т.п.)
    pub user_hub: Arc<DashMap<i32, broadcast::Sender<String>>>,
    // Количество активных ws-соединений по user_id (для мульти-девайсной сессии)
    pub online_connections: Arc<DashMap<i32, usize>>,
    // P1-7: Rate limiter для общих запросов
    pub rate_limiter: middleware::RateLimiter,
    // P1-7: Rate limiter для auth-эндпоинтов
    pub auth_rate_limiter: middleware::AuthRateLimiter,
}

// Основная асинхронная функция запуска приложения
async fn async_main() {
    // Загружаем переменные окружения из файла .env (если он есть).
    let _ = dotenvy::dotenv();
    let postgres_user =
        std::env::var("POSTGRES_USER").expect("Переменная окружения POSTGRES_USER не установлена");
    let postgres_password = std::env::var("POSTGRES_PASSWORD")
        .expect("Переменная окружения POSTGRES_PASSWORD не установлена");
    let postgres_host =
        std::env::var("POSTGRES_HOST").expect("Переменная окружения POSTGRES_HOST не установлена");
    let postgres_port = std::env::var("POSTGRES_PORT").unwrap_or_else(|_| "8081".to_string());
    let postgres_db =
        std::env::var("POSTGRES_DB").expect("Переменная окружения POSTGRES_DB не установлена");
    let database_url = format!(
        "postgres://{}:{}@{}:{}/{}",
        postgres_user, postgres_password, postgres_host, postgres_port, postgres_db
    );
    // Секрет для подписи JWT, обязателен
    let jwt_secret =
        std::env::var("JWT_SECRET").expect("Переменная окружения JWT_SECRET не установлена");
    let cors_allow_origins = std::env::var("CORS_ALLOW_ORIGINS")
        .unwrap_or_else(|_| {
            "https://messanger-ren.ru,https://www.messanger-ren.ru,http://localhost:3000,http://127.0.0.1:3000".to_string()
        })
        .split(',')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| HeaderValue::from_str(s).expect("invalid CORS_ALLOW_ORIGINS value"))
        .collect::<Vec<HeaderValue>>();

    // Порт для прослушивания
    let port = 8081;

    // Создаем пул соединений с БД.
    // Пул — это набор заранее открытых соединений, чтобы хендлеры могли быстро
    // получать доступ к БД без накладных расходов на установку соединения.
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await
        .expect("Не удалось подключиться к базе данных");

    // Выполняем миграции при старте (из каталога ./migrations)
    // Это надёжнее, чем создавать таблицы вручную в коде.
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Не удалось выполнить миграции базы данных");

    // Инициализируем состояние для передачи в маршруты.
    let ws_hub = Arc::new(DashMap::new());
    let user_hub = Arc::new(DashMap::new());
    let online_connections = Arc::new(DashMap::new());

    // P1-7: Initialize rate limiters
    let rate_limiter = middleware::RateLimiter::new(RateLimiterConfig {
        max_requests: 100, // 100 requests per minute
        window_duration: std::time::Duration::from_secs(60),
        enable_ip_limiting: true,
        enable_account_limiting: true,
    });

    let auth_rate_limiter = middleware::AuthRateLimiter::new(AuthRateLimiterConfig {
        max_failures: 5,                                      // 5 failed attempts
        lockout_duration: std::time::Duration::from_secs(60), // 1 minute initial
        backoff_multiplier: 2,                                // Exponential backoff
        max_lockout: std::time::Duration::from_secs(3600),    // Max 1 hour
    });

    let state = AppState {
        pool,
        jwt_secret,
        ws_hub,
        user_hub,
        online_connections,
        rate_limiter,
        auth_rate_limiter,
    };

    // Сборка роутера приложения.
    // Добавим простой health-check и подключим роуты авторизации.
    let app = Router::new()
        .route("/health", get(|| async { "OK" }))
        .merge(route::router())
        .layer(
            CorsLayer::new()
                .allow_origin(AllowOrigin::list(cors_allow_origins))
                .allow_methods([
                    Method::GET,
                    Method::POST,
                    Method::PUT,
                    Method::PATCH,
                    Method::DELETE,
                    Method::OPTIONS,
                ])
                .allow_headers([
                    header::AUTHORIZATION,
                    header::CONTENT_TYPE,
                    HeaderName::from_static("x-device-name"),
                    HeaderName::from_static("x-app-version"),
                ]),
        )
        .layer(from_fn(middleware::logging))
        .with_state(state);

    let addr = std::net::SocketAddr::from(([0, 0, 0, 0], port));
    println!("Server running on http://{addr}");
    let listener = TcpListener::bind(addr)
        .await
        .expect("Не удалось открыть порт для прослушивания");
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .expect("Сервер завершился с ошибкой");
}

fn main() {
    // Точка входа в приложение. Запускаем асинхронный рантайм Tokio.
    // Отдельная асинхронная функция `async_main` содержит всю логику запуска.
    tokio::runtime::Runtime::new()
        .expect("failed to create tokio runtime")
        .block_on(async_main());
}
