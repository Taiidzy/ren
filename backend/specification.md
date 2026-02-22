 # API спецификация
 
 Все эндпоинты (кроме регистрации/входа) требуют заголовок авторизации:
 - Authorization: Bearer <JWT>
 
 Бэкенд: Axum + Postgres. Формат данных — JSON. Даты/время — ISO8601 (UTC).
 
## Модели
- UserResponse
  - id: number
  - login: string
  - username: string
  - avatar: string|null (путь к файлу аватара, например "avatars/user_123.jpg")
 
 - Chat
   - id: number
   - kind: string ("private" | "group" | "channel")
   - title: string|null
   - created_at: string (ISO)
   - updated_at: string (ISO)
   - is_archived: boolean|null
   - peer_avatar: string|null
   - peer_username: string
 
- Message
  - id: number
  - chat_id: number
  - sender_id: number
  - message: string (зашифрованное сообщение, E2EE)
  - message_type: string ("text" | "file" | "image" и т.д.)
  - created_at: string (ISO)
  - edited_at: string|null (ISO)
  - is_read: boolean
  - has_files?: boolean
  - metadata?: FileMetadata[] (метаданные файлов)
  - envelopes?: { [userId: string]: Envelope } (конверты для каждого участника)
  - status?: "pending" | "sent" (для клиента)

- Envelope (конверт для E2EE)
  - key: string (зашифрованный ключ, base64)
  - ephem_pub_key: string (эфемерный публичный ключ, base64)
  - iv: string (вектор инициализации, base64)

- FileMetadata (метаданные файла)
  - file_id?: number
  - filename: string
  - mimetype: string
  - size: number
  - enc_file: string|null (зашифрованный файл, base64)
  - nonce: string|null (nonce для файла, base64)
  - file_creation_date?: string|null
  - nonces?: string[] (для chunked файлов)
  - chunk_size?: number
  - chunk_count?: number
 
 ---
 
 ## Auth
 
### POST /auth/register
- Описание: регистрация нового пользователя с поддержкой E2EE (End-to-End Encryption).
- Content-Type: `multipart/form-data`
- Тело запроса (multipart/form-data):
  - `login`: string (обязательно)
  - `username`: string (обязательно)
  - `password`: string (обязательно, >=6 символов)
  - `pkebymk`: string (обязательно) - публичный ключ, зашифрованный мастер-ключом
  - `pkebyrk`: string (обязательно) - публичный ключ, зашифрованный ключом восстановления
  - `salt`: string (обязательно) - соль для криптографии
  - `pk`: string (обязательно) - публичный ключ
  - `avatar`: file (опционально) - файл аватара (изображение)
- Ответ 200
  ```json
  {
    "id": 1,
    "login": "string",
    "username": "string",
    "avatar": "avatars/user_1.jpg" | null
  }
  ```
- Ошибки
  - 400 Некорректные данные (например, короткий пароль, отсутствуют обязательные поля E2EE)
  - 409 Логин или имя пользователя занято
  - 500 Ошибка БД/хеширования/сохранения файла
 
 ### POST /auth/login
 - Описание: аутентификация по логину/паролю и выдача JWT.
 - Тело запроса
   ```json
   {
     "login": "string",
     "password": "string",
     "remember_me": true
   }
   ```
 - TTL токена
   - remember_me=true → 365 дней
   - иначе → 24 часа
 - Ответ 200
   ```json
   {
     "message": "Успешный вход",
     "user": { /* UserResponse */ },
     "token": "<jwt>"
   }
   ```
 - Ошибки
   - 401 Неверный логин или пароль
   - 500 Ошибка БД/верификации пароля
 
 ---
 
 ## Users
 
 ### GET /users/me
 - Описание: вернуть профиль текущего пользователя.
 - Заголовки
   - Authorization: Bearer <JWT>
 - Ответ 200
   ```json
   { /* UserResponse */ }
   ```
 - Ошибки
   - 401 Нет/невалидный токен
   - 404 Пользователь не найден
   - 500 Ошибка БД
 
 ### PATCH /users/username
 - Описание: сменить имя пользователя текущего пользователя.
 - Заголовки
   - Authorization: Bearer <JWT>
 - Тело запроса
   ```json
   { "username": "new_name" }
   ```
 - Ответ 200
   ```json
   { /* UserResponse */ }
   ```
 - Ошибки
   - 400 Пустой username
   - 401 Нет/невалидный токен
   - 409 Имя пользователя уже занято
   - 500 Ошибка БД
 
