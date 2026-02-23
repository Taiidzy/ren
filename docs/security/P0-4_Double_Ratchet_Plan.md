# P0-4: Forward Secrecy & Double Ratchet Implementation Plan

## Overview

**Цель**: Внедрить Forward Secrecy (FS) и Post-Compromise Security (PCS) через реализацию X3DH + Double Ratchet протокола.

**Статус**: ⏳ Not Started

**Приоритет**: P0 (Critical)

**Оценка времени**: 2-4 недели

---

## Problem Statement

### Текущее состояние
- E2EE использует статические X25519 ключи
- Компрометация долгосрочного ключа раскрывает:
  - Всю историю переписки
  - Все будущие сообщения (до смены ключа)
- Отсутствует механизм automatic key rotation

### Требуемое состояние
- **Forward Secrecy**: Компрометация текущего ключа не раскрывает прошлые сообщения
- **Post-Compromise Security**: Автоматическое восстановление после компрометации
- **Asynchronous**: Поддержка offline сообщений

---

## Architecture

### 1. X3DH (Extended Triple Diffie-Hellman)

#### Key Types
```
Identity Key (IK)     - Долгосрочный, хранится на устройстве
Signed PreKey (SPK)   - Среднесрочный, подписывается IK, хранится на сервере
One-Time PreKey (OPK) - Одноразовый, хранится на сервере (50-100 шт)
```

#### Initial Key Exchange
```
Alice (Initiator)                Server                    Bob (Recipient)
     |                             |                             |
     |-- GET /prekeys/{bob_id} --->|                             |
     |                             |                             |
     |<-- {SPK, OPK, IK_sig} ------|                             |
     |                             |                             |
     |-- X3DH Key Agreement ------->|                             |
     |   (IK_A, SPK_B, OPK_B)      |                             |
     |                             |                             |
     |-- Send Message (ephemeral) ->|                             |
     |                             |                             |
     |                             |-------- Notify Bob -------->|
     |                             |                             |
     |                             |<-- Bob computes shared secret
```

#### Shared Secret Computation
```
SK = KDF(
  ECDH(IK_A, SPK_B) ||
  ECDH(EK_A, IK_B) ||
  ECDH(EK_A, SPK_B) ||
  ECDH(EK_A, OPK_B)
)
```

### 2. Double Ratchet

#### Components
```
┌─────────────────────────────────────────────────────────────┐
│                    Double Ratchet State                      │
├─────────────────────────────────────────────────────────────┤
│  DH Ratchet                                                  │
│  ├─ Local DH Key Pair (ratchet key)                         │
│  ├─ Remote DH Public Key                                     │
│  └─ DH Output → Root Key                                     │
│                                                              │
│  Symmetric Ratchet                                           │
│  ├─ Root Key Chain                                           │
│  ├─ Sending Chain (chain_key → message_key)                 │
│  └─ Receiving Chain (chain_key → message_key)               │
└─────────────────────────────────────────────────────────────┘
```

#### Ratchet Flow
```
Send Message:
  1. ChainKey → MessageKey + NewChainKey (KDF)
  2. Encrypt with MessageKey (AES-256/ChaCha20)
  3. Increment message counter

Receive Message:
  1. Check message counter
  2. Derive MessageKey from stored ChainKey
  3. Decrypt with MessageKey
  4. Store skipped keys if out-of-order

DH Ratchet Step (every other message):
  1. Generate new DH key pair
  2. Compute DH with remote public key
  3. Mix DH output into Root Key (HMAC)
  4. Derive new ChainKeys
```

---

## Implementation Plan

### Phase 1: X3DH Protocol (Week 1-2)

#### 1.1 Ren-SDK Changes

**New Files**:
```
Ren-SDK/src/x3dh/
├── mod.rs           # Module exports
├── identity.rs      # Identity key management
├── prekey.rs        # PreKey generation & storage
├── bundle.rs        # PreKey bundle structures
└── protocol.rs      # X3DH key agreement logic
```

**Identity Key Management** (`identity.rs`):
```rust
pub struct IdentityKeyStore {
    identity_keypair: KeyPair,      // X25519
    signed_prekey: SignedPreKey,    // X25519 + Ed25519 signature
}

impl IdentityKeyStore {
    pub fn generate() -> Result<Self>;
    pub fn load_from_storage() -> Result<Self>;
    pub fn get_public_identity() -> PublicKey;
    pub fn sign_prekey(&self, prekey: &PublicKey) -> Signature;
}
```

