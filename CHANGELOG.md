# Changelog

## [Unreleased] - 2026-02-19

### Flutter App (`apps/flutter`)

#### Realtime / auth transport hardening
- Убран токен из query-параметра WebSocket URL в `lib/core/realtime/realtime_client.dart`.
- Авторизация WebSocket переведена на `Authorization` header.
- Добавлена передача `X-SDK-Fingerprint` в WS handshake headers.
- Практический эффект:
  - меньше риск утечки токена через access-логи прокси/серверов;
  - cleaner trust boundary между клиентом и backend attestation.

#### Privacy controls (runtime-toggle, default OFF)
- Добавлен модуль `lib/core/security/privacy_protection.dart`.
- В `lib/main.dart` добавлен ранний вызов `PrivacyProtection.configure()`.
- Поддержаны флаги через `--dart-define`:
  - `REN_ANDROID_FLAG_SECURE`
  - `REN_IOS_PRIVACY_OVERLAY`
  - `REN_IOS_ANTI_CAPTURE`
- Реализован MethodChannel `ren/privacy_protection` между Flutter и нативными платформами.
- Все privacy-механизмы по умолчанию выключены (без изменения поведения в dev-сценариях).

#### Android privacy
- В `android/app/src/main/kotlin/com/example/ren/MainActivity.kt` добавлен toggle для `FLAG_SECURE` через MethodChannel.
- Поддержка включения/выключения anti-screenshot без пересборки нативной логики.

#### iOS privacy
- В `ios/Runner/AppDelegate.swift` добавлен управляемый privacy overlay при уходе приложения в background.
- Добавлен управляемый anti-capture flow (реакция на изменение screen capture state).
- Оба механизма управляются из Flutter-конфига, с default OFF.

#### SDK fingerprint propagation
- `lib/core/network/auth_session_interceptor.dart`:
  - добавлен `X-SDK-Fingerprint` в обычные запросы и в refresh-клиент.
- `lib/core/realtime/realtime_client.dart`:
  - добавлен `X-SDK-Fingerprint` в WS headers.
- `lib/features/profile/data/profile_api.dart`:
  - добавлен `X-SDK-Fingerprint` в multipart upload.
- Практический эффект:
  - backend может стабильно связывать сессию и сетевые вызовы с ожидаемым fingerprint SDK.

#### SDK integrity checks (client side)
- В `lib/core/sdk/ren_sdk.dart`:
  - добавлен ABI-specific hash pinning для Android `libren_sdk.so`;
  - добавлен runtime поиск фактически загруженной библиотеки через `/proc/self/maps`;
  - добавлена проверка SHA-256 загруженного binary against pinned hash;
  - добавлен `currentSdkFingerprint()` для transport attestation.
- Практический эффект:
  - базовая защита от подмены `.so` на устройстве и от несоответствия ожидаемого SDK.

#### Attachments performance / memory pressure
- `lib/features/chats/presentation/widgets/chat_pending_attachment.dart`:
  - `PendingChatAttachment` расширен до явной модели состояния (`queued/sending/failed`), добавлен `clientId`, `error`, `copyWith`, state transitions.
- `lib/features/chats/presentation/chat_page.dart`:
  - отправка берёт только `queued` элементы;
  - добавлен send-guard `_isSendingMessage` против повторной/параллельной отправки;
  - ошибка отправки переводит pending-вложения в `failed`, а не теряет их;
  - successful send удаляет только отправленные элементы по `clientId`;
  - сохранено восстановление draft/reply/editing при fail.
- `lib/features/chats/presentation/widgets/chat_input_bar.dart`:
  - добавлен UI состояния pending-вложений: overlay для `sending`, label ошибки для `failed`, retry/cancel controls;
  - кнопка Send теперь учитывает только `queued` pending (failed не триггерят send state);
  - при записи voice/video убрано eager `readAsBytes`, используется size/path-first подход.
- Практический эффект:
  - меньше RAM spikes на медиа;
  - меньше race conditions;
  - предсказуемое UX-поведение очереди вложений на плохой сети.

#### Media pipeline / heavy work isolation
- `lib/features/chats/data/chats_repository.dart`:
  - добавлена serial media queue (`_runInMediaPipeline`) для backpressure;
  - добавлен retry upload (`_uploadMediaWithRetry`);
  - encryption для attachments вынесена в `Isolate.run`.
- Практический эффект:
  - снижена конкуренция тяжелых задач на UI thread;
  - выше устойчивость при burst send/media.

