#ifndef EXTERIA_CRYPTO_H
#define EXTERIA_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_bytes.h"
#include "exteria_status.h"

/* openssl stays behind this boundary so protocol code builds against 1.1.1 and 3.x */

#define EXTERIA_SHA1_LEN 20
#define EXTERIA_SHA256_LEN 32
#define EXTERIA_MD5_LEN 16

exteria_status exteria_sha1(const exteria_slice *parts, size_t count, uint8_t out[EXTERIA_SHA1_LEN]);
exteria_status exteria_sha256(const exteria_slice *parts, size_t count, uint8_t out[EXTERIA_SHA256_LEN]);
exteria_status exteria_md5(const exteria_slice *parts, size_t count, uint8_t out[EXTERIA_MD5_LEN]);

/* the message is the parts joined, at most EXTERIA_HMAC_MAX_MESSAGE bytes (EXTERIA_E_LIMIT above that) */
#define EXTERIA_HMAC_MAX_MESSAGE 4096
exteria_status exteria_hmac_sha1(const uint8_t *key, size_t key_len, const exteria_slice *parts, size_t count,
                                 uint8_t out[EXTERIA_SHA1_LEN]);

/* AES-128 in counter mode over len bytes, the whole 16 byte iv being the first counter block. in and out may be the same */
exteria_status exteria_aes128_ctr(const uint8_t key[16], const uint8_t iv[16], const uint8_t *in, uint8_t *out, size_t len);

exteria_status exteria_sha1_one(const void *data, size_t len, uint8_t out[EXTERIA_SHA1_LEN]);
exteria_status exteria_sha256_one(const void *data, size_t len, uint8_t out[EXTERIA_SHA256_LEN]);

/* the WireGuard primitives: the curve25519 function of RFC 7748 and the AEAD of RFC 8439 with a 12 byte nonce */
#define EXTERIA_X25519_LEN 32
#define EXTERIA_CHACHA_KEY_LEN 32
#define EXTERIA_CHACHA_NONCE_LEN 12
#define EXTERIA_POLY1305_TAG_LEN 16

/* the public key of a private key (which need not be clamped) */
exteria_status exteria_x25519_public(const uint8_t priv[EXTERIA_X25519_LEN], uint8_t pub[EXTERIA_X25519_LEN]);
/* the shared secret; EXTERIA_E_SECURITY when the peer key is a point of small order (the secret would be all zeros) */
exteria_status exteria_x25519_shared(const uint8_t priv[EXTERIA_X25519_LEN], const uint8_t peer[EXTERIA_X25519_LEN], uint8_t out[EXTERIA_X25519_LEN]);

/* out holds len bytes and may be the same buffer as in; ad may be empty */
exteria_status exteria_chacha20poly1305_seal(const uint8_t key[EXTERIA_CHACHA_KEY_LEN], const uint8_t nonce[EXTERIA_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             uint8_t tag[EXTERIA_POLY1305_TAG_LEN]);
/* EXTERIA_E_SECURITY when the tag does not match; out is wiped then */
exteria_status exteria_chacha20poly1305_open(const uint8_t key[EXTERIA_CHACHA_KEY_LEN], const uint8_t nonce[EXTERIA_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             const uint8_t tag[EXTERIA_POLY1305_TAG_LEN]);

exteria_status exteria_pbkdf2_sha512(const uint8_t *password, size_t password_len,
                                     const uint8_t *salt, size_t salt_len,
                                     uint32_t iterations, uint8_t *out, size_t out_len);

exteria_status exteria_aes_ige(const uint8_t key[32], const uint8_t iv[32], int encrypt,
                               const uint8_t *in, uint8_t *out, size_t len);

typedef struct exteria_digest exteria_digest;
exteria_digest *exteria_digest_new(int sha256);
exteria_status exteria_digest_update(exteria_digest *digest, const void *data, size_t len);
exteria_status exteria_digest_finish(exteria_digest *digest, uint8_t *out, size_t cap);
void exteria_digest_free(exteria_digest *digest);

typedef struct exteria_aes_ctr exteria_aes_ctr;
exteria_aes_ctr *exteria_aes_ctr_new(const uint8_t key[32], const uint8_t iv[16]);
exteria_status exteria_aes_ctr_apply(exteria_aes_ctr *ctr, const uint8_t *in, uint8_t *out, size_t len);
void exteria_aes_ctr_free(exteria_aes_ctr *ctr);

typedef struct exteria_bn exteria_bn;

exteria_bn *exteria_bn_from_bin(const uint8_t *be, size_t len);
exteria_bn *exteria_bn_from_u64(uint64_t value);
void exteria_bn_free(exteria_bn *bn);
size_t exteria_bn_bits(const exteria_bn *bn);
size_t exteria_bn_bytes(const exteria_bn *bn);
int exteria_bn_cmp(const exteria_bn *a, const exteria_bn *b);
int exteria_bn_is_zero(const exteria_bn *bn);
exteria_status exteria_bn_to_bin_padded(const exteria_bn *bn, uint8_t *out, size_t len);
exteria_status exteria_bn_to_bin(const exteria_bn *bn, uint8_t *out, size_t cap, size_t *len);
exteria_bn *exteria_bn_add(const exteria_bn *a, const exteria_bn *b);
exteria_bn *exteria_bn_sub(const exteria_bn *a, const exteria_bn *b);
exteria_bn *exteria_bn_mul(const exteria_bn *a, const exteria_bn *b);
exteria_bn *exteria_bn_mod(const exteria_bn *a, const exteria_bn *m);
exteria_bn *exteria_bn_mod_add(const exteria_bn *a, const exteria_bn *b, const exteria_bn *m);
exteria_bn *exteria_bn_mod_sub(const exteria_bn *a, const exteria_bn *b, const exteria_bn *m);
exteria_bn *exteria_bn_mod_mul(const exteria_bn *a, const exteria_bn *b, const exteria_bn *m);
exteria_bn *exteria_bn_mod_exp(const exteria_bn *base, const exteria_bn *exp, const exteria_bn *m);
exteria_bn *exteria_bn_mod_exp_secret(const exteria_bn *base, const exteria_bn *exp, const exteria_bn *m);
exteria_bn *exteria_bn_rshift1(const exteria_bn *a);
uint32_t exteria_bn_mod_word(const exteria_bn *a, uint32_t word);
int exteria_bn_is_prime(const exteria_bn *a);

exteria_status exteria_rsa_public_raw(const uint8_t *n, size_t n_len, uint32_t e,
                                      const uint8_t *in, size_t in_len, uint8_t *out);

#endif
