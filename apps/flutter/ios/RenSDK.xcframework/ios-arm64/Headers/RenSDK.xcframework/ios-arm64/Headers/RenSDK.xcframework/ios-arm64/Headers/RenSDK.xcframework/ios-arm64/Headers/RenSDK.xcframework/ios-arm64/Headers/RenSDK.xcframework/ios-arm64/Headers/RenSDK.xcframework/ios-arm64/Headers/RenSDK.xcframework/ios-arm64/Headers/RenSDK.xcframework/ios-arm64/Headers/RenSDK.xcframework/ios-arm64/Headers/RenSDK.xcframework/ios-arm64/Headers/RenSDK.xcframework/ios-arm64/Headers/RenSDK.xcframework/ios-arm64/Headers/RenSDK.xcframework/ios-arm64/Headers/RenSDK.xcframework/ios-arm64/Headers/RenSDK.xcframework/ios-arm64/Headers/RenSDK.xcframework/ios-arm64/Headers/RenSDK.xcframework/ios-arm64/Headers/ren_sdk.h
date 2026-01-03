#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct REN_RenKeyPair {
  char *public_key;
  char *private_key;
} REN_RenKeyPair;

typedef struct REN_RenEncryptedMessage {
  char *ciphertext;
  char *nonce;
} REN_RenEncryptedMessage;

typedef struct REN_RenEncryptedFile {
  char *ciphertext;
  char *nonce;
  char *filename;
  char *mimetype;
} REN_RenEncryptedFile;

typedef struct REN_RenWrappedKey {
  char *wrapped_key;
  char *ephemeral_public_key;
  char *nonce;
} REN_RenWrappedKey;

typedef struct REN_RenDecryptedFile {
  uint8_t *data;
  uintptr_t len;
  char *filename;
  char *mimetype;
  char *message;
} REN_RenDecryptedFile;

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * Освобождает строку, выделенную в Rust и переданную в C
 */
void ren_free_string(char *aS);

/**
 * Освобождает массив байт, выделенный в Rust
 */
void ren_free_bytes(uint8_t *aPtr, uintptr_t aLen);

void ren_free_key_pair(struct REN_RenKeyPair aKp);

void ren_free_encrypted_message(struct REN_RenEncryptedMessage aMsg);

void ren_free_encrypted_file(struct REN_RenEncryptedFile aFile);

void ren_free_wrapped_key(struct REN_RenWrappedKey aWk);

void ren_free_decrypted_file(struct REN_RenDecryptedFile aFile);

char *ren_generate_nonce(void);

char *ren_generate_salt(void);

struct REN_RenKeyPair ren_generate_key_pair(void);

char *ren_generate_message_key(void);

char *ren_derive_key_from_password(const char *aPassword, const char *aSaltB64);

char *ren_derive_key_from_string(const char *aSecret);

char *ren_encrypt_data(const char *aData, const char *aKeyB64);

char *ren_decrypt_data(const char *aEncryptedB64, const char *aKeyB64);

struct REN_RenEncryptedMessage ren_encrypt_message(const char *aMessage, const char *aKeyB64);

char *ren_decrypt_message(const char *aCiphertextB64, const char *aNonceB64, const char *aKeyB64);

struct REN_RenEncryptedFile ren_encrypt_file(const uint8_t *aData,
                                             uintptr_t aLen,
                                             const char *aFilename,
                                             const char *aMimetype,
                                             const char *aKeyB64);

uint8_t *ren_decrypt_file(const char *aCiphertextB64,
                          const char *aNonceB64,
                          const char *aKeyB64,
                          uintptr_t *aOutLen);

struct REN_RenWrappedKey ren_wrap_symmetric_key(const char *aKeyB64,
                                                const char *aReceiverPublicKeyB64);

char *ren_unwrap_symmetric_key(const char *aWrappedKeyB64,
                               const char *aEphemeralPublicKeyB64,
                               const char *aNonceB64,
                               const char *aReceiverPrivateKeyB64);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus
