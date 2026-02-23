# P0-5: Group E2EE (Sender Keys) Implementation Plan

## Overview

**Цель**: Реализовать End-to-End Encryption для групповых чатов и каналов через Sender Keys protocol.

**Статус**: 🟡 Partially Implemented (UI Warning only)

**Приоритет**: P0 (Critical)

**Оценка времени**: 1-2 недели

---

## Problem Statement

### Текущее состояние
- Групповые/канальные сообщения **НЕ защищены E2EE**
- Сервер имеет доступ к plaintext содержимому
- В README задокументировано как известное ограничение
- UI warning добавлен (виджет `GroupE2EEWarning`)

### Требуемое состояние
- Все групповые сообщения зашифрованы E2EE
- Сервер не может расшифровать контент
- Поддержка dynamic member join/leave
- Эффективная distribution ключей

---

## Architecture

### Sender Keys Protocol

#### Concept
```
Каждый отправитель имеет свой "sender chain":
┌──────────────────────────────────────────┐
│  Sender Alice                            │
│  ├─ Chain Key A → Message Key A1        │
│  ├─ Chain Key A → Message Key A2        │
│  └─ Chain Key A → Message Key A3        │
├──────────────────────────────────────────┤
│  Sender Bob                              │
│  ├─ Chain Key B → Message Key B1        │
│  ├─ Chain Key B → Message Key B2        │
│  └─ Chain Key B → Message Key B3        │
└──────────────────────────────────────────┘
```

#### Key Distribution
```
1. Alice создает Sender Key
2. Шифрует для каждого участника через 1:1 E2EE
3. Отправляет зашифрованные ключи через сервер
4. Участники расшифровывают своим 1:1 ключом
5. Сохраняют Sender Key для будущих сообщений
```

#### Message Flow
```
┌──────────┐     ┌────────┐     ┌──────────┐
│  Alice   │     │ Server │     │  Bob     │
│          │     │        │     │          │
│ Create   │     │        │     │          │
│ Sender   │     │        │     │          │
│ Key      │     │        │     │          │
│    │     │     │        │     │          │
│    ├─────│────>│        │     │          │
│    │     │     │ Store  │     │          │
│    │     │     │        │     │          │
│ Encrypt │     │        │     │          │
│ Message │     │        │     │          │
│    │     │     │        │     │          │
│    ├─────│────>│        │     │          │
│    │     │     │Forward │     │          │
│    │     │     │    │   │─────│────────>│
│    │     │     │    │   │     │ Decrypt│
│    │     │     │    │   │     │ with   │
│    │     │     │    │   │     │ Sender │
│    │     │     │    │   │     │ Key    │
└──────────┘     └────────┘     └──────────┘
```

---

## Implementation Plan

### Phase 1: Sender Keys Core (Week 1)

#### 1.1 Ren-SDK Changes

**New Files**:
```
Ren-SDK/src/sender_keys/
├── mod.rs              # Module exports
├── sender_key.rs       # Sender key structure
├── sender_chain.rs     # Chain key management
├── group_session.rs    # Group session state
└── distribution.rs     # Key distribution logic
```

**Sender Key Structure** (`sender_key.rs`):
```rust
pub struct SenderKey {
    pub sender_id: i32,
    pub sender_chain_id: u32,
    pub chain_key: [u8; 32],
    pub signing_key: KeyPair, // Ed25519 for signing
    pub iteration: u32,
}

impl SenderKey {
    pub fn generate(sender_id: i32) -> Result<Self>;
    
    pub fn next_message_key(&mut self) -> Result<MessageKey> {
        // KDF: chain_key -> message_key + new_chain_key
        let mut hasher = HmacSha256::new_from_slice(&self.chain_key)?;
        hasher.update(&self.iteration.to_le_bytes());
        let result = hasher.finalize().into_bytes();
        
        self.chain_key = result[..32].try_into()?;
        self.iteration += 1;
        
        Ok(MessageKey {
            cipher_key: result[32..].try_into()?,
            iv: generate_iv(&self.iteration),
            iteration: self.iteration - 1,
        })
    }
}
```

