# API Reference

Base: backend Axum server (`backend/src/route/*`).

## Auth
- `POST /auth/register`
  - body: `{ login, username, nickname?, password, pkebymk, pkebyrk, pubk, salt }`
- `POST /auth/login`
  - body: `{ login, password, remember_me? }`
- `POST /auth/refresh`
  - body: `{ refresh_token }`
- `POST /auth/logout`
- `GET /auth/sessions`
- `DELETE /auth/sessions`
  - revokes all sessions except current
- `DELETE /auth/sessions/:id`

Auth/session behavior:
- Access token is JWT (`token_type=access`).
- Refresh token stored hashed in `auth_sessions`.

## Users
- `GET /users/me`
- `DELETE /users/me`
- `PATCH /users/username`
  - body: `{ username }`
- `PATCH /users/nickname`
  - body: `{ nickname }`
- `PATCH|POST /users/avatar` (multipart)
  - fields: `avatar` file, `remove`
- `GET /users/search?q=<string>&limit=<n>`
- `GET /users/:id/public-key`
  - returns: `{ user_id, public_key, signature, key_version, signed_at, identity_key }`
- `GET /avatars/*path`

## Chats
- `POST /chats`
  - body: `{ kind: private|group|channel, title?, user_ids[] }`
- `GET /chats`
- `GET /chats/:chat_id/messages?limit=&before_id=&after_id=`
- `POST /chats/:id/read`
  - body: `{ message_id? }`
- `POST /chats/:id/delivered`
  - body: `{ message_id? }`
- `PATCH|POST /chats/:id/avatar` (multipart)
- `GET /chats/:id/members`
- `POST /chats/:id/members`
  - body: `{ user_id, role? }`
- `PATCH /chats/:id/members/:user_id`
  - body: `{ role }`
- `DELETE /chats/:id/members/:user_id`
- `POST /chats/:id/favorite`
- `DELETE /chats/:id/favorite`
- `PATCH /chats/:id`
  - body: `{ title?, avatar? }`
- `DELETE /chats/:id?for_all=true|false`

## Media
- `POST /media` (multipart)
  - fields: `file`, `chat_id`, `filename?`, `mimetype?`
  - size limit: 50 MB
- `GET /media/:id`
  - streams ciphertext bytes

## WebSocket
- `GET /ws` with auth headers.
- Client events (snake_case):
  - `init`, `join_chat`, `leave_chat`
  - `send_message`, `voice_message`, `video_message`
  - `edit_message`, `delete_message`, `forward_message`, `typing`
- Server events:
  - `ok`, `error`
  - `message_new`, `message_updated`, `message_deleted`
  - `typing`, `presence`, membership events

## Common Headers
- `Authorization: Bearer <access_token>`
- `X-Device-Name`
- `X-App-Version`

## Error Codes
- `400` invalid input
- `401` auth/session failure
- `403` permission denied
- `404` not found
- `409` conflict (unique constraints)
- `429` auth throttling
- `500` server/database/internal errors

## Notes
- Messages may contain encrypted payload and envelopes (1:1 chat), or plaintext payload for non-E2EE contexts.
- Anti-replay for WS send flow uses `client_message_id` deduplication.
