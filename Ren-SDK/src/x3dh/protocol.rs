/// X3DH Protocol Implementation
/// 
/// Implements the Extended Triple Diffie-Hellman key agreement protocol
/// as specified by Signal.
/// 
/// # References
/// - [Signal X3DH Specification](https://signal.org/docs/specifications/x3dh/)

use crate::crypto::{
    import_private_key_b64,
    import_public_key_b64,
    CryptoError,
};
use crate::x3dh::bundle::PreKeyBundle;
use hkdf::Hkdf;
use sha2::Sha256;

/// Общий секрет, вычисленный через X3DH
/// 
/// # Fields
/// * `bytes` - 32 байта общего секрета
#[derive(Debug, Clone)]
pub struct SharedSecret {
    pub bytes: [u8; 32],
}

impl SharedSecret {
    /// Создать новый SharedSecret из байтов
    pub fn new(bytes: [u8; 32]) -> Self {
        Self { bytes }
    }
    
    /// Получить байты секрета
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.bytes
    }
    
    /// Преобразовать в вектор байтов
    pub fn to_vec(&self) -> Vec<u8> {
        self.bytes.to_vec()
    }
}

/// X3DH Initiate — Alice вычисляет общий секрет
/// 
/// # Arguments
/// * `my_identity_sk` - Приватный Identity Key Alice (Base64)
/// * `my_ephemeral` - Эфемерный ключpair Alice для этой сессии
/// * `their_bundle` - PreKey Bundle Bob
/// 
/// # Returns
/// * `Ok(SharedSecret)` - общий секрет
/// * `Err(CryptoError)` - ошибка вычисления
/// 
/// # Formula
/// ```text
/// SK = KDF(
///   ECDH(IK_A, SPK_B) ||
///   ECDH(EK_A, IK_B) ||
///   ECDH(EK_A, SPK_B) ||
///   ECDH(EK_A, OPK_B)  // если есть
/// )
/// ```
/// 
/// # Example
/// ```
/// let alice_identity = IdentityKeyStore::generate()?;
/// let bob_bundle = get_bob_bundle_from_server()?;
/// let alice_ephemeral = generate_key_pair(false);
/// 
/// let shared_secret = x3dh_initiate(
///     &alice_identity.identity_keypair.private_key,
///     &alice_ephemeral,
///     &bob_bundle,
/// )?;
/// ```
pub fn x3dh_initiate(
    my_identity_sk: &str,
    my_ephemeral: &crate::crypto::KeyPair,
    their_bundle: &PreKeyBundle,
) -> Result<SharedSecret, CryptoError> {
    // 1. ECDH(IK_A, SPK_B) - Identity Key Alice → Signed PreKey Bob
    let ik_a = import_private_key_b64(my_identity_sk)?;
    let spk_b = import_public_key_b64(&their_bundle.signed_prekey)?;
    let dh1 = ik_a.diffie_hellman(&spk_b);
    
    // 2. ECDH(EK_A, IK_B) - Ephemeral Alice → Identity Key Bob
    let ek_a_sk = import_private_key_b64(&my_ephemeral.private_key)?;
    let ik_b = import_public_key_b64(&their_bundle.identity_key)?;
    let dh2 = ek_a_sk.diffie_hellman(&ik_b);
    
    // 3. ECDH(EK_A, SPK_B) - Ephemeral Alice → Signed PreKey Bob
    let dh3 = ek_a_sk.diffie_hellman(&spk_b);
    
    // Собираем все DH выходы
    let mut dh_output = dh1.as_bytes().to_vec();
    dh_output.extend_from_slice(dh2.as_bytes());
    dh_output.extend_from_slice(dh3.as_bytes());
    
    // 4. ECDH(EK_A, OPK_B) - если есть One-Time PreKey
    if let Some(opk) = &their_bundle.one_time_prekey {
        let opk_b = import_public_key_b64(opk)?;
        let dh4 = ek_a_sk.diffie_hellman(&opk_b);
        dh_output.extend_from_slice(dh4.as_bytes());
    }
    
    // KDF: HKDF-SHA256
    let hkdf = Hkdf::<Sha256>::new(None, &dh_output);
    let mut okm = [0u8; 32];
    hkdf.expand(b"X3DH", &mut okm)
        .map_err(|_| CryptoError::Aead)?;
    
    Ok(SharedSecret { bytes: okm })
}

