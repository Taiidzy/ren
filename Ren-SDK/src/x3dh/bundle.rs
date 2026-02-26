/// PreKey Bundle for X3DH Key Agreement
/// 
/// A bundle of public keys used to initiate an X3DH key exchange.
/// Contains identity key, signed prekey, and optionally a one-time prekey.

use serde::{Serialize, Deserialize};
use crate::CryptoError;

/// PreKey Bundle для X3DH инициализации
/// 
/// # Fields
/// * `user_id` - ID пользователя, владельца этого bundle
/// * `identity_key` - Публичный Identity Key (X25519, Base64, 32 байта)
/// * `signed_prekey` - Публичный Signed PreKey (X25519, Base64, 32 байта)
/// * `signed_prekey_signature` - Подпись Signed PreKey (Ed25519, Base64, 64 байта)
/// * `one_time_prekey` - Одноразовый PreKey (опционально, X25519, Base64, 32 байта)
/// * `one_time_prekey_id` - ID одноразового PreKey (для удаления после использования)
/// 
/// # Example
/// ```
/// let bundle = PreKeyBundle {
///     user_id: 123,
///     identity_key: "base64...".to_string(),
///     signed_prekey: "base64...".to_string(),
///     signed_prekey_signature: "base64...".to_string(),
///     one_time_prekey: Some("base64...".to_string()),
///     one_time_prekey_id: Some(42),
/// };
/// ```
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct PreKeyBundle {
    /// ID пользователя
    pub user_id: i32,
    
    /// Публичный Identity Key (X25519, Base64)
    pub identity_key: String,
    
    /// Публичный Signed PreKey (X25519, Base64)
    pub signed_prekey: String,
    
    /// Подпись Signed PreKey (Ed25519, Base64)
    pub signed_prekey_signature: String,
    
    /// Одноразовый PreKey (опционально)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub one_time_prekey: Option<String>,
    
    /// ID одноразового PreKey
    #[serde(skip_serializing_if = "Option::is_none")]
    pub one_time_prekey_id: Option<u32>,
}

impl PreKeyBundle {
    /// Создать новый PreKey Bundle
    /// 
    /// # Arguments
    /// * `user_id` - ID пользователя
    /// * `identity_key` - Публичный Identity Key
    /// * `signed_prekey` - Публичный Signed PreKey
    /// * `signed_prekey_signature` - Подпись Signed PreKey
    /// * `one_time_prekey` - Одноразовый PreKey (опционально)
    /// * `one_time_prekey_id` - ID одноразового PreKey
    pub fn new(
        user_id: i32,
        identity_key: String,
        signed_prekey: String,
        signed_prekey_signature: String,
        one_time_prekey: Option<String>,
        one_time_prekey_id: Option<u32>,
    ) -> Self {
        Self {
            user_id,
            identity_key,
            signed_prekey,
            signed_prekey_signature,
            one_time_prekey,
            one_time_prekey_id,
        }
    }
    
    /// Создать PreKey Bundle без One-Time PreKey
    /// 
    /// # Arguments
    /// * `user_id` - ID пользователя
    /// * `identity_key` - Публичный Identity Key
    /// * `signed_prekey` - Публичный Signed PreKey
    /// * `signed_prekey_signature` - Подпись Signed PreKey
    pub fn without_one_time_prekey(
        user_id: i32,
        identity_key: String,
        signed_prekey: String,
        signed_prekey_signature: String,
    ) -> Self {
        Self {
            user_id,
            identity_key,
            signed_prekey,
            signed_prekey_signature,
            one_time_prekey: None,
            one_time_prekey_id: None,
        }
    }
    
    /// Проверить наличие One-Time PreKey
    pub fn has_one_time_prekey(&self) -> bool {
        self.one_time_prekey.is_some()
    }
    
    /// Проверить, что bundle содержит все необходимые ключи
    /// 
    /// # Returns
    /// * `true` - все обязательные поля заполнены
    /// * `false` - отсутствуют обязательные поля
    pub fn is_valid(&self) -> bool {
        !self.identity_key.is_empty() 
            && !self.signed_prekey.is_empty() 
            && !self.signed_prekey_signature.is_empty()
    }
}

