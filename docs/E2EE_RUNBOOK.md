# E2EE Runbook

Операционный документ для диагностики проблем шифрования/расшифровки.

## Симптомы и первичная проверка

### Симптом: сообщение отправлено, но не расшифровывается

Проверь:

1. `PATCH /users/signal-bundle` возвращает 2xx при login/splash.
2. `GET /users/:id/public-key` возвращает bundle с prekeys.
3. На отправке `ciphertext_by_user` содержит ключ для каждого recipient.
4. Для медиа в `metadata[]` присутствует `ciphertext_by_user`.

### Симптом: `sessionNotFound(...)`

Действия:

1. `resetSession(peerUserId)` на проблемной паре.
2. Повторная отправка первого сообщения (должен пройти prekey flow).
3. Проверка, что one-time prekeys у получателя не исчерпаны.

## Что логировать (без утечки секретов)

Можно логировать:

- `chat_id`, `sender_id`, `recipient_count`
- `message_type`
- наличие/отсутствие `ciphertext_by_user` по recipient id
- `signal envelope type` (`prekey|whisper`)
- коды ошибок (`invalid prekey message`, `sessionNotFound`, `duplicate message`)

Нельзя логировать:

- plaintext
- private keys
- raw decrypted media bytes
- полные ciphertext payloads в production

## База данных: критичные поля

- `users.one_time_pre_keys`
- `users.signed_pre_key*`
- `users.kyber_pre_key*`
- `users.key_signature` (если используется)
- `messages.message`
- `messages.metadata` (`ciphertext_by_user` must persist)

## Fail-closed правило

Если шифрование не завершилось для хотя бы одного получателя, WS send не выполняется.

## После деплоя изменений в E2EE

1. Проверить миграции БД.
2. Проверить login + обновление bundle.
3. Протестировать private text + media в обе стороны.
4. Протестировать сценарий с restart приложения.
