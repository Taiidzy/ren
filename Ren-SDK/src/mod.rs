use chacha20poly1305::Key;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use zeroize::Zeroize;

#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("base64 error: {0}")]
    Base64(#[from] base64::DecodeError),
    #[error("invalid key length: {0}")]
    InvalidKeyLen(String),
    #[error("aead error")]
    Aead,
    #[error("argon2 error: {0}")]
    Argon2(String),
    #[error("signature error: {0}")]
    Signature(String),
}

impl From<chacha20poly1305::aead::Error> for CryptoError {
    fn from(_: chacha20poly1305::aead::Error) -> Self {
        CryptoError::Aead
    }
}

#[derive(Clone)]
pub struct AeadKey(pub Key);

impl Drop for AeadKey {
    fn drop(&mut self) {
        self.0.as_mut_slice().zeroize();
    }
}

impl AeadKey {
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, CryptoError> {
        if bytes.len() != 32 {
            return Err(CryptoError::InvalidKeyLen(format!("{}", bytes.len())));
        }
        let mut arr = [0u8; 32];
        arr.copy_from_slice(bytes);
        Ok(AeadKey(Key::from(arr)))
    }
    pub fn to_bytes(&self) -> [u8; 32] {
        self.0.clone().into()
    }
}

/// P0-3: Recovery key derivation parameters for Argon2id
/// Memory-hard KDF parameters for secure recovery key derivation
pub struct Argon2Config {
    /// Memory size in KiB (default: 64 MiB = 65536 KiB)
    pub memory_kib: u32,
    /// Number of iterations (default: 3)
    pub iterations: u32,
    /// Degree of parallelism (default: 4)
    pub parallelism: u32,
}

impl Default for Argon2Config {
    fn default() -> Self {
        // OWASP recommended parameters for password hashing (2023)
        // For recovery key derivation, we use similar hardening
        Argon2Config {
            memory_kib: 65536,  // 64 MiB
            iterations: 3,
            parallelism: 4,
        }
    }
}

/// P0-2: Identity key pair for Ed25519 signing (used for key authentication)
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct IdentityKeyPair {
    pub public_key: String,  // Base64-encoded Ed25519 public key (32 bytes)
    pub private_key: String, // Base64-encoded Ed25519 private key (64 bytes with public key)
}

/// P0-2: Signed public key bundle for E2EE
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SignedPublicKey {
    /// X25519 public key (Base64, 32 bytes)
    pub public_key: String,
    /// Ed25519 signature of the public key (Base64, 64 bytes)
    pub signature: String,
    /// Key version for rotation support
    pub key_version: u32,
    /// Timestamp when key was signed (ISO8601)
    pub signed_at: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct EncryptedMessage {
    pub ciphertext: String,
    pub nonce: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct EncryptedFile {
    pub ciphertext: String,
    pub nonce: String,
    pub filename: String,
    pub mimetype: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct EncryptedFileWithMessage {
    pub enc_file: String,
    pub ciphertext: String,
    pub nonce: String,
    pub filename: String,
    pub mimetype: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct DecryptedFileWithMessage {
    pub file: Vec<u8>,
    pub message: String,
    pub filename: String,
    pub mimetype: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct KeyPair {
    pub public_key: String,  // base64 raw 32 bytes
    pub private_key: String, // base64 raw 32 bytes
}
