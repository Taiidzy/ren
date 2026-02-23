---
title: API Reference
description: Полная документация HTTP и WebSocket API
sidebar_position: 1
---

# API Reference

Бэкенд Ren предоставляет REST API и WebSocket для real-time событий.

**Базовый URL:** `http://localhost:8081` (по умолчанию)

**Формат данных:** JSON

**Даты/время:** ISO8601 (UTC)

## Аутентификация

Все эндпоинты (кроме регистрации/входа) требуют заголовок:

```
Authorization: Bearer <JWT>
```

## Auth

### POST /auth/register

Регистрация нового пользователя с поддержкой E2EE.

**Content-Type:** `multipart/form-data`

**Параметры:**

| Поле | Тип | Обязательное | Описание |
|------|-----|--------------|----------|
| `login` | string | ✅ | Уникальный логин |
| `username` | string | ✅ | Уникальное имя пользователя |
| `password` | string | ✅ | Минимум 6 символов |
| `nickname` | string | ❌ | Отображаемое имя (макс. 32 символа) |
| `pkebymk` | string | ✅ | Публичный ключ, зашифрованный мастер-ключом |
| `pkebyrk` | string | ✅ | Публичный ключ, зашифрованный ключом восстановления |
| `salt` | string | ✅ | Соль для криптографии |
| `pk` | string | ✅ | Публичный ключ X25519 |
| `avatar` | file | ❌ | Файл аватара |

**Ответ 200:**

```json
{
  "id": 1,
  "login": "john_doe",
  "username": "john",
  "nickname": "John Doe",
  "avatar": "avatars/user_1.jpg"
}
```

**Ошибки:**

- `400` — Некорректные данные
- `409` — Логин или username заняты
- `500` — Ошибка БД/хеширования

---

### POST /auth/login

Аутентификация по логину/паролю.

**Тело запроса:**

```json
{
  "login": "john_doe",
  "password": "password123",
  "remember_me": true
}
```

**TTL токена:**

- `remember_me=true` → 365 дней
- `remember_me=false` → 24 часа

**Ответ 200:**

```json
{
  "message": "Успешный вход",
  "user": {
    "id": 1,
    "login": "john_doe",
    "username": "john",
    "nickname": "John Doe",
    "avatar": "avatars/user_1.jpg"
  },
  "token": "<jwt>"
}
```

**Ошибки:**

- `401` — Неверный логин или пароль
- `500` — Ошибка БД

---

### POST /auth/refresh

Обновление JWT токена.

**Заголовки:**

```
Authorization: Bearer <JWT>
```

**Ответ 200:**

```json
{
  "token": "<новый JWT>"
}
```

**Ошибки:**

- `401` — Невалидный токен
- `403` — SDK fingerprint не в allowlist

---

## Users

### GET /users/me

Получить профиль текущего пользователя.

**Ответ 200:**

```json
{
  "id": 1,
  "login": "john_doe",
  "username": "john",
  "nickname": "John Doe",
  "avatar": "avatars/user_1.jpg"
}
```

---

### PATCH /users/nickname

Изменить отображаемое имя.

**Тело запроса:**

```json
{
  "nickname": "New Name"
}
```

**Валидация:**

- Не пустое
- Максимум 32 символа

---

### PATCH /users/avatar

Установить/удалить аватар.

**Content-Type:** `multipart/form-data`

**Параметры:**

| Поле | Тип | Описание |
|------|-----|----------|
| `avatar` | file | Файл аватара |
| `remove` | string | `"true"` для удаления |

---

### GET /users/:id/public-key

Получить публичный ключ пользователя для E2EE.

**Ответ 200:**

```json
{
  "user_id": 1,
  "public_key": "base64_encoded_key",
  "signature": "base64_signature",
  "key_version": 1,
  "identity_key": "base64_identity_key",
  "signed_at": "2026-02-24T10:00:00Z"
}
```

> **P0-2:** Возвращается подписанный публичный ключ с Ed25519 signature.

---

### GET /users/search

Поиск пользователей по username.

**Query параметры:**

| Параметр | Тип | Описание |
|----------|-----|----------|
| `q` | string | Поисковый запрос |

**Ответ 200:**

```json
[
  {
    "id": 2,
    "username": "alice",
    "nickname": "Alice Smith",
    "avatar": "avatars/user_2.jpg"
  }
]
```

---

## Chats

### POST /chats

Создать чат.

**Тело запроса (group):**

```json
{
  "kind": "group",
  "title": "My Group",
  "user_ids": [1, 2, 3]
}
```

**Тело запроса (channel):**

```json
{
  "kind": "channel",
  "title": "My Channel",
  "user_ids": [1, 2, 3]
}
```

**Тело запроса (private):**

```json
{
  "kind": "private",
  "user_ids": [alice_id, bob_id]
}
```

**Правила:**

- `private`: ровно 2 участника, текущий пользователь обязан входить
- `group/channel`: обязателен непустой `title`

**Ответ 200:**

```json
{
  "id": 1,
  "kind": "group",
  "title": "My Group",
  "created_at": "2026-02-24T10:00:00Z",
  "updated_at": "2026-02-24T10:00:00Z",
  "avatar": "chats/chat_1.jpg",
  "is_archived": false
}
```

---

### GET /chats

Список чатов текущего пользователя.

**Ответ 200:**

```json
[
  {
    "id": 1,
    "kind": "private",
    "title": null,
    "peer_id": 2,
    "peer_username": "alice",
    "peer_nickname": "Alice Smith",
    "peer_avatar": "avatars/user_2.jpg",
    "last_message": {
      "id": 10,
      "body": "Привет!",
      "type": "text",
      "created_at": "2026-02-24T12:00:00Z",
      "is_outgoing": false,
      "is_delivered": true,
      "is_read": true
    },
    "unread_count": 0,
    "updated_at": "2026-02-24T12:00:00Z"
  }
]
```