### PATCH /users/avatar
- Описание: установить/очистить аватар текущего пользователя (загрузка файла).
- Заголовки
  - Authorization: Bearer <JWT>
- Content-Type: `multipart/form-data`
- Тело запроса (multipart/form-data):
  - `avatar`: file (опционально) - файл аватара (изображение). Если не передан, аватар остается без изменений.
  - `remove`: string (опционально) - установить в "true" или "1" для удаления аватара
- Ответ 200
  ```json
  { /* UserResponse */ }
  ```
- Ошибки
  - 400 Некорректный формат запроса
  - 401 Нет/невалидный токен
  - 500 Ошибка БД/сохранения файла

### GET /avatars/{path}
- Описание: получить файл аватара по пути.
- Параметры пути
  - path: string (например, "user_123.jpg")
- Ответ 200
  - Content-Type: image/jpeg, image/png, image/gif, image/webp (определяется по расширению файла)
  - Тело: бинарные данные файла
- Ошибки
  - 400 Некорректный путь
  - 404 Файл не найден
 
### DELETE /users/me
- Описание: удалить аккаунт текущего пользователя.
- Заголовки
  - Authorization: Bearer <JWT>
- Ответ 204 No Content
- Ошибки
  - 401 Нет/невалидный токен
  - 500 Ошибка БД

### GET /users/{id}/public-key
- Описание: получить публичный ключ пользователя (для E2EE шифрования сообщений).
- Параметры пути
  - id: number (ID пользователя)
- Ответ 200
  ```json
  {
    "user_id": 1,
    "public_key": "base64_encoded_public_key_string"
  }
  ```
- Ошибки
  - 400 Некорректный ID пользователя
  - 404 Пользователь не найден или публичный ключ отсутствует
  - 500 Ошибка БД
 
 ---
 
 ## Chats
 
 ### POST /chats
 - Описание: создать чат.
   - group: создаёт новый групповой чат и добавляет участников.
   - channel: создаёт канал и добавляет участников (создатель получает роль `owner`).
   - private: используется каноническая пара `user_a <= user_b` (уникальный индекс). Если такой чат уже есть, возвращается существующий и текущий пользователь повторно добавляется в участники (если ранее вышел). Для старых данных есть fallback по участникам с одноразовым проставлением `user_a/user_b`.
 - Заголовки
   - Authorization: Bearer <JWT>
 - Тело запроса (group)
  ```json
  {
    "kind": "group",
    "title": "My Group",
    "user_ids": [1,2,3]
  }
  ```
 - Тело запроса (channel)
   ```json
   {
     "kind": "channel",
     "title": "My Channel",
     "user_ids": [1,2,3]
   }
   ```
 - Тело запроса (private)
   ```json
   {
     "kind": "private",
     "user_ids": [alice_id, bob_id]
   }
   ```
 - Правила
   - private: ровно 2 пользователя; текущий пользователь обязан входить в список.
   - group/channel: обязателен непустой `title`.
 - Ответ 200
   ```json
   { /* Chat */ }
   ```
 - Ошибки
   - 400 Некорректные параметры (например, private без 2 участников)
   - 401 Нет/невалидный токен
   - 500 Ошибка БД (создание/поиск)
 
 ### GET /chats
 - Описание: список чатов, где текущий пользователь — участник (`chat_participants`).
 - Заголовки
   - Authorization: Bearer <JWT>
 - Ответ 200
   ```json
   [ { /* Chat */ }, ... ]
   ```
 - Ошибки
   - 401 Нет/невалидный токен
   - 500 Ошибка БД
 
 ### GET /chats/{chat_id}/messages
 - Описание: список сообщений чата, доступен только участникам (ensure_member).
 - Заголовки
   - Authorization: Bearer <JWT>
 - Параметры пути
   - chat_id: number
 - Ответ 200
   ```json
   [ { /* Message */ }, ... ]
   ```
 - Ошибки
   - 401 Нет/невалидный токен
   - 403 Нет доступа (пользователь не участник чата)
   - 500 Ошибка БД
 
 ### DELETE /chats/{id}
 - Описание: удаление/выход из чата.
 - Заголовки
   - Authorization: Bearer <JWT>
 - Параметры пути
   - id: number
 - Query-параметры
   - for_all: boolean (опционально)
 - Поведение
   - kind=group/channel:
     - Требуется роль admin/owner (ensure_admin). Полное удаление чата.
   - kind=private:
     - for_all=true → удаляет чат целиком (у всех). Инициатор должен быть участником.
     - иначе → удаляет только участие инициатора; если участников не остаётся — чат удаляется.
 - Ответ 204 No Content
 - Ошибки
   - 401 Нет/невалидный токен
   - 403 Нет прав (для group) / Не участник (для private)
   - 404 Чат не найден
   - 500 Ошибка БД/удаления

