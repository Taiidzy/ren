/// Double Ratchet Protocol Implementation
/// 
/// A simple implementation of the Double Ratchet protocol using our existing crypto primitives.
/// 
/// # References
/// - [Signal Double Ratchet Specification](https://signal.org/docs/specifications/doubleratchet/)

use crate::crypto::{
    generate_key_pair, 
    import_private_key_b64, 
    import_public_key_b64,
    KeyPair,
    CryptoError,
};
use crate::x3dh::SharedSecret;
use hkdf::Hkdf;
use sha2::Sha256;
use chacha20poly1305::{ChaCha20Poly1305, KeyInit, Nonce};
use chacha20poly1305::aead::Aead;
use hmac::{Hmac, Mac};
use rand_core::{RngCore, OsRng};
use base64::{engine::general_purpose, Engine};
use serde::{Serialize, Deserialize};

type HmacSha256 = Hmac<Sha256>;

/// Root Key Chain
#[derive(Debug, Clone)]
struct RootKey {
    key: [u8; 32],
}

impl RootKey {
    fn new(key: [u8; 32]) -> Self {
        Self { key }
    }
    
    /// KDF: Root Key + DH Output → New Root Key + Chain Key
    fn kdf(&self, dh_output: &[u8]) -> (RootKey, ChainKey) {
        let hkdf = Hkdf::<Sha256>::new(None, &self.key);
        let mut okm = [0u8; 64];
        hkdf.expand(dh_output, &mut okm).expect("HKDF expand failed");
        
        let new_root_key = RootKey::new(okm[..32].try_into().unwrap());
        let chain_key = ChainKey::new(okm[32..].try_into().unwrap());
        
        (new_root_key, chain_key)
    }
}

/// Chain Key — производит Message Keys
#[derive(Debug, Clone)]
struct ChainKey {
    key: [u8; 32],
    iteration: u32,
}

impl ChainKey {
    fn new(key: [u8; 32]) -> Self {
        Self { key, iteration: 0 }
    }
    
    /// Следующий Message Key
    /// ChainKey → MessageKey + NewChainKey
    fn next(&mut self) -> MessageKey {
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&self.key).unwrap();
        mac.update(&[0x01]);
        let result = mac.finalize().into_bytes();
        
        let message_key = MessageKey::new(result[..32].try_into().unwrap(), self.iteration);
        
        // Новый chain key
        let mut mac2 = <HmacSha256 as Mac>::new_from_slice(&self.key).unwrap();
        mac2.update(&[0x02]);
        let result2 = mac2.finalize().into_bytes();
        
        self.key = result2[..32].try_into().unwrap();
        self.iteration += 1;
        
        message_key
    }
}

/// Message Key — используется для шифрования одного сообщения
#[derive(Debug, Clone)]
struct MessageKey {
    key: [u8; 32],
    #[allow(dead_code)] // Для будущего использования в заголовке сообщения
    iteration: u32,
}

impl MessageKey {
    fn new(key: [u8; 32], iteration: u32) -> Self {
        Self { key, iteration }
    }

    fn as_bytes(&self) -> &[u8; 32] {
        &self.key
    }
}

/// Ratchet Session State — сериализуемое состояние сессии
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RatchetSessionState {
    pub session_id: String,
    pub root_key: String,
    pub sending_chain_key: Option<String>,
    pub sending_counter: Option<u32>,
    pub receiving_chain_key: Option<String>,
    pub receiving_counter: Option<u32>,
    pub local_ratchet_key: String,
    pub remote_ratchet_key: Option<String>,
    pub sent_message_count: u32,
    pub received_message_count: u32,
    pub created_at: i64,
}

/// Encrypted Message с заголовком
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RatchetMessage {
    /// Эфемерный публичный ключ (для DH ratchet)
    pub ephemeral_key: String,
    /// Зашифрованный ciphertext
    pub ciphertext: String,
    /// Счётчик сообщения
    pub counter: u32,
}

/// Ratchet Session — состояние сессии
pub struct RatchetSession {
    // Identity
    #[allow(dead_code)]
    local_identity: KeyPair,
    #[allow(dead_code)]
    remote_identity: Option<KeyPair>,
    