#### Additional chat reliability fixes
- Улучшен rollback optimistic send для voice/video при ошибке.
- Убрано лишнее future churn в `chat_message_bubble.dart` (стабильнее рендер на скролле и при частых rebuild).


### Backend (`backend`)

#### Auth transport hardening
- В `src/middleware/mod.rs` удалён fallback аутентификации через query-параметры.
- Поддержан только header-based flow (`Authorization`).

#### Request logging sanitization
- В `src/middleware/mod.rs` добавлена санитизация query-параметров (`token`, `access_token`, `refresh_token`) в логах.

#### SDK attestation (session-bound)
- В `src/main.rs`:
  - добавлен `sdk_fingerprint_allowlist` в `AppState`;
  - добавлен парсинг `SDK_FINGERPRINT_ALLOWLIST` из env.
- Миграция `migrations/20260219120000_auth_sessions_sdk_fingerprint.sql`:
  - добавлена колонка `auth_sessions.sdk_fingerprint`;
  - добавлен индекс по fingerprint.
- В `src/route/auth.rs`:
  - login/refresh требуют и валидируют `x-sdk-fingerprint` при непустом allowlist;
  - fingerprint сохраняется/обновляется в `auth_sessions`;
  - список сессий возвращает fingerprint.
- В `src/models/auth.rs`:
  - `SessionResponse` расширен `sdk_fingerprint: Option<String>`.
- В `src/middleware/mod.rs`:
  - на защищённых роутерах при включённом allowlist проверяется:
    - наличие `x-sdk-fingerprint`,
    - вхождение в allowlist,
    - совпадение с fingerprint, привязанным к текущей auth session.
- Практический эффект:
  - усилен контроль целостности client SDK на уровне сессий и API-доступа.

#### CORS tightening
- В `src/main.rs`:
  - `CorsLayer::permissive()` заменён на allowlist origins через `CORS_ALLOW_ORIGINS`;
  - явно ограничены методы и headers (в т.ч. `x-sdk-fingerprint`).


### Ren-SDK (`Ren-SDK`)

#### FFI panic safety
- В `src/ffi.rs` введён `ffi_catch(...)` (catch_unwind) и обёрнуты FFI entrypoints.
- Практический эффект:
  - снижена вероятность process abort из-за panic при внешних FFI-вызовах.

#### Key material zeroization
- В `Cargo.toml` добавлен `zeroize`.
- В `src/mod.rs` добавлен `Drop` lifecycle для очистки `AeadKey`.
- В `src/crypto.rs` и `src/ffi.rs` очищаются временные ключевые буферы.

#### base64 API modernization
- В `src/ffi.rs` и `src/wasm.rs` deprecated `base64::encode/decode` переведены на `Engine`.

#### Sync API for isolate-friendly encryption
- В SDK добавлен sync encrypt pathway (`encryptFileSync` на стороне Flutter wrapper), используемый для вынесения тяжёлого encryption из UI isolate.


### Build / Release automation (`Ren-SDK`)

#### New cross-platform build scripts
- Добавлены:
  - `Ren-SDK/build.macos.sh`
  - `Ren-SDK/build.windows.ps1`
- Оба скрипта реализуют единый функциональный pipeline:
  - сборка SDK под целевые платформы;
  - копирование артефактов в Flutter app;
  - сборка verification bundle;
  - копирование verification bundle в backend;
  - опциональная отправка на удалённый сервер для верификации.

#### Unified wrappers with shared flags
- Добавлены:
  - `Ren-SDK/build.sdk.sh`
  - `Ren-SDK/build.sdk.ps1`
- Общие флаги:
  - `--android-only`
  - `--no-upload`
  - `--no-sync-flutter`
- Эквивалентные env-переменные:
  - `SDK_BUILD_ANDROID_ONLY`
  - `SDK_SKIP_REMOTE_UPLOAD`
  - `SDK_SKIP_FLUTTER_SYNC`

#### Verification artifacts
- Verification bundle формируется в `Ren-SDK/target/sdk-verification/<timestamp>/`.
- Содержит:
  - platform binaries;
  - `SHA256SUMS.txt`;
  - `SDK_FINGERPRINT_ALLOWLIST.env`.
- Локальная синхронизация по умолчанию:
  - `backend/sdk-verification/current`
- Опциональная удалённая синхронизация:
  - `SDK_VERIFY_SCP_TARGET=<user@host:/path>`


### Validation
- `flutter analyze` (apps/flutter): OK.
- Targeted tests (pending attachment model): OK.
- `cargo check` (backend): OK.
