use wasm_bindgen::prelude::*;
use serde::{Deserialize, Serialize};
use serde_wasm_bindgen::to_value;

use crate::crypto::{
    decrypt_data, decrypt_file, decrypt_file_with_message, decrypt_message,
    derive_key_from_password, derive_key_from_string, encrypt_data, encrypt_file,
    encrypt_file_with_message, encrypt_message, generate_key_pair,
    generate_message_encryption_key, generate_nonce, generate_salt, unwrap_symmetric_key,
    wrap_symmetric_key,
};
use crate::crypto::types::AeadKey;

// ============================================================================
// Инициализация WASM
// ============================================================================

#[wasm_bindgen(start)]
pub fn init_wasm() {
    console_error_panic_hook::set_once();
}

// ============================================================================
// Вспомогательные структуры для WASM (JS-совместимые)
// ============================================================================

#[wasm_bindgen]
#[derive(Serialize, Deserialize)]
pub struct WasmKeyPair {
    #[wasm_bindgen(getter_with_clone)]
    pub public_key: String,
    #[wasm_bindgen(getter_with_clone)]
    pub private_key: String,
}

#[wasm_bindgen]
impl WasmKeyPair {
    #[wasm_bindgen(constructor)]
    pub fn new(public_key: String, private_key: String) -> WasmKeyPair {
        WasmKeyPair {
            public_key,
            private_key,
        }
    }
}

#[wasm_bindgen]
#[derive(Serialize, Deserialize)]
pub struct WasmEncryptedMessage {
    #[wasm_bindgen(getter_with_clone)]
    pub ciphertext: String,
    #[wasm_bindgen(getter_with_clone)]
    pub nonce: String,
}

#[wasm_bindgen]
impl WasmEncryptedMessage {
    #[wasm_bindgen(constructor)]
    pub fn new(ciphertext: String, nonce: String) -> WasmEncryptedMessage {
        WasmEncryptedMessage { ciphertext, nonce }
    }
}

#[wasm_bindgen]
#[derive(Serialize, Deserialize)]
pub struct WasmEncryptedFile {
    #[wasm_bindgen(getter_with_clone)]
    pub ciphertext: String,
    #[wasm_bindgen(getter_with_clone)]
    pub nonce: String,
    #[wasm_bindgen(getter_with_clone)]
    pub filename: String,
    #[wasm_bindgen(getter_with_clone)]
    pub mimetype: String,
}

#[wasm_bindgen]
impl WasmEncryptedFile {
    #[wasm_bindgen(constructor)]
    pub fn new(
        ciphertext: String,
        nonce: String,
        filename: String,
        mimetype: String,
    ) -> WasmEncryptedFile {
        WasmEncryptedFile {
            ciphertext,
            nonce,
            filename,
            mimetype,
        }
    }
}

#[wasm_bindgen]
#[derive(Serialize, Deserialize)]
pub struct WasmWrappedKey {
    #[wasm_bindgen(getter_with_clone)]
    pub wrapped_key: String,
    #[wasm_bindgen(getter_with_clone)]
    pub ephemeral_public_key: String,
    #[wasm_bindgen(getter_with_clone)]
    pub nonce: String,
}

#[wasm_bindgen]
impl WasmWrappedKey {
    #[wasm_bindgen(constructor)]
    pub fn new(
        wrapped_key: String,
        ephemeral_public_key: String,
        nonce: String,
    ) -> WasmWrappedKey {
        WasmWrappedKey {
            wrapped_key,
            ephemeral_public_key,
            nonce,
        }
    }
}

#[wasm_bindgen]
#[derive(Serialize, Deserialize)]
pub struct WasmDecryptedFile {
    #[wasm_bindgen(skip)]
    pub data: Vec<u8>,
    #[wasm_bindgen(getter_with_clone)]
    pub filename: String,
    #[wasm_bindgen(getter_with_clone)]
    pub mimetype: String,
    #[wasm_bindgen(getter_with_clone)]
    pub message: String,
}