/// X3DH Respond — Bob вычисляет общий секрет
/// 
/// # Arguments
/// * `my_identity_sk` - Приватный Identity Key Bob (Base64)
/// * `my_signed_prekey_sk` - Приватный Signed PreKey Bob (Base64)
/// * `their_identity` - Публичный Identity Key Alice (Base64)
/// * `their_ephemeral` - Публичный эфемерный ключ Alice (Base64)
/// 
/// # Returns
/// * `Ok(SharedSecret)` - общий секрет
/// * `Err(CryptoError)` - ошибка вычисления
/// 
/// # Formula
/// ```text
/// SK = KDF(
///   ECDH(SPK_B, IK_A) ||
///   ECDH(IK_B, EK_A) ||
///   ECDH(SPK_B, EK_A) ||
///   ECDH(OPK_B, EK_A)  // если использовался OPK
/// )
/// ```
/// 
/// # Example
/// ```
/// let bob_identity = IdentityKeyStore::generate()?;
/// let alice_identity_pk = get_alice_identity()?;
/// let alice_ephemeral_pk = get_ephemeral_from_message()?;
/// 
/// let shared_secret = x3dh_respond(
///     &bob_identity.identity_keypair.private_key,
///     &bob_identity.signed_prekey.private_key,
///     &alice_identity_pk,
///     &alice_ephemeral_pk,
/// )?;
/// ```
pub fn x3dh_respond(
    my_identity_sk: &str,
    my_signed_prekey_sk: &str,
    their_identity: &str,
    their_ephemeral: &str,
) -> Result<SharedSecret, CryptoError> {
    // 1. ECDH(SPK_B, IK_A) - Signed PreKey Bob → Identity Key Alice
    let spk_b_sk = import_private_key_b64(my_signed_prekey_sk)?;
    let ik_a = import_public_key_b64(their_identity)?;
    let dh1 = spk_b_sk.diffie_hellman(&ik_a);
    
    // 2. ECDH(IK_B, EK_A) - Identity Key Bob → Ephemeral Alice
    let ik_b_sk = import_private_key_b64(my_identity_sk)?;
    let ek_a = import_public_key_b64(their_ephemeral)?;
    let dh2 = ik_b_sk.diffie_hellman(&ek_a);
    
    // 3. ECDH(SPK_B, EK_A) - Signed PreKey Bob → Ephemeral Alice
    let dh3 = spk_b_sk.diffie_hellman(&ek_a);
    
    // Собираем все DH выходы
    let mut dh_output = dh1.as_bytes().to_vec();
    dh_output.extend_from_slice(dh2.as_bytes());
    dh_output.extend_from_slice(dh3.as_bytes());
    
    // 4. ECDH(OPK_B, EK_A) - если использовался One-Time PreKey
    // Для этого нужно проверить, был ли OPK в bundle
    // В этой базовой реализации мы не передаём информацию об OPK,
    // поэтому эта функция используется только когда OPK не было
    
    // KDF: HKDF-SHA256
    let hkdf = Hkdf::<Sha256>::new(None, &dh_output);
    let mut okm = [0u8; 32];
    hkdf.expand(b"X3DH", &mut okm)
        .map_err(|_| CryptoError::Aead)?;
    
    Ok(SharedSecret { bytes: okm })
}