/// One-Time PreKey для загрузки на сервер
/// 
/// # Fields
/// * `prekey_id` - Уникальный ID PreKey
/// * `prekey` - Публичный PreKey (Base64, 32 байта)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct OneTimePreKey {
    /// Уникальный ID PreKey
    pub prekey_id: u32,
    
    /// Публичный PreKey (Base64)
    pub prekey: String,
}

impl OneTimePreKey {
    /// Создать новый One-Time PreKey
    pub fn new(prekey_id: u32, prekey: String) -> Self {
        Self { prekey_id, prekey }
    }
    
    /// Сгенерировать новый One-Time PreKey
    /// 
    /// # Arguments
    /// * `prekey_id` - Уникальный ID
    /// 
    /// # Returns
    /// * `Ok(OneTimePreKey)` - новый PreKey
    /// * `Err(CryptoError)` - ошибка генерации
    pub fn generate(prekey_id: u32) -> Result<Self, CryptoError> {
        use crate::crypto::generate_key_pair;
        
        let keypair = generate_key_pair(false);
        Ok(Self {
            prekey_id,
            prekey: keypair.public_key,
        })
    }
}

/// Запрос на загрузку One-Time PreKeys на сервер
/// 
/// # Fields
/// * `prekeys` - Список One-Time PreKeys для загрузки
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct UploadPreKeysRequest {
    /// Список One-Time PreKeys
    pub prekeys: Vec<OneTimePreKey>,
}

impl UploadPreKeysRequest {
    /// Создать новый запрос на загрузку
    pub fn new(prekeys: Vec<OneTimePreKey>) -> Self {
        Self { prekeys }
    }
}

/// Ответ сервера с PreKey Bundle
/// 
/// # Fields
/// * `bundle` - PreKey Bundle
/// * `signed_prekey_signature_valid` - Флаг валидности подписи
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct PreKeyBundleResponse {
    /// PreKey Bundle
    pub bundle: PreKeyBundle,
    
    /// Флаг валидности подписи (если сервер проверял)
    #[serde(default = "default_true")]
    pub signed_prekey_signature_valid: bool,
}

fn default_true() -> bool {
    true
}

impl PreKeyBundleResponse {
    /// Создать новый ответ
    pub fn new(bundle: PreKeyBundle) -> Self {
        Self {
            bundle,
            signed_prekey_signature_valid: true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_prekey_bundle_creation() {
        let bundle = PreKeyBundle::new(
            123,
            "identity_key".to_string(),
            "signed_prekey".to_string(),
            "signature".to_string(),
            Some("one_time_prekey".to_string()),
            Some(42),
        );
        
        assert_eq!(bundle.user_id, 123);
        assert_eq!(bundle.identity_key, "identity_key");
        assert_eq!(bundle.signed_prekey, "signed_prekey");
        assert_eq!(bundle.signed_prekey_signature, "signature");
        assert!(bundle.has_one_time_prekey());
        assert!(bundle.is_valid());
    }
    
    #[test]
    fn test_prekey_bundle_without_otk() {
        let bundle = PreKeyBundle::without_one_time_prekey(
            123,
            "identity_key".to_string(),
            "signed_prekey".to_string(),
            "signature".to_string(),
        );
        
        assert!(!bundle.has_one_time_prekey());
        assert!(bundle.is_valid());
    }
    
    #[test]
    fn test_prekey_bundle_invalid() {
        let bundle = PreKeyBundle::new(
            123,
            "".to_string(), // Пустой identity key
            "signed_prekey".to_string(),
            "signature".to_string(),
            None,
            None,
        );
        
        assert!(!bundle.is_valid());
    }
    
    #[test]
    fn test_one_time_prekey_generation() {
        let otk = OneTimePreKey::generate(1).unwrap();
        
        assert_eq!(otk.prekey_id, 1);
        assert!(!otk.prekey.is_empty());
        // Base64 encoded 32 bytes = 44 characters
        assert_eq!(otk.prekey.len(), 44);
    }
}