#[wasm_bindgen]
impl WasmDecryptedFile {
    #[wasm_bindgen(getter)]
    pub fn data(&self) -> Vec<u8> {
        self.data.clone()
    }
}

// ============================================================================
// Генерация случайных значений
// ============================================================================

#[wasm_bindgen(js_name = generateNonce)]
pub fn wasm_generate_nonce() -> String {
    generate_nonce()
}

#[wasm_bindgen(js_name = generateSalt)]
pub fn wasm_generate_salt() -> String {
    generate_salt()
}

#[wasm_bindgen(js_name = generateKeyPair)]
pub fn wasm_generate_key_pair() -> WasmKeyPair {
    let kp = generate_key_pair(true);
    WasmKeyPair {
        public_key: kp.public_key,
        private_key: kp.private_key,
    }
}

#[wasm_bindgen(js_name = generateMessageKey)]
pub fn wasm_generate_message_key() -> String {
    let key = generate_message_encryption_key();
    let bytes = key.to_bytes();
    base64::encode(&bytes)
}

// ============================================================================
// Деривация ключей
// ============================================================================

#[wasm_bindgen(js_name = deriveKeyFromPassword)]
pub fn wasm_derive_key_from_password(password: &str, salt_b64: &str) -> Result<String, JsValue> {
    derive_key_from_password(password, salt_b64)
        .map(|key| {
            let bytes = key.to_bytes();
            base64::encode(&bytes)
        })
        .map_err(|e| JsValue::from_str(&format!("{}", e)))
}

#[wasm_bindgen(js_name = deriveKeyFromString)]
pub fn wasm_derive_key_from_string(secret: &str) -> Result<String, JsValue> {
    derive_key_from_string(secret)
        .map(|key| {
            let bytes = key.to_bytes();
            base64::encode(&bytes)
        })
        .map_err(|e| JsValue::from_str(&format!("{}", e)))
}

// ============================================================================
// Шифрование/дешифрование данных
// ============================================================================

#[wasm_bindgen(js_name = encryptData)]
pub fn wasm_encrypt_data(data: &str, key_b64: &str) -> Result<String, JsValue> {
    let key_bytes = base64::decode(key_b64).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    let key = AeadKey::from_bytes(&key_bytes).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    encrypt_data(data, &key).map_err(|e| JsValue::from_str(&format!("{}", e)))
}

#[wasm_bindgen(js_name = decryptData)]
pub fn wasm_decrypt_data(encrypted_b64: &str, key_b64: &str) -> Result<String, JsValue> {
    let key_bytes = base64::decode(key_b64).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    let key = AeadKey::from_bytes(&key_bytes).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    decrypt_data(encrypted_b64, &key).map_err(|e| JsValue::from_str(&format!("{}", e)))
}

// ============================================================================
// Шифрование/дешифрование сообщений
// ============================================================================

#[wasm_bindgen(js_name = encryptMessage)]
pub fn wasm_encrypt_message(message: &str, key_b64: &str) -> Result<WasmEncryptedMessage, JsValue> {
    let key_bytes = base64::decode(key_b64).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    let key = AeadKey::from_bytes(&key_bytes).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    
    encrypt_message(message, &key)
        .map(|enc| WasmEncryptedMessage {
            ciphertext: enc.ciphertext,
            nonce: enc.nonce,
        })
        .map_err(|e| JsValue::from_str(&format!("{}", e)))
}

#[wasm_bindgen(js_name = decryptMessage)]
pub fn wasm_decrypt_message(
    ciphertext_b64: &str,
    nonce_b64: &str,
    key_b64: &str,
) -> Result<String, JsValue> {
    let key_bytes = base64::decode(key_b64).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    let key = AeadKey::from_bytes(&key_bytes).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    
    decrypt_message(ciphertext_b64, nonce_b64, &key)
        .map_err(|e| JsValue::from_str(&format!("{}", e)))
}

// ============================================================================
// Шифрование/дешифрование файлов
// ============================================================================

