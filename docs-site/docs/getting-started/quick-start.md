---
title: Быстрый старт
description: Минимальный пример запуска Ren от нуля до работающего приложения
sidebar_position: 2
---

# Быстрый старт

Это руководство поможет вам запустить Ren локально за несколько минут.

## Шаг 1: Клонирование репозитория

```bash
git clone https://github.com/taiidzy/ren.git
cd ren
```

## Шаг 2: Настройка PostgreSQL

```bash
# Создайте базу данных
psql -U postgres
CREATE DATABASE ren_messenger;
\q
```

## Шаг 3: Настройка backend

Создайте файл `backend/.env`:

```env
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432
POSTGRES_DB=ren_messenger
JWT_SECRET=change-me-use-32-bytes-min

# Опционально: SDK attestation
SDK_FINGERPRINT_ALLOWLIST=

# Опционально: CORS allowlist
CORS_ALLOW_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
```

## Шаг 4: Сборка Ren-SDK

### macOS

```bash
cd Ren-SDK
chmod +x build.sdk.sh
./build.sdk.sh
```

### Windows (PowerShell)

```powershell
cd Ren-SDK
.\build.sdk.ps1
```

### Linux

```bash
cd Ren-SDK
chmod +x build.sh
./build.sh linux
```

Скрипт автоматически:
- Соберёт SDK для целевой платформы
- Скопирует библиотеки в `apps/flutter`
- Создаст verification bundle

## Шаг 5: Запуск backend

```bash
cd backend
cargo run
```

При первом запуске автоматически выполняются миграции из `backend/migrations`.

Сервер запустится на `http://0.0.0.0:8081`.

Проверка:

```bash
curl http://localhost:8081/health
# Ответ: OK
```

## Шаг 6: Запуск Flutter приложения

```bash
cd apps/flutter
flutter pub get
flutter run
```

### Privacy toggles (опционально)

```bash
flutter run \
  --dart-define=REN_ANDROID_FLAG_SECURE=false \
  --dart-define=REN_IOS_PRIVACY_OVERLAY=false \
  --dart-define=REN_IOS_ANTI_CAPTURE=false
```

### Release сборка с privacy-фичами

```bash
# Android
flutter build apk --release \
  --dart-define=REN_ANDROID_FLAG_SECURE=true

# iOS
flutter build ios --release \
  --dart-define=REN_IOS_PRIVACY_OVERLAY=true
```

## Шаг 7: Запуск frontend (опционально)

```bash
cd frontend

# Установите зависимости
npm install

# Настройте API URL
echo "VITE_API_URL=http://localhost:8081" > .env
echo "VITE_WS_URL=ws://localhost:8081" >> .env

# Запустите dev-сервер
npm run dev
```

Веб-приложение будет доступно на `http://localhost:5173`

## Проверка работы

1. Откройте Flutter приложение или веб-интерфейс
2. Зарегистрируйте нового пользователя:
   - Введите логин, username, пароль
   - Сохраните ключ восстановления (6 символов)
3. Войдите под учётной записью
4. Создайте чат с другим пользователем (откройте в другом браузере/устройстве)
5. Отправьте зашифрованное сообщение

## Использование скриптов запуска

В репозитории есть удобные скрипты для запуска и сборки:

### Запуск

```bash
# iOS с пересборкой SDK
./scripts/run.sh ios --sdk

# macOS
./scripts/run.sh macos

# Linux
./scripts/run.sh linux --release

# Windows
./scripts/run.sh windows
```

### Сборка

```bash
# iOS без codesign
./scripts/build.sh ios --sdk --no-codesign

# macOS release
./scripts/build.sh macos --release --output dist/

# Linux debug
./scripts/build.sh linux --debug
```

## Возможные проблемы

### Ошибка подключения к PostgreSQL

```
error: connection refused
```

**Решение:** Убедитесь, что PostgreSQL запущен:

```bash
# Linux
sudo systemctl start postgresql

# macOS
brew services start postgresql@14
```

### Ошибка компиляции Rust

```
error[E0xxx]: ...
```

**Решение:** Обновите Rust до последней версии:

```bash
rustup update
```

### Flutter не находит SDK

```
Error: Couldn't find the file 'libren_sdk.so'
```

**Решение:** Пересоберите Ren-SDK:

```bash
cd Ren-SDK
./build.sdk.sh
```

## Следующие шаги

- [Конфигурация](/docs/getting-started/configuration) — описание всех параметров
- [Руководства пользователя](/docs/guides/registration) — сценарии использования
- [API Reference](/docs/api/reference) — документация API
