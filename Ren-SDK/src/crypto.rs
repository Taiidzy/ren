use base64::{engine::general_purpose, Engine as _};
use chacha20poly1305::aead::Aead;
use chacha20poly1305::KeyInit;
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use hkdf::Hkdf;
use pbkdf2::pbkdf2_hmac;
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey as X25519PublicKey, StaticSecret};
use zeroize::Zeroize;

#[path = "mod.rs"]
pub mod types;
pub use types::{
    AeadKey, Argon2Config, CryptoError, DecryptedFileWithMessage, EncryptedFile,
    EncryptedFileWithMessage, EncryptedMessage, IdentityKeyPair, KeyPair, SignedPublicKey,
};

// Helpers for base64
fn b64_encode(data: &[u8]) -> String {
    general_purpose::STANDARD.encode(data)
}
fn b64_decode(s: &str) -> Result<Vec<u8>, CryptoError> {
    Ok(general_purpose::STANDARD.decode(s)?)
}

fn nonce_from_slice(n: &[u8]) -> Result<Nonce, CryptoError> {
    if n.len() != 12 {
        return Err(CryptoError::InvalidKeyLen("nonce".into()));
    }
    let mut arr = [0u8; 12];
    arr.copy_from_slice(n);
    Ok(Nonce::from(arr))
}

fn nonce_from_b64(b64: &str) -> Result<Nonce, CryptoError> {
    let n = b64_decode(b64)?;
    nonce_from_slice(&n)
}

// Nonce: 12 bytes as in WebCrypto examples
pub fn generate_nonce() -> String {
    let mut nonce = [0u8; 12];
    getrandom::getrandom(&mut nonce).expect("rand");
    b64_encode(&nonce)
}

// Salt: 16 bytes
pub fn generate_salt() -> String {
    let mut salt = [0u8; 16];
    getrandom::getrandom(&mut salt).expect("rand");
    b64_encode(&salt)
}

// types moved to self::types

/// Generates an X25519 key pair for ECDH (RAW 32 bytes, Base64 when exported).
pub fn generate_key_pair(_extractable_private_key: bool) -> KeyPair {
    let mut sk_bytes = [0u8; 32];
    getrandom::getrandom(&mut sk_bytes).expect("rand");
    let sk = StaticSecret::from(sk_bytes);
    let pk = X25519PublicKey::from(&sk);
    KeyPair {
        public_key: b64_encode(pk.as_bytes()),
        private_key: b64_encode(sk.to_bytes().as_slice()),
    }
}

/// Экспортирует публичный X25519-ключ в Base64 (RAW 32 байта).
pub fn export_public_key_b64(public_key: &X25519PublicKey) -> String {
    b64_encode(public_key.as_bytes())
}

/// Экспортирует приватный X25519-ключ в Base64 (RAW 32 байта).
pub fn export_private_key_b64(private_key: &StaticSecret) -> String {
    b64_encode(private_key.to_bytes().as_slice())
}

