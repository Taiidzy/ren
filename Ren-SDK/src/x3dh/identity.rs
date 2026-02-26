/// Identity Key Store for X3DH Protocol
/// 
/// Stores and manages:
/// - Identity Key Pair (X25519) - long-term identity key
/// - Identity Signature Key Pair (Ed25519) - for signing prekeys
/// - Signed PreKey (X25519) - medium-term prekey signed by identity key

use crate::crypto::{
    generate_key_pair, 
    generate_identity_key_pair, 
    sign_public_key,
    KeyPair, 
    IdentityKeyPair,
    SignedPublicKey,
    CryptoError,
};

/// Identity Key Store — хранит Identity Key Pair и подписанный PreKey
#[derive(Debug, Clone)]
pub struct IdentityKeyStore {
    /// X25519 Identity Key Pair (долгосрочный ключ)
    pub identity_keypair: KeyPair,
    
    /// Ed25519 Identity Signature Key Pair (для подписи PreKey)
    pub identity_signature_key: IdentityKeyPair,
    
    /// X25519 Signed PreKey (среднесрочный ключ)
    pub signed_prekey: KeyPair,
    
    /// Версия ключа для поддержки ротации
    pub key_version: u32,
}

impl IdentityKeyStore {
    /// Генерация нового Identity Key Store
    /// 
    /// # Returns
    /// * `Ok(IdentityKeyStore)` - новый экземпляр
    /// * `Err(CryptoError)` - ошибка генерации ключей
    /// 
    /// # Example
    /// ```
    /// let identity_store = IdentityKeyStore::generate()?;
    /// ```
    pub fn generate() -> Result<Self, CryptoError> {
        let identity_keypair = generate_key_pair(false);
        let identity_signature_key = generate_identity_key_pair()?;
        let signed_prekey = generate_key_pair(false);
        
        Ok(Self {
            identity_keypair,
            identity_signature_key,
            signed_prekey,
            key_version: 1,
        })
    }
    
    /// Загрузка из существующих ключей
    /// 
    /// # Arguments
    /// * `identity_keypair` - X25519 Identity Key Pair
    /// * `identity_signature_key` - Ed25519 Identity Signature Key Pair
    /// * `signed_prekey` - X25519 Signed PreKey
    /// * `key_version` - Версия ключа
    pub fn from_keys(
        identity_keypair: KeyPair,
        identity_signature_key: IdentityKeyPair,
        signed_prekey: KeyPair,
        key_version: u32,
    ) -> Self {
        Self {
            identity_keypair,
            identity_signature_key,
            signed_prekey,
            key_version,
        }
    }
    
    /// Получить публичный Identity Key
    pub fn get_public_identity(&self) -> &str {
        &self.identity_keypair.public_key
    }
    
    /// Получить публичный ключ подписи (Ed25519)
    pub fn get_public_signature_key(&self) -> &str {
        &self.identity_signature_key.public_key
    }
    
    /// Подписать PreKey
    /// 
    /// # Arguments
    /// * `prekey` - Публичный PreKey для подписи (Base64)
    /// * `key_version` - Версия ключа
    /// 
    /// # Returns
    /// * `Ok(SignedPublicKey)` - подписанный ключ с метаданными
    /// * `Err(CryptoError)` - ошибка подписи
    pub fn sign_prekey(&self, prekey: &str, key_version: u32) -> Result<SignedPublicKey, CryptoError> {
        sign_public_key(prekey, &self.identity_signature_key.private_key, key_version)
    }
    
    /// Подписать текущий Signed PreKey
    /// 
    /// # Returns
    /// * `Ok(SignedPublicKey)` - подписанный PreKey
    /// * `Err(CryptoError)` - ошибка подписи
    pub fn sign_current_prekey(&self) -> Result<SignedPublicKey, CryptoError> {
        self.sign_prekey(&self.signed_prekey.public_key, self.key_version)
    }
    
    /// Сгенерировать новый Signed PreKey
    /// 
    /// # Returns
    /// * `Ok(KeyPair)` - новый Signed PreKey
    pub fn rotate_signed_prekey(&mut self) -> Result<KeyPair, CryptoError> {
        self.signed_prekey = generate_key_pair(false);
        self.key_version += 1;
        Ok(self.signed_prekey.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_generate_identity_key_store() {
        let identity = IdentityKeyStore::generate();
        assert!(identity.is_ok());
        
        let identity = identity.unwrap();
        assert!(!identity.identity_keypair.public_key.is_empty());
        assert!(!identity.identity_keypair.private_key.is_empty());
        assert!(!identity.identity_signature_key.public_key.is_empty());
        assert!(!identity.identity_signature_key.private_key.is_empty());
        assert!(!identity.signed_prekey.public_key.is_empty());
        assert_eq!(identity.key_version, 1);
    }
    
    #[test]
    fn test_sign_prekey() {
        let identity = IdentityKeyStore::generate().unwrap();
        let signed = identity.sign_current_prekey();
        assert!(signed.is_ok());
        
        let signed = signed.unwrap();
        assert_eq!(signed.public_key, identity.signed_prekey.public_key);
        assert_eq!(signed.key_version, identity.key_version);
        assert!(!signed.signature.is_empty());
    }
    
    #[test]
    fn test_rotate_signed_prekey() {
        let mut identity = IdentityKeyStore::generate().unwrap();
        let old_prekey = identity.signed_prekey.public_key.clone();
        let old_version = identity.key_version;
        
        let result = identity.rotate_signed_prekey();
        assert!(result.is_ok());
        
        assert_ne!(identity.signed_prekey.public_key, old_prekey);
        assert_eq!(identity.key_version, old_version + 1);
    }
}
