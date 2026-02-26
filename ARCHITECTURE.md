# Architecture

## System Components

```mermaid
flowchart LR
  subgraph Client[Client Layer]
    F[Flutter App\napps/flutter]
    W[Web App\nfrontend]
    I[iOS Native App\napps/ios]
  end

  subgraph Crypto[Crypto Layer]
    SDK[Ren-SDK Rust\nFFI/WASM]
  end

  subgraph Server[Server Layer]
    API[Axum API + WS\nbackend]
    DB[(PostgreSQL)]
    FS[(uploads/*)]
  end

  F --> SDK
  W --> SDK
  F --> API
  W --> API
  I --> API
  API --> DB
  API --> FS
```

## Runtime Architecture
- Flutter client uses `RenSdk` (`apps/flutter/lib/core/sdk/ren_sdk.dart`) for local cryptographic operations.
- Backend (`backend/src/main.rs`) exposes HTTP + WebSocket routes, validates JWT sessions, and stores encrypted payloads.
- Postgres stores users, chats, messages, auth sessions, and metadata.
- Binary media ciphertext is stored on disk under `backend/uploads` via `/media` endpoints.

## Trust Boundaries
- Boundary A: Device <-> API transport (TLS expected in deployment).
- Boundary B: API <-> PostgreSQL.
- Boundary C: API <-> filesystem uploads.
- Boundary D: Local secure storage on device (private key/token/session).

## Data Flow (High Level)

```mermaid
flowchart TD
  U[User Input] --> ENC[Encrypt in Client\nRen-SDK]
  ENC --> WS[WS SendMessage]
  WS --> API[Backend]
  API --> DB[(messages.envelopes\nmessages.message\nmessages.metadata)]
  API --> Push[WS fan-out to recipients]
  Push --> DEC[Decrypt in recipient client\nusing local private key]
```

## Sequence: Registration

```mermaid
sequenceDiagram
  participant C as Flutter Client
  participant S as Ren-SDK
  participant B as Backend
  participant P as Postgres

  C->>S: generate_key_pair()
  C->>S: derive_key_from_password(password, salt)
  C->>S: encrypt private key -> pkebymk
  C->>S: derive_key_from_string(recovery_secret)
  C->>S: encrypt private key -> pkebyrk
  C->>B: POST /auth/register (login, password, pubk, pkebymk, pkebyrk, salt)
  B->>P: INSERT users
  B-->>C: user profile fields
```

## Sequence: Private Message Send

```mermaid
sequenceDiagram
  participant A as Sender Client
  participant SDK as Ren-SDK
  participant B as Backend WS
  participant DB as Postgres
  participant R as Recipient Client

  A->>SDK: generateMessageKey()
  A->>SDK: encryptMessage(plaintext, msgKey)
  A->>SDK: wrapSymmetricKey(msgKey, sender_pub)
  A->>SDK: wrapSymmetricKey(msgKey, recipient_pub)
  A->>B: send_message{message,ciphertext nonce,envelopes,metadata}
  B->>DB: INSERT messages
  B-->>R: message_new
  R->>SDK: unwrapSymmetricKey(envelope, recipient_priv)
  R->>SDK: decryptMessage(ciphertext, nonce, msgKey)
```

## Sequence: Device Session Refresh / Device Change

```mermaid
sequenceDiagram
  participant C as Client Device
  participant B as Backend
  participant P as Postgres

  C->>B: POST /auth/refresh (refresh_token + X-SDK-Fingerprint)
  B->>P: validate auth_sessions row
  B->>P: rotate refresh_token_hash + update sdk_fingerprint
  B-->>C: new access token + refresh token + session_id
  C->>B: GET /auth/sessions
  B-->>C: list active sessions (device/ip/city/app_version/fingerprint)
```

## Fault Points
- SDK integrity mismatch on Android blocks startup (`RenSdk.initialize`).
- Missing/invalid fingerprint when allowlist enabled causes 401 on auth/session validation.
- Media file persistence depends on local filesystem availability in backend container.
- WebSocket state recovery relies on client reconnect logic.

## Scalability Notes
- Single-process in-memory WS hubs (`DashMap`) imply state is local to one backend instance.
- Horizontal scaling requires shared pub/sub for cross-node WS fan-out.
- DB connection pool configured at startup (`max_connections(10)`) and may require tuning.

## Technical Debt (from code)
- Group/channel messages are non-E2EE by design today.
- Double Ratchet and Sender Keys are planned docs, not production implementation.
- Public key “signature” endpoint currently uses hash-based placeholder, not full Ed25519 verification chain.
