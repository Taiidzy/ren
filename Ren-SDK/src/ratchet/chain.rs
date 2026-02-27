/// Chain Key Management for Double Ratchet
///
/// This module handles the symmetric ratchet chain key derivation.
/// Chain keys produce message keys through HMAC-SHA256 iterations.

use hmac::{Hmac, Mac};
use sha2::Sha256;
use serde::{Serialize, Deserialize};

type HmacSha256 = Hmac<Sha256>;

/// Message Key — используется для шифрования одного сообщения
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageKey {
    key: [u8; 32],
    pub iteration: u32,
}

impl MessageKey {
    pub fn new(key: [u8; 32], iteration: u32) -> Self {
        Self { key, iteration }
    }

    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.key
    }
}

/// Chain Key — производит Message Keys через HMAC-SHA256
/// 
/// ChainKey → MessageKey + NewChainKey
#[derive(Debug, Clone)]
pub struct ChainKey {
    key: [u8; 32],
    pub iteration: u32,
}

impl ChainKey {
    pub fn new(key: [u8; 32]) -> Self {
        Self { key, iteration: 0 }
    }

    pub fn from_state(key: [u8; 32], iteration: u32) -> Self {
        Self { key, iteration }
    }

    /// Следующий Message Key
    /// ChainKey → MessageKey + NewChainKey
    pub fn next(&mut self) -> MessageKey {
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

    /// Skip ahead to a specific iteration (для out-of-order сообщений)
    /// Возвращает временный ChainKey для получения message key
    pub fn skip_to(&self, target_iteration: u32) -> ChainKey {
        let mut skipped = self.clone();
        while skipped.iteration < target_iteration {
            skipped.next();
        }
        skipped
    }

    pub fn get_key(&self) -> &[u8; 32] {
        &self.key
    }
}

/// Root Key Chain
/// 
/// Root Key + DH Output → New Root Key + Chain Key
#[derive(Debug, Clone)]
pub struct RootKey {
    key: [u8; 32],
}

impl RootKey {
    pub fn new(key: [u8; 32]) -> Self {
        Self { key }
    }

    /// KDF: Root Key + DH Output → New Root Key + Chain Key
    pub fn kdf(&self, dh_output: &[u8]) -> (RootKey, ChainKey) {
        use hkdf::Hkdf;
        use sha2::Sha256;

        let hkdf = Hkdf::<Sha256>::new(None, &self.key);
        let mut okm = [0u8; 64];
        hkdf.expand(dh_output, &mut okm).expect("HKDF expand failed");

        let new_root_key = RootKey::new(okm[..32].try_into().unwrap());
        let chain_key = ChainKey::new(okm[32..].try_into().unwrap());

        (new_root_key, chain_key)
    }

    pub fn get_key(&self) -> &[u8; 32] {
        &self.key
    }
}

/// Skipped Message Key — хранится для расшифровки out-of-order сообщений
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkippedMessageKey {
    pub ephemeral_key: String,
    pub counter: u32,
    pub key: [u8; 32],
}

impl SkippedMessageKey {
    pub fn new(ephemeral_key: String, counter: u32, key: [u8; 32]) -> Self {
        Self { ephemeral_key, counter, key }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn test_chain_key_skip() {
        let chain_key = ChainKey::new([1u8; 32]);
        
        // Skip to iteration 5
        let skipped = chain_key.skip_to(5);
        assert_eq!(skipped.iteration, 5);
        
        // Original chain key unchanged
        assert_eq!(chain_key.iteration, 0);
    }
}
