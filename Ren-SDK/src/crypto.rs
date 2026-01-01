use base64::{engine::general_purpose, Engine as _};
use chacha20poly1305::aead::Aead;
use chacha20poly1305::KeyInit;
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use hkdf::Hkdf;
use pbkdf2::pbkdf2_hmac;
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey as X25519PublicKey, StaticSecret};

#[path = "mod.rs"]
pub mod types;
pub use types::{
    AeadKey, CryptoError, DecryptedFileWithMessage, EncryptedFile, EncryptedFileWithMessage,
    EncryptedMessage, KeyPair,
};

// Helpers for base64
fn b64_encode(data: &[u8]) -> String {
    general_purpose::STANDARD.encode(data)
}
fn b64_decode(s: &str) -> Result<Vec<u8>, CryptoError> {
    Ok(general_purpose::STANDARD.decode(s)?)
}

fn nonce_from_slice(n: &[u8]) -> Result<Nonce, CryptoError> {
    if n.len() != 12 { return Err(CryptoError::InvalidKeyLen("nonce".into())); }
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
    if bytes.len() != 32 { return Err(CryptoError::InvalidKeyLen(format!("{}", bytes.len()))); }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Ok(X25519PublicKey::from(arr))
}

/// Импортирует приватный X25519-ключ из Base64 (ожидается 32 байта RAW).
pub fn import_private_key_b64(b64: &str) -> Result<StaticSecret, CryptoError> {
    let bytes = b64_decode(b64)?;
    if bytes.len() != 32 { return Err(CryptoError::InvalidKeyLen(format!("{}", bytes.len()))); }
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
    AeadKey::from_bytes(&out)
}

/// Деривирует 32-байтный ключ из произвольной строки: SHA-256(secret)[0..32].
pub fn derive_key_from_string(secret: &str) -> Result<AeadKey, CryptoError> {
    let mut hasher = Sha256::new();
    hasher.update(secret.as_bytes());
    let digest = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest[..32]);
    AeadKey::from_bytes(&out)
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
    if data.len() < 12 { return Err(CryptoError::Aead); }
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
    AeadKey::from_bytes(&key_bytes).expect("key size")
}

// Wrap symmetric key using X25519 ECDH + HKDF-SHA256 -> ChaCha20-Poly1305
/// Оборачивает симметричный ключ `key_to_wrap` для получателя (X25519 ECDH + HKDF + AEAD).
pub fn wrap_symmetric_key(
    key_to_wrap: &AeadKey,
    receiver_public_key_b64: &str,
) -> Result<(String /*wrappedKey*/, String /*ephemeralPublicKey*/, String /*nonce*/ ), CryptoError> {
    let receiver_pk = import_public_key_b64(receiver_public_key_b64)?;
    // ephemeral keypair
    let mut eph_bytes = [0u8; 32];
    getrandom::getrandom(&mut eph_bytes).expect("rand");
    let eph_sk = StaticSecret::from(eph_bytes);
    let eph_pk = X25519PublicKey::from(&eph_sk);
    // shared secret
    let shared = eph_sk.diffie_hellman(&receiver_pk);
    // derive wrapping key
    let hk = Hkdf::<Sha256>::new(None, shared.as_bytes());
    let mut wrap_key_bytes = [0u8; 32];
    hk.expand(b"ren-sdk-wrap", &mut wrap_key_bytes).map_err(|_| CryptoError::Aead)?;
    let wrap_key = AeadKey::from_bytes(&wrap_key_bytes)?;
    // encrypt raw key bytes
    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes).expect("rand");
    let cipher = ChaCha20Poly1305::new(&wrap_key.0);
    let nonce = Nonce::from(nonce_bytes);
    let ct = cipher.encrypt(&nonce, &key_to_wrap.to_bytes()[..])?;
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
    hk.expand(b"ren-sdk-wrap", &mut wrap_key_bytes).map_err(|_| CryptoError::Aead)?;
    let wrap_key = AeadKey::from_bytes(&wrap_key_bytes)?;
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
    Ok(EncryptedMessage { ciphertext: b64_encode(&ct), nonce: b64_encode(&nonce_bytes) })
}

/// AEAD-дешифрование сообщения по Base64 `ciphertext` и `nonce`.
pub fn decrypt_message(ciphertext_b64: &str, nonce_b64: &str, key: &AeadKey) -> Result<String, CryptoError> {
    let ct = b64_decode(ciphertext_b64)?;
    let nonce = nonce_from_b64(nonce_b64)?;
    let cipher = ChaCha20Poly1305::new(&key.0);
    let pt = cipher.decrypt(&nonce, ct.as_ref())?;
    let s = String::from_utf8(pt).map_err(|_| CryptoError::Aead)?;
    Ok(s)
}

/// AEAD-шифрование произвольных байт файла. Возвращает Base64 ciphertext и nonce.
pub fn encrypt_file(bytes: &[u8], filename: &str, mimetype: &str, key: &AeadKey) -> Result<EncryptedFile, CryptoError> {
    let cipher = ChaCha20Poly1305::new(&key.0);
    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes).expect("rand");
    let nonce = Nonce::from(nonce_bytes);
    let ct = cipher.encrypt(&nonce, bytes)?;
    Ok(EncryptedFile { ciphertext: b64_encode(&ct), nonce: b64_encode(&nonce_bytes), filename: filename.to_string(), mimetype: mimetype.to_string() })
}

/// AEAD-дешифрование файла по Base64 `ciphertext` и `nonce`.
pub fn decrypt_file(ciphertext_b64: &str, nonce_b64: &str, key: &AeadKey) -> Result<Vec<u8>, CryptoError> {
    let ct = b64_decode(ciphertext_b64)?;
    let nonce = nonce_from_b64(nonce_b64)?;
    let cipher = ChaCha20Poly1305::new(&key.0);
    let pt = cipher.decrypt(&nonce, ct.as_ref())?;
    Ok(pt)
}

/// Удобный вариант: шифрует файл и сообщение под один nonce/ключ.
pub fn encrypt_file_with_message(bytes: &[u8], message: &str, key: &AeadKey, filename: &str, mimetype: &str) -> Result<EncryptedFileWithMessage, CryptoError> {
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
pub fn decrypt_file_with_message(enc_file_b64: &str, ciphertext_b64: &str, nonce_b64: &str, key: &AeadKey, filename: &str, mimetype: &str) -> Result<DecryptedFileWithMessage, CryptoError> {
    let nonce = nonce_from_b64(nonce_b64)?;
    let cipher = ChaCha20Poly1305::new(&key.0);
    let file_ct = b64_decode(enc_file_b64)?;
    let msg_ct = b64_decode(ciphertext_b64)?;
    let file = cipher.decrypt(&nonce, file_ct.as_ref())?;
    let msg = cipher.decrypt(&nonce, msg_ct.as_ref())?;
    let message = String::from_utf8(msg).map_err(|_| CryptoError::Aead)?;
    Ok(DecryptedFileWithMessage { file, message, filename: filename.to_string(), mimetype: mimetype.to_string() })
}
