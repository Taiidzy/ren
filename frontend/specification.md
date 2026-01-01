 # API спецификация
 
 Все эндпоинты (кроме регистрации/входа) требуют заголовок авторизации:
 - Authorization: Bearer <JWT>
 
 Бэкенд: Axum + Postgres. Формат данных — JSON. Даты/время — ISO8601 (UTC).
 
 ## Модели
 - UserResponse
   - id: number
   - login: string
   - username: string
   - avatar: string|null
 
 - Chat
   - id: number
   - kind: string ("private" | "group")
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
   - body: string|null
   - created_at: string (ISO)
 
 ---
 
 ## Auth
 
 ### POST /auth/register
 - Описание: регистрация нового пользователя.
 - Тело запроса
   ```json
   {
     "login": "string",
     "username": "string",
     "avatar": "string|null",
     "password": "string (>=6)"
   }
   ```
 - Ответ 200
   ```json
   {
     "id": 1,
     "login": "string",
     "username": "string",
     "avatar": "string|null"
   }
   ```
 - Ошибки
   - 400 Некорректные данные (например, короткий пароль)
   - 409 Логин или имя пользователя занято
   - 500 Ошибка БД/хеширования
 
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
 - Описание: установить/очистить аватар текущего пользователя.
 - Заголовки
   - Authorization: Bearer <JWT>
 - Тело запроса
   ```json
   { "avatar": "https://example.com/ava.png" }
   ```
   или
   ```json
   { "avatar": null }
   ```
 - Ответ 200
   ```json
   { /* UserResponse */ }
   ```
 - Ошибки
   - 401 Нет/невалидный токен
   - 500 Ошибка БД
 
 ### DELETE /users/me
 - Описание: удалить аккаунт текущего пользователя.
 - Заголовки
   - Authorization: Bearer <JWT>
 - Ответ 204 No Content
 - Ошибки
   - 401 Нет/невалидный токен
   - 500 Ошибка БД
 
 ---
 
 ## Chats
 
 ### POST /chats
 - Описание: создать чат.
   - group: создаёт новый групповой чат и добавляет участников.
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
 - Тело запроса (private)
   ```json
   {
     "kind": "private",
     "user_ids": [alice_id, bob_id]
   }
   ```
 - Правила
   - private: ровно 2 пользователя; текущий пользователь обязан входить в список.
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
   - kind=group:
     - Требуется роль admin (ensure_admin). Полное удаление чата.
   - kind=private:
     - for_all=true → удаляет чат целиком (у всех). Инициатор должен быть участником.
     - иначе → удаляет только участие инициатора; если участников не остаётся — чат удаляется.
 - Ответ 204 No Content
 - Ошибки
   - 401 Нет/невалидный токен
   - 403 Нет прав (для group) / Не участник (для private)
   - 404 Чат не найден
   - 500 Ошибка БД/удаления
 
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
{ "type": "send_message", "chat_id": 123, "body": "Привет" }
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
    "body": "Привет",
    "created_at": "2025-11-11T10:10:00Z"
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
 - users(id SERIAL, login UNIQUE, username UNIQUE, avatar, password)
 - chats(id SERIAL, kind, title, created_at, updated_at, is_archived, user_a?, user_b?)
   - UNIQUE (user_a, user_b) WHERE kind = 'private'
 - chat_participants(chat_id, user_id, joined_at, role, last_read_message_id, is_muted)
   - PK(chat_id, user_id)
   - FK chat_id → chats(id) ON DELETE CASCADE
   - FK user_id → users(id)
 - messages(id SERIAL, chat_id, sender_id, body, created_at)
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
   {"error":"Недостаточно прав (нужна роль admin)"}
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
