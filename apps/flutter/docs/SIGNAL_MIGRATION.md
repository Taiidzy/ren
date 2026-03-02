# Signal Integration Guide (Flutter + Native)

Документ описывает актуальную интеграцию Signal в мобильном клиенте.

## 1. Каналы и контракт

### MethodChannel

- channel: `ren/signal_protocol`

Методы:

- `initUser({userId, deviceId}) -> bundle`
- `hasSession({peerUserId, deviceId}) -> bool`
- `encrypt({peerUserId, deviceId, plaintext, preKeyBundle?}) -> ciphertext`
- `decrypt({peerUserId, deviceId, ciphertext}) -> plaintext`
- `resetSession({peerUserId, deviceId})`
- `getFingerprint({peerUserId, deviceId}) -> String`

### EventChannel

- channel: `ren/signal_protocol/events`
- событие: `identity_changed`

## 2. Bundle payload

`initUser` возвращает bundle для backend (`PATCH /users/signal-bundle`):

- `public_key`
- `identity_key`
- `signature`
- `key_version`
- `signed_at`
- `registration_id`
- `signed_pre_key_id`, `signed_pre_key`, `signed_pre_key_signature`
- `kyber_pre_key_id`, `kyber_pre_key`, `kyber_pre_key_signature`
- `one_time_pre_keys[]`

## 3. Отправка сообщений

### Text

`ChatsRepository.buildOutgoingWsTextMessage`:

- шифрует plaintext per-recipient;
- формирует `ciphertext_by_user`;
- отправляет в WS только при полном успехе для всех recipients.

### Media

`ChatsRepository.buildOutgoingWsMediaMessage`:

- caption шифруется per-recipient;
- содержимое файла кодируется в base64 и шифруется per-recipient;
- `metadata[]` содержит `ciphertext_by_user`.

## 4. Fail-closed политика

Если шифрование не удалось хотя бы для одного получателя:

- сообщение не отправляется в WS;
- выполняется recovery-попытка (reset session + fresh bundle + retry);
- при повторной ошибке отправка отменяется.

## 5. Backend требования

Backend обязан:

- хранить `message`/`metadata` без изменения ciphertext полей;
- корректно сериализовать/десериализовать `metadata.ciphertext_by_user`;
- atomically расходовать one-time pre-keys при выдаче public bundle.

## 6. Известные ограничения

- E2EE только для private-чатов.
- Без backup/restore Signal state новый девайс не гарантирует расшифровку старой истории.
- Strict server verify подписи bundle включается отдельным флагом и требует согласованного формата подписи.