**PreKey Bundle** (`bundle.rs`):
```rust
pub struct PreKeyBundle {
    pub identity_key: String,      // Base64, 32 bytes
    pub signed_prekey: String,     // Base64, 32 bytes
    pub signed_prekey_signature: String, // Base64, 64 bytes
    pub one_time_prekey: Option<String>, // Base64, 32 bytes
    pub one_time_prekey_id: Option<u32>,
}
```

**X3DH Protocol** (`protocol.rs`):
```rust
pub fn x3dh_initiate(
    my_identity: &IdentityKeyStore,
    their_bundle: &PreKeyBundle,
) -> Result<SharedSecret>;

pub fn x3dh_respond(
    my_identity: &IdentityKeyStore,
    their_identity: &PublicKey,
    ephemeral: &PublicKey,
) -> Result<SharedSecret>;
```

#### 1.2 Backend API Changes

**New Migration** (`backend/migrations/20260301_x3dh_prekeys.sql`):
```sql
-- One-Time PreKeys storage
CREATE TABLE prekeys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prekey_id INTEGER NOT NULL,
    prekey_public TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    used_at TIMESTAMPTZ,
    UNIQUE(user_id, prekey_id)
);

-- Signed PreKeys
CREATE TABLE signed_prekeys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prekey_public TEXT NOT NULL,
    signature TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    is_current BOOLEAN DEFAULT true
);

-- Indexes
CREATE INDEX idx_prekeys_user ON prekeys(user_id) WHERE used_at IS NULL;
CREATE INDEX idx_signed_prekeys_user ON signed_prekeys(user_id, is_current);
```

**New API Endpoints** (`backend/src/route/keys.rs`):
```rust
// GET /keys/{user_id}/bundle
// Returns PreKeyBundle for X3DH initiation
async fn get_prekey_bundle(
    State(state): State<AppState>,
    Path(user_id): Path<i32>,
) -> Result<Json<PreKeyBundleResponse>>;

// POST /keys/one-time
// Upload new one-time prekeys
async fn upload_one_time_prekeys(
    State(state): State<AppState>,
    CurrentUser { id }: CurrentUser,
    Json(payload): Json<UploadPreKeysRequest>,
) -> Result<StatusCode>;

// DELETE /keys/one-time/{prekey_id}
// Mark prekey as used
async fn consume_prekey(
    State(state): State<AppState>,
    Path(prekey_id): Path<i32>,
) -> Result<StatusCode>;
```

#### 1.3 Flutter Integration

**New Files**:
```
apps/flutter/lib/core/cryptography/x3dh/
├── identity_key_store.dart
├── prekey_bundle.dart
├── x3dh_protocol.dart
└── prekey_repository.dart
```

**PreKey Repository** (`prekey_repository.dart`):
```dart
abstract class PreKeyRepository {
  Future<PreKeyBundle> getBundle(String userId);
  Future<void> uploadOneTimePreKeys(List<OneTimePreKey> prekeys);
  Future<void> markPreKeyUsed(int preKeyId);
  Future<List<OneTimePreKey>> getUnusedPreKeys();
}
```

### Phase 2: Double Ratchet (Week 2-3)

#### 2.1 Ren-SDK Changes

**New Files**:
```
Ren-SDK/src/ratchet/
├── mod.rs              # Module exports
├── chain.rs            # Chain key management
├── message_keys.rs     # Message key derivation
├── root_chain.rs       # Root key chain
├── dh_ratchet.rs       # DH ratchet step
├── symmetric_ratchet.rs # Symmetric ratchet step
└── session.rs          # Session state
```

**Session State** (`session.rs`):
```rust
pub struct RatchetSession {
    // Identity
    pub local_identity: KeyPair,
    pub remote_identity: PublicKey,
    
    // Ratchet state
    pub root_key: RootKey,
    pub sending_chain: ChainKey,
    pub receiving_chain: Option<ChainKey>,
    
    // DH ratchet
    pub local_ratchet_key: KeyPair,
    pub remote_ratchet_key: Option<PublicKey>,
    
    // Counters
    pub sent_message_count: u32,
    pub received_message_count: u32,
    
    // Metadata
    pub session_version: u8,
    pub created_at: i64,
}
```

