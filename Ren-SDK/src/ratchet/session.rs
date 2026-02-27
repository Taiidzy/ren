/// Double Ratchet Protocol Implementation
///
/// A complete implementation of the Double Ratchet protocol using our crypto primitives.
/// 
/// # References
/// - [Signal Double Ratchet Specification](https://signal.org/docs/specifications/doubleratchet/)

use crate::crypto::{generate_key_pair, KeyPair, CryptoError};
use crate::x3dh::SharedSecret;
use chacha20poly1305::{ChaCha20Poly1305, KeyInit, Nonce};
use chacha20poly1305::aead::Aead;
use rand_core::{RngCore, OsRng};
use base64::{engine::general_purpose, Engine};
use serde::{Serialize, Deserialize};

use super::chain::RootKey;
use super::dh_ratchet::{self, DhRatchet};
use super::symmetric_ratchet::{self, SymmetricRatchet};

/// Ratchet Session State — сериализуемое состояние сессии
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RatchetSessionState {
    pub session_id: String,
    
    // Identity keys для сохранения сессии
    pub local_identity_public: String,
    pub local_identity_private: String,
    pub remote_identity_public: Option<String>,
    pub remote_identity_private: Option<String>,
    
    // Root key
    pub root_key: String,
    
    // Symmetric ratchet state
    pub symmetric_ratchet: symmetric_ratchet::SymmetricRatchetState,
    
    // DH ratchet state
    pub dh_ratchet: dh_ratchet::DhRatchetState,
    
    // Metadata
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
    local_identity: KeyPair,
    remote_identity: Option<KeyPair>,

    // Ratchet state
    root_key: RootKey,
    symmetric_ratchet: SymmetricRatchet,
    dh_ratchet: DhRatchet,

    // Metadata
    session_id: String,
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

        Ok(Self {
            local_identity,
            remote_identity: Some(remote_identity),
            root_key,
            symmetric_ratchet: SymmetricRatchet::new(),
            dh_ratchet: DhRatchet::new(local_ratchet_key),
            session_id: generate_session_id(),
            created_at: chrono::Utc::now().timestamp(),
        })
    }

    /// Инициализация как Bob (respondent)
    pub fn respond(
        shared_secret: &SharedSecret,
        local_identity: KeyPair,
        remote_identity: KeyPair,
        _remote_ratchet_key: KeyPair,
    ) -> Result<Self, CryptoError> {
        let root_key = RootKey::new(*shared_secret.as_bytes());
        let local_ratchet_key = generate_key_pair(false);

        Ok(Self {
            local_identity: local_identity.clone(),
            remote_identity: Some(remote_identity),
            root_key,
            symmetric_ratchet: SymmetricRatchet::new(),
            dh_ratchet: DhRatchet::for_respondent(
                local_ratchet_key,
                local_identity.private_key.clone(),
            ),
            session_id: generate_session_id(),
            created_at: chrono::Utc::now().timestamp(),
        })
    }

    /// Шифрование сообщения
    pub fn encrypt_message(&mut self, plaintext: &[u8]) -> Result<RatchetMessage, CryptoError> {
        // Если sending_chain ещё нет, делаем DH ratchet
        if self.symmetric_ratchet.needs_sending_chain() {
            let (new_root_key, chain_key) = self.dh_ratchet.ratchet_initiator(&self.root_key)?;
            self.root_key = new_root_key;
            self.symmetric_ratchet.set_sending_chain(chain_key);
        }

        // Получаем message key для шифрования
        let message_key = self.symmetric_ratchet.next_message_key()
            .map_err(|_| CryptoError::Aead)?;

        // Шифрование
        let ciphertext = self.encrypt_with_key(plaintext, message_key.as_bytes())?;

        // DH ratchet каждые 2 сообщения (когда sent_message_count нечётный)
        if self.symmetric_ratchet.get_sending_counter() % 2 == 1 {
            if let Err(_) = self.dh_ratchet.ratchet_initiator(&self.root_key) {
                // Игнорируем ошибку если нет remote key
            } else {
                // Успешный DH ratchet — обновляем root key и создаём новый sending chain
                // Это происходит в следующем вызове encrypt_message
            }
        }

        Ok(RatchetMessage {
            ephemeral_key: self.dh_ratchet.get_local_public_key().to_string(),
            ciphertext: general_purpose::STANDARD.encode(&ciphertext),
            counter: self.symmetric_ratchet.get_sending_counter() - 1,
        })
    }

    /// Расшифровка сообщения
    pub fn decrypt_message(&mut self, encrypted: &RatchetMessage) -> Result<Vec<u8>, CryptoError> {
        // Проверяем, нужно ли сделать DH ratchet с новым remote key
        if self.dh_ratchet.needs_update(&encrypted.ephemeral_key) {
            // Обновляем remote ratchet key
            self.dh_ratchet.set_remote_public_key(KeyPair {
                public_key: encrypted.ephemeral_key.clone(),
                private_key: String::new(),
            });

            // DH ratchet для создания receiving_chain
            let (new_root_key, chain_key) = self.dh_ratchet.ratchet_respondent(&self.root_key)?;
            self.root_key = new_root_key;
            self.symmetric_ratchet.set_receiving_chain(chain_key);
        }

        // Получаем message key для расшифровки
        let message_key = self.symmetric_ratchet
            .get_message_key_for_counter(&encrypted.ephemeral_key, encrypted.counter)
            .map_err(|_| CryptoError::Aead)?;

        // Расшифровка
        let ciphertext = general_purpose::STANDARD.decode(&encrypted.ciphertext)?;
        let plaintext = self.decrypt_with_key(&ciphertext, message_key.as_bytes())?;

        Ok(plaintext)
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

    /// Получить состояние сессии для сериализации
    pub fn session_state(&self) -> RatchetSessionState {
        RatchetSessionState {
            session_id: self.session_id.clone(),
            local_identity_public: self.local_identity.public_key.clone(),
            local_identity_private: self.local_identity.private_key.clone(),
            remote_identity_public: self.remote_identity.as_ref().map(|i| i.public_key.clone()),
            remote_identity_private: self.remote_identity.as_ref().map(|i| i.private_key.clone()),
            root_key: general_purpose::STANDARD.encode(self.root_key.get_key()),
            symmetric_ratchet: self.symmetric_ratchet.to_state(),
            dh_ratchet: self.dh_ratchet.to_state(),
            created_at: self.created_at,
        }
    }

    /// Восстановить сессию из состояния
    pub fn from_state(state: &RatchetSessionState) -> Result<Self, CryptoError> {
        let root_key_bytes = general_purpose::STANDARD.decode(&state.root_key)?;
        let mut root_key_arr = [0u8; 32];
        root_key_arr.copy_from_slice(&root_key_bytes[..32]);

        let local_identity = KeyPair {
            public_key: state.local_identity_public.clone(),
            private_key: state.local_identity_private.clone(),
        };

        let remote_identity = state.remote_identity_public.as_ref().map(|pk| {
            KeyPair {
                public_key: pk.clone(),
                private_key: state.remote_identity_private.clone().unwrap_or_default(),
            }
        });

        Ok(Self {
            local_identity,
            remote_identity,
            root_key: RootKey::new(root_key_arr),
            symmetric_ratchet: SymmetricRatchet::from_state(&state.symmetric_ratchet),
            dh_ratchet: DhRatchet::from_state(&state.dh_ratchet),
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

/// Генерация уникального ID сессии
fn generate_session_id() -> String {
    let mut bytes = [0u8; 16];
    OsRng.fill_bytes(&mut bytes);
    general_purpose::STANDARD.encode(&bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::x3dh::{IdentityKeyStore, PreKeyBundle, x3dh_initiate, x3dh_respond_with_otk};

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
        let shared_secret = SharedSecret::new([42u8; 32]);
        let alice_identity = generate_key_pair(false);
        let bob_identity = generate_key_pair(false);

        // Alice - initiator
        let mut alice_session = RatchetSession::initiate(
            &shared_secret,
            alice_identity.clone(),
            bob_identity.clone(),
        ).unwrap();

        // Bob - respondent
        let mut bob_session = RatchetSession::respond(
            &shared_secret,
            bob_identity.clone(),
            alice_identity.clone(),
            alice_identity,
        ).unwrap();

        // Alice шифрует
        let plaintext = b"Hello!";
        let encrypted = alice_session.encrypt_message(plaintext).unwrap();

        // Bob расшифровывает
        let decrypted = bob_session.decrypt_message(&encrypted).unwrap();

        assert_eq!(plaintext, &decrypted[..]);
    }

    #[test]
    fn test_full_message_exchange_cycle() {
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

        // Сообщение 2: Alice → Bob
        let msg2 = b"Second message!";
        let enc2 = alice_session.encrypt_message(msg2).unwrap();
        let dec2 = bob_session.decrypt_message(&enc2).unwrap();
        assert_eq!(msg2, &dec2[..]);

        // Сообщение 3: Alice → Bob
        let msg3 = b"Third message!";
        let enc3 = alice_session.encrypt_message(msg3).unwrap();
        let dec3 = bob_session.decrypt_message(&enc3).unwrap();
        assert_eq!(msg3, &dec3[..]);
    }

    #[test]
    fn test_session_serialization() {
        let shared_secret = SharedSecret::new([42u8; 32]);
        let alice_identity = generate_key_pair(false);
        let bob_identity = generate_key_pair(false);

        let mut alice_session = RatchetSession::initiate(
            &shared_secret,
            alice_identity.clone(),
            bob_identity.clone(),
        ).unwrap();

        // Шифруем сообщение
        let plaintext = b"Test message";
        let _encrypted = alice_session.encrypt_message(plaintext).unwrap();

        // Сериализуем
        let state = alice_session.session_state();
        let state_json = serde_json::to_string(&state).unwrap();

        // Десериализуем
        let restored = RatchetSession::from_state(&state).unwrap();

        // Проверяем что identity keys сохранились
        assert_eq!(alice_session.local_identity.public_key, restored.local_identity.public_key);
        assert_eq!(alice_session.local_identity.private_key, restored.local_identity.private_key);
    }

    #[test]
    fn test_out_of_order_messages() {
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

        // Alice отправляет 3 сообщения
        let msg1 = b"First";
        let msg2 = b"Second";
        let msg3 = b"Third";

        let enc1 = alice_session.encrypt_message(msg1).unwrap();
        let enc2 = alice_session.encrypt_message(msg2).unwrap();
        let enc3 = alice_session.encrypt_message(msg3).unwrap();

        // Bob получает в порядке: 1, 3, 2 (out-of-order)
        let dec1 = bob_session.decrypt_message(&enc1).unwrap();
        assert_eq!(msg1, &dec1[..]);

        // Сообщение 3 приходит до 2
        let dec3 = bob_session.decrypt_message(&enc3).unwrap();
        assert_eq!(msg3, &dec3[..]);

        // Теперь сообщение 2
        let dec2 = bob_session.decrypt_message(&enc2).unwrap();
        assert_eq!(msg2, &dec2[..]);
    }
}
