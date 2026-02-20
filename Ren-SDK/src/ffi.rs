use base64::{engine::general_purpose, Engine as _};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, UnwindSafe};
use std::ptr;
use zeroize::Zeroize;

use crate::crypto::{
    decrypt_data, decrypt_file, decrypt_file_raw, decrypt_message, derive_key_from_password,
    derive_key_from_string, encrypt_data, encrypt_file, encrypt_message, generate_key_pair,
    generate_message_encryption_key, generate_nonce, generate_salt, unwrap_symmetric_key,
    wrap_symmetric_key,
};

// ============================================================================
// Helper functions для работы со строками C
// ============================================================================

fn c_str_to_str<'a>(c_str: *const c_char) -> Option<&'a str> {
    if c_str.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(c_str).to_str().ok() }
}

fn rust_str_to_c(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c_string) => c_string.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn ffi_catch<T, F>(default: T, f: F) -> T
where
    F: FnOnce() -> T + UnwindSafe,
{
    match catch_unwind(f) {
        Ok(v) => v,
        Err(_) => default,
    }
}

fn empty_key_pair() -> RenKeyPair {
    RenKeyPair {
        public_key: ptr::null_mut(),
        private_key: ptr::null_mut(),
    }
}

fn empty_encrypted_message() -> RenEncryptedMessage {
    RenEncryptedMessage {
        ciphertext: ptr::null_mut(),
        nonce: ptr::null_mut(),
    }
}

fn empty_encrypted_file() -> RenEncryptedFile {
    RenEncryptedFile {
        ciphertext: ptr::null_mut(),
        nonce: ptr::null_mut(),
        filename: ptr::null_mut(),
        mimetype: ptr::null_mut(),
    }
}

fn empty_wrapped_key() -> RenWrappedKey {
    RenWrappedKey {
        wrapped_key: ptr::null_mut(),
        ephemeral_public_key: ptr::null_mut(),
        nonce: ptr::null_mut(),
    }
}

/// Освобождает строку, выделенную в Rust и переданную в C
#[no_mangle]
pub extern "C" fn ren_free_string(s: *mut c_char) {
    ffi_catch((), || {
        if !s.is_null() {
            unsafe {
                let _ = CString::from_raw(s);
            }
        }
    })
}

/// Освобождает массив байт, выделенный в Rust
#[no_mangle]
pub extern "C" fn ren_free_bytes(ptr: *mut u8, len: usize) {
    ffi_catch((), || {
        if !ptr.is_null() {
            unsafe {
                let _ = Vec::from_raw_parts(ptr, len, len);
            }
        }
    })
}

// ============================================================================
// Структуры для FFI
// ============================================================================

#[repr(C)]
pub struct RenKeyPair {
    pub public_key: *mut c_char,
    pub private_key: *mut c_char,
}

#[no_mangle]
pub extern "C" fn ren_free_key_pair(kp: RenKeyPair) {
    ffi_catch((), || {
        ren_free_string(kp.public_key);
        ren_free_string(kp.private_key);
    })
}

#[repr(C)]
pub struct RenEncryptedMessage {
    pub ciphertext: *mut c_char,
    pub nonce: *mut c_char,
}

#[no_mangle]
pub extern "C" fn ren_free_encrypted_message(msg: RenEncryptedMessage) {
    ffi_catch((), || {
        ren_free_string(msg.ciphertext);
        ren_free_string(msg.nonce);
    })
}

#[repr(C)]
pub struct RenEncryptedFile {
    pub ciphertext: *mut c_char,
    pub nonce: *mut c_char,
    pub filename: *mut c_char,
    pub mimetype: *mut c_char,
}

#[no_mangle]
pub extern "C" fn ren_free_encrypted_file(file: RenEncryptedFile) {
    ffi_catch((), || {
        ren_free_string(file.ciphertext);
        ren_free_string(file.nonce);
        ren_free_string(file.filename);
        ren_free_string(file.mimetype);
    })
}

#[repr(C)]
pub struct RenWrappedKey {
    pub wrapped_key: *mut c_char,
    pub ephemeral_public_key: *mut c_char,
    pub nonce: *mut c_char,
}