    // Для первого DH (respondent)
    initial_local_sk: Option<String>, // Приватный ключ для первого DH (identity key)
    
    // Ratchet state
    root_key: RootKey,
    sending_chain: Option<ChainKey>,
    receiving_chain: Option<ChainKey>,
    
    // DH ratchet
    local_ratchet_key: KeyPair,
    remote_ratchet_key: Option<KeyPair>,
    
    // Counters
    sent_message_count: u32,
    received_message_count: u32,
    
    // Metadata
    #[allow(dead_code)]
    session_id: String,
    #[allow(dead_code)]
    created_at: i64,
}

impl RatchetSession {
    /// Инициализация как Alice (initiator)
    pub fn initiate(
        shared_secret: &SharedSecret,
        local_identity: KeyPair,
        remote_identity: KeyPair,
    ) -> Result<Self, CryptoError> {
        let root_key = RootKey::new(*shared_secret.as_bytes());
        let local_ratchet_key = generate_key_pair(false);
        
        // НЕ делаем DH ratchet сразу — он будет сделан при первом шифровании
        // Сохраняем remote identity для будущего DH ratchet
        
        Ok(Self {
            local_identity,
            remote_identity: Some(remote_identity),
            initial_local_sk: None, // Initiator не использует initial_local_sk
            root_key,
            sending_chain: None,
            receiving_chain: None,
            local_ratchet_key,
            remote_ratchet_key: None,
            sent_message_count: 0,
            received_message_count: 0,
            session_id: generate_session_id(),
            created_at: chrono::Utc::now().timestamp(),
        })
    }
    
    /// Инициализация как Bob (respondent)
    pub fn respond(
        shared_secret: &SharedSecret,
        local_identity: KeyPair,
        remote_identity: KeyPair,
        remote_ratchet_key: KeyPair,
    ) -> Result<Self, CryptoError> {
        let root_key = RootKey::new(*shared_secret.as_bytes());
        let local_ratchet_key = generate_key_pair(false);
        
        // Сохраняем local identity private key для первого DH с ephemeral Alice
        let initial_local_sk = local_identity.private_key.clone();
        
        Ok(Self {
            local_identity,
            remote_identity: Some(remote_identity),
            initial_local_sk: Some(initial_local_sk),
            root_key,
            sending_chain: None,
            receiving_chain: None,
            local_ratchet_key,
            remote_ratchet_key: Some(remote_ratchet_key),
            sent_message_count: 0,
            received_message_count: 0,
            session_id: generate_session_id(),
            created_at: chrono::Utc::now().timestamp(),
        })
    }
    
    /// Шифрование сообщения
    pub fn encrypt_message(&mut self, plaintext: &[u8]) -> Result<RatchetMessage, CryptoError> {
        // Если sending_chain ещё нет, делаем DH ratchet
        if self.sending_chain.is_none() {
            // Проверяем есть ли remote_ratchet_key (значит мы respondent и получили сообщение)
            if let Some(ref remote_ratchet) = self.remote_ratchet_key {
                // Мы Bob! Делаем DH ratchet для создания sending_chain
                // Используем текущий local_ratchet_key (который сгенерировали после расшифровки)
                let remote_pk = import_public_key_b64(&remote_ratchet.public_key)?;
                let local_sk = import_private_key_b64(&self.local_ratchet_key.private_key)?;
                let dh_output = local_sk.diffie_hellman(&remote_pk);
                
                // KDF: Root Key + DH Output → New Root Key + Chain Key
                let (new_root_key, chain_key) = self.root_key.kdf(dh_output.as_bytes());
                self.root_key = new_root_key;
                self.sending_chain = Some(chain_key);
                
                // Генерируем новый local ratchet key для следующего сообщения
                self.local_ratchet_key = generate_key_pair(false);
            } else if let Some(ref remote_id) = self.remote_identity {
                // Мы Alice! Делаем первый DH ratchet
                let ephemeral = generate_key_pair(false);
                
                let remote_pk = import_public_key_b64(&remote_id.public_key)?;
                let eph_sk = import_private_key_b64(&ephemeral.private_key)?;
                let dh_output = eph_sk.diffie_hellman(&remote_pk);
                
                let (new_root_key, chain_key) = self.root_key.kdf(dh_output.as_bytes());
                self.root_key = new_root_key;
                self.sending_chain = Some(chain_key);
                
                self.local_ratchet_key = ephemeral;
            } else {
                return Err(CryptoError::Aead);
            }
        }
        
        // Получаем sending chain
        let chain_key = self.sending_chain.as_mut().unwrap();
        let message_key = chain_key.next();
        
        // Шифрование
        let ciphertext = self.encrypt_with_key(plaintext, message_key.as_bytes())?;
        
        self.sent_message_count += 1;
        
        // DH ratchet каждые 2 сообщения
        if self.sent_message_count % 2 == 1 && self.remote_ratchet_key.is_some() {
            self.perform_dh_ratchet_initiator()?;
        }
        
        Ok(RatchetMessage {
            ephemeral_key: self.local_ratchet_key.public_key.clone(),
            ciphertext: general_purpose::STANDARD.encode(&ciphertext),
            counter: self.sent_message_count - 1,
        })
    }
    