### GET /chats/{id}/members
- Описание: получить список участников чата (доступно участнику чата).
- Заголовки
  - Authorization: Bearer <JWT>
- Ответ 200
  ```json
  [
    {
      "user_id": 1,
      "username": "alice",
      "avatar": "avatars/u1.jpg",
      "role": "owner",
      "joined_at": "2026-02-22T08:00:00Z"
    }
  ]
  ```

### POST /chats/{id}/members
- Описание: добавить участника в `group/channel` (только admin/owner).
- Тело запроса
  ```json
  { "user_id": 2, "role": "member" }
  ```
- Допустимые роли:
  - group: `member`, `admin`
  - channel: `member`, `admin`

### PATCH /chats/{id}/members/{user_id}
- Описание: изменить роль участника в `group/channel` (только admin/owner).
- Тело запроса
  ```json
  { "role": "admin" }
  ```
- Примечание: роль `owner` этим endpoint менять нельзя.

### DELETE /chats/{id}/members/{user_id}
- Описание: удалить участника из `group/channel` (только admin/owner).
- Ограничения:
  - нельзя удалить `owner`;
  - нельзя удалить самого себя через этот endpoint.
 
 ---
 
 ## WebSocket

- Эндпоинт: `GET /ws`
- Авторизация: заголовок `Authorization: Bearer <JWT>` обязателен и участвует в апгрейде.
- Назначение: глобальный presence (онлайн/офлайн) и события чатов (новые сообщения, typing).

### Инициализация соединения (глобальный presence)
- После установления WebSocket-соединения клиент ДОЛЖЕН отправить событие `init` с массивом `contacts` — это список `user_id` пользователей, для которых необходимо разослать ваше состояние онлайн.

Клиент → Сервер
```json
{ "type": "init", "contacts": [2, 5, 7] }
```

- Сервер подписывает соединение на личный канал текущего пользователя (по его `user_id` из JWT) и рассылает указанным контактам событие presence:

Сервер → Контакты
```json
{ "type": "presence", "user_id": 1, "status": "online" }
```

- При разрыве соединения сервер рассылает тем же контактам:
```json
{ "type": "presence", "user_id": 1, "status": "offline" }
```

Примечания:
- Передавать свой `user_id` в `init` не требуется — он берётся из JWT.
- Если список контактов изменился, можно повторно отправить `init` с новым массивом — новое значение заменит предыдущее.

### События чата (per-chat)
Для получения событий конкретного чата клиент должен присоединиться к чату через `join_chat`.

Клиент → Сервер
```json
{ "type": "join_chat", "chat_id": 123 }
```
- Требуется, чтобы пользователь был участником чата (проверяется `ensure_member`).
- Для отписки:
```json
{ "type": "leave_chat", "chat_id": 123 }
```

Typing индикатор (рассылка всем подписчикам чата):
```json
{ "type": "typing", "chat_id": 123, "is_typing": true }
```

Отправка сообщения (сервер сохраняет в БД и рассылает событие `message_new` подписчикам):
```json
{
  "type": "send_message",
  "chat_id": 123,
  "message": "base64_encrypted_message",
  "message_type": "text",
  "envelopes": {
    "2": {
      "key": "base64_wrapped_key",
      "ephem_pub_key": "base64_ephemeral_public_key",
      "iv": "base64_iv"
    },
    "3": {
      "key": "base64_wrapped_key",
      "ephem_pub_key": "base64_ephemeral_public_key",
      "iv": "base64_iv"
    }
  },
  "metadata": null
}
```

