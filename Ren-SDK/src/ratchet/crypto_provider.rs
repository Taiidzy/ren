/// Crypto Provider utilities для Double Ratchet
/// 
/// Вспомогательные функции для криптографических операций

use crate::crypto::{generate_key_pair, KeyPair};

/// Генерация новой пары ключей для DH ratchet
pub fn generate_dh_keypair() -> KeyPair {
    generate_key_pair(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_generate_dh_keypair() {
        let keypair = generate_dh_keypair();
        assert!(!keypair.public_key.is_empty());
        assert!(!keypair.private_key.is_empty());
    }
}
