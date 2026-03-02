# E2EE Fix: Self-Readability + Media Encryption Pipeline

## Что было сломано

1. В части сообщений клиент искал ciphertext только в `ciphertext_by_user`.
   - Исторические/совместимые payload могли приходить с `signal_ciphertext_by_user`.
   - Результат: отправитель периодически видел `[encrypted]` вместо текста.

2. Media-пайплайн шифровал **весь файл** через Signal для каждого получателя и передавал это в metadata.
   - Это не соответствует attachment-схеме (симметричное шифрование файла + upload ciphertext).
   - Результат: нестабильная работа на медиа, особенно при росте размера и self-echo сценариях.

## Что изменено

### Flutter клиент

1. Добавлен модуль `AttachmentCipher` (AES-GCM 256):
   - файл: `apps/flutter/lib/core/e2ee/attachment_cipher.dart`
   - генерирует `key (32 bytes)` + `nonce (12 bytes)`;
   - шифрует/дешифрует бинарный payload;
   - считает SHA-256 для plaintext/ciphertext.

2. `buildOutgoingWsMediaMessage(...)` переведён на attachment flow:
   - перед upload файл шифруется локально AES-GCM;
   - на сервер загружается только ciphertext (`/media`);
   - в Signal-сообщение отправляется зашифрованный descriptor (`file_id`, `key`, `nonce`, `sha256`, `mimetype`, `filename`, `size`);
   - descriptor шифруется **per recipient**, включая отправителя.

3. `decryptIncomingWsMessage`/`_decryptMessageWithKey`:
   - добавлена поддержка alias-поля `signal_ciphertext_by_user` (backward compatibility для текста).

4. `_tryDecryptAttachments(...)`:
   - поддерживает новый descriptor (`signal_v2_attachment`);
   - скачивает ciphertext по `file_id`, расшифровывает локально по `key/nonce`;
   - проверяет `sha256` plaintext (если передан);
   - сохраняет fallback на старый формат (где в Signal лежал base64 plaintext файла).

### Rust сервер

1. Добавлен регрессионный тест stream-пути медиа:
   - файл: `backend/src/route/media.rs`
   - тест `reader_stream_keeps_binary_payload_unchanged` проверяет, что `ReaderStream` не меняет байты.

## Тесты

### Flutter

`flutter test test/features/chats/data/chats_repository_e2ee_media_test.dart`

Покрыто:
- `AttachmentCipher` encrypt/decrypt round-trip;
- дешифрование текста через alias `signal_ciphertext_by_user`;
- media round-trip на уровне payload-builder:
  - upload получает ciphertext (не plaintext),
  - metadata содержит encrypted descriptor и ключи для всех участников (включая self).

### Rust

`cargo test reader_stream_keeps_binary_payload_unchanged -- --nocapture`

Покрыто:
- бинарный payload в download stream не мутирует байты.

## Миграция и совместимость

1. Клиент теперь отправляет media descriptor v2 (`signal_v2_attachment`).
2. Новый клиент умеет читать и v2, и старый формат.
3. Старые клиенты, не знающие v2 descriptor, не смогут корректно расшифровать новые media-сообщения.

Рекомендуемый rollout:
1. Сначала выкатить этот клиент на внутренний/канареечный процент.
2. После достижения целевой доли обновлённых клиентов включить обязательность v2 для всех пользователей.
3. При необходимости — временный feature flag на клиенте для возврата к legacy media-формату.

## Риски

1. Межверсионная несовместимость медиа (новый -> старый клиент).
2. Повышенная чувствительность к целостности metadata (`key/nonce/sha256`) — при порче descriptor файл не откроется.

## Rollback

1. Откат Flutter клиента на предыдущий релиз (legacy media path).
2. Серверных schema/DB изменений нет, rollback сервера не требуется.
3. После rollback новые v2 media, уже отправленные пользователями, останутся недоступными на старом клиенте.

## Файлы изменений

- `apps/flutter/lib/core/e2ee/attachment_cipher.dart`
- `apps/flutter/lib/features/chats/data/chats_repository.dart`
- `apps/flutter/test/features/chats/data/chats_repository_e2ee_media_test.dart`
- `apps/flutter/pubspec.yaml`
- `apps/flutter/pubspec.lock`
- `backend/src/route/media.rs`
