# Changelog

## 2026-03-03

### Added
- Docker Compose конфигурация для dev и prod окружений:
  - `docker-compose.dev.yaml` — запуск через `cargo run`, отдельная dev БД;
  - `docker-compose.prod.yaml` — сборка в release режиме и запуск бинарника, отдельная prod БД;
  - использование `.env` для управления переменными окружения.

## 2026-03-02

### Fixed
- Критический дефект инициализации Signal-сессии: устранена потеря первого prekey-message на отправителе.
- Fail-closed отправка для E2EE:
  - сообщение не отправляется, если шифрование не удалось хотя бы для одного получателя;
  - добавлен recovery-проход (reset session + fresh bundle + повторное шифрование).
- Android pre-key lifecycle:
  - синхронизация и автопополнение one-time pre-keys;
  - устранено повторное «воскрешение» использованных pre-key после перезапуска.
- iOS key-store namespace:
  - изоляция session/prekey/identity key state по `userId/deviceId`.
- Backend `GET /users/:id/public-key`:
  - атомарная выдача и расходование one-time pre-key (`FOR UPDATE` + update в транзакции).
- Медиа E2EE для получателя:
  - backend-модель `FileMetadata` теперь сохраняет/возвращает `ciphertext_by_user` и `signal_ciphertext_by_user`.
- Self-echo merge для медиа:
  - в `ChatPage` сохранён локальный fallback вложений, если decrypt вложения из WS временно недоступен.

### Changed
- In-app top banner:
  - добавлена анимация появления/скрытия (slide + fade + scale);
  - добавлен haptic feedback при показе.
- Realtime sync списка чатов:
  - убраны лишние `GET /chats` на каждый message event при открытом чате;
  - добавлен debounce для фоновой синхронизации.
- Репозиторий очищен от legacy SDK-сборки в dev-скриптах:
  - удалены `--sdk` флаги из `scripts/build.sh` и `scripts/run.sh`;
  - удалён устаревший `scripts/run-ios-release-with-sdk.sh`.

### Security
- Подготовлена инфраструктура под клиентскую подпись Signal bundle:
  - добавлена колонка `users.key_signature`;
  - сервер хранит клиентскую подпись в bundle.
- Валидация подписи на сервере переведена в управляемый режим:
  - strict-check включается через `STRICT_SIGNAL_SIGNATURE_VERIFY`.

## 2026-03-01

### Added
- Native Signal Protocol bridge для Flutter (`MethodChannel` / `EventChannel`):
  - `initUser`
  - `encrypt`
  - `decrypt`
  - `hasSession`
  - `getFingerprint`
- События смены identity (`identity_changed`) из native слоя в Flutter.
- Поддержка Kyber полей в Signal bundle на backend:
  - `kyber_pre_key_id`
  - `kyber_pre_key`
  - `kyber_pre_key_signature`

### Changed
- Flutter переведён с legacy SDK на native Signal-интеграцию.
- iOS: переход на `LibSignalClient` flow с persistent store в Keychain.
- Android: переход на `libsignal-client` flow с persistent store в `EncryptedSharedPreferences`.
- Подправлена iOS-сборка (Signal/FFmpeg зависимости для simulator).

### Removed
- Legacy SDK артефакты и старые FFI-привязки из Flutter.