**Message Encryption Flow**:
```rust
impl RatchetSession {
    pub fn encrypt_message(&mut self, plaintext: &[u8]) -> Result<EncryptedMessage> {
        // 1. Symmetric ratchet step
        let message_keys = self.sending_chain.next_message_key()?;
        
        // 2. DH ratchet every other message
        if self.should_ratchet() {
            self.perform_dh_ratchet()?;
        }
        
        // 3. Encrypt with message key
        let ciphertext = encrypt_with_key(plaintext, &message_keys.cipher_key)?;
        
        // 4. Build message
        Ok(EncryptedMessage {
            ciphertext: base64_encode(&ciphertext),
            ephemeral_key: base64_encode(&self.local_ratchet_key.public),
            counter: self.sent_message_count,
        })
    }
    
    pub fn decrypt_message(&mut self, encrypted: &EncryptedMessage) -> Result<Vec<u8>> {
        // 1. Check counter and handle out-of-order
        let message_keys = self.get_message_keys_for_counter(encrypted.counter)?;
        
        // 2. Decrypt
        let plaintext = decrypt_with_key(
            &base64_decode(&encrypted.ciphertext)?,
            &message_keys.cipher_key,
        )?;
        
        Ok(plaintext)
    }
}
```

#### 2.2 Session Storage

**Local Storage** (Flutter):
```dart
abstract class SessionStore {
  Future<RatchetSession?> getSession(String recipientId);
  Future<void> storeSession(String recipientId, RatchetSession session);
  Future<void> deleteSession(String recipientId);
  Future<List<String>> getAllSessionIds();
}
```

**Implementation** (Hive/Isar):
```dart
@HiveType(typeId: 3)
class RatchetSessionBox extends HiveObject {
  @HiveField(0)
  String sessionId;
  
  @HiveField(1)
  String rootKey; // Base64
  
  @HiveField(2)
  String sendingChainKey; // Base64
  
  @HiveField(3)
  int sendingCounter;
  
  // ... other fields
}
```

### Phase 3: Integration & Migration (Week 3-4)

#### 3.1 Protocol Versioning

**Message Envelope Update**:
```json
{
  "protocol_version": 2,
  "message_type": "ratchet_message",
  "ciphertext": "base64...",
  "ephemeral_key": "base64...",
  "counter": 42,
  "envelopes": { ... }
}
```

**Backward Compatibility**:
```rust
pub enum MessageFormat {
    Legacy { /* current format */ },
    Ratchet { /* new format */ },
}

pub fn decrypt_message(
    encrypted: &EncryptedMessage,
    my_keys: &Keys,
) -> Result<MessageFormat> {
    match encrypted.protocol_version {
        1 => decrypt_legacy(encrypted, my_keys),
        2 => decrypt_ratchet(encrypted, my_keys),
        _ => Err(Error::UnsupportedProtocol),
    }
}
```

#### 3.2 Migration Strategy

**Phase 1: Dual-Write (2 weeks)**
- Новые сессии используют Double Ratchet
- Старые сессии продолжают работать
- Клиент поддерживает оба формата

**Phase 2: Gradual Rollout (2 weeks)**
- 10% трафика на новый протокол
- Мониторинг ошибок
- Постепенное увеличение до 100%

**Phase 3: Deprecation (4 weeks)**
- Предупреждение о legacy протоколе
- Принудительная миграция через 30 дней

---

## Database Schema

### New Tables

```sql
-- One-Time PreKeys
CREATE TABLE prekeys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prekey_id INTEGER NOT NULL,
    prekey_public TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    used_at TIMESTAMPTZ,
    UNIQUE(user_id, prekey_id)
);

-- Signed PreKeys
CREATE TABLE signed_prekeys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prekey_public TEXT NOT NULL,
    signature TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    is_current BOOLEAN DEFAULT true
);

-- Indexes for performance
CREATE INDEX idx_prekeys_user_unused ON prekeys(user_id) WHERE used_at IS NULL;
CREATE INDEX idx_signed_prekeys_current ON signed_prekeys(user_id, is_current);
```

---

## API Changes

### New Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/keys/{user_id}/bundle` | Get PreKey bundle for X3DH |
| POST | `/keys/one-time` | Upload one-time prekeys |
| DELETE | `/keys/one-time/{id}` | Mark prekey as used |
| POST | `/keys/signed` | Upload/update signed prekey |

### Request/Response Examples

**GET /keys/{user_id}/bundle**:
```json
{
  "user_id": 123,
  "identity_key": "base64...",
  "signed_prekey": "base64...",
  "signed_prekey_signature": "base64...",
  "one_time_prekey": "base64...",
  "one_time_prekey_id": 42
}
```

**POST /keys/one-time**:
```json
{
  "prekeys": [
    { "prekey_id": 1, "prekey": "base64..." },
    { "prekey_id": 2, "prekey": "base64..." }
  ]
}
```