/// Импортирует публичный X25519-ключ из Base64 (ожидается 32 байта RAW).
pub fn import_public_key_b64(b64: &str) -> Result<X25519PublicKey, CryptoError> {
    let bytes = b64_decode(b64)?;
    if bytes.len() != 32 {
        return Err(CryptoError::InvalidKeyLen(format!("{}", bytes.len())));
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Ok(X25519PublicKey::from(arr))
}

/// Импортирует приватный X25519-ключ из Base64 (ожидается 32 байта RAW).
pub fn import_private_key_b64(b64: &str) -> Result<StaticSecret, CryptoError> {
    let bytes = b64_decode(b64)?;
    if bytes.len() != 32 {
        return Err(CryptoError::InvalidKeyLen(format!("{}", bytes.len())));
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Ok(StaticSecret::from(arr))
}

/// Деривирует 32-байтный мастер-ключ по PBKDF2-HMAC-SHA256(100k) из пароля и соли (Base64-16).
/// Замечание: используется для расшифровки приватного ключа с сервера, не для шифрования сообщений/файлов.
pub fn derive_key_from_password(password: &str, salt_b64: &str) -> Result<AeadKey, CryptoError> {
    let mut out = [0u8; 32];
    let salt = b64_decode(salt_b64)?;
    pbkdf2_hmac::<Sha256>(password.as_bytes(), &salt, 100_000, &mut out);
    let key = AeadKey::from_bytes(&out);
    out.zeroize();
    key
}

/// Деривирует 32-байтный ключ из произвольной строки: SHA-256(secret)[0..32].
pub fn derive_key_from_string(secret: &str) -> Result<AeadKey, CryptoError> {
    let mut hasher = Sha256::new();
    hasher.update(secret.as_bytes());
    let digest = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest[..32]);
    let key = AeadKey::from_bytes(&out);
    out.zeroize();
    key
}

// ==============================
// P0-3: Argon2id Recovery KDF Functions
// ==============================

/// P0-3: Derives a 32-byte recovery key using Argon2id (memory-hard KDF).
/// 
/// This function is designed for secure recovery key derivation from a mnemonic phrase
/// or high-entropy recovery secret. It uses Argon2id with OWASP-recommended parameters:
/// - Memory: 64 MiB
/// - Iterations: 3
/// - Parallelism: 4
/// 
/// # Arguments
/// * `recovery_secret` - The recovery phrase or secret (must have >= 128 bits of entropy)
/// * `salt_b64` - A unique salt (Base64-encoded, should be at least 16 bytes)
/// 
/// # Returns
/// A 32-byte AEAD key suitable for encrypting/decrypting recovery data.
/// 
/// # Security Notes
/// - The recovery_secret MUST have at least 128 bits of entropy
/// - Use a unique, random salt for each user/recovery key
/// - Store the salt alongside the encrypted recovery data (it's not secret)
pub fn derive_recovery_key_argon2id(
    recovery_secret: &str,
    salt_b64: &str,
) -> Result<AeadKey, CryptoError> {
    derive_recovery_key_argon2id_with_config(recovery_secret, salt_b64, &Argon2Config::default())
}

/// P0-3: Derives a 32-byte recovery key using Argon2id with custom configuration.
/// 
/// This function allows fine-tuning of Argon2id parameters for specific security
/// requirements or hardware constraints.
/// 
/// # Arguments
/// * `recovery_secret` - The recovery phrase or secret
/// * `salt_b64` - A unique salt (Base64-encoded)
/// * `config` - Argon2 configuration (memory, iterations, parallelism)
/// 
/// # Returns
/// A 32-byte AEAD key.
pub fn derive_recovery_key_argon2id_with_config(
    recovery_secret: &str,
    salt_b64: &str,
    config: &Argon2Config,
) -> Result<AeadKey, CryptoError> {
    use argon2::{Argon2, Params, Version};
    
    let mut salt = b64_decode(salt_b64)?;
    if salt.len() < 16 {
        return Err(CryptoError::InvalidKeyLen(format!(
            "Salt must be at least 16 bytes, got {}",
            salt.len()
        )));
    }
    
    // Validate Argon2 parameters
    if config.memory_kib < 8 {
        return Err(CryptoError::Argon2(
            "Memory must be at least 8 KiB".into()
        ));
    }
    if config.iterations < 1 {
        return Err(CryptoError::Argon2(
            "Iterations must be at least 1".into()
        ));
    }
    if config.parallelism < 1 {
        return Err(CryptoError::Argon2(
            "Parallelism must be at least 1".into()
        ));
    }
    
    // Create Argon2id parameters
    let params = Params::new(
        config.memory_kib,
        config.iterations,
        config.parallelism,
        Some(32), // Output length: 32 bytes
    )
    .map_err(|e| CryptoError::Argon2(format!("Invalid Argon2 parameters: {}", e)))?;
    
    // Create Argon2id instance with version 0x13 (v1.3)
    let argon2 = Argon2::new(argon2::Algorithm::Argon2id, Version::V0x13, params);
    
    // Hash the recovery secret
    let mut out = [0u8; 32];
    argon2
        .hash_password_into(recovery_secret.as_bytes(), &salt, &mut out)
        .map_err(|e| CryptoError::Argon2(format!("Argon2 hashing failed: {}", e)))?;
    
    let key = AeadKey::from_bytes(&out);
    out.zeroize();
    salt.zeroize();
    key
}

/// P0-3: Generate a secure random salt for Argon2id KDF.
/// 
/// Returns a Base64-encoded salt of the specified size.
/// 
/// # Arguments
/// * `size_bytes` - Salt size in bytes (default: 16, minimum: 16)
/// 
/// # Returns
/// Base64-encoded random salt.
pub fn generate_recovery_salt(size_bytes: usize) -> Result<String, CryptoError> {
    let size = size_bytes.max(16); // Minimum 16 bytes for security
    let mut salt = vec![0u8; size];
    getrandom::getrandom(&mut salt).expect("rand");
    let salt_b64 = b64_encode(&salt);
    salt.zeroize();
    Ok(salt_b64)
}

/// P0-3: Validate that a recovery secret has sufficient entropy.
/// 
/// This is a basic check - in production, use proper entropy estimation.
/// 
/// # Arguments
/// * `recovery_phrase` - The recovery phrase to validate
/// 
/// # Returns
/// `Ok(true)` if the phrase appears to have >= 128 bits of entropy.
pub fn validate_recovery_entropy(recovery_phrase: &str) -> Result<bool, CryptoError> {
    let phrase = recovery_phrase.trim();
    
    // Check for word-based mnemonic (12 words = ~128 bits with BIP39)
    let words: Vec<&str> = phrase.split_whitespace().collect();
    if words.len() >= 12 {
        return Ok(true);
    }
    
    // Check for base64-like high-entropy string (22+ chars = ~128 bits)
    if phrase.len() >= 22 && phrase.chars().all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '/' || c == '=' || c == '-' || c == '_') {
        return Ok(true);
    }
    
    // Fallback: check character count for alphanumeric strings
    // 20+ random alphanumeric chars ≈ 128 bits
    if phrase.len() >= 20 && phrase.chars().all(|c| c.is_ascii_alphanumeric()) {
        return Ok(true);
    }
    
    Ok(false)
}