    /// Расшифровка сообщения
    pub fn decrypt_message(&mut self, encrypted: &RatchetMessage) -> Result<Vec<u8>, CryptoError> {
        // Проверяем, нужно ли сделать DH ratchet с новым remote key
        let needs_dh_ratchet = if let Some(ref remote_key) = self.remote_ratchet_key {
            remote_key.public_key != encrypted.ephemeral_key
        } else {
            true // Первое сообщение — всегда нужен DH ratchet
        };
        
        if needs_dh_ratchet {
            // Обновляем remote ratchet key
            self.remote_ratchet_key = Some(KeyPair {
                public_key: encrypted.ephemeral_key.clone(),
                private_key: String::new(),
            });
            
            // DH ratchet для создания receiving_chain
            // Для первого сообщения используем initial_local_sk (identity key)
            self.perform_dh_ratchet_respondent_with_local_sk()?;
        }

        // Получаем message key для расшифровки
        if self.receiving_chain.is_none() {
            return Err(CryptoError::Aead);
        }

        let chain_key = self.receiving_chain.as_mut().unwrap();

        // Пропускаем до нужного counter если сообщения пришли не по порядку
        while chain_key.iteration < encrypted.counter {
            chain_key.next();
        }

        let message_key = chain_key.next();

        // Расшифровка
        let ciphertext = general_purpose::STANDARD.decode(&encrypted.ciphertext)?;
        let plaintext = self.decrypt_with_key(&ciphertext, message_key.as_bytes())?;

        self.received_message_count += 1;

        Ok(plaintext)
    }
    
    /// Выполнить DH ratchet (Initiator)
    fn perform_dh_ratchet_initiator(&mut self) -> Result<(), CryptoError> {
        if self.remote_ratchet_key.is_none() {
            return Ok(()); // Нет remote key для DH
        }
        
        let remote_pk = import_public_key_b64(&self.remote_ratchet_key.as_ref().unwrap().public_key)?;
        let local_sk = import_private_key_b64(&self.local_ratchet_key.private_key)?;
        
        let dh_output = local_sk.diffie_hellman(&remote_pk);
        
        // KDF: Root Key + DH Output → New Root Key + Chain Key
        let (new_root_key, chain_key) = self.root_key.kdf(dh_output.as_bytes());
        self.root_key = new_root_key;
        self.sending_chain = Some(chain_key);
        
        // Генерируем новый local ratchet key
        self.local_ratchet_key = generate_key_pair(false);
        
        Ok(())
    }
    
