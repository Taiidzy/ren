/// DH Ratchet for Double Ratchet Protocol
///
/// This module handles the Diffie-Hellman ratchet step that provides
/// Post-Compromise Security by periodically updating the ratchet keys.

use crate::crypto::{generate_key_pair, import_private_key_b64, import_public_key_b64, KeyPair, CryptoError};
use super::chain::{RootKey, ChainKey};

/// DH Ratchet State
#[derive(Debug, Clone)]
pub struct DhRatchet {
    /// Local DH key pair (ratchet key)
    pub local_key: KeyPair,
    /// Remote DH public key
    pub remote_public_key: Option<KeyPair>,
    /// Initial local secret key (для первого DH respondent)
    pub initial_local_sk: Option<String>,
}

impl DhRatchet {
    pub fn new(local_key: KeyPair) -> Self {
        Self {
            local_key,
            remote_public_key: None,
            initial_local_sk: None,
        }
    }

    pub fn for_respondent(local_key: KeyPair, initial_local_sk: String) -> Self {
        Self {
            local_key,
            remote_public_key: None,
            initial_local_sk: Some(initial_local_sk),
        }
    }

    /// Получить локальный публичный ключ для отправки
    pub fn get_local_public_key(&self) -> &str {
        &self.local_key.public_key
    }

    /// Установить remote public key
    pub fn set_remote_public_key(&mut self, remote_pk: KeyPair) {
        self.remote_public_key = Some(remote_pk);
    }

    /// Выполнить DH ratchet шаг (Initiator — Alice)
    /// 
    /// Генерирует новый local key pair и вычисляет DH с remote public key
    pub fn ratchet_initiator(&mut self, root_key: &RootKey) -> Result<(RootKey, ChainKey), CryptoError> {
        if self.remote_public_key.is_none() {
            return Err(CryptoError::Aead);
        }

        let remote_pk = import_public_key_b64(&self.remote_public_key.as_ref().unwrap().public_key)?;
        let local_sk = import_private_key_b64(&self.local_key.private_key)?;

        let dh_output = local_sk.diffie_hellman(&remote_pk);

        // KDF: Root Key + DH Output → New Root Key + Chain Key
        let (new_root_key, chain_key) = root_key.kdf(dh_output.as_bytes());

        // Генерируем новый local ratchet key для следующего сообщения
        self.local_key = generate_key_pair(false);

        Ok((new_root_key, chain_key))
    }

    /// Выполнить DH ratchet шаг (Respondent — Bob)
    /// 
    /// Использует initial_local_sk для первого сообщения или текущий local key
    pub fn ratchet_respondent(&mut self, root_key: &RootKey) -> Result<(RootKey, ChainKey), CryptoError> {
        if self.remote_public_key.is_none() {
            return Err(CryptoError::Aead);
        }

        // Используем initial_local_sk если есть (для первого сообщения)
        let local_sk_b64 = if let Some(ref sk) = self.initial_local_sk {
            sk.clone()
        } else {
            self.local_key.private_key.clone()
        };

        let remote_pk = import_public_key_b64(&self.remote_public_key.as_ref().unwrap().public_key)?;
        let local_sk = import_private_key_b64(&local_sk_b64)?;

        let dh_output = local_sk.diffie_hellman(&remote_pk);

        // KDF: Root Key + DH Output → New Root Key + Chain Key
        let (new_root_key, chain_key) = root_key.kdf(dh_output.as_bytes());

        // Очищаем initial_local_sk после первого использования
        self.initial_local_sk = None;

        // Генерируем новый local ratchet key для следующего сообщения
        self.local_key = generate_key_pair(false);

        Ok((new_root_key, chain_key))
    }

    /// Проверить, нужно ли обновить remote ratchet key
    pub fn needs_update(&self, new_ephemeral_key: &str) -> bool {
        match &self.remote_public_key {
            None => true,
            Some(remote_pk) => remote_pk.public_key != new_ephemeral_key,
        }
    }

    /// Сериализация состояния для хранения
    pub fn to_state(&self) -> DhRatchetState {
        DhRatchetState {
            local_public_key: self.local_key.public_key.clone(),
            local_private_key: self.local_key.private_key.clone(),
            remote_public_key: self.remote_public_key.as_ref().map(|k| k.public_key.clone()),
            initial_local_sk: self.initial_local_sk.clone(),
        }
    }

    /// Десериализация состояния
    pub fn from_state(state: &DhRatchetState) -> Self {
        Self {
            local_key: KeyPair {
                public_key: state.local_public_key.clone(),
                private_key: state.local_private_key.clone(),
            },
            remote_public_key: state.remote_public_key.as_ref().map(|pk| KeyPair {
                public_key: pk.clone(),
                private_key: String::new(),
            }),
            initial_local_sk: state.initial_local_sk.clone(),
        }
    }
}

/// Сериализуемое состояние DH Ratchet
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DhRatchetState {
    pub local_public_key: String,
    pub local_private_key: String,
    pub remote_public_key: Option<String>,
    pub initial_local_sk: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::x3dh::SharedSecret;

    #[test]
    fn test_dh_ratchet_initiator() {
        let shared_secret = SharedSecret::new([42u8; 32]);
        let root_key = RootKey::new(*shared_secret.as_bytes());
        
        let local_key = generate_key_pair(false);
        let remote_key = generate_key_pair(false);
        
        let mut ratchet = DhRatchet::new(local_key);
        ratchet.set_remote_public_key(remote_key);
        
        let (new_root, chain_key) = ratchet.ratchet_initiator(&root_key).unwrap();
        
        // Root key должен измениться
        assert_ne!(root_key.get_key(), new_root.get_key());
        // Chain key должен быть создан
        assert_eq!(chain_key.iteration, 0);
    }

    #[test]
    fn test_dh_ratchet_respondent() {
        let shared_secret = SharedSecret::new([42u8; 32]);
        let root_key = RootKey::new(*shared_secret.as_bytes());
        
        let local_key = generate_key_pair(false);
        let remote_key = generate_key_pair(false);
        
        let mut ratchet = DhRatchet::for_respondent(local_key, remote_key.private_key.clone());
        ratchet.set_remote_public_key(remote_key);
        
        let (new_root, chain_key) = ratchet.ratchet_respondent(&root_key).unwrap();
        
        // Root key должен измениться
        assert_ne!(root_key.get_key(), new_root.get_key());
        // Chain key должен быть создан
        assert_eq!(chain_key.iteration, 0);
        // initial_local_sk должен очиститься
        assert!(ratchet.initial_local_sk.is_none());
    }
}
