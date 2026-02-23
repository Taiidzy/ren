---
title: Troubleshooting
description: Типичные проблемы и их решения
sidebar_position: 2
---

# Troubleshooting

Это руководство поможет решить типичные проблемы при установке, запуске и использовании Ren.

## Установка

### Ошибка компиляции Rust

**Проблема:**

```
error[E0xxx]: ...
```

**Причина:** Устаревшая версия Rust.

**Решение:**

```bash
rustup update stable
rustup default stable
```

### Flutter не находит SDK

**Проблема:**

```
Error: Couldn't find the file 'libren_sdk.so'
```

**Причина:** Ren-SDK не собран.

**Решение:**

```bash
cd Ren-SDK
./build.sdk.sh

# Для Android
./build.sdk.sh android

# Для iOS
./build.sdk.sh ios
```

### PostgreSQL не подключается

**Проблема:**

```
error: connection refused
```

**Причина:** PostgreSQL не запущен или неверные учётные данные.

**Решение:**

```bash
# Проверить статус
sudo systemctl status postgresql

# Запустить
sudo systemctl start postgresql

# Проверить подключение
psql -U postgres -h localhost
```

### Node.js версия

**Проблема:**

```
Error: Node.js v16 is not supported. Please use v18 or higher.
```

**Решение:**

```bash
# Через nvm
nvm install 18
nvm use 18

# Или обновите глобально
npm install -g n
n 18
```

## Backend

### Миграции не выполняются

**Проблема:**

```
Error: migration failed: relation "users" already exists
```

**Причина:** Конфликт с существующей БД.

**Решение:**

```bash
# Очистить БД (development only!)
psql -U postgres -d ren_messenger
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
\q

# Перезапустить backend
cargo run
```

### JWT токен невалидный

**Проблема:**

```
401 Unauthorized: Невалидный или просроченный токен
```

**Причина:** Истёк срок действия токена или изменён JWT_SECRET.

**Решение:**

1. Перезайдите в приложение
2. Проверьте `JWT_SECRET` в `.env` (не менялся ли)
3. Используйте `remember_me=true` для долгого токена

### WebSocket не подключается

**Проблема:**

```
WebSocket connection failed
```

**Причина:** Неправильная конфигурация Nginx или firewall.

**Решение:**

Проверьте Nginx конфигурацию:

```nginx
location /ws {
    proxy_pass http://backend:8081/ws;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

### Rate limit превышен

**Проблема:**

```
429 Too Many Requests
```

**Причина:** Превышен лимит запросов.

**Решение:**

- Подождите 1 минуту (initial lockout)
- При повторных нарушениях lockout увеличивается до 1 часа
- Проверьте логи на предмет атак

## Flutter приложение

### Приложение не запускается

**Проблема:**

```
Unable to start activity: FileNotFoundException
```

**Причина:** Нативная библиотека не найдена.

**Решение:**

```bash
# Пересобрать SDK
cd Ren-SDK
./build.sdk.sh

# Очистить Flutter
flutter clean
flutter pub get

# Запустить
flutter run
```

### Ошибка FFI

**Проблема:**

```
Invalid argument(s): Failed to load dynamic library
```

**Причина:** Несоответствие архитектуры или пути к библиотеке.

**Решение:**

```bash
# Для Android
cargo ndk --target aarch64-linux-android build --release

# Для iOS
./build.sdk.sh ios

# Проверить наличие библиотек
ls apps/flutter/android/app/src/main/jniLibs/
ls apps/flutter/ios/RenSDK.xcframework/
```

### Secure storage не работает

**Проблема:**

```
PlatformException: Key not found
```

**Причина:** Ключи не сохранены или приложение переустановлено.

**Решение:**

1. Выйдите из приложения
2. Зайдите заново с логином/паролем
3. Сохраните ключ восстановления

### Уведомления не приходят

**Проблема:**

```
Push notifications not working
```

**Причина:** Не настроены Firebase (Android) или APNs (iOS).

**Решение:**

> TODO: Добавить инструкцию по настройке push-уведомлений

Временно используются локальные уведомления.

## Frontend

### WASM не загружается

**Проблема:**

```
Error: WebAssembly.instantiate(): Import #0 module="env" function="__wbindgen_malloc"
```

**Причина:** Несоответствие версий wasm-bindgen.

**Решение:**

```bash
# Пересобрать WASM
cd Ren-SDK
wasm-pack build --target web

# Пересобрать frontend
cd frontend
npm run build
```

### CORS ошибка

**Проблема:**

```
Access to fetch at 'http://localhost:8081' has been blocked by CORS policy
```

**Причина:** Backend не настроен для CORS.

**Решение:**

Проверьте `CORS_ALLOW_ORIGINS` в `.env` backend:

```env
CORS_ALLOW_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
```

### Vite dev server не запускается

**Проблема:**

```
Error: Port 5173 is already in use
```

**Решение:**

```bash
# Найти процесс
lsof -i :5173

# Убить процесс
kill -9 <PID>

# Или использовать другой порт
npm run dev -- --port 5174
```

## E2EE шифрование

### Сообщение не расшифровывается

**Проблема:**

```
CryptoError: Key mismatch
```

**Причина:** Приватный ключ не соответствует публичному.

**Решение:**

1. Выйдите из приложения
2. Очистите данные приложения
3. Зайдите заново с логином/паролем
4. Если не помогает — восстановите через recovery key

### Recovery key не работает

**Проблема:**

```
RecoveryError: Invalid recovery key
```

**Причина:** Неправильно введённая фраза.

**Решение:**

- Проверьте каждое слово (12 слов)
- Фраза чувствительна к порядку
- Используйте слова из стандартного списка BIP39

### Self-check не прошёл

**Проблема:**

```
SelfCheckError: Key pair mismatch
```

**Причина:** Приватный ключ был изменён или повреждён.

**Решение:**

Восстановите доступ через recovery key.

## Производительность

### Медленная загрузка файлов

**Проблема:**

```
Файлы загружаются дольше 30 секунд
```

**Причина:** Большие файлы или медленное соединение.

**Решение:**

- Разделите файл на части (&lt;50MB каждая)
- Проверьте скорость соединения
- Используйте chunked upload

### Приложение тормозит

**Проблема:**

```
UI лагает при прокрутке чата
```

**Причина:** Много сообщений или кэшированных файлов.

**Решение:**

```bash
# Очистить кэш (Flutter)
Настройки → Хранилище → Очистить кэш

# Или вручную
rm -rf <app_data_directory>/ren_ciphertext_cache/
```

## Логи и отладка

### Backend логи

```bash
# Запуск с логированием
RUST_LOG=debug cargo run

# Просмотр логов Docker
docker-compose logs -f backend
```

### Flutter логи

```bash
# Запуск с логированием
flutter run --verbose

# Просмотр логов
adb logcat | grep ren  # Android
idevicesyslog | grep ren  # iOS
```

### Frontend логи

```bash
# Browser console
# Откройте DevTools → Console

# Vite логи
npm run dev -- --debug
```

## Ещё помощь

Если проблема не решена:

1. **Проверьте Issues:** https://github.com/taiidzy/ren/issues
2. **Создайте Issue:** Опишите проблему, шаги воспроизведения, логи
3. **Контакты:** taiidzy@yandex.ru