/// X3DH Respond с One-Time PreKey
/// 
/// # Arguments
/// * `my_identity_sk` - Приватный Identity Key Bob (Base64)
/// * `my_signed_prekey_sk` - Приватный Signed PreKey Bob (Base64)
/// * `my_one_time_prekey_sk` - Приватный One-Time PreKey Bob (Base64, опционально)
/// * `their_identity` - Публичный Identity Key Alice (Base64)
/// * `their_ephemeral` - Публичный эфемерный ключ Alice (Base64)
/// 
/// # Returns
/// * `Ok(SharedSecret)` - общий секрет
/// * `Err(CryptoError)` - ошибка вычисления
pub fn x3dh_respond_with_otk(
    my_identity_sk: &str,
    my_signed_prekey_sk: &str,
    my_one_time_prekey_sk: Option<&str>,
    their_identity: &str,
    their_ephemeral: &str,
) -> Result<SharedSecret, CryptoError> {
    // Базовые 3 ECDH
    let spk_b_sk = import_private_key_b64(my_signed_prekey_sk)?;
    let ik_a = import_public_key_b64(their_identity)?;
    let dh1 = spk_b_sk.diffie_hellman(&ik_a);
    
    let ik_b_sk = import_private_key_b64(my_identity_sk)?;
    let ek_a = import_public_key_b64(their_ephemeral)?;
    let dh2 = ik_b_sk.diffie_hellman(&ek_a);
    
    let dh3 = spk_b_sk.diffie_hellman(&ek_a);
    
    let mut dh_output = dh1.as_bytes().to_vec();
    dh_output.extend_from_slice(dh2.as_bytes());
    dh_output.extend_from_slice(dh3.as_bytes());
    
    // 4. ECDH(OPK_B, EK_A) - если есть One-Time PreKey
    if let Some(otk_sk) = my_one_time_prekey_sk {
        let otk_b_sk = import_private_key_b64(otk_sk)?;
        let dh4 = otk_b_sk.diffie_hellman(&ek_a);
        dh_output.extend_from_slice(dh4.as_bytes());
    }
    
    // KDF: HKDF-SHA256
    let hkdf = Hkdf::<Sha256>::new(None, &dh_output);
    let mut okm = [0u8; 32];
    hkdf.expand(b"X3DH", &mut okm)
        .map_err(|_| CryptoError::Aead)?;
    
    Ok(SharedSecret { bytes: okm })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::generate_key_pair;
    use crate::x3dh::identity::IdentityKeyStore;
    use crate::x3dh::bundle::PreKeyBundle;
    
    #[test]
    fn test_x3dh_full_exchange_with_otk() {
        // 1. Alice и Bob генерируют Identity Keys
        let alice_identity = IdentityKeyStore::generate().unwrap();
        let bob_identity = IdentityKeyStore::generate().unwrap();
        
        // 2. Bob генерирует One-Time PreKey
        let bob_otk = generate_key_pair(false);
        
        // 3. Bob создаёт PreKey Bundle
        let bob_signed = bob_identity.sign_current_prekey().unwrap();
        let bob_bundle = PreKeyBundle::new(
            2, // Bob's user_id
            bob_identity.identity_keypair.public_key.clone(),
            bob_identity.signed_prekey.public_key.clone(),
            bob_signed.signature,
            Some(bob_otk.public_key.clone()),
            Some(1),
        );
        
        // 4. Alice генерирует эфемерный ключ
        let alice_ephemeral = generate_key_pair(false);
        
        // 5. Alice вычисляет общий секрет
        let alice_sk = x3dh_initiate(
            &alice_identity.identity_keypair.private_key,
            &alice_ephemeral,
            &bob_bundle,
        ).unwrap();
        
        // 6. Bob вычисляет общий секрет
        let bob_sk = x3dh_respond_with_otk(
            &bob_identity.identity_keypair.private_key,
            &bob_identity.signed_prekey.private_key,
            Some(&bob_otk.private_key),
            &alice_identity.identity_keypair.public_key,
            &alice_ephemeral.public_key,
        ).unwrap();
        
        // 7. Проверка: SK одинаковый
        assert_eq!(alice_sk.bytes, bob_sk.bytes);
    }
    
    #[test]
    fn test_x3dh_without_otk() {
        // 1. Alice и Bob генерируют Identity Keys
        let alice_identity = IdentityKeyStore::generate().unwrap();
        let bob_identity = IdentityKeyStore::generate().unwrap();
        
        // 2. Bob создаёт PreKey Bundle без OTK
        let bob_signed = bob_identity.sign_current_prekey().unwrap();
        let bob_bundle = PreKeyBundle::without_one_time_prekey(
            2,
            bob_identity.identity_keypair.public_key.clone(),
            bob_identity.signed_prekey.public_key.clone(),
            bob_signed.signature,
        );
        
        // 3. Alice генерирует эфемерный ключ
        let alice_ephemeral = generate_key_pair(false);
        
        // 4. Alice вычисляет общий секрет
        let alice_sk = x3dh_initiate(
            &alice_identity.identity_keypair.private_key,
            &alice_ephemeral,
            &bob_bundle,
        ).unwrap();
        
        // 5. Bob вычисляет общий секрет (без OTK)
        let bob_sk = x3dh_respond(
            &bob_identity.identity_keypair.private_key,
            &bob_identity.signed_prekey.private_key,
            &alice_identity.identity_keypair.public_key,
            &alice_ephemeral.public_key,
        ).unwrap();
        
        // 6. Проверка: SK одинаковый
        assert_eq!(alice_sk.bytes, bob_sk.bytes);
    }
    
    #[test]
    fn test_shared_secret_operations() {
        let secret = SharedSecret::new([1u8; 32]);
        
        assert_eq!(secret.as_bytes(), &[1u8; 32]);
        assert_eq!(secret.to_vec(), vec![1u8; 32]);
        assert_eq!(secret.to_vec().len(), 32);
    }
}
