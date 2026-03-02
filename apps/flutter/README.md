# Ren Flutter App

Мобильный клиент Ren (iOS/Android) на Flutter.

## Что внутри

- UI/UX чатов и профиля.
- Realtime через WebSocket.
- Native Signal bridge (`MethodChannel`) для E2EE в private-чатах.
- Медиа-сообщения: фото/видео/голосовые/файлы.

## Запуск

```bash
flutter pub get
flutter run
```

## Проверки

```bash
flutter analyze
flutter test
```

## E2EE (private)

Основной клиентский фасад:

- `lib/core/e2ee/signal_protocol_client.dart`

Интеграция с отправкой/получением сообщений:

- `lib/features/chats/data/chats_repository.dart`
- `lib/features/chats/presentation/chat_page.dart`

Ключевые свойства:

- fail-closed отправка: при ошибке шифрования сообщение не уходит;
- retry/recovery шифрования: reset session + fresh prekey bundle;
- медиа шифруется per-recipient в `metadata.ciphertext_by_user`.

## Документация

- `docs/SIGNAL_MIGRATION.md`
- `../../docs/E2EE_RUNBOOK.md`
