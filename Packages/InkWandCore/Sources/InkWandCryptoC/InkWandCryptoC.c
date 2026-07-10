#include "InkWandCryptoC.h"

#if INKWAND_USE_OPENSSL
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#include <string.h>

int inkwand_random_bytes(uint8_t *out, size_t out_len) {
    return RAND_bytes(out, (int)out_len) == 1;
}

int inkwand_x25519_generate(uint8_t public_key[32], uint8_t private_key[32]) {
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_X25519, NULL);
    EVP_PKEY *key = NULL;
    size_t public_len = 32;
    size_t private_len = 32;
    int ok = 0;

    if (ctx != NULL &&
        EVP_PKEY_keygen_init(ctx) == 1 &&
        EVP_PKEY_keygen(ctx, &key) == 1 &&
        EVP_PKEY_get_raw_public_key(key, public_key, &public_len) == 1 &&
        EVP_PKEY_get_raw_private_key(key, private_key, &private_len) == 1 &&
        public_len == 32 &&
        private_len == 32) {
        ok = 1;
    }

    EVP_PKEY_free(key);
    EVP_PKEY_CTX_free(ctx);
    return ok;
}

int inkwand_x25519_shared(const uint8_t private_key[32], const uint8_t public_key[32], uint8_t shared_secret[32]) {
    EVP_PKEY *private_pkey = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, private_key, 32);
    EVP_PKEY *public_pkey = EVP_PKEY_new_raw_public_key(EVP_PKEY_X25519, NULL, public_key, 32);
    EVP_PKEY_CTX *ctx = NULL;
    size_t shared_len = 32;
    int ok = 0;

    if (private_pkey != NULL && public_pkey != NULL) {
        ctx = EVP_PKEY_CTX_new(private_pkey, NULL);
        if (ctx != NULL &&
            EVP_PKEY_derive_init(ctx) == 1 &&
            EVP_PKEY_derive_set_peer(ctx, public_pkey) == 1 &&
            EVP_PKEY_derive(ctx, shared_secret, &shared_len) == 1 &&
            shared_len == 32) {
            ok = 1;
        }
    }

    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(private_pkey);
    EVP_PKEY_free(public_pkey);
    return ok;
}

int inkwand_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *data, size_t data_len, uint8_t out[32]) {
    unsigned int out_len = 0;
    unsigned char *result = HMAC(EVP_sha256(), key, (int)key_len, data, data_len, out, &out_len);
    return result != NULL && out_len == 32;
}

int inkwand_aes_256_gcm_encrypt(
    const uint8_t key[32],
    const uint8_t nonce[12],
    const uint8_t *plaintext,
    size_t plaintext_len,
    uint8_t *ciphertext,
    uint8_t tag[16]
) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    int len = 0;
    int out_len = 0;
    int ok = 0;

    if (ctx != NULL &&
        EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) == 1 &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL) == 1 &&
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, nonce) == 1 &&
        EVP_EncryptUpdate(ctx, ciphertext, &len, plaintext, (int)plaintext_len) == 1) {
        out_len = len;
        if (EVP_EncryptFinal_ex(ctx, ciphertext + out_len, &len) == 1 &&
            EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag) == 1) {
            ok = 1;
        }
    }

    EVP_CIPHER_CTX_free(ctx);
    return ok;
}

int inkwand_aes_256_gcm_decrypt(
    const uint8_t key[32],
    const uint8_t nonce[12],
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    const uint8_t tag[16],
    uint8_t *plaintext
) {
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    int len = 0;
    int out_len = 0;
    int ok = 0;

    if (ctx != NULL &&
        EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) == 1 &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL) == 1 &&
        EVP_DecryptInit_ex(ctx, NULL, NULL, key, nonce) == 1 &&
        EVP_DecryptUpdate(ctx, plaintext, &len, ciphertext, (int)ciphertext_len) == 1) {
        out_len = len;
        (void)out_len;
        if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, (void *)tag) == 1 &&
            EVP_DecryptFinal_ex(ctx, plaintext + len, &len) == 1) {
            ok = 1;
        }
    }

    EVP_CIPHER_CTX_free(ctx);
    return ok;
}
#else
int inkwand_random_bytes(uint8_t *out, size_t out_len) { return 0; }
int inkwand_x25519_generate(uint8_t public_key[32], uint8_t private_key[32]) { return 0; }
int inkwand_x25519_shared(const uint8_t private_key[32], const uint8_t public_key[32], uint8_t shared_secret[32]) { return 0; }
int inkwand_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *data, size_t data_len, uint8_t out[32]) { return 0; }
int inkwand_aes_256_gcm_encrypt(const uint8_t key[32], const uint8_t nonce[12], const uint8_t *plaintext, size_t plaintext_len, uint8_t *ciphertext, uint8_t tag[16]) { return 0; }
int inkwand_aes_256_gcm_decrypt(const uint8_t key[32], const uint8_t nonce[12], const uint8_t *ciphertext, size_t ciphertext_len, const uint8_t tag[16], uint8_t *plaintext) { return 0; }
#endif