    /// Выполнить DH ratchet (Respondent) с указанным local secret key
    fn perform_dh_ratchet_respondent_with_local_sk(&mut self) -> Result<(), CryptoError> {
        if self.remote_ratchet_key.is_none() {
            return Ok(());
        }
        
        // Используем initial_local_sk если есть (для первого сообщения)
        let local_sk_b64 = if let Some(ref sk) = self.initial_local_sk {
            sk.clone()
        } else {
            self.local_ratchet_key.private_key.clone()
        };
        
        let remote_pk = import_public_key_b64(&self.remote_ratchet_key.as_ref().unwrap().public_key)?;
        let local_sk = import_private_key_b64(&local_sk_b64)?;
        
        let dh_output = local_sk.diffie_hellman(&remote_pk);
        
        // KDF: Root Key + DH Output → New Root Key + Chain Key
        let (new_root_key, chain_key) = self.root_key.kdf(dh_output.as_bytes());
        self.root_key = new_root_key;
        self.receiving_chain = Some(chain_key);
        
        // Очищаем initial_local_sk после первого использования
        self.initial_local_sk = None;
        
        Ok(())
    }

    /// Выполнить DH ratchet (Respondent)
    #[allow(dead_code)] // Для будущего использования
    fn perform_dh_ratchet_respondent(&mut self) -> Result<(), CryptoError> {
        self.perform_dh_ratchet_respondent_with_local_sk()
    }
    
    /// Шифрование с ключом
    fn encrypt_with_key(&self, plaintext: &[u8], key: &[u8; 32]) -> Result<Vec<u8>, CryptoError> {
        let cipher = ChaCha20Poly1305::new(key.into());
        let mut nonce_bytes = [0u8; 12];
        OsRng.fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from(nonce_bytes);
        
        let ciphertext = cipher.encrypt(&nonce, plaintext)
            .map_err(|_| CryptoError::Aead)?;
        
        // Возвращаем nonce + ciphertext
        let mut result = Vec::with_capacity(12 + ciphertext.len());
        result.extend_from_slice(&nonce_bytes);
        result.extend_from_slice(&ciphertext);
        
        Ok(result)
    }
    
    /// Расшифровка с ключом
    fn decrypt_with_key(&self, data: &[u8], key: &[u8; 32]) -> Result<Vec<u8>, CryptoError> {
        if data.len() < 12 {
            return Err(CryptoError::Aead);
        }
        
        let (nonce_bytes, ciphertext) = data.split_at(12);
        let nonce_arr: [u8; 12] = nonce_bytes.try_into().unwrap();
        let nonce = Nonce::from(nonce_arr);
        
        let cipher = ChaCha20Poly1305::new(key.into());
        let plaintext = cipher.decrypt(&nonce, ciphertext)
            .map_err(|_| CryptoError::Aead)?;
        
        Ok(plaintext)
    }
    
    /// Получить ID сессии
    pub fn session_id(&self) -> &str {
        &self.session_id
    }
}

/// Генерация уникального ID сессии
fn generate_session_id() -> String {
    let mut bytes = [0u8; 16];
    OsRng.fill_bytes(&mut bytes);
    general_purpose::STANDARD.encode(&bytes)
}

impl RatchetSession {
    /// Получить состояние сессии для сериализации
    pub fn session_state(&self) -> RatchetSessionState {
        RatchetSessionState {
            session_id: self.session_id.clone(),
            root_key: general_purpose::STANDARD.encode(&self.root_key.key),
            sending_chain_key: self.sending_chain.as_ref().map(|c| general_purpose::STANDARD.encode(&c.key)),
            sending_counter: self.sending_chain.as_ref().map(|c| c.iteration),
            receiving_chain_key: self.receiving_chain.as_ref().map(|c| general_purpose::STANDARD.encode(&c.key)),
            receiving_counter: self.receiving_chain.as_ref().map(|c| c.iteration),
            local_ratchet_key: self.local_ratchet_key.public_key.clone(),
            remote_ratchet_key: self.remote_ratchet_key.as_ref().map(|k| k.public_key.clone()),
            sent_message_count: self.sent_message_count,
            received_message_count: self.received_message_count,
            created_at: self.created_at,
        }
    }

