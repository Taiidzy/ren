# Security

## Scope
This document describes the security model implemented in code as of 2026-02-26.

## E2EE Status
- Private 1:1 chats: E2EE enabled.
- Group/channel chats: E2EE not implemented (explicit warning shown in UI).

Relevant code:
- `apps/flutter/lib/features/chats/data/chats_repository.dart`
- `apps/flutter/lib/features/chats/presentation/widgets/group_e2ee_warning.dart`

## Cryptographic Primitives (implemented)
- X25519 ECDH (`x25519-dalek`) for key agreement.
- ChaCha20-Poly1305 AEAD (`chacha20poly1305`) for message/file encryption.
- HKDF-SHA256 for wrapping-key derivation from shared secret.
- PBKDF2-HMAC-SHA256 (100k iterations) for password-derived key (client).
- Argon2id for server password hashing and recovery-KDF support in SDK.
- Ed25519 APIs exist in SDK but key-auth chain is incomplete in product flow.

## Message Encryption Flow (1:1)
1. Sender generates random message key (`generateMessageKey`, 32 bytes).
2. Sender encrypts message (`ciphertext`, `nonce`).
3. Sender wraps message key per participant using recipient public key (envelopes).
4. Backend stores encrypted payload + envelopes.
5. Recipient unwraps envelope with local private key and decrypts message locally.

## Key Storage
- Flutter stores sensitive material with `flutter_secure_storage`:
  - private key
  - public key
  - access token
  - refresh token
  - session id
- On iOS: Keychain backend (via plugin).
- On Android: Keystore-backed secure storage (via plugin).

## Key Generation and Rotation
- Key pair is generated on registration (`generate_key_pair`).
- Private key is encrypted as:
  - `pkebymk` (password-derived master key)
  - `pkebyrk` (recovery-derived key)
- Session tokens rotate via `/auth/refresh`.
- Public key rotation and full device-key lifecycle are not fully implemented as a production workflow.

## Forward Secrecy / Post-Compromise Security
- Double Ratchet is **not** implemented in production flow.
- Current design uses long-lived key pairs + per-message symmetric keys.
- Result: limited forward secrecy properties compared to Signal-style ratcheting.

## Device Change Handling
- Multi-device session tracking exists (`auth_sessions` table + `/auth/sessions`).
- Key migration UX/protocol between devices is not fully documented in current app flow.

## Metadata Not Protected by E2EE
- Sender/recipient identifiers
- Chat membership
- Message timestamps
- Message type flags
- Delivery/read state
- File size/mimetype and media metadata container

## Threat Model (current)
- Mitigated:
  - passive network interception (with TLS deployment)
  - backend plaintext access for 1:1 payloads
  - message replay duplicates (idempotency via `client_message_id`)
- Partially mitigated / open:
  - MITM on public key distribution (endpoint currently uses hash-based placeholder signature)
  - no production ratchet (FS/PCS gap)
  - groups/channels non-E2EE

## Vulnerability Reporting
- Use private security channel (maintainer-controlled) for sensitive reports.
- Do not open public issue with exploit details before coordinated fix.

Suggested intake template:
- Component/path
- Impact
- Reproduction steps
- Expected vs actual
- Proposed mitigation

## Secret Handling Rules
- Never commit:
  - private keys
  - JWT secrets
  - API tokens
- Use placeholders in documentation.
- Store build/runtime secrets in CI secret manager.

## Secret Rotation Rules
- JWT signing secret: rotate on schedule and incident response.
- DB credentials: rotate on schedule and after exposure.

## Security Findings (from current code)
1. `GET /users/:id/public-key` returns hash-derived placeholder signature, not true Ed25519 signature chain.
2. Group/channel messages are plaintext at application layer (no E2EE envelopes).

## Recommended Immediate Actions
1. Complete public-key authenticity (real Ed25519 signatures end-to-end in app flow).
2. Implement group E2EE (Sender Keys or MLS).
3. Implement Double Ratchet for 1:1 sessions.