**Group Session** (`group_session.rs`):
```rust
pub struct GroupSession {
    pub group_id: i32,
    pub my_sender_key: SenderKey,
    pub sender_keys: HashMap<i32, SenderKeyState>, // Other members' keys
}

pub struct SenderKeyState {
    pub sender_id: i32,
    pub chain_key: [u8; 32],
    pub iteration: u32,
    pub signing_key: PublicKey,
}
```

**Encryption Flow**:
```rust
impl GroupSession {
    pub fn encrypt_group_message(
        &mut self,
        plaintext: &[u8],
        group_id: i32,
    ) -> Result<EncryptedGroupMessage> {
        // 1. Get or create my sender key
        let message_key = self.my_sender_key.next_message_key()?;
        
        // 2. Encrypt message
        let ciphertext = encrypt_with_key(plaintext, &message_key.cipher_key)?;
        
        // 3. Sign with Ed25519
        let signature = self.my_sender_key.signing_key.sign(&ciphertext)?;
        
        Ok(EncryptedGroupMessage {
            group_id,
            sender_id: self.my_sender_key.sender_id,
            chain_id: self.my_sender_key.sender_chain_id,
            iteration: message_key.iteration,
            ciphertext: base64_encode(&ciphertext),
            signature: base64_encode(&signature),
        })
    }
    
    pub fn decrypt_group_message(
        &mut self,
        encrypted: &EncryptedGroupMessage,
    ) -> Result<Vec<u8>> {
        // 1. Get sender's chain
        let sender_state = self.sender_keys
            .get_mut(&encrypted.sender_id)
            .ok_or(Error::UnknownSender)?;
        
        // 2. Derive message key
        let message_key = derive_message_key(
            &sender_state.chain_key,
            encrypted.iteration,
        )?;
        
        // 3. Verify signature
        let ciphertext = base64_decode(&encrypted.ciphertext)?;
        let signature = base64_decode(&encrypted.signature)?;
        verify_signature(&ciphertext, &signature, &sender_state.signing_key)?;
        
        // 4. Decrypt
        let plaintext = decrypt_with_key(&ciphertext, &message_key.cipher_key)?;
        
        Ok(plaintext)
    }
}
```

#### 1.2 Key Distribution

**Distribution Protocol**:
```rust
pub struct SenderKeyDistribution {
    pub group_id: i32,
    pub sender_id: i32,
    pub chain_id: u32,
    pub sender_key: [u8; 32], // Encrypted for each recipient
    pub signing_key: PublicKey,
}

pub fn distribute_sender_keys(
    group_id: i32,
    my_sender_key: &SenderKey,
    members: &[i32],
    e2ee_service: &E2EEService,
) -> Result<HashMap<i32, Vec<u8>>> {
    let mut distributions = HashMap::new();
    
    for member_id in members {
        // Get member's 1:1 public key
        let member_pubkey = e2ee_service.get_public_key(*member_id)?;
        
        // Encrypt sender key with member's key
        let encrypted_key = wrap_symmetric_key(
            &my_sender_key.chain_key,
            &member_pubkey,
        )?;
        
        // Build distribution message
        let distribution = SenderKeyDistribution {
            group_id,
            sender_id: my_sender_key.sender_id,
            chain_id: my_sender_key.sender_chain_id,
            sender_key: encrypted_key,
            signing_key: my_sender_key.signing_key.public,
        };
        
        distributions.insert(
            *member_id,
            serialize(&distribution)?,
        );
    }
    
    Ok(distributions)
}
```

### Phase 2: Backend Integration (Week 1-2)

#### 2.1 Database Schema

**New Migration** (`backend/migrations/20260301_sender_keys.sql`):
```sql
-- Sender Keys storage (encrypted)
CREATE TABLE group_sender_keys (
    id SERIAL PRIMARY KEY,
    group_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chain_id INTEGER NOT NULL,
    sender_key_public TEXT NOT NULL, -- Encrypted sender key
    signing_key_public TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(group_id, sender_id, chain_id)
);

-- Indexes
CREATE INDEX idx_sender_keys_group ON group_sender_keys(group_id);
CREATE INDEX idx_sender_keys_sender ON group_sender_keys(sender_id);
```

#### 2.2 API Endpoints