---

## Testing Strategy

### Unit Tests

**X3DH Protocol**:
```rust
#[test]
fn test_x3dh_key_agreement() {
    let alice_identity = IdentityKeyStore::generate();
    let bob_identity = IdentityKeyStore::generate();
    let bob_bundle = bob_identity.get_prekey_bundle();
    
    let alice_secret = x3dh_initiate(&alice_identity, &bob_bundle);
    let bob_secret = x3dh_respond(&bob_identity, &alice_identity.public, &ephemeral);
    
    assert_eq!(alice_secret, bob_secret);
}
```

**Double Ratchet**:
```rust
#[test]
fn test_message_encryption_decryption() {
    let mut alice = RatchetSession::initiate(...);
    let mut bob = RatchetSession::respond(...);
    
    let encrypted = alice.encrypt_message(b"Hello");
    let decrypted = bob.decrypt_message(&encrypted);
    
    assert_eq!(decrypted, b"Hello");
}

#[test]
fn test_forward_secrecy() {
    // Compromise current state
    // Verify past messages cannot be decrypted
}

#[test]
fn test_post_compromise_security() {
    // Simulate compromise
    // Verify recovery after DH ratchet steps
}
```

### Integration Tests

1. **End-to-End Key Agreement**
2. **Message Exchange with Ratcheting**
3. **Out-of-Order Message Handling**
4. **Session Recovery after Backup**

### Security Tests

1. **Key Compromise Simulation**
2. **Replay Attack Prevention**
3. **Man-in-the-Middle Detection**
4. **Entropy Analysis**

---

## Security Considerations

### Key Storage
- Identity keys: Secure Enclave / KeyStore
- Session state: Encrypted storage
- PreKeys: Server-side encryption at rest

### Trust on First Use (TOFU)
- Safety numbers for key verification
- Key change notifications
- QR code verification

### Cryptographic Choices
- X25519 for ECDH
- Ed25519 for signatures
- ChaCha20-Poly1305 for encryption
- HKDF-SHA256 for key derivation
- AES-256-GCM as alternative

---

## Rollback Plan

### Phase Gates
1. **After X3DH**: Can rollback without breaking existing E2EE
2. **After Double Ratchet**: Dual-write mode allows fallback
3. **After Full Rollout**: Requires coordinated rollback

### Fallback Mechanism
```rust
pub fn encrypt_with_fallback(
    message: &str,
    recipient: &User,
    use_ratchet: bool,
) -> Result<EncryptedMessage> {
    if use_ratchet {
        encrypt_ratchet(message, recipient)
    } else {
        encrypt_legacy(message, recipient)
    }
}
```

---

## Success Criteria

### Definition of Done

- [ ] X3DH key agreement implemented and tested
- [ ] Double Ratchet encryption/decryption working
- [ ] Forward secrecy verified (cryptographic audit)
- [ ] Post-compromise security verified
- [ ] Session backup/restore working
- [ ] Backward compatibility maintained
- [ ] Performance benchmarks met (<100ms encrypt/decrypt)
- [ ] Security audit completed
- [ ] Documentation updated

### Metrics

- **Encryption latency**: < 50ms p95
- **Decryption latency**: < 50ms p95
- **Message size overhead**: < 200 bytes
- **Session storage**: < 10KB per chat
- **PreKey consumption**: < 10/day per user

---

## Dependencies

### External Libraries
- `x25519-dalek` — X25519 ECDH
- `ed25519-dalek` — Ed25519 signatures
- `hkdf` — Key derivation
- `chacha20poly1305` — AEAD encryption

### Internal Dependencies
- Ren-SDK crypto module
- Backend auth_sessions
- Flutter secure_storage

---

## Timeline

| Week | Milestone |
|------|-----------|
| 1 | X3DH protocol implementation |
| 2 | Backend PreKey API |
| 3 | Double Ratchet core |
| 4 | Session storage & backup |
| 5 | Flutter integration |
| 6 | Testing & security audit |
| 7 | Gradual rollout (10%) |
| 8 | Full rollout |

---

## Resources

### Reference Implementations
- [Signal Protocol](https://signal.org/docs/)
- [libolm](https://gitlab.matrix.org/matrix-org/olm)
- [Double Ratchet Spec](https://doubleratchet.specs.matrix.org/)

### Documentation
- X3DH: https://signal.org/docs/specifications/x3dh/
- Double Ratchet: https://signal.org/docs/specifications/doubleratchet/
