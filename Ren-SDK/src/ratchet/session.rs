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
        // Если sending_chain ещё нет, делаем первый DH ratchet
        if self.sending_chain.is_none() {
            // Для первого сообщения Alice генерирует новый ephemeral key
            // и использует remote_identity как remote key
            if let Some(ref remote_id) = self.remote_identity {
                // Генерируем новый ephemeral key для этой сессии
                let ephemeral = generate_key_pair(false);
                
                // DH: ephemeral_sk ⊗ remote_pk
                let remote_pk = import_public_key_b64(&remote_id.public_key)?;
                let eph_sk = import_private_key_b64(&ephemeral.private_key)?;
                let dh_output = eph_sk.diffie_hellman(&remote_pk);
                
                // KDF: Root Key + DH Output → New Root Key + Chain Key
                let (new_root_key, chain_key) = self.root_key.kdf(dh_output.as_bytes());
                self.root_key = new_root_key;
                self.sending_chain = Some(chain_key);
                
                // Сохраняем ephemeral как текущий ratchet key
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
            ciphertext: base64::encode(&ciphertext),
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
        let ciphertext = base64::decode(&encrypted.ciphertext)?;
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
    base64::encode(&bytes)
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
        
        let bob_sk = x3dh_respond_with_otk(
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
}