**New File** (`backend/src/route/group_keys.rs`):
```rust
// POST /groups/{group_id}/sender-keys
// Upload my sender key distribution
async fn upload_sender_keys(
    State(state): State<AppState>,
    CurrentUser { id }: CurrentUser,
    Path(group_id): Path<i32>,
    Json(payload): Json<UploadSenderKeysRequest>,
) -> Result<StatusCode>;

// GET /groups/{group_id}/sender-keys
// Get all sender keys for group members
async fn get_sender_keys(
    State(state): State<AppState>,
    CurrentUser { id }: CurrentUser,
    Path(group_id): Path<i32>,
) -> Result<Json<Vec<SenderKeyResponse>>>;

// DELETE /groups/{group_id}/sender-keys/{sender_id}
// Remove sender key (when member leaves)
async fn remove_sender_key(
    State(state): State<AppState>,
    CurrentUser { id }: CurrentUser,
    Path((group_id, sender_id)): Path<(i32, i32)>,
) -> Result<StatusCode>;
```

#### 2.3 WebSocket Integration

**Update Message Types** (`backend/src/route/ws.rs`):
```rust
enum ClientEvent {
    // ... existing variants ...
    
    // New: Group message with sender key
    GroupMessage {
        chat_id: i32,
        message: String,
        message_type: Option<String>,
        sender_key_distribution: Option<SenderKeyDistribution>,
        metadata: Option<Vec<FileMetadata>>,
    },
}
```

### Phase 3: Member Management (Week 2)

#### 3.1 Member Join Flow

```rust
pub async fn handle_member_added(
    group_id: i32,
    new_member_id: i32,
    existing_members: &[i32],
    e2ee_service: &E2EEService,
) -> Result<()> {
    // 1. Each existing member sends their sender key to new member
    for member_id in existing_members {
        let my_sender_key = e2ee_service.get_my_sender_key(group_id)?;
        
        // Encrypt with new member's 1:1 key
        let new_member_pubkey = e2ee_service.get_public_key(new_member_id)?;
        let encrypted_key = wrap_symmetric_key(
            &my_sender_key.chain_key,
            &new_member_pubkey,
        )?;
        
        // Send via 1:1 message
        e2ee_service.send_1to1_message(
            new_member_id,
            SenderKeyDistribution {
                group_id,
                sender_id: *member_id,
                sender_key: encrypted_key,
                ..
            },
        ).await?;
    }
    
    // 2. New member creates their sender key and distributes
    let new_sender_key = SenderKey::generate(new_member_id)?;
    distribute_sender_keys(
        group_id,
        &new_sender_key,
        existing_members,
        e2ee_service,
    ).await?;
    
    Ok(())
}
```

#### 3.2 Member Leave Flow (Key Rotation)

```rust
pub async fn handle_member_removed(
    group_id: i32,
    removed_member_id: i32,
    remaining_members: &[i32],
    e2ee_service: &E2EEService,
) -> Result<()> {
    // CRITICAL: All remaining members must rotate their sender keys
    // This prevents removed member from reading future messages
    
    for member_id in remaining_members {
        // 1. Generate new sender key
        let new_sender_key = SenderKey::generate(*member_id)?;
        
        // 2. Distribute to all remaining members (NOT removed member)
        distribute_sender_keys(
            group_id,
            &new_sender_key,
            remaining_members,
            e2ee_service,
        ).await?;
        
        // 3. Delete old sender key from server
        e2ee_service.delete_sender_key(group_id, *member_id).await?;
    }
    
    // 4. Remove removed member's key from server
    e2ee_service.delete_sender_key(group_id, removed_member_id).await?;
    
    Ok(())
}
```

---

## Flutter Integration

### New Files

```
apps/flutter/lib/core/cryptography/sender_keys/
├── sender_key_manager.dart
├── group_session_store.dart
├── sender_key_distribution.dart
└── group_crypto_service.dart

apps/flutter/lib/features/chats/domain/
├── group_message.dart
└── group_key_repository.dart
```

### Group Crypto Service

