pub mod crypto;

#[cfg(feature = "ffi")]
pub mod ffi;

#[cfg(feature = "wasm")]
pub mod wasm;

// Re-export основных типов для удобства
pub use crypto::{
    generate_key_pair, generate_nonce, generate_salt,
    derive_key_from_password, derive_key_from_string,
    encrypt_data, decrypt_data,
    encrypt_message, decrypt_message,
    encrypt_file, decrypt_file,
    wrap_symmetric_key, unwrap_symmetric_key,
};

pub use crypto::types::{
    AeadKey, CryptoError, KeyPair,
    EncryptedMessage, EncryptedFile,
    EncryptedFileWithMessage, DecryptedFileWithMessage,
};