#[no_mangle]
pub extern "C" fn ren_free_wrapped_key(wk: RenWrappedKey) {
    ffi_catch((), || {
        ren_free_string(wk.wrapped_key);
        ren_free_string(wk.ephemeral_public_key);
        ren_free_string(wk.nonce);
    })
}

#[repr(C)]
pub struct RenDecryptedFile {
    pub data: *mut u8,
    pub len: usize,
    pub filename: *mut c_char,
    pub mimetype: *mut c_char,
    pub message: *mut c_char,
}

#[no_mangle]
pub extern "C" fn ren_free_decrypted_file(file: RenDecryptedFile) {
    ffi_catch((), || {
        ren_free_bytes(file.data, file.len);
        ren_free_string(file.filename);
        ren_free_string(file.mimetype);
        ren_free_string(file.message);
    })
}

// ============================================================================
// Генерация ключей и случайных значений
// ============================================================================

#[no_mangle]
pub extern "C" fn ren_generate_nonce() -> *mut c_char {
    ffi_catch(ptr::null_mut(), || rust_str_to_c(generate_nonce()))
}

#[no_mangle]
pub extern "C" fn ren_generate_salt() -> *mut c_char {
    ffi_catch(ptr::null_mut(), || rust_str_to_c(generate_salt()))
}