---

### GET /chats/:id/messages

Список сообщений чата.

**Ответ 200:**

```json
[
  {
    "id": 10,
    "chat_id": 1,
    "sender_id": 2,
    "sender_name": "Alice Smith",
    "sender_avatar": "avatars/user_2.jpg",
    "message": "base64_encrypted_message",
    "message_type": "text",
    "created_at": "2026-02-24T12:00:00Z",
    "edited_at": null,
    "is_read": false,
    "is_delivered": true,
    "envelopes": {
      "1": {
        "key": "base64_wrapped_key",
        "ephem_pub_key": "base64_ephemeral_key",
        "iv": "base64_iv"
      }
    },
    "metadata": null,
    "client_message_id": "uuid_v4"
  }
]
```

---

### DELETE /chats/:id

Удалить/выйти из чата.

**Query параметры:**

| Параметр | Тип | Описание |
|----------|-----|----------|
| `for_all` | boolean | Удалить чат для всех (private) |

**Поведение:**

| Тип | Поведение |
|-----|-----------|
| `group/channel` | Полное удаление (требуется admin/owner) |
| `private` + `for_all=true` | Удалить у всех |
| `private` + `for_all=false` | Выйти (удалить своё участие) |

**Ответ:** `204 No Content`

---

### GET /chats/:id/members

Получить участников чата.

**Ответ 200:**

```json
[
  {
    "user_id": 1,
    "username": "john",
    "nickname": "John Doe",
    "avatar": "avatars/user_1.jpg",
    "role": "owner",
    "joined_at": "2026-02-24T10:00:00Z"
  }
]
```

---

### POST /chats/:id/members

Добавить участника в group/channel.

**Тело запроса:**

```json
{
  "user_id": 5,
  "role": "member"
}
```

**Допустимые роли:** `member`, `admin`

---

### PATCH /chats/:id/members/:user_id

Изменить роль участника.

**Тело запроса:**

```json
{
  "role": "admin"
}
```

> Нельзя изменить роль `owner`.

---

### DELETE /chats/:id/members/:user_id

Удалить участника.

> Нельзя удалить `owner`. Требуется admin/owner.

---

### PATCH /chats/:id

Обновить информацию о чате.

**Тело запроса:**

```json
{
  "title": "New Title"
}
```

> Требуется роль owner.

---

### POST /chats/:id/avatar

Загрузить аватар чата.

**Content-Type:** `multipart/form-data`

---

### DELETE /chats/:id/avatar

Удалить аватар чата.

---

## Media

### POST /media

Загрузить зашифрованный файл.

**Content-Type:** `multipart/form-data`

**Параметры:**

| Поле | Тип | Описание |
|------|-----|----------|
| `file` | file | Зашифрованный файл |

**Ответ 200:**

```json
{
  "id": 1,
  "url": "/media/1",
  "size": 1024000
}
```

---

### GET /media/:id

Скачать файл.

**Ответ:**

- `Content-Type`: определяется по расширению
- Тело: бинарные данные

---

### GET /avatars/:path

Получить аватар пользователя.

---

## WebSocket

**Эндпоинт:** `GET /ws`

**Авторизация:** `Authorization: Bearer <JWT>` (в заголовке upgrade)

### Инициализация

**Клиент → Сервер:**

```json
{
  "type": "init",
  "contacts": [2, 5, 7]
}
```

Сервер подписывает на личный канал и рассылает `presence` контактам.

### События чата

**join_chat:**

```json
{
  "type": "join_chat",
  "chat_id": 123
}
```

**leave_chat:**

```json
{
  "type": "leave_chat",
  "chat_id": 123
}
```

**typing:**

```json
{
  "type": "typing",
  "chat_id": 123,
  "is_typing": true
}
```

**send_message:**

```json
{
  "type": "send_message",
  "chat_id": 123,
  "message": "base64_encrypted",
  "message_type": "text",
  "envelopes": {
    "2": {
      "key": "base64_wrapped_key",
      "ephem_pub_key": "base64_ephemeral_key",
      "iv": "base64_iv"
    }
  },
  "metadata": null,
  "client_message_id": "uuid_v4"
}
```

### Сервер → Клиент

**message_new:**

```json
{
  "type": "message_new",
  "chat_id": 123,
  "message": { /* Message object */ }
}
```

**presence:**

```json
{
  "type": "presence",
  "user_id": 1,
  "status": "online"
}
```

**typing:**

```json
{
  "type": "typing",
  "chat_id": 123,
  "user_id": 1,
  "is_typing": true
}
```

**member_added, member_removed, member_role_changed:**

```json
{
  "type": "member_added",
  "chat_id": 123,
  "user_id": 5,
  "role": "member"
}
```

**message_delivered, message_read:**

```json
{
  "type": "message_delivered",
  "chat_id": 123,
  "message_ids": [10, 11, 12]
}
```

**ok (подтверждение):**

```json
{
  "type": "ok"
}
```

**error:**

```json
{
  "type": "error",
  "error": "Некорректный формат сообщения"
}
```

---

## Форматы ошибок

**401 Unauthorized:**

```json
{
  "error": "Невалидный или просроченный токен"
}
```

**403 Forbidden:**

```json
{
  "error": "Недостаточно прав (нужна роль admin/owner)"
}
```

**404 Not Found:**

```json
{
  "error": "Чат не найден"
}
```

**409 Conflict:**

```json
{
  "error": "Логин или имя пользователя уже занято"
}
```

**500 Internal Server Error:**

```json
{
  "error": "Ошибка БД: <detail>"
}
```