Для сообщений с файлами:
```json
{
  "type": "send_message",
  "chat_id": 123,
  "message": "base64_encrypted_message",
  "message_type": "file",
  "envelopes": { /* ... */ },
  "metadata": [
    {
      "file_id": null,
      "filename": "document.pdf",
      "mimetype": "application/pdf",
      "size": 1024000,
      "enc_file": "base64_encrypted_file",
      "nonce": "base64_nonce",
      "file_creation_date": "2025-11-12T10:00:00Z"
    }
  ]
}
```

Сервер → Клиент (успех подтверждений общим `ok`):
```json
{ "type": "ok" }
```

Сервер → Подписчики чата (новое сообщение):
```json
{
  "type": "message_new",
  "chat_id": 123,
  "message": {
    "id": 10,
    "chat_id": 123,
    "sender_id": 1,
    "message": "base64_encrypted_message",
    "message_type": "text",
    "created_at": "2025-11-11T10:10:00Z",
    "edited_at": null,
    "is_read": false,
    "has_files": false,
    "metadata": null,
    "envelopes": {
      "2": {
        "key": "base64_wrapped_key",
        "ephem_pub_key": "base64_ephemeral_public_key",
        "iv": "base64_iv"
      },
      "3": {
        "key": "base64_wrapped_key",
        "ephem_pub_key": "base64_ephemeral_public_key",
        "iv": "base64_iv"
      }
    },
    "status": "sent"
  }
}
```

Сервер → Подписчики чата (typing):
```json
{ "type": "typing", "chat_id": 123, "user_id": 1, "is_typing": true }
```

Сервер → Клиент (ошибка):
```json
{ "type": "error", "error": "Некорректный формат сообщения" }
```

---

## Схема БД (кратко)
 - users(id SERIAL, login UNIQUE, username UNIQUE, avatar TEXT, password TEXT, pkebymk TEXT, pkebyrk TEXT, salt TEXT, pk TEXT)
   - avatar: путь к файлу аватара (например, "avatars/user_123.jpg") или NULL
   - pkebymk: публичный ключ, зашифрованный мастер-ключом (для E2EE)
   - pkebyrk: публичный ключ, зашифрованный ключом восстановления (для E2EE)
   - salt: соль для криптографии (для E2EE)
   - pk: публичный ключ (для E2EE)
 - chats(id SERIAL, kind, title, created_at, updated_at, is_archived, user_a?, user_b?)
   - UNIQUE (user_a, user_b) WHERE kind = 'private'
 - chat_participants(chat_id, user_id, joined_at, role, last_read_message_id, is_muted)
   - role: member | admin | owner
   - PK(chat_id, user_id)
   - FK chat_id → chats(id) ON DELETE CASCADE
   - FK user_id → users(id)
 - messages(id SERIAL, chat_id, sender_id, message TEXT, message_type TEXT, created_at, edited_at, is_read BOOLEAN, envelopes JSONB, metadata JSONB)
   - message: зашифрованное сообщение (E2EE)
   - message_type: тип сообщения ('text', 'file', 'image' и т.д.)
   - envelopes: JSON объект с конвертами для каждого участника {"userId": {"key": "...", "ephemPubKey": "...", "iv": "..."}}
   - metadata: JSON массив с метаданными файлов [{"file_id": 1, "filename": "...", ...}]
   - FK chat_id → chats(id) ON DELETE CASCADE
   - FK sender_id → users(id)
 
 ---
 
 ## Форматы ошибок (примеры)
 - 401
   ```json
   {"error":"Невалидный или просроченный токен"}
   ```
 - 403
   ```json
  {"error":"Недостаточно прав (нужна роль admin/owner)"}
   ```
 - 404
   ```json
   {"error":"Чат не найден"}
   ```
 - 409
   ```json
   {"error":"Логин или имя пользователя уже занято"}
   ```
 - 500
   ```json
   {"error":"Ошибка БД: <detail>"}
   ```
