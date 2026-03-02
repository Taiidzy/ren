# Ren

Self-hosted мессенджер на Flutter + Rust backend с E2EE для личных чатов.

## Текущее состояние

- Личные чаты (`private`): Signal-based E2EE (native iOS/Android bridge).
- Группы/каналы: без E2EE (server-visible payload).
- Медиа в личных чатах: шифруется per-recipient через `ciphertext_by_user`.
- Backend хранит/ретранслирует ciphertext и не участвует в расшифровке.

Важно: при потере локального Signal state на устройстве часть истории может быть нерасшифруема. Механизм защищённого кросс-девайс backup/restore будет добавлен отдельно.

## Репозиторий

- `apps/flutter` — мобильный клиент (Dart + native Signal bridge).
- `backend` — API + WebSocket (Axum, PostgreSQL).
- `frontend` — web-клиент (вторичный).
- `docs` — техдок и runbook.

`Ren-SDK` оставлен в репозитории как legacy-архив и не участвует в текущем runtime-потоке Signal E2EE.

## Быстрый старт

### Backend

```bash
cd backend
cp .env.example .env
cargo run
```

Минимально требуются переменные:

- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_HOST`
- `POSTGRES_PORT`
- `POSTGRES_DB`
- `JWT_SECRET`

### Flutter

```bash
cd apps/flutter
flutter pub get
flutter run
```

## E2EE: как устроено

### Личные сообщения

- Клиент шифрует сообщение на каждого получателя (`ciphertext_by_user`).
- Payload в `message`:
  - `{"signal_v":1,"ciphertext_by_user":{"<uid>":"<signal-envelope>"}}`
- Signal envelope (внутри значения):
  - base64(JSON) `{"v":2,"t":"prekey|whisper","b":"<base64(signal-bytes)>"}`

### Медиа

- Для файла/голосового/видео/фото используется тот же per-recipient подход.
- В `metadata[]` сохраняется `ciphertext_by_user` (или alias `signal_ciphertext_by_user`).
- Клиент расшифровывает вложение из персонального ciphertext.

### Fail-closed отправка

Отправка не выполняется, если:

- не удалось зашифровать хотя бы для одного получателя;
- ciphertext пустой или отсутствует для кого-то из recipients.

Клиент пытается recovery (reset session + fresh prekey bundle), и только при успехе отправляет сообщение.

## Ограничения

- E2EE только для `private`.
- Нет полной multi-device синхронизации Signal state.
- Нет гарантии чтения старой истории на новом устройстве без backup/restore key state.
- Метаданные чатов (кто, когда, куда) видны серверу.

## Диагностика

Смотри:

- `docs/E2EE_RUNBOOK.md`
- `apps/flutter/docs/SIGNAL_MIGRATION.md`
- `CHANGELOG.md`

## Лицензия

См. `LICENSE`.
