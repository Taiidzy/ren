pub mod crypto;

#[cfg(feature = "ffi")]
pub mod ffi;

#[cfg(feature = "wasm")]
pub mod wasm;

// Re-export основных типов для удобства
pub use crypto::{
    decrypt_data, decrypt_file, decrypt_message, derive_key_from_password, derive_key_from_string,
    encrypt_data, encrypt_file, encrypt_message, generate_key_pair, generate_nonce, generate_salt,
    unwrap_symmetric_key, wrap_symmetric_key,
};

pub use crypto::types::{
    AeadKey, CryptoError, DecryptedFileWithMessage, EncryptedFile, EncryptedFileWithMessage,
    EncryptedMessage, KeyPair,
};