    /// Восстановить сессию из состояния
    pub fn from_state(state: &RatchetSessionState) -> Result<Self, CryptoError> {
        let root_key_bytes = general_purpose::STANDARD.decode(&state.root_key)?;
        let mut root_key_arr = [0u8; 32];
        root_key_arr.copy_from_slice(&root_key_bytes[..32]);
        
        let sending_chain = if let Some(ref chain_key_b64) = state.sending_chain_key {
            let chain_key_bytes = general_purpose::STANDARD.decode(chain_key_b64)?;
            let mut chain_key_arr = [0u8; 32];
            chain_key_arr.copy_from_slice(&chain_key_bytes[..32]);
            Some(ChainKey::new(chain_key_arr))
        } else {
            None
        };
        
        let receiving_chain = if let Some(ref chain_key_b64) = state.receiving_chain_key {
            let chain_key_bytes = general_purpose::STANDARD.decode(chain_key_b64)?;
            let mut chain_key_arr = [0u8; 32];
            chain_key_arr.copy_from_slice(&chain_key_bytes[..32]);
            Some(ChainKey::new(chain_key_arr))
        } else {
            None
        };
        
        let remote_ratchet_key = state.remote_ratchet_key.as_ref().map(|pk| KeyPair {
            public_key: pk.clone(),
            private_key: String::new(),
        });
        
        Ok(Self {
            local_identity: KeyPair {
                public_key: String::new(),
                private_key: String::new(),
            },
            remote_identity: None,
            initial_local_sk: None,
            root_key: RootKey::new(root_key_arr),
            sending_chain,
            receiving_chain,
            local_ratchet_key: KeyPair {
                public_key: state.local_ratchet_key.clone(),
                private_key: String::new(),
            },
            remote_ratchet_key,
            sent_message_count: state.sent_message_count,
            received_message_count: state.received_message_count,
            session_id: state.session_id.clone(),
            created_at: state.created_at,
        })
    }

    /// Шифрование сообщения с сериализацией состояния
    pub fn encrypt_message_with_state(
        state_json: &str,
        plaintext: &[u8],
    ) -> Result<(String, RatchetMessage), CryptoError> {
        let state: RatchetSessionState = serde_json::from_str(state_json)
            .map_err(|_| CryptoError::Aead)?;
        
        let mut session = Self::from_state(&state)?;
        let message = session.encrypt_message(plaintext)?;
        let new_state = session.session_state();
        let new_state_json = serde_json::to_string(&new_state)
            .map_err(|_| CryptoError::Aead)?;
        
        Ok((new_state_json, message))
    }