// ==============================
// P0-2: Ed25519 Identity Key Functions for Key Authentication
// ==============================

/// P0-2: Generate an Ed25519 identity key pair for signing.
/// 
/// The identity key is used to sign X25519 public keys for authentication,
/// preventing MITM attacks through key substitution.
/// 
/// # Returns
/// IdentityKeyPair with Base64-encoded keys:
/// - public_key: 32 bytes (Ed25519 public key)
/// - private_key: 64 bytes (Ed25519 secret key with embedded public key)
pub fn generate_identity_key_pair() -> Result<IdentityKeyPair, CryptoError> {
    use ed25519_dalek::SigningKey;
    
    // Generate Ed25519 signing key
    let mut secret_bytes = [0u8; 32];
    getrandom::getrandom(&mut secret_bytes).expect("rand");
    let signing_key = SigningKey::from_bytes(&secret_bytes);
    let verifying_key = signing_key.verifying_key();
    
    Ok(IdentityKeyPair {
        public_key: b64_encode(verifying_key.as_bytes()),
        private_key: b64_encode(signing_key.to_keypair_bytes().as_slice()),
    })
}

/// P0-2: Sign an X25519 public key with Ed25519 identity key.
/// 
/// Creates a cryptographic signature that binds the X25519 public key
/// to the identity key, preventing MITM attacks.
/// 
/// # Arguments
/// * `x25519_public_key_b64` - X25519 public key to sign (Base64, 32 bytes)
/// * `identity_private_key_b64` - Ed25519 private key for signing (Base64, 64 bytes)
/// * `key_version` - Version number for key rotation support
/// 
/// # Returns
/// SignedPublicKey bundle with signature and metadata.
pub fn sign_public_key(
    x25519_public_key_b64: &str,
    identity_private_key_b64: &str,
    key_version: u32,
) -> Result<SignedPublicKey, CryptoError> {
    use ed25519_dalek::{SigningKey, Signature, Signer};
    use chrono::Utc;
    
    // Decode keys
    let id_key_bytes = b64_decode(identity_private_key_b64)?;
    if id_key_bytes.len() != 64 {
        return Err(CryptoError::InvalidKeyLen(format!(
            "Identity private key must be 64 bytes, got {}",
            id_key_bytes.len()
        )));
    }
    
    // Create signing key from keypair bytes
    let signing_key = SigningKey::from_keypair_bytes(
        &id_key_bytes.try_into().map_err(|_| CryptoError::InvalidKeyLen("Invalid key length".into()))?
    )
    .map_err(|e| CryptoError::Signature(format!("Invalid signing key: {}", e)))?;
    
    // Create message to sign: public_key || key_version
    let pk_bytes = b64_decode(x25519_public_key_b64)?;
    let version_bytes = key_version.to_le_bytes();
    let mut message = Vec::with_capacity(pk_bytes.len() + version_bytes.len());
    message.extend_from_slice(&pk_bytes);
    message.extend_from_slice(&version_bytes);
    
    // Sign the message
    let signature: Signature = signing_key.try_sign(&message)
        .map_err(|e| CryptoError::Signature(format!("Signing failed: {}", e)))?;
    
    Ok(SignedPublicKey {
        public_key: x25519_public_key_b64.to_string(),
        signature: b64_encode(signature.to_bytes().as_slice()),
        key_version,
        signed_at: Utc::now().to_rfc3339(),
    })
}

