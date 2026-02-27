# Changelog

This project follows Semantic Versioning.

## [Unreleased]

### Added
- **P0-4: Forward Secrecy & Double Ratchet Implementation**
  - X3DH (Extended Triple Diffie-Hellman) key agreement protocol
    - Identity Key Store (X25519 + Ed25519)
    - Signed PreKey management
    - One-Time PreKey management (50-100 keys)
    - PreKey Bundle API for async key exchange
  - Double Ratchet protocol implementation
    - DH Ratchet with X25519
    - Symmetric Ratchet with HMAC-SHA256
    - Forward Secrecy (per-message key rotation)
    - Post-Compromise Security (automatic recovery)
    - Out-of-order message support with skipped key storage
  - FFI bindings for X3DH and Double Ratchet
    - `x3dh_initiate_ffi()` — Alice initiates key exchange
    - `x3dh_respond_ffi()` — Bob responds to key exchange
    - `ratchet_initiate_ffi()` — Initialize Ratchet session (Alice)
    - `ratchet_respond_ffi()` — Initialize Ratchet session (Bob)
    - `ratchet_encrypt_ffi()` — Encrypt message with Double Ratchet
    - `ratchet_decrypt_ffi()` — Decrypt message with Double Ratchet
  - Flutter integration
    - `RatchetSession` class using Ren-SDK FFI
    - `HiveSessionStore` for persistent session storage
    - `ChatE2EEService` for 1:1 chat encryption/decryption
    - Automatic session initialization (X3DH + Ratchet)
  - Backend PreKey API endpoints
    - `GET /keys/:user_id/bundle` — Get PreKey Bundle for X3DH
    - `POST /keys/one-time` — Upload One-Time PreKeys
    - `POST /keys/signed` — Upload Signed PreKey
    - `DELETE /keys/one-time/:id` — Mark PreKey as used
    - `GET /keys/one-time/count` — Get unused PreKey count
  - Backend Double Ratchet message support
    - `protocol_version` field in messages table (1=legacy, 2=Double Ratchet)
    - `sender_identity_key` field for Double Ratchet authentication
    - Automatic extraction and storage of Double Ratchet fields
  - Database migrations
    - `20260301_x3dh_prekeys.sql` — PreKeys storage tables
    - `20260302_double_ratchet_messages.sql` — Double Ratchet message fields

### Changed
- **Ren-SDK ratchet module reorganization**
  - Split into separate modules: `chain.rs`, `dh_ratchet.rs`, `symmetric_ratchet.rs`, `session.rs`
  - Added `SkippedMessageKey` storage for out-of-order message decryption
  - Added identity keys to `RatchetSessionState` for session persistence
- **Flutter cryptography modules**
  - `ratchet_session.dart` — Now uses Ren-SDK FFI directly (removed stubs)
  - `session_store.dart` — Added `HiveSessionStore` implementation
  - `x3dh_protocol.dart` — Fixed base64 encoding/decoding
  - `identity_key_store.dart` — Added `getIdentityKeys()`, `getSignedPreKey()` methods
  - `prekey_repository.dart` — Implemented `syncPreKeys()` with count endpoint
- **ChatsRepository integration**
  - `buildOutgoingWsTextMessage()` — Uses Double Ratchet for private chats
  - `buildOutgoingWsMediaMessage()` — Encrypts attachments with Double Ratchet
  - `_tryDecryptMessageAndKey()` — Supports both Double Ratchet and legacy
  - Automatic fallback to legacy encryption if Double Ratchet fails
- **Backend message handling**
  - `ws.rs` — Extracts and stores `protocol_version` and `sender_identity_key`
  - `chats.rs` — Returns Double Ratchet fields in message lists
  - `models/chats.rs` — Added `protocol_version` and `sender_identity_key` fields
- Updated `Ren-SDK/Cargo.toml` with new dependencies:
  - `hmac` v0.12 for chain key derivation
  - `rand_core` v0.6 for secure random generation
- Updated `apps/flutter/pubspec.yaml` — Added `hive` and `hive_flutter` dependencies

### Deprecated
- Legacy E2EE encryption (will be removed in future versions)
- `ren_sdk_p04.dart` — Merged into `ren_sdk.dart`

### Removed
- `Ren-SDK/src/p04_ffi_additions.rs` — Merged into `ffi.rs`
- `apps/flutter/lib/core/sdk/ren_sdk_p04.dart` — Merged into `ren_sdk.dart`
- Stub implementations in `RatchetSession` (replaced with FFI calls)

### Fixed
- Base64 encoding/decoding in `x3dh_protocol.dart` (was using runes instead of proper base64)
- Borrow checker issues in `symmetric_ratchet.rs`
- Duplicate method definitions in `chats_repository.dart`
- Missing session persistence in `RatchetSessionState`
- Out-of-order message decryption (now properly stores skipped keys)

### Security
- **Forward Secrecy**: Each message uses unique encryption key derived from chain
- **Post-Compromise Security**: Automatic recovery via DH ratchet every 2 messages
- **Asynchronous Support**: X3DH with PreKey Bundles for offline messages
- **Key Authentication**: Ed25519 signatures prevent MITM attacks
- **Secure Storage**: Identity keys stored in Secure Enclave/KeyStore
- **Skipped Key Storage**: Protects against DoS with MAX_SKIPPED_KEYS limit
- **Fallback Encryption**: Legacy E2EE as fallback if Double Ratchet unavailable

---

## Release Template

Use this template for each release section:

```md
## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Deprecated
- ...

### Removed
- ...

### Fixed
- ...

### Security
- ...
```

## Versioning Policy
- `MAJOR`: incompatible API/protocol/data model changes.
- `MINOR`: backward-compatible features.
- `PATCH`: backward-compatible fixes and documentation corrections.