```dart
class GroupCryptoService {
  final SenderKeyManager _senderKeyManager;
  final GroupSessionStore _sessionStore;
  final E2EEService _e2ee;
  
  /// Encrypt message for group
  Future<EncryptedGroupMessage> encryptGroupMessage({
    required int groupId,
    required String plaintext,
    required String messageType,
  }) async {
    // Get or create my sender key for this group
    var senderKey = await _senderKeyManager.getSenderKey(groupId);
    if (senderKey == null) {
      senderKey = await _senderKeyManager.generateSenderKey(groupId);
      await _distributeSenderKey(groupId, senderKey);
    }
    
    // Encrypt with sender key
    final messageKey = senderKey.nextMessageKey();
    final ciphertext = await _encrypt(plaintext, messageKey.cipherKey);
    final signature = await _sign(ciphertext, senderKey.signingKey);
    
    return EncryptedGroupMessage(
      groupId: groupId,
      senderId: senderKey.senderId,
      chainId: senderKey.chainId,
      iteration: messageKey.iteration,
      ciphertext: base64Encode(ciphertext),
      signature: base64Encode(signature),
    );
  }
  
  /// Decrypt message from group
  Future<String> decryptGroupMessage(
    EncryptedGroupMessage encrypted,
  ) async {
    // Get sender's chain
    final senderState = await _sessionStore.getSenderKeyState(
      encrypted.groupId,
      encrypted.senderId,
    );
    
    if (senderState == null) {
      throw GroupCryptoError.unknownSender(encrypted.senderId);
    }
    
    // Derive message key
    final messageKey = _deriveMessageKey(
      senderState.chainKey,
      encrypted.iteration,
    );
    
    // Verify signature
    final ciphertext = base64Decode(encrypted.ciphertext);
    final signature = base64Decode(encrypted.signature);
    final valid = await _verifySignature(
      ciphertext,
      signature,
      senderState.signingKey,
    );
    
    if (!valid) {
      throw GroupCryptoError.invalidSignature();
    }
    
    // Decrypt
    final plaintext = await _decrypt(ciphertext, messageKey.cipherKey);
    
    // Update chain state
    await _sessionStore.updateSenderKeyIteration(
      encrypted.groupId,
      encrypted.senderId,
      encrypted.iteration + 1,
    );
    
    return plaintext;
  }
  
  /// Distribute my sender key to group members
  Future<void> _distributeSenderKey(
    int groupId,
    SenderKey senderKey,
  ) async {
    final members = await _getGroupMembers(groupId);
    
    for (final memberId in members) {
      if (memberId == senderKey.senderId) continue;
      
      // Get member's 1:1 public key
      final memberPubKey = await _e2ee.getPublicKey(memberId);
      
      // Encrypt sender key with member's key
      final wrappedKey = await _wrapKey(
        senderKey.chainKey,
        memberPubKey,
      );
      
      // Send distribution message via 1:1 E2EE channel
      await _e2ee.sendMessage(
        recipientId: memberId,
        message: SenderKeyDistribution(
          groupId: groupId,
          senderId: senderKey.senderId,
          chainId: senderKey.chainId,
          encryptedSenderKey: wrappedKey,
          signingKey: senderKey.signingKey.public,
        ),
      );
    }
  }
}
```

---

## UI Changes

### Remove E2EE Warning

**Update** `apps/flutter/lib/features/chats/presentation/widgets/group_e2ee_warning.dart`:
```dart
// OLD: Always show warning for groups
// NEW: Show warning only during migration period

class GroupE2EEWarning extends StatelessWidget {
  final String chatKind;
  final bool isE2EEEnabled; // New flag
  
  const GroupE2EEWarning({
    required this.chatKind,
    this.isE2EEEnabled = false,
  });
  
  @override
  Widget build(BuildContext context) {
    if (isE2EEEnabled) {
      // Show "E2EE Enabled" badge instead
      return _E2EEBadge();
    }
    
    if (!_shouldShow) return SizedBox.shrink();
    
    return _WarningBanner();
  }
}
```

### E2EE Status Indicator