/// P0-2: Verify a signed X25519 public key.
/// 
/// Verifies that the signature was created by the holder of the identity
/// private key, ensuring the public key hasn't been tampered with.
/// 
/// # Arguments
/// * `signed_key` - The SignedPublicKey bundle to verify
/// * `identity_public_key_b64` - Ed25519 public key for verification (Base64, 32 bytes)
/// 
/// # Returns
/// `Ok(true)` if signature is valid, `Ok(false)` otherwise.
pub fn verify_signed_public_key(
    signed_key: &SignedPublicKey,
    identity_public_key_b64: &str,
) -> Result<bool, CryptoError> {
    use ed25519_dalek::{VerifyingKey, Signature, Verifier};
    
    // Decode identity public key
    let id_key_bytes = b64_decode(identity_public_key_b64)?;
    if id_key_bytes.len() != 32 {
        return Err(CryptoError::InvalidKeyLen(format!(
            "Identity public key must be 32 bytes, got {}",
            id_key_bytes.len()
        )));
    }
    
    // Decode signature
    let sig_bytes = b64_decode(&signed_key.signature)?;
    if sig_bytes.len() != 64 {
        return Err(CryptoError::InvalidKeyLen(format!(
            "Signature must be 64 bytes, got {}",
            sig_bytes.len()
        )));
    }
    
    // Create verifying key
    let key_array: [u8; 32] = id_key_bytes.try_into()
        .map_err(|_| CryptoError::InvalidKeyLen("Invalid key length".into()))?;
    let verifying_key = VerifyingKey::from_bytes(&key_array)
        .map_err(|e| CryptoError::Signature(format!("Invalid identity key: {}", e)))?;
    
    // Create signature
    let mut sig_bytes_arr = [0u8; 64];
    sig_bytes_arr.copy_from_slice(&sig_bytes);
    let signature = Signature::from_bytes(&sig_bytes_arr);
    
    // Reconstruct message
    let pk_bytes = b64_decode(&signed_key.public_key)?;
    let version_bytes = signed_key.key_version.to_le_bytes();
    let mut message = Vec::with_capacity(pk_bytes.len() + version_bytes.len());
    message.extend_from_slice(&pk_bytes);
    message.extend_from_slice(&version_bytes);
    
    // Verify signature
    match verifying_key.verify(&message, &signature) {
        Ok(_) => Ok(true),
        Err(_) => Ok(false),
    }
}

/// P0-2: Import Ed25519 identity public key from Base64.
/// 
/// # Arguments
/// * `b64` - Base64-encoded Ed25519 public key (32 bytes)
/// 
/// # Returns
/// Result with success status or error message.
pub fn import_identity_public_key(b64: &str) -> Result<(), CryptoError> {
    let bytes = b64_decode(b64)?;
    if bytes.len() != 32 {
        return Err(CryptoError::InvalidKeyLen(format!(
            "Identity public key must be 32 bytes, got {}",
            bytes.len()
        )));
    }
    Ok(())
}

/// Шифрует строку и возвращает Base64-последовательность: nonce(12) || ciphertext.
pub fn encrypt_data(data: &str, key: &AeadKey) -> Result<String, CryptoError> {
    let cipher = ChaCha20Poly1305::new(&key.0);
    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes).expect("rand");
    let nonce = Nonce::from(nonce_bytes);
    let ciphertext = cipher.encrypt(&nonce, data.as_bytes())?;
    let mut out = Vec::with_capacity(12 + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(b64_encode(&out))
}

/// Дешифрует результат `encrypt_data` (Base64: nonce(12)||ciphertext) в строку.
pub fn decrypt_data(b64_combined: &str, key: &AeadKey) -> Result<String, CryptoError> {
    let data = b64_decode(b64_combined)?;
    if data.len() < 12 {
        return Err(CryptoError::Aead);
    }
    let (nonce_bytes, ct) = data.split_at(12);
    let nonce = nonce_from_slice(nonce_bytes)?;
    let cipher = ChaCha20Poly1305::new(&key.0);
    let pt = cipher.decrypt(&nonce, ct)?;
    let s = String::from_utf8(pt).map_err(|_| CryptoError::Aead)?;
    Ok(s)
}