#[no_mangle]
pub extern "C" fn ren_generate_key_pair() -> RenKeyPair {
    ffi_catch(empty_key_pair(), || {
        let kp = generate_key_pair(true);
        RenKeyPair {
            public_key: rust_str_to_c(kp.public_key),
            private_key: rust_str_to_c(kp.private_key),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_generate_message_key() -> *mut c_char {
    ffi_catch(ptr::null_mut(), || {
        let key = generate_message_encryption_key();
        let mut bytes = key.to_bytes();
        let out = rust_str_to_c(general_purpose::STANDARD.encode(&bytes));
        bytes.zeroize();
        out
    })
}

// ============================================================================
// Деривация ключей
// ============================================================================

#[no_mangle]
pub extern "C" fn ren_derive_key_from_password(
    password: *const c_char,
    salt_b64: *const c_char,
) -> *mut c_char {
    ffi_catch(ptr::null_mut(), || {
        let pwd = match c_str_to_str(password) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let salt = match c_str_to_str(salt_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        match derive_key_from_password(&pwd, &salt) {
            Ok(key) => {
                let mut bytes = key.to_bytes();
                let out = rust_str_to_c(general_purpose::STANDARD.encode(&bytes));
                bytes.zeroize();
                out
            }
            Err(_) => ptr::null_mut(),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_derive_key_from_string(secret: *const c_char) -> *mut c_char {
    ffi_catch(ptr::null_mut(), || {
        let s = match c_str_to_str(secret) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        match derive_key_from_string(&s) {
            Ok(key) => {
                let mut bytes = key.to_bytes();
                let out = rust_str_to_c(general_purpose::STANDARD.encode(&bytes));
                bytes.zeroize();
                out
            }
            Err(_) => ptr::null_mut(),
        }
    })
}

// ============================================================================
// Шифрование/дешифрование данных
// ============================================================================

#[no_mangle]
pub extern "C" fn ren_encrypt_data(data: *const c_char, key_b64: *const c_char) -> *mut c_char {
    ffi_catch(ptr::null_mut(), || {
        let data_str = match c_str_to_str(data) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let key_str = match c_str_to_str(key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        let mut key_bytes = match general_purpose::STANDARD.decode(&key_str) {
            Ok(b) => b,
            Err(_) => return ptr::null_mut(),
        };
        let key = match crate::crypto::types::AeadKey::from_bytes(&key_bytes) {
            Ok(k) => k,
            Err(_) => return ptr::null_mut(),
        };
        key_bytes.zeroize();

        match encrypt_data(&data_str, &key) {
            Ok(encrypted) => rust_str_to_c(encrypted),
            Err(_) => ptr::null_mut(),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_decrypt_data(
    encrypted_b64: *const c_char,
    key_b64: *const c_char,
) -> *mut c_char {
    ffi_catch(ptr::null_mut(), || {
        let enc_str = match c_str_to_str(encrypted_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let key_str = match c_str_to_str(key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        let mut key_bytes = match general_purpose::STANDARD.decode(&key_str) {
            Ok(b) => b,
            Err(_) => return ptr::null_mut(),
        };
        let key = match crate::crypto::types::AeadKey::from_bytes(&key_bytes) {
            Ok(k) => k,
            Err(_) => return ptr::null_mut(),
        };
        key_bytes.zeroize();

        match decrypt_data(&enc_str, &key) {
            Ok(decrypted) => rust_str_to_c(decrypted),
            Err(_) => ptr::null_mut(),
        }
    })
}

// ============================================================================
// Шифрование/дешифрование сообщений
// ============================================================================

#[no_mangle]
pub extern "C" fn ren_encrypt_message(
    message: *const c_char,
    key_b64: *const c_char,
) -> RenEncryptedMessage {
    ffi_catch(empty_encrypted_message(), || {
        let msg = match c_str_to_str(message) {
            Some(s) => s,
            None => return empty_encrypted_message(),
        };
        let key_str = match c_str_to_str(key_b64) {
            Some(s) => s,
            None => return empty_encrypted_message(),
        };

        let mut key_bytes = match general_purpose::STANDARD.decode(&key_str) {
            Ok(b) => b,
            Err(_) => return empty_encrypted_message(),
        };
        let key = match crate::crypto::types::AeadKey::from_bytes(&key_bytes) {
            Ok(k) => k,
            Err(_) => return empty_encrypted_message(),
        };
        key_bytes.zeroize();

        match encrypt_message(&msg, &key) {
            Ok(enc) => RenEncryptedMessage {
                ciphertext: rust_str_to_c(enc.ciphertext),
                nonce: rust_str_to_c(enc.nonce),
            },
            Err(_) => empty_encrypted_message(),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_decrypt_message(
    ciphertext_b64: *const c_char,
    nonce_b64: *const c_char,
    key_b64: *const c_char,
) -> *mut c_char {
    ffi_catch(ptr::null_mut(), || {
        let ct = match c_str_to_str(ciphertext_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let nonce = match c_str_to_str(nonce_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let key_str = match c_str_to_str(key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        let mut key_bytes = match general_purpose::STANDARD.decode(&key_str) {
            Ok(b) => b,
            Err(_) => return ptr::null_mut(),
        };
        let key = match crate::crypto::types::AeadKey::from_bytes(&key_bytes) {
            Ok(k) => k,
            Err(_) => return ptr::null_mut(),
        };
        key_bytes.zeroize();

        match decrypt_message(&ct, &nonce, &key) {
            Ok(msg) => rust_str_to_c(msg),
            Err(_) => ptr::null_mut(),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_decrypt_message_with_key_bytes(
    ciphertext_b64: *const c_char,
    nonce_b64: *const c_char,
    key_ptr: *const u8,
    key_len: usize,
) -> *mut c_char {
    ffi_catch(ptr::null_mut(), || {
        if key_ptr.is_null() {
            return ptr::null_mut();
        }

        let ct = match c_str_to_str(ciphertext_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let nonce = match c_str_to_str(nonce_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        let key_bytes = unsafe { std::slice::from_raw_parts(key_ptr, key_len) };
        let key = match crate::crypto::types::AeadKey::from_bytes(key_bytes) {
            Ok(k) => k,
            Err(_) => return ptr::null_mut(),
        };

        match decrypt_message(&ct, &nonce, &key) {
            Ok(msg) => rust_str_to_c(msg),
            Err(_) => ptr::null_mut(),
        }
    })
}

// ============================================================================
// Шифрование/дешифрование файлов
// ============================================================================

#[no_mangle]
pub extern "C" fn ren_encrypt_file(
    data: *const u8,
    len: usize,
    filename: *const c_char,
    mimetype: *const c_char,
    key_b64: *const c_char,
) -> RenEncryptedFile {
    ffi_catch(empty_encrypted_file(), || {
        if data.is_null() {
            return empty_encrypted_file();
        }

        let bytes = unsafe { std::slice::from_raw_parts(data, len) };
        let fname = c_str_to_str(filename).unwrap_or("");
        let mime = c_str_to_str(mimetype).unwrap_or("");
        let key_str = match c_str_to_str(key_b64) {
            Some(s) => s,
            None => return empty_encrypted_file(),
        };

        let mut key_bytes = match general_purpose::STANDARD.decode(&key_str) {
            Ok(b) => b,
            Err(_) => return empty_encrypted_file(),
        };
        let key = match crate::crypto::types::AeadKey::from_bytes(&key_bytes) {
            Ok(k) => k,
            Err(_) => return empty_encrypted_file(),
        };
        key_bytes.zeroize();

        match encrypt_file(bytes, &fname, &mime, &key) {
            Ok(enc) => RenEncryptedFile {
                ciphertext: rust_str_to_c(enc.ciphertext),
                nonce: rust_str_to_c(enc.nonce),
                filename: rust_str_to_c(enc.filename),
                mimetype: rust_str_to_c(enc.mimetype),
            },
            Err(_) => empty_encrypted_file(),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_decrypt_file(
    ciphertext_b64: *const c_char,
    nonce_b64: *const c_char,
    key_b64: *const c_char,
    out_len: *mut usize,
) -> *mut u8 {
    ffi_catch(ptr::null_mut(), || {
        if out_len.is_null() {
            return ptr::null_mut();
        }

        let ct = match c_str_to_str(ciphertext_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let nonce = match c_str_to_str(nonce_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let key_str = match c_str_to_str(key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        let mut key_bytes = match general_purpose::STANDARD.decode(&key_str) {
            Ok(b) => b,
            Err(_) => return ptr::null_mut(),
        };
        let key = match crate::crypto::types::AeadKey::from_bytes(&key_bytes) {
            Ok(k) => k,
            Err(_) => return ptr::null_mut(),
        };
        key_bytes.zeroize();

        match decrypt_file(&ct, &nonce, &key) {
            Ok(bytes) => {
                let len = bytes.len();
                let mut v = bytes;
                let ptr = v.as_mut_ptr();
                std::mem::forget(v);
                unsafe {
                    *out_len = len;
                }
                ptr
            }
            Err(_) => ptr::null_mut(),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_decrypt_file_raw(
    ciphertext_ptr: *const u8,
    ciphertext_len: usize,
    nonce_b64: *const c_char,
    key_b64: *const c_char,
    out_len: *mut usize,
) -> *mut u8 {
    ffi_catch(ptr::null_mut(), || {
        if out_len.is_null() {
            return ptr::null_mut();
        }
        if ciphertext_ptr.is_null() {
            return ptr::null_mut();
        }

        let nonce = match c_str_to_str(nonce_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let key_str = match c_str_to_str(key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        let mut key_bytes = match general_purpose::STANDARD.decode(&key_str) {
            Ok(b) => b,
            Err(_) => return ptr::null_mut(),
        };
        let key = match crate::crypto::types::AeadKey::from_bytes(&key_bytes) {
            Ok(k) => k,
            Err(_) => return ptr::null_mut(),
        };
        key_bytes.zeroize();

        let ct = unsafe { std::slice::from_raw_parts(ciphertext_ptr, ciphertext_len) };

        match decrypt_file_raw(ct, &nonce, &key) {
            Ok(bytes) => {
                let len = bytes.len();
                let mut v = bytes;
                let ptr = v.as_mut_ptr();
                std::mem::forget(v);
                unsafe {
                    *out_len = len;
                }
                ptr
            }
            Err(_) => ptr::null_mut(),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_decrypt_file_raw_with_key_bytes(
    ciphertext_ptr: *const u8,
    ciphertext_len: usize,
    nonce_b64: *const c_char,
    key_ptr: *const u8,
    key_len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    ffi_catch(ptr::null_mut(), || {
        if out_len.is_null() {
            return ptr::null_mut();
        }
        if ciphertext_ptr.is_null() {
            return ptr::null_mut();
        }
        if key_ptr.is_null() {
            return ptr::null_mut();
        }

        let nonce = match c_str_to_str(nonce_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        let key_bytes = unsafe { std::slice::from_raw_parts(key_ptr, key_len) };
        let key = match crate::crypto::types::AeadKey::from_bytes(key_bytes) {
            Ok(k) => k,
            Err(_) => return ptr::null_mut(),
        };

        let ct = unsafe { std::slice::from_raw_parts(ciphertext_ptr, ciphertext_len) };

        match decrypt_file_raw(ct, &nonce, &key) {
            Ok(bytes) => {
                let len = bytes.len();
                let mut v = bytes;
                let ptr = v.as_mut_ptr();
                std::mem::forget(v);
                unsafe {
                    *out_len = len;
                }
                ptr
            }
            Err(_) => ptr::null_mut(),
        }
    })
}

// ============================================================================
// Wrap/Unwrap symmetric key
// ============================================================================

#[no_mangle]
pub extern "C" fn ren_wrap_symmetric_key(
    key_b64: *const c_char,
    receiver_public_key_b64: *const c_char,
) -> RenWrappedKey {
    ffi_catch(empty_wrapped_key(), || {
        let key_str = match c_str_to_str(key_b64) {
            Some(s) => s,
            None => return empty_wrapped_key(),
        };
        let recv_pk = match c_str_to_str(receiver_public_key_b64) {
            Some(s) => s,
            None => return empty_wrapped_key(),
        };

        let mut key_bytes = match general_purpose::STANDARD.decode(&key_str) {
            Ok(b) => b,
            Err(_) => return empty_wrapped_key(),
        };
        let key = match crate::crypto::types::AeadKey::from_bytes(&key_bytes) {
            Ok(k) => k,
            Err(_) => return empty_wrapped_key(),
        };
        key_bytes.zeroize();

        match wrap_symmetric_key(&key, &recv_pk) {
            Ok((wrapped, eph_pk, nonce)) => RenWrappedKey {
                wrapped_key: rust_str_to_c(wrapped),
                ephemeral_public_key: rust_str_to_c(eph_pk),
                nonce: rust_str_to_c(nonce),
            },
            Err(_) => empty_wrapped_key(),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_unwrap_symmetric_key(
    wrapped_key_b64: *const c_char,
    ephemeral_public_key_b64: *const c_char,
    nonce_b64: *const c_char,
    receiver_private_key_b64: *const c_char,
) -> *mut c_char {
    ffi_catch(ptr::null_mut(), || {
        let wrapped = match c_str_to_str(wrapped_key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let eph_pk = match c_str_to_str(ephemeral_public_key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let nonce = match c_str_to_str(nonce_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let recv_sk = match c_str_to_str(receiver_private_key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        match unwrap_symmetric_key(&wrapped, &eph_pk, &nonce, &recv_sk) {
            Ok(key) => {
                let mut bytes = key.to_bytes();
                let out = rust_str_to_c(general_purpose::STANDARD.encode(&bytes));
                bytes.zeroize();
                out
            }
            Err(_) => ptr::null_mut(),
        }
    })
}

#[no_mangle]
pub extern "C" fn ren_unwrap_symmetric_key_bytes(
    wrapped_key_b64: *const c_char,
    ephemeral_public_key_b64: *const c_char,
    nonce_b64: *const c_char,
    receiver_private_key_b64: *const c_char,
    out_len: *mut usize,
) -> *mut u8 {
    ffi_catch(ptr::null_mut(), || {
        if out_len.is_null() {
            return ptr::null_mut();
        }

        let wrapped = match c_str_to_str(wrapped_key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let eph_pk = match c_str_to_str(ephemeral_public_key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let nonce = match c_str_to_str(nonce_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };
        let recv_sk = match c_str_to_str(receiver_private_key_b64) {
            Some(s) => s,
            None => return ptr::null_mut(),
        };

        match unwrap_symmetric_key(&wrapped, &eph_pk, &nonce, &recv_sk) {
            Ok(key) => {
                let mut bytes = key.to_bytes();
                let mut v = bytes.to_vec();
                bytes.zeroize();
                let len = v.len();
                let ptr = v.as_mut_ptr();
                std::mem::forget(v);
                unsafe {
                    *out_len = len;
                }
                ptr
            }
            Err(_) => ptr::null_mut(),
        }
    })
}
