#pragma once

#include <stddef.h>
#include <stdint.h>

int inkwand_random_bytes(uint8_t *out, size_t out_len);
int inkwand_x25519_generate(uint8_t public_key[32], uint8_t private_key[32]);
int inkwand_x25519_shared(const uint8_t private_key[32], const uint8_t public_key[32], uint8_t shared_secret[32]);
int inkwand_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *data, size_t data_len, uint8_t out[32]);
int inkwand_aes_256_gcm_encrypt(
    const uint8_t key[32],
    const uint8_t nonce[12],
    const uint8_t *plaintext,
    size_t plaintext_len,
    uint8_t *ciphertext,
    uint8_t tag[16]
);
int inkwand_aes_256_gcm_decrypt(
    const uint8_t key[32],
    const uint8_t nonce[12],
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    const uint8_t tag[16],
    uint8_t *plaintext
);
