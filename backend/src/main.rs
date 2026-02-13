// ---------------------------
// Импорты
// ---------------------------
use axum::{Router, middleware::from_fn, routing::get};
use dashmap::{DashMap, DashSet};
use sqlx::{PgPool, postgres::PgPoolOptions};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::broadcast;
use tower_http::cors::CorsLayer;

// Подключаем модуль с маршрутами
mod route;
// Подключаем модуль с моделями (auth/chats)
pub mod models;
// Подключаем модуль с экстракторами аутентификации
pub mod middleware;

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
    // Онлайн пользователи (наличие активного ws-соединения)
    pub online_users: Arc<DashSet<i32>>,
    // Пользователи, находящиеся внутри конкретного чата (join_chat)
    pub in_chat: Arc<DashSet<(i32, i32)>>,
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
    let online_users = Arc::new(DashSet::new());
    let in_chat = Arc::new(DashSet::new());
    let state = AppState {
        pool,
        jwt_secret,
        ws_hub,
        user_hub,
        online_users,
        in_chat,
    };

    // Сборка роутера приложения.
    // Добавим простой health-check и подключим роуты авторизации.
    let app = Router::new()
        .route("/health", get(|| async { "OK" }))
        .merge(route::router())
        .layer(CorsLayer::permissive())
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