pub fn generate_message_encryption_key() -> AeadKey {
    let mut key_bytes = [0u8; 32];
    getrandom::getrandom(&mut key_bytes).expect("rand");
    let key = AeadKey::from_bytes(&key_bytes).expect("key size");
    key_bytes.zeroize();
    key
}

// Wrap symmetric key using X25519 ECDH + HKDF-SHA256 -> ChaCha20-Poly1305
/// Оборачивает симметричный ключ `key_to_wrap` для получателя (X25519 ECDH + HKDF + AEAD).
pub fn wrap_symmetric_key(
    key_to_wrap: &AeadKey,
    receiver_public_key_b64: &str,
) -> Result<
    (
        String, /*wrappedKey*/
        String, /*ephemeralPublicKey*/
        String, /*nonce*/
    ),
    CryptoError,
> {
    let receiver_pk = import_public_key_b64(receiver_public_key_b64)?;
    // ephemeral keypair
    let mut eph_bytes = [0u8; 32];
    getrandom::getrandom(&mut eph_bytes).expect("rand");
    let eph_sk = StaticSecret::from(eph_bytes);
    eph_bytes.zeroize();
    let eph_pk = X25519PublicKey::from(&eph_sk);
    // shared secret
    let shared = eph_sk.diffie_hellman(&receiver_pk);
    // derive wrapping key
    let hk = Hkdf::<Sha256>::new(None, shared.as_bytes());
    let mut wrap_key_bytes = [0u8; 32];
    hk.expand(b"ren-sdk-wrap", &mut wrap_key_bytes)
        .map_err(|_| CryptoError::Aead)?;
    let wrap_key = AeadKey::from_bytes(&wrap_key_bytes)?;
    wrap_key_bytes.zeroize();
    // encrypt raw key bytes
    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes).expect("rand");
    let cipher = ChaCha20Poly1305::new(&wrap_key.0);
    let nonce = Nonce::from(nonce_bytes);
    let mut key_bytes = key_to_wrap.to_bytes();
    let ct = cipher.encrypt(&nonce, &key_bytes[..])?;
    key_bytes.zeroize();
    Ok((
        b64_encode(&ct),
        export_public_key_b64(&eph_pk),
        b64_encode(&nonce_bytes),
    ))
}

/// Разворачивает симметричный ключ, ранее обёрнутый `wrap_symmetric_key`.
pub fn unwrap_symmetric_key(
    wrapped_key_b64: &str,
    ephemeral_public_key_b64: &str,
    nonce_b64: &str,
    receiver_private_key_b64: &str,
) -> Result<AeadKey, CryptoError> {
    let ct = b64_decode(wrapped_key_b64)?;
    let nonce = nonce_from_b64(nonce_b64)?;
    let eph_pk = import_public_key_b64(ephemeral_public_key_b64)?;
    let recv_sk = import_private_key_b64(receiver_private_key_b64)?;
    let shared = recv_sk.diffie_hellman(&eph_pk);
    let hk = Hkdf::<Sha256>::new(None, shared.as_bytes());
    let mut wrap_key_bytes = [0u8; 32];
    hk.expand(b"ren-sdk-wrap", &mut wrap_key_bytes)
        .map_err(|_| CryptoError::Aead)?;
    let wrap_key = AeadKey::from_bytes(&wrap_key_bytes)?;
    wrap_key_bytes.zeroize();
    let cipher = ChaCha20Poly1305::new(&wrap_key.0);
    let pt = cipher.decrypt(&nonce, ct.as_ref())?;
    AeadKey::from_bytes(&pt)
}

/// AEAD-шифрование короткого сообщения (возвращает Base64 ciphertext + nonce).
pub fn encrypt_message(data: &str, key: &AeadKey) -> Result<EncryptedMessage, CryptoError> {
    let cipher = ChaCha20Poly1305::new(&key.0);
    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes).expect("rand");
    let nonce = Nonce::from(nonce_bytes);
    let ct = cipher.encrypt(&nonce, data.as_bytes())?;
    Ok(EncryptedMessage {
        ciphertext: b64_encode(&ct),
        nonce: b64_encode(&nonce_bytes),
    })
}

/// AEAD-дешифрование сообщения по Base64 `ciphertext` и `nonce`.
pub fn decrypt_message(
    ciphertext_b64: &str,
    nonce_b64: &str,
    key: &AeadKey,
) -> Result<String, CryptoError> {
    let ct = b64_decode(ciphertext_b64)?;
    let nonce = nonce_from_b64(nonce_b64)?;
    let cipher = ChaCha20Poly1305::new(&key.0);
    let pt = cipher.decrypt(&nonce, ct.as_ref())?;
    let s = String::from_utf8(pt).map_err(|_| CryptoError::Aead)?;
    Ok(s)
}