#[wasm_bindgen(js_name = encryptFile)]
pub fn wasm_encrypt_file(
    bytes: &[u8],
    filename: &str,
    mimetype: &str,
    key_b64: &str,
) -> Result<WasmEncryptedFile, JsValue> {
    let key_bytes = base64::decode(key_b64).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    let key = AeadKey::from_bytes(&key_bytes).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    
    encrypt_file(bytes, filename, mimetype, &key)
        .map(|enc| WasmEncryptedFile {
            ciphertext: enc.ciphertext,
            nonce: enc.nonce,
            filename: enc.filename,
            mimetype: enc.mimetype,
        })
        .map_err(|e| JsValue::from_str(&format!("{}", e)))
}

#[wasm_bindgen(js_name = decryptFile)]
pub fn wasm_decrypt_file(
    ciphertext_b64: &str,
    nonce_b64: &str,
    key_b64: &str,
) -> Result<Vec<u8>, JsValue> {
    let key_bytes = base64::decode(key_b64).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    let key = AeadKey::from_bytes(&key_bytes).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    
    decrypt_file(ciphertext_b64, nonce_b64, &key)
        .map_err(|e| JsValue::from_str(&format!("{}", e)))
}

#[wasm_bindgen(js_name = encryptFileWithMessage)]
pub fn wasm_encrypt_file_with_message(
    bytes: &[u8],
    message: &str,
    filename: &str,
    mimetype: &str,
    key_b64: &str,
) -> Result<JsValue, JsValue> {
    let key_bytes = base64::decode(key_b64).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    let key = AeadKey::from_bytes(&key_bytes).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    
    encrypt_file_with_message(bytes, message, &key, filename, mimetype)
        .map(|enc| {
            to_value(&enc).unwrap_or(JsValue::NULL)
        })
        .map_err(|e| JsValue::from_str(&format!("{}", e)))
}

#[wasm_bindgen(js_name = decryptFileWithMessage)]
pub fn wasm_decrypt_file_with_message(
    enc_file_b64: &str,
    ciphertext_b64: &str,
    nonce_b64: &str,
    filename: &str,
    mimetype: &str,
    key_b64: &str,
) -> Result<WasmDecryptedFile, JsValue> {
    let key_bytes = base64::decode(key_b64).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    let key = AeadKey::from_bytes(&key_bytes).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    
    decrypt_file_with_message(enc_file_b64, ciphertext_b64, nonce_b64, &key, filename, mimetype)
        .map(|dec| WasmDecryptedFile {
            data: dec.file,
            filename: dec.filename,
            mimetype: dec.mimetype,
            message: dec.message,
        })
        .map_err(|e| JsValue::from_str(&format!("{}", e)))
}

// ============================================================================
// Wrap/Unwrap symmetric key
// ============================================================================

#[wasm_bindgen(js_name = wrapSymmetricKey)]
pub fn wasm_wrap_symmetric_key(
    key_b64: &str,
    receiver_public_key_b64: &str,
) -> Result<WasmWrappedKey, JsValue> {
    let key_bytes = base64::decode(key_b64).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    let key = AeadKey::from_bytes(&key_bytes).map_err(|e| JsValue::from_str(&format!("{}", e)))?;
    
    wrap_symmetric_key(&key, receiver_public_key_b64)
        .map(|(wrapped, eph_pk, nonce)| WasmWrappedKey {
            wrapped_key: wrapped,
            ephemeral_public_key: eph_pk,
            nonce,
        })
        .map_err(|e| JsValue::from_str(&format!("{}", e)))
}

#[wasm_bindgen(js_name = unwrapSymmetricKey)]
pub fn wasm_unwrap_symmetric_key(
    wrapped_key_b64: &str,
    ephemeral_public_key_b64: &str,
    nonce_b64: &str,
    receiver_private_key_b64: &str,
) -> Result<String, JsValue> {
    unwrap_symmetric_key(
        wrapped_key_b64,
        ephemeral_public_key_b64,
        nonce_b64,
        receiver_private_key_b64,
    )
    .map(|key| {
        let bytes = key.to_bytes();
        base64::encode(&bytes)
    })
    .map_err(|e| JsValue::from_str(&format!("{}", e)))
}