**New Widget** `apps/flutter/lib/features/chats/presentation/widgets/e2ee_badge.dart`:
```dart
class E2EEBadge extends StatelessWidget {
  const E2EEBadge({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 12, color: Colors.green.shade700),
          SizedBox(width: 4),
          Text(
            'E2EE Enabled',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.green.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Migration Strategy

### Phase 1: Dual Mode (2 weeks)
- Новые группы используют Sender Keys
- Старые группы работают в legacy режиме
- UI показывает статус E2EE

### Phase 2: Gradual Rollout (2 weeks)
- 25% новых групп на Sender Keys
- Мониторинг ошибок расшифровки
- Постепенное увеличение до 100%

### Phase 3: Legacy Deprecation (4 weeks)
- Предупреждение о legacy группах
- Предложение миграции
- Принудительная миграция через 30 дней

---

## Testing Strategy

### Unit Tests

```rust
#[test]
fn test_sender_key_chain_derivation() {
    let mut sender_key = SenderKey::generate(1);
    
    let key1 = sender_key.next_message_key();
    let key2 = sender_key.next_message_key();
    
    assert_ne!(key1.cipher_key, key2.cipher_key);
    assert_eq!(key1.iteration, 0);
    assert_eq!(key2.iteration, 1);
}

#[test]
fn test_group_message_encryption() {
    let mut session = GroupSession::new(1);
    let plaintext = b"Hello, group!";
    
    let encrypted = session.encrypt_group_message(1, plaintext);
    let decrypted = session.decrypt_group_message(&encrypted);
    
    assert_eq!(decrypted, plaintext);
}

#[test]
fn test_member_rotation_on_leave() {
    // Create group with 3 members
    // Remove 1 member
    // Verify remaining members rotated keys
    // Verify removed member cannot decrypt new messages
}
```

### Integration Tests

1. **Key Distribution**: Alice sends key to Bob via 1:1 E2EE
2. **Group Messaging**: Multiple senders, out-of-order delivery
3. **Member Join**: New member receives all sender keys
4. **Member Leave**: Key rotation prevents future access

### Security Tests

1. **Confidentiality**: Server cannot decrypt group messages
2. **Forward Secrecy**: Removed member cannot read future messages
3. **Authentication**: Verify sender signatures
4. **Replay Prevention**: Iteration counters prevent replay

---

## Security Considerations

### Key Storage
- Sender keys: Encrypted local storage
- Signing keys: Secure Enclave / KeyStore
- Server storage: Encrypted at rest

### Trust Model
- Server distributes keys but cannot decrypt
- Members trust sender signatures
- Key verification via 1:1 E2EE channel

### Cryptographic Choices
- ChaCha20-Poly1305: Message encryption
- HMAC-SHA256: Chain key derivation
- Ed25519: Sender authentication
- X25519: Key wrapping for distribution

---

## Success Criteria

### Definition of Done

- [ ] Sender Keys protocol implemented
- [ ] Key distribution working via 1:1 E2EE
- [ ] Member join/leave key rotation working
- [ ] Server cannot decrypt group messages (verified)
- [ ] UI shows E2EE status for groups
- [ ] Performance: <100ms encrypt/decrypt
- [ ] Backward compatibility maintained
- [ ] Documentation updated

### Metrics

- **Encryption latency**: < 50ms p95
- **Decryption latency**: < 50ms p95
- **Key distribution time**: < 1s for 50 members
- **Message size overhead**: < 100 bytes
- **Storage**: < 1KB per sender

---

## Dependencies

### External Libraries
- Same as P0-4 (X25519, Ed25519, ChaCha20)

### Internal Dependencies
- P0-2: Public Key Authentication (for key distribution)
- P0-3: Recovery Scheme (for backup)
- Existing 1:1 E2EE infrastructure

---

## Timeline

| Week | Milestone |
|------|-----------|
| 1 | Sender Keys core implementation |
| 2 | Backend API & distribution |
| 3 | Member management (join/leave) |
| 4 | Flutter integration & UI |
| 5 | Testing & security review |
| 6 | Gradual rollout |

---

## Resources

### Reference Implementations
- [Signal Sender Keys](https://signal.org/docs/specifications/senderkeys/)
- [WhatsApp Security Whitepaper](https://www.whatsapp.com/security/WhatsApp-Security-Whitepaper.pdf)

### Documentation
- Sender Keys: https://signal.org/docs/specifications/senderkeys/
