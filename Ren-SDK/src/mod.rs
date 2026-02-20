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