/// AEAD-дешифрование файла, когда ciphertext уже в виде raw bytes (без base64).
pub fn decrypt_file_raw(
    ciphertext: &[u8],
    nonce_b64: &str,
    key: &AeadKey,
) -> Result<Vec<u8>, CryptoError> {
    let nonce = nonce_from_b64(nonce_b64)?;
    let cipher = ChaCha20Poly1305::new(&key.0);
    let pt = cipher.decrypt(&nonce, ciphertext)?;
    Ok(pt)
}

/// AEAD-шифрование произвольных байт файла. Возвращает Base64 ciphertext и nonce.
pub fn encrypt_file(
    bytes: &[u8],
    filename: &str,
    mimetype: &str,
    key: &AeadKey,
) -> Result<EncryptedFile, CryptoError> {
    let cipher = ChaCha20Poly1305::new(&key.0);
    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes).expect("rand");
    let nonce = Nonce::from(nonce_bytes);
    let ct = cipher.encrypt(&nonce, bytes)?;
    Ok(EncryptedFile {
        ciphertext: b64_encode(&ct),
        nonce: b64_encode(&nonce_bytes),
        filename: filename.to_string(),
        mimetype: mimetype.to_string(),
    })
}

/// AEAD-дешифрование файла по Base64 `ciphertext` и `nonce`.
pub fn decrypt_file(
    ciphertext_b64: &str,
    nonce_b64: &str,
    key: &AeadKey,
) -> Result<Vec<u8>, CryptoError> {
    let ct = b64_decode(ciphertext_b64)?;
    let nonce = nonce_from_b64(nonce_b64)?;
    let cipher = ChaCha20Poly1305::new(&key.0);
    let pt = cipher.decrypt(&nonce, ct.as_ref())?;
    Ok(pt)
}

/// AEAD-шифрование произвольных байт файла. Возвращает raw ciphertext bytes + nonce (base64).
pub fn encrypt_file_raw(
    bytes: &[u8],
    key: &AeadKey,
) -> Result<(Vec<u8> /*ciphertext*/, String /*nonce*/), CryptoError> {
    let cipher = ChaCha20Poly1305::new(&key.0);
    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes).expect("rand");
    let nonce = Nonce::from(nonce_bytes);
    let ct = cipher.encrypt(&nonce, bytes)?;
    Ok((ct, b64_encode(&nonce_bytes)))
}

/// Удобный вариант: шифрует файл и сообщение под один nonce/ключ.
pub fn encrypt_file_with_message(
    bytes: &[u8],
    message: &str,
    key: &AeadKey,
    filename: &str,
    mimetype: &str,
) -> Result<EncryptedFileWithMessage, CryptoError> {
    let cipher = ChaCha20Poly1305::new(&key.0);
    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes).expect("rand");
    let nonce = Nonce::from(nonce_bytes);
    let enc_file = cipher.encrypt(&nonce, bytes)?;
    let enc_msg = cipher.encrypt(&nonce, message.as_bytes())?;
    Ok(EncryptedFileWithMessage {
        enc_file: b64_encode(&enc_file),
        ciphertext: b64_encode(&enc_msg),
        nonce: b64_encode(&nonce_bytes),
        filename: filename.to_string(),
        mimetype: mimetype.to_string(),
    })
}

/// Дешифрует результат `encrypt_file_with_message` и возвращает байты файла и строку сообщения.
pub fn decrypt_file_with_message(
    enc_file_b64: &str,
    ciphertext_b64: &str,
    nonce_b64: &str,
    key: &AeadKey,
    filename: &str,
    mimetype: &str,
) -> Result<DecryptedFileWithMessage, CryptoError> {
    let nonce = nonce_from_b64(nonce_b64)?;
    let cipher = ChaCha20Poly1305::new(&key.0);
    let file_ct = b64_decode(enc_file_b64)?;
    let msg_ct = b64_decode(ciphertext_b64)?;
    let file = cipher.decrypt(&nonce, file_ct.as_ref())?;
    let msg = cipher.decrypt(&nonce, msg_ct.as_ref())?;
    let message = String::from_utf8(msg).map_err(|_| CryptoError::Aead)?;
    Ok(DecryptedFileWithMessage {
        file,
        message,
        filename: filename.to_string(),
        mimetype: mimetype.to_string(),
    })
}
