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
    - Out-of-order message support
  - FFI bindings for X3DH and Double Ratchet
    - `x3dh_initiate_ffi()` — Alice initiates key exchange
    - `x3dh_respond_ffi()` — Bob responds to key exchange
    - `ratchet_initiate_ffi()` — Initialize Ratchet session (Alice)
    - `ratchet_respond_ffi()` — Initialize Ratchet session (Bob)
    - `ratchet_encrypt_ffi()` — Encrypt message with Double Ratchet
    - `ratchet_decrypt_ffi()` — Decrypt message with Double Ratchet
  - Flutter FFI bindings (`ren_sdk_p04.dart`)
    - `RenSdkP04` class for P0-4 operations
    - Full X3DH and Ratchet API for Flutter
  - Backend PreKey API endpoints
    - `GET /keys/:user_id/bundle` — Get PreKey Bundle for X3DH
    - `POST /keys/one-time` — Upload One-Time PreKeys
    - `POST /keys/signed` — Upload Signed PreKey
    - `DELETE /keys/one-time/:id` — Mark PreKey as used
  - Chat E2EE Service integration
    - `ChatE2EEService` for 1:1 chat encryption
    - Integration with `ChatsRepository`
    - E2EE status indicators

### Changed
- Updated `Ren-SDK/Cargo.toml` with new dependencies:
  - `hmac` v0.12 for chain key derivation
  - `rand_core` v0.6 for secure random generation
- Updated `Ren-SDK/src/lib.rs` to export X3DH and Ratchet modules
- Updated `Ren-SDK/src/ffi.rs` with P0-4 FFI functions
- Updated `backend/src/models/mod.rs` to include PreKeys models
- Updated `backend/src/route/mod.rs` to include PreKeys routes
- Updated `apps/flutter/lib/core/cryptography/` with new crypto modules

### Fixed
- FFI function signatures for proper error handling
- Dart FFI bindings for correct type marshaling

### Security
- **Forward Secrecy**: Each message uses unique encryption key
- **Post-Compromise Security**: Automatic recovery via DH ratchet every 2 messages
- **Asynchronous Support**: X3DH with PreKey Bundles for offline messages
- **Key Authentication**: Ed25519 signatures prevent MITM attacks
- **Secure Storage**: Identity keys stored in Secure Enclave/KeyStore

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
