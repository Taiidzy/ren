---
title: Конфигурация
description: Описание всех конфигурационных параметров Ren
sidebar_position: 3
---

# Конфигурация

В этом документе описаны все конфигурационные параметры для каждого компонента Ren.

## Backend

Backend конфигурируется через переменные окружения. Рекомендуется использовать файл `.env` в директории `backend/`.

### Обязательные параметры

| Переменная | Описание | Пример |
|------------|----------|--------|
| `POSTGRES_USER` | Пользователь PostgreSQL | `postgres` |
| `POSTGRES_PASSWORD` | Пароль пользователя PostgreSQL | `postgres` |
| `POSTGRES_HOST` | Хост PostgreSQL | `127.0.0.1` или `db` (в Docker) |
| `POSTGRES_PORT` | Порт PostgreSQL | `5432` |
| `POSTGRES_DB` | Имя базы данных | `ren_messenger` |
| `JWT_SECRET` | Секретный ключ для подписи JWT (минимум 32 байта) | `change-me-use-32-bytes-min` |

### Опциональные параметры

| Переменная | Описание | По умолчанию | Пример |
|------------|----------|--------------|--------|
| `SDK_FINGERPRINT_ALLOWLIST` | Разрешённые fingerprint SDK (через запятую). Пустое значение отключает проверку. | `` | `abc123,def456` |
| `CORS_ALLOW_ORIGINS` | Разрешённые CORS origin (через запятую) | `https://messanger-ren.ru,https://www.messanger-ren.ru,http://localhost:3000,http://127.0.0.1:3000` | `https://example.com` |
| `PORT` | Порт для прослушивания backend | `8081` | `8081` |
| `ENABLE_EXTERNAL_GEO` | Включить внешние geo-запросы (0/1) | `0` | `0` |

### Пример полного `.env` файла

```env
# PostgreSQL
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432
POSTGRES_DB=ren_messenger

# JWT
JWT_SECRET=super-secret-32-byte-key-change-in-production

# Security
SDK_FINGERPRINT_ALLOWLIST=
CORS_ALLOW_ORIGINS=http://localhost:3000,http://127.0.0.1:3000

# Server
PORT=8081

# Geo
ENABLE_EXTERNAL_GEO=0
```

## Frontend

Frontend конфигурируется через файл `.env` в директории `frontend/` или переменные окружения при сборке.

### Переменные окружения

| Переменная | Описание | Пример |
|------------|----------|--------|
| `VITE_API_URL` | URL backend API | `http://localhost:8081` |
| `VITE_WS_URL` | URL WebSocket сервера | `ws://localhost:8081` |

### Пример `.env` для разработки

```env
VITE_API_URL=http://localhost:8081
VITE_WS_URL=ws://localhost:8081
```

### Пример для продакшена (при сборке)

```bash
VITE_API_URL=https://api.ren-messenger.com \
VITE_WS_URL=wss://api.ren-messenger.com \
npm run build
```

## Flutter приложение

Flutter приложение использует `dart-define` флаги для конфигурации privacy-функций.

### Privacy toggles

| Флаг | Описание | По умолчанию | Платформа |
|------|----------|--------------|-----------|
| `REN_ANDROID_FLAG_SECURE` | Запрет скриншотов на Android (FLAG_SECURE) | `false` | Android |
| `REN_IOS_PRIVACY_OVERLAY` | Privacy overlay на iOS | `false` | iOS |
| `REN_IOS_ANTI_CAPTURE` | Anti-capture на iOS | `false` | iOS |

### Пример запуска с privacy-фичами

```bash
# Debug с выключенными privacy-фичами
flutter run \
  --dart-define=REN_ANDROID_FLAG_SECURE=false \
  --dart-define=REN_IOS_PRIVACY_OVERLAY=false \
  --dart-define=REN_IOS_ANTI_CAPTURE=false

# Release с включённой защитой от скриншотов
flutter build apk --release \
  --dart-define=REN_ANDROID_FLAG_SECURE=true

# iOS release
flutter build ios --release \
  --dart-define=REN_IOS_PRIVACY_OVERLAY=true \
  --dart-define=REN_IOS_ANTI_CAPTURE=true
```

## Nginx

Nginx конфигурируется через файл `nginx/nginx.conf`.

### Переменные для Let's Encrypt

| Переменная | Описание | Пример |
|------------|----------|--------|
| `LETSENCRYPT_EMAIL` | Email для уведомлений Let's Encrypt | `admin@example.com` |
| `DOMAIN` | Доменное имя | `messanger-ren.ru` |

### Пример `.env` для Docker Compose

```env
LETSENCRYPT_EMAIL=admin@example.com
DOMAIN=messanger-ren.ru
```

## Ren-SDK

Ren-SDK не требует конфигурации на этапе выполнения. Все параметры задаются при сборке.

### Переменные окружения для скриптов сборки

| Переменная | Описание | Пример |
|------------|----------|--------|
| `SDK_VERIFY_LOCAL_DIR` | Локальный путь для verification bundle | `./backend/sdk-verification/current` |
| `SDK_VERIFY_SCP_TARGET` | Remote target для scp upload | `user@host:/path` |

### Флаги скриптов сборки

| Флаг | Описание |
|------|----------|
| `--android-only` | Собирать только для Android |
| `--no-upload` | Не загружать verification bundle на remote |
| `--no-sync-flutter` | Не копировать артефакты в flutter app |

## Docker Compose

Docker Compose использует файл `docker-compose.yaml` и `.env` в корне проекта.

### Переменные окружения

| Переменная | Описание | Пример |
|------------|----------|--------|
| `POSTGRES_USER` | Пользователь PostgreSQL | `postgres` |
| `POSTGRES_PASSWORD` | Пароль PostgreSQL | `postgres` |
| `POSTGRES_DB` | Имя базы данных | `ren_messenger` |
| `JWT_SECRET` | JWT секрет | `super-secret-key` |
| `LETSENCRYPT_EMAIL` | Email для Let's Encrypt | `admin@example.com` |
| `DOMAIN` | Домен | `messanger-ren.ru` |

### Запуск через Docker Compose

```bash
# Создать .env файл
cp .env.example .env

# Запустить все сервисы
docker-compose up -d

# Просмотр логов
docker-compose logs -f backend

# Остановить
docker-compose down
```

## Проверка конфигурации

### Backend

```bash
cd backend
cargo run

# Проверка health endpoint
curl http://localhost:8081/health
# Ответ: OK
```

### Frontend

```bash
cd frontend
npm run dev

# Откройте http://localhost:5173
```

### Flutter

```bash
cd apps/flutter
flutter pub get
flutter run

# Проверьте, что приложение подключается к backend
```

## Безопасность

### Рекомендации для продакшена

1. **JWT_SECRET**: Используйте криптографически стойкий случайный ключ (минимум 32 байта):

```bash
# Генерация случайного ключа
openssl rand -base64 32
```

2. **PostgreSQL**: Используйте сложные пароли и ограничьте доступ по сети.

3. **TLS**: Всегда используйте HTTPS/WSS в продакшене.

4. **CORS**: Укажите только доверенные origin.

5. **SDK_FINGERPRINT_ALLOWLIST**: Включите проверку fingerprint в продакшене.

## Миграция конфигурации

При обновлении версии проверяйте `CHANGELOG.md` на наличие новых конфигурационных параметров.