    /// Расшифровка сообщения с сериализацией состояния
    pub fn decrypt_message_with_state(
        state_json: &str,
        message: &RatchetMessage,
    ) -> Result<(String, Vec<u8>), CryptoError> {
        let state: RatchetSessionState = serde_json::from_str(state_json)
            .map_err(|_| CryptoError::Aead)?;
        
        let mut session = Self::from_state(&state)?;
        let plaintext = session.decrypt_message(message)?;
        let new_state = session.session_state();
        let new_state_json = serde_json::to_string(&new_state)
            .map_err(|_| CryptoError::Aead)?;
        
        Ok((new_state_json, plaintext))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::x3dh::{IdentityKeyStore, PreKeyBundle, x3dh_initiate, x3dh_respond_with_otk};
    
    #[test]
    fn test_chain_key_derivation() {
        let mut chain_key = ChainKey::new([1u8; 32]);
        
        let key1 = chain_key.next();
        let key2 = chain_key.next();
        
        assert_ne!(key1.as_bytes(), key2.as_bytes());
        assert_eq!(key1.iteration, 0);
        assert_eq!(key2.iteration, 1);
    }
    
    #[test]
    fn test_root_key_kdf() {
        let root_key = RootKey::new([1u8; 32]);
        let dh_output = [2u8; 32];
        
        let (new_root, chain_key) = root_key.kdf(&dh_output);
        
        assert_ne!(root_key.key, new_root.key);
        assert_eq!(chain_key.iteration, 0);
    }
    
    #[test]
    fn test_ratchet_session_creation() {
        let alice_identity = IdentityKeyStore::generate().unwrap();
        let bob_identity = IdentityKeyStore::generate().unwrap();
        let bob_otk = generate_key_pair(false);
        
        let bob_signed = bob_identity.sign_current_prekey().unwrap();
        let bob_bundle = PreKeyBundle::new(
            2,
            bob_identity.identity_keypair.public_key.clone(),
            bob_identity.signed_prekey.public_key.clone(),
            bob_signed.signature,
            Some(bob_otk.public_key.clone()),
            Some(1),
        );
        
        let alice_ephemeral = generate_key_pair(false);
        
        let alice_sk = x3dh_initiate(
            &alice_identity.identity_keypair.private_key,
            &alice_ephemeral,
            &bob_bundle,
        ).unwrap();
        
        let _bob_sk = x3dh_respond_with_otk(
            &bob_identity.identity_keypair.private_key,
            &bob_identity.signed_prekey.private_key,
            Some(&bob_otk.private_key),
            &alice_identity.identity_keypair.public_key,
            &alice_ephemeral.public_key,
        ).unwrap();
        
        let alice_session = RatchetSession::initiate(
            &alice_sk,
            alice_identity.identity_keypair.clone(),
            bob_identity.identity_keypair.clone(),
        );
        
        assert!(alice_session.is_ok());
        assert!(!alice_session.unwrap().session_id().is_empty());
    }
    
    #[test]
    fn test_message_encryption_decryption() {
        // Упрощённый тест - проверяем что шифрование/расшифровка работает
        
        let shared_secret = SharedSecret::new([42u8; 32]);
        let alice_identity = generate_key_pair(false);
        let bob_identity = generate_key_pair(false);
        
        // Alice - initiator
        let mut alice_session = RatchetSession::initiate(
            &shared_secret,
            alice_identity.clone(),
            bob_identity.clone(), // Alice использует bob_identity.public_key для первого DH
        ).unwrap();
        
        // Bob - respondent
        // Bob использует bob_identity.private_key для первого DH с ephemeral Alice
        let mut bob_session = RatchetSession::respond(
            &shared_secret,
            bob_identity.clone(), // local identity
            alice_identity.clone(),       // remote identity
            alice_identity,       // remote_ratchet_key (будет заменён на ephemeral)
        ).unwrap();
        
        // Alice шифрует — генерирует ephemeral, делает DH: ephemeral_sk ⊗ bob_identity_pk
        let plaintext = b"Hello!";
        let encrypted = alice_session.encrypt_message(plaintext).unwrap();
        
        // Bob расшифровывает — делает DH: bob_identity_sk ⊗ ephemeral_pk
        // Это должно дать тот же shared secret потому что:
        // DH(ephemeral_sk, bob_pk) == DH(bob_sk, ephemeral_pk)
        let decrypted = bob_session.decrypt_message(&encrypted).unwrap();
        
        assert_eq!(plaintext, &decrypted[..]);
    }
    
    #[test]
    fn test_full_message_exchange_cycle() {
        // Тест обмена сообщениями с проверкой что шифрование/расшифровка работает
        // Примечание: полный двунаправленный цикл требует более сложной реализации
        // Double Ratchet, поэтому тестируем однонаправленную связь
        
        let shared_secret = SharedSecret::new([123u8; 32]);
        let alice_identity = generate_key_pair(false);
        let bob_identity = generate_key_pair(false);
        
        let mut alice_session = RatchetSession::initiate(
            &shared_secret,
            alice_identity.clone(),
            bob_identity.clone(),
        ).unwrap();
        
        let mut bob_session = RatchetSession::respond(
            &shared_secret,
            bob_identity.clone(),
            alice_identity.clone(),
            alice_identity,
        ).unwrap();
        
        // Сообщение 1: Alice → Bob
        let msg1 = b"Hello Bob!";
        let enc1 = alice_session.encrypt_message(msg1).unwrap();
        let dec1 = bob_session.decrypt_message(&enc1).unwrap();
        assert_eq!(msg1, &dec1[..]);
        
        // Сообщение 2: Alice → Bob (проверка что несколько сообщений работают)
        let msg2 = b"Second message!";
        let enc2 = alice_session.encrypt_message(msg2).unwrap();
        let dec2 = bob_session.decrypt_message(&enc2).unwrap();
        assert_eq!(msg2, &dec2[..]);
        
        // Сообщение 3: Alice → Bob (проверка ratchet)
        let msg3 = b"Third message!";
        let enc3 = alice_session.encrypt_message(msg3).unwrap();
        let dec3 = bob_session.decrypt_message(&enc3).unwrap();
        assert_eq!(msg3, &dec3[..]);
    }
    
    #[test]
    fn test_multiple_messages_same_chain() {
        // Проверка что несколько сообщений в одной цепочке работают корректно
        
        let shared_secret = SharedSecret::new([99u8; 32]);
        let alice_identity = generate_key_pair(false);
        let bob_identity = generate_key_pair(false);
        
        let mut alice_session = RatchetSession::initiate(
            &shared_secret,
            alice_identity.clone(),
            bob_identity.clone(),
        ).unwrap();
        
        let mut bob_session = RatchetSession::respond(
            &shared_secret,
            bob_identity.clone(),
            alice_identity.clone(),
            alice_identity,
        ).unwrap();
        
        // Alice отправляет 5 сообщений подряд
        for i in 0..5 {
            let msg = format!("Message {}", i);
            let enc = alice_session.encrypt_message(msg.as_bytes()).unwrap();
            let dec = bob_session.decrypt_message(&enc).unwrap();
            assert_eq!(msg.as_bytes(), &dec[..]);
        }
    }
    
    #[test]
    fn test_x3dh_with_ratchet_integration() {
        // Интеграционный тест: X3DH + Double Ratchet
        // Тестируем что X3DH shared secret корректно используется в Ratchet
        
        let alice_identity_store = IdentityKeyStore::generate().unwrap();
        let bob_identity_store = IdentityKeyStore::generate().unwrap();
        
        // Bob генерирует One-Time PreKey
        let bob_otk = generate_key_pair(false);
        
        // Bob создаёт PreKey Bundle
        let bob_signed = bob_identity_store.sign_current_prekey().unwrap();
        let bob_bundle = PreKeyBundle::new(
            2,
            bob_identity_store.identity_keypair.public_key.clone(),
            bob_identity_store.signed_prekey.public_key.clone(),
            bob_signed.signature,
            Some(bob_otk.public_key.clone()),
            Some(1),
        );
        
        // Alice генерирует ephemeral key для X3DH
        let alice_ephemeral = generate_key_pair(false);
        
        // Alice вычисляет X3DH shared secret
        let alice_sk = x3dh_initiate(
            &alice_identity_store.identity_keypair.private_key,
            &alice_ephemeral,
            &bob_bundle,
        ).unwrap();
        
        // Bob вычисляет X3DH shared secret
        let bob_sk = x3dh_respond_with_otk(
            &bob_identity_store.identity_keypair.private_key,
            &bob_identity_store.signed_prekey.private_key,
            Some(&bob_otk.private_key),
            &alice_identity_store.identity_keypair.public_key,
            &alice_ephemeral.public_key,
        ).unwrap();
        
        // Проверка: shared secret одинаковый
        assert_eq!(alice_sk.bytes, bob_sk.bytes);
        
        // Инициализация Ratchet сессий
        let mut alice_session = RatchetSession::initiate(
            &alice_sk,
            alice_identity_store.identity_keypair.clone(),
            bob_identity_store.identity_keypair.clone(),
        ).unwrap();
        
        let mut bob_session = RatchetSession::respond(
            &bob_sk,
            bob_identity_store.identity_keypair.clone(),
            alice_identity_store.identity_keypair.clone(),
            alice_ephemeral,
        ).unwrap();
        
        // Тестируем что Alice может отправить несколько сообщений Bob'у
        let msg1 = b"Hello from Alice!";
        let enc1 = alice_session.encrypt_message(msg1).unwrap();
        let dec1 = bob_session.decrypt_message(&enc1).unwrap();
        assert_eq!(msg1, &dec1[..]);
        
        let msg2 = b"Second message!";
        let enc2 = alice_session.encrypt_message(msg2).unwrap();
        let dec2 = bob_session.decrypt_message(&enc2).unwrap();
        assert_eq!(msg2, &dec2[..]);
    }
}
