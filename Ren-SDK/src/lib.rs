pub mod crypto;

#[cfg(feature = "ffi")]
pub mod ffi;

#[cfg(feature = "wasm")]
pub mod wasm;

// Re-export основных типов для удобства
pub use crypto::{
    decrypt_data, decrypt_file, decrypt_message, derive_key_from_password, derive_key_from_string,
    derive_recovery_key_argon2id, derive_recovery_key_argon2id_with_config,
    encrypt_data, encrypt_file, encrypt_message, generate_key_pair, generate_nonce, generate_salt,
    generate_recovery_salt, validate_recovery_entropy,
    generate_identity_key_pair, sign_public_key, verify_signed_public_key,
    unwrap_symmetric_key, wrap_symmetric_key,
};

pub use crypto::types::{
    AeadKey, Argon2Config, CryptoError, DecryptedFileWithMessage, EncryptedFile,
    EncryptedFileWithMessage, EncryptedMessage, IdentityKeyPair, KeyPair, SignedPublicKey,
};
