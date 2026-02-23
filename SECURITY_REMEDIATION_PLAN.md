# Security Remediation Plan (2026-02-23)

Документ фиксирует приоритетный план устранения уязвимостей и недочётов по критичности.

## Critical (P0) — исправить немедленно

### 1) Удаление чужих сообщений любым участником чата
- Риск: компрометация целостности переписки.
- Где: `backend/src/route/ws.rs` (`delete_message`).
- План:
  1. Ограничить удаление: `sender_id == current_user_id` (или отдельная роль moderator/admin).
  2. Добавить audit-поле причины/типа удаления.
  3. Добавить integration-тесты:
     - пользователь A не может удалить сообщение B;
     - автор может удалить своё сообщение.
- Критерий готовности: негативный кейс стабильно возвращает `403`.

### 2) Отсутствие аутентификации публичных ключей (MITM через сервер)
- Риск: расшифровка сообщений при подмене ключей сервером.
- Где: `GET /users/:id/public-key`, клиентское потребление peer key.
- План:
  1. Ввести identity signing key (Ed25519) на устройство.
  2. Подписывать публикуемые prekey bundles.
  3. Добавить safety numbers/QR verification между пользователями.
  4. Добавить key-change warning (блокирующий отправку до подтверждения).
- Критерий готовности: клиент детектирует неподписанный/подменённый ключ и блокирует E2EE отправку.

### 3) Слабая recovery-схема (6 символов + fast SHA-256)
- Риск: offline brute-force восстановления приватного ключа.
- Где: `apps/flutter/lib/core/cryptography/recovery_key_generator.dart`, `Ren-SDK/src/crypto.rs`.
- План:
  1. Перейти на recovery secret >= 128 бит энтропии (wordlist/seed-фраза).
  2. Использовать Argon2id (memory-hard) для recovery KDF + уникальную salt.
  3. Ввести лимиты/задержки на recovery-операции.
  4. Ротация существующих recovery-материалов.
- Критерий готовности: recovery offline brute-force становится практически нереалистичным.

### 4) Отсутствие FS/PCS (нет Double Ratchet)
- Риск: компрометация долгоживущего ключа раскрывает историю/часть будущих сообщений.
- Где: текущий E2EE flow (static key + envelope wrap).
- План:
  1. Внедрить X3DH + Double Ratchet (по устройствам).
  2. Ввести отдельное состояние сессий для каждой device pair.
  3. Реализовать rekey и break-in recovery.
  4. Миграция протокола по версиям с backward compatibility окном.
- Критерий готовности: достигнуты forward secrecy и post-compromise security.

### 5) Group/Channel работают как non-E2EE при security-позиционировании E2EE
- Риск: сервер читает групповой/канальный контент.
- Где: клиентский flow отправки сообщений в group/channel.
- План:
  1. Краткосрочно: явно маркировать режим как non-E2EE в UI и документации.
  2. Долгосрочно: внедрить Sender Keys (или MLS) для групп.
  3. Добавить отдельные тесты на невозможность серверной расшифровки group payload.
- Критерий готовности: групповой контент не хранится и не передаётся как plaintext.

## High (P1) — исправить в ближайшем релизе

### 6) Нет anti-replay/idempotency для сообщений
- План:
  1. Добавить `client_message_id` в протокол.
  2. В БД сделать уникальность `(chat_id, sender_id, client_message_id)`.
  3. При повторе возвращать прежний результат, не создавать дубликат.
- Критерий: повторная отправка не создаёт второе сообщение.

### 7) Нет rate limiting для auth и критичных endpoint
- План:
  1. Ввести rate limit на login/register/refresh/ws-connect.
  2. Добавить IP + account + device bucketing.
  3. Добавить lockout/backoff при brute-force.
- Критерий: автоматизированный перебор режется на уровне API.

### 8) Веб-токен хранится в `localStorage`
- План:
  1. Перейти на `HttpOnly + Secure + SameSite` cookies.
  2. Ввести CSP и минимизацию XSS поверхности.
  3. Убрать bearer storage из JS runtime.
- Критерий: токен недоступен JavaScript-коду страницы.

### 9) SDK integrity check на Android не форсируется при старте
- План:
  1. Вызвать проверку целостности в `RenSdk.initialize()`.
  2. Фейлить старт при mismatch.
  3. Логировать событие в security telemetry.
- Критерий: модифицированный SDK не запускается.

### 10) Документация безопасности расходится с реализацией
- План:
  1. Обновить README/spec с точным статусом (что E2EE, что нет).
  2. Добавить раздел Known Security Limitations.
  3. Добавить changelog security-impact changes.
- Критерий: нет ложных security claims.

## Medium (P2) — исправить в плановом цикле

### 11) HTTP/TLS hardening в nginx-конфиге
- План:
  1. Явный 301 redirect HTTP -> HTTPS.
  2. Включить HSTS.
  3. Перепроверить 443 server blocks в репозитории.

### 12) Внешняя geo-служба получает клиентский IP
- План:
  1. Отключить внешние запросы по умолчанию.
  2. Перейти на локальную/offline geo-базу или opt-in.
  3. Обновить privacy policy.

### 13) Секреты и операционный контур
- План:
  1. Централизованный secret manager.
  2. Ротация JWT/DB паролей.
  3. Secret scanning в CI.

## Low (P3) — улучшения качества и устойчивости

### 14) Исправить крипто-неточности в документации
- План: заменить ошибочные формулировки (`generate_nonce` vs `generateMessageKey`), добавить тест-векторы.

### 15) Расширить тестовое покрытие security-сценариев
- План:
  1. Integration tests: auth/session/ws/permissions/replay.
  2. Негативные тесты на key mismatch и invalid envelopes.
  3. Regression suite для security bugs.

---

## Порядок выполнения (рекомендуемый)
1. P0-1: запрет удаления чужих сообщений.
2. P0-2: key authentication baseline (подписи + warnings).
3. P0-3: recovery hardening.
4. P1-6/7/8/9: anti-replay, rate-limit, web token model, SDK verify.
5. P0-4/5: миграция к ratchet + group E2EE.
6. P1/P2/P3: документация, TLS/privacy/process hardening.
