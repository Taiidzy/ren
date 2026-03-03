# Message Flow Gap Map

Этот файл — карта текущего разрыва отправки сообщений (где именно цепочка обрывается) и точки, куда возвращать шифрование.

## 1) UI и точка разрыва отправки

Файл: `apps/flutter/lib/features/chats/presentation/chat_page.dart`

- `_messageTransportDisabled` — флаг разрыва (сейчас `true`).
- `_send()` — основная отправка текста/вложений.
- `_sendRecordedMedia()` — отправка голосовых/видео.
- `_forwardSelected()` — пересылка сообщений.
- `_dispatchPendingMediaTask()` — фоновая отправка pending media.
- `_buildSendPayload()` — собирает payload перед отправкой.

Ключевая идея: сейчас все эти точки останавливаются до реальной отправки в `RealtimeClient`.

## 2) Подготовка payload / шифрование (сейчас отключено)

Файл: `apps/flutter/lib/features/chats/data/chats_repository.dart`

- `buildOutgoingWsTextMessage(...)` — сборка исходящего text payload.
- `buildOutgoingWsMediaMessage(...)` — сборка исходящего media payload.
- `_encryptForRecipients(...)` — шифрование для получателей.
- `_encryptForRecipientWithRecovery(...)` — шифрование для одного получателя.
- `_ensureCiphertextsComplete(...)` — валидация ciphertext.

Сейчас эти функции выбрасывают `UnsupportedError('Message sending is disabled')`/`Message encryption is disabled`.

## 3) Транспорт WS (куда раньше уходила отправка)

Файл: `apps/flutter/lib/core/realtime/realtime_client.dart`

- `sendMessage(...)`
- `editMessage(...)`
- `forwardMessage(...)`
- внутренний `_send(...)`

Сюда должен попадать уже зашифрованный payload после восстановления цепочки.

## 4) Нативные каналы Signal (сейчас вырезаны из runtime)

Файлы:

- `apps/flutter/android/app/src/main/kotlin/com/example/ren/MainActivity.kt`
- `apps/flutter/ios/Runner/AppDelegate.swift`

Что удалено:

- Регистрация каналов `ren/signal_protocol` и `ren/signal_protocol/events`.
- Хэндлеры методов Signal на Android/iOS.

## 5) Flutter-обертка Signal (заглушка)

Файл: `apps/flutter/lib/core/e2ee/signal_protocol_client.dart`

- `initialize()`, `initUser()`, `hasSession()` — no-op/пустые ответы.
- `encrypt()/decrypt()/getFingerprint()/exportBackup()` — `UnsupportedError`.
- `importBackup()` — возвращает `false`.

## 6) Где включать обратно шифрование (минимальный маршрут)

1. В `chat_page.dart` убрать/переключить `_messageTransportDisabled`.
2. В `ChatsRepository` восстановить:
   - `buildOutgoingWsTextMessage`
   - `buildOutgoingWsMediaMessage`
   - `_encryptForRecipients` и связанные recovery-функции.
3. Убедиться, что из `_send()` и `_sendRecordedMedia()` payload доходит до `RealtimeClient.sendMessage(...)`.
4. Если нужен нативный Signal runtime, вернуть MethodChannel/EventChannel в `MainActivity.kt` и `AppDelegate.swift`.
5. Синхронизировать `signal_protocol_client.dart` с реальными channel-вызовами.

