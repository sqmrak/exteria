#include "exteria_crypto.h"

#include <stdlib.h>
#include <string.h>

#include <openssl/bn.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/opensslv.h>

static exteria_status digest_parts(const EVP_MD *md, const exteria_slice *parts, size_t count,
                                   uint8_t *out, unsigned expected) {
    EVP_MD_CTX *ctx;
    unsigned got = 0;
    size_t i;
    exteria_status status = EXTERIA_E_CRYPTO;
    if (!md || !out || (count && !parts)) return EXTERIA_E_ARG;
    ctx = EVP_MD_CTX_new();
    if (!ctx) return EXTERIA_E_NOMEM;
    if (EVP_DigestInit_ex(ctx, md, NULL) != 1) goto done;
    for (i = 0; i < count; ++i) {
        if (parts[i].len == 0) continue;
        if (!parts[i].data || EVP_DigestUpdate(ctx, parts[i].data, parts[i].len) != 1) goto done;
    }
    if (EVP_DigestFinal_ex(ctx, out, &got) != 1 || got != expected) goto done;
    status = EXTERIA_OK;
done:
    EVP_MD_CTX_free(ctx);
    return status;
}

exteria_status exteria_sha1(const exteria_slice *parts, size_t count, uint8_t out[EXTERIA_SHA1_LEN]) {
    return digest_parts(EVP_sha1(), parts, count, out, EXTERIA_SHA1_LEN);
}

exteria_status exteria_sha256(const exteria_slice *parts, size_t count, uint8_t out[EXTERIA_SHA256_LEN]) {
    return digest_parts(EVP_sha256(), parts, count, out, EXTERIA_SHA256_LEN);
}

exteria_status exteria_md5(const exteria_slice *parts, size_t count, uint8_t out[EXTERIA_MD5_LEN]) {
    return digest_parts(EVP_md5(), parts, count, out, EXTERIA_MD5_LEN);
}

exteria_status exteria_sha1_one(const void *data, size_t len, uint8_t out[EXTERIA_SHA1_LEN]) {
    exteria_slice part;
    part.data = (const uint8_t *)data;
    part.len = len;
    return exteria_sha1(&part, 1, out);
}

exteria_status exteria_sha256_one(const void *data, size_t len, uint8_t out[EXTERIA_SHA256_LEN]) {
    exteria_slice part;
    part.data = (const uint8_t *)data;
    part.len = len;
    return exteria_sha256(&part, 1, out);
}

exteria_status exteria_hmac_sha1(const uint8_t *key, size_t key_len, const exteria_slice *parts, size_t count,
                                 uint8_t out[EXTERIA_SHA1_LEN]) {
    uint8_t joined[EXTERIA_HMAC_MAX_MESSAGE];
    size_t used = 0, i;
    unsigned got = 0;
    if (!out || (key_len && !key) || (count && !parts) || key_len > 0x7fffffffu) return EXTERIA_E_ARG;
    for (i = 0; i < count; ++i) {
        if (parts[i].len == 0) continue;
        if (!parts[i].data) return EXTERIA_E_ARG;
        if (parts[i].len > sizeof(joined) - used) return EXTERIA_E_LIMIT;
        memcpy(joined + used, parts[i].data, parts[i].len);
        used += parts[i].len;
    }
    if (!HMAC(EVP_sha1(), key ? key : (const uint8_t *)"", (int)key_len, joined, used, out, &got) || got != EXTERIA_SHA1_LEN) return EXTERIA_E_CRYPTO;
    return EXTERIA_OK;
}

exteria_status exteria_aes128_ctr(const uint8_t key[16], const uint8_t iv[16], const uint8_t *in, uint8_t *out, size_t len) {
    EVP_CIPHER_CTX *ctx;
    size_t done = 0;
    exteria_status status = EXTERIA_E_CRYPTO;
    if (!key || !iv || (len && (!in || !out))) return EXTERIA_E_ARG;
    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return EXTERIA_E_NOMEM;
    if (EVP_EncryptInit_ex(ctx, EVP_aes_128_ctr(), NULL, key, iv) != 1) goto done;
    while (done < len) {
        size_t step = len - done;
        int outl = 0;
        if (step > 0x40000000u) step = 0x40000000u;
        if (EVP_EncryptUpdate(ctx, out + done, &outl, in + done, (int)step) != 1 || (size_t)outl != step) goto done;
        done += step;
    }
    status = EXTERIA_OK;
done:
    EVP_CIPHER_CTX_free(ctx);
    return status;
}

exteria_status exteria_x25519_public(const uint8_t priv[EXTERIA_X25519_LEN], uint8_t pub[EXTERIA_X25519_LEN]) {
    EVP_PKEY *key;
    size_t len = EXTERIA_X25519_LEN;
    exteria_status status = EXTERIA_E_CRYPTO;
    if (!priv || !pub) return EXTERIA_E_ARG;
    key = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, priv, EXTERIA_X25519_LEN);
    if (!key) return EXTERIA_E_CRYPTO;
    if (EVP_PKEY_get_raw_public_key(key, pub, &len) == 1 && len == EXTERIA_X25519_LEN) status = EXTERIA_OK;
    EVP_PKEY_free(key);
    return status;
}

exteria_status exteria_x25519_shared(const uint8_t priv[EXTERIA_X25519_LEN], const uint8_t peer[EXTERIA_X25519_LEN], uint8_t out[EXTERIA_X25519_LEN]) {
    EVP_PKEY *own, *other;
    EVP_PKEY_CTX *ctx = NULL;
    size_t len = EXTERIA_X25519_LEN;
    uint8_t zero = 0;
    size_t i;
    exteria_status status = EXTERIA_E_CRYPTO;
    if (!priv || !peer || !out) return EXTERIA_E_ARG;
    own = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, priv, EXTERIA_X25519_LEN);
    other = EVP_PKEY_new_raw_public_key(EVP_PKEY_X25519, NULL, peer, EXTERIA_X25519_LEN);
    if (!own || !other) goto done;
    ctx = EVP_PKEY_CTX_new(own, NULL);
    if (!ctx || EVP_PKEY_derive_init(ctx) != 1 || EVP_PKEY_derive_set_peer(ctx, other) != 1) goto done;
    /* with two well formed keys the only way derive fails is a peer point of small order, which openssl refuses */
    if (EVP_PKEY_derive(ctx, out, &len) != 1) {
        status = EXTERIA_E_SECURITY;
        goto done;
    }
    if (len != EXTERIA_X25519_LEN) goto done;
    for (i = 0; i < EXTERIA_X25519_LEN; ++i) zero |= out[i];
    if (zero == 0) {
        status = EXTERIA_E_SECURITY;
        goto done;
    }
    status = EXTERIA_OK;
done:
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(own);
    EVP_PKEY_free(other);
    if (status != EXTERIA_OK) exteria_wipe(out, EXTERIA_X25519_LEN);
    return status;
}

static exteria_status chacha_run(int encrypt, const uint8_t key[EXTERIA_CHACHA_KEY_LEN], const uint8_t nonce[EXTERIA_CHACHA_NONCE_LEN],
                                 const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out, uint8_t *tag) {
    EVP_CIPHER_CTX *ctx;
    uint8_t final_block[EXTERIA_POLY1305_TAG_LEN];
    int outl = 0;
    exteria_status status = EXTERIA_E_CRYPTO;
    if (!key || !nonce || (ad_len && !ad) || (len && (!in || !out)) || !tag || ad_len > 0x40000000u || len > 0x40000000u) return EXTERIA_E_ARG;
    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return EXTERIA_E_NOMEM;
    if (EVP_CipherInit_ex(ctx, EVP_chacha20_poly1305(), NULL, key, nonce, encrypt) != 1) goto done;
    if (!encrypt && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, EXTERIA_POLY1305_TAG_LEN, tag) != 1) goto done;
    if (ad_len && EVP_CipherUpdate(ctx, NULL, &outl, ad, (int)ad_len) != 1) goto done;
    if (len) {
        if (EVP_CipherUpdate(ctx, out, &outl, in, (int)len) != 1 || (size_t)outl != len) goto done;
    }
    if (EVP_CipherFinal_ex(ctx, final_block, &outl) != 1) {
        /* a decryption whose tag fails ends here, and nothing it produced may be used */
        status = encrypt ? EXTERIA_E_CRYPTO : EXTERIA_E_SECURITY;
        if (!encrypt && len) exteria_wipe(out, len);
        goto done;
    }
    if (encrypt && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, EXTERIA_POLY1305_TAG_LEN, tag) != 1) goto done;
    status = EXTERIA_OK;
done:
    EVP_CIPHER_CTX_free(ctx);
    return status;
}

exteria_status exteria_chacha20poly1305_seal(const uint8_t key[EXTERIA_CHACHA_KEY_LEN], const uint8_t nonce[EXTERIA_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             uint8_t tag[EXTERIA_POLY1305_TAG_LEN]) {
    return chacha_run(1, key, nonce, ad, ad_len, in, len, out, tag);
}

exteria_status exteria_chacha20poly1305_open(const uint8_t key[EXTERIA_CHACHA_KEY_LEN], const uint8_t nonce[EXTERIA_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             const uint8_t tag[EXTERIA_POLY1305_TAG_LEN]) {
    uint8_t copy[EXTERIA_POLY1305_TAG_LEN];
    exteria_status status;
    if (!tag) return EXTERIA_E_ARG;
    memcpy(copy, tag, sizeof(copy));
    status = chacha_run(0, key, nonce, ad, ad_len, in, len, out, copy);
    return status;
}

exteria_status exteria_pbkdf2_sha512(const uint8_t *password, size_t password_len,
                                     const uint8_t *salt, size_t salt_len,
                                     uint32_t iterations, uint8_t *out, size_t out_len) {
    if (!password || !salt || !out || iterations == 0 || out_len == 0) return EXTERIA_E_ARG;
    if (password_len > 0x7fffffffu || salt_len > 0x7fffffffu || out_len > 0x7fffffffu) return EXTERIA_E_LIMIT;
    if (PKCS5_PBKDF2_HMAC((const char *)password, (int)password_len, salt, (int)salt_len,
                          (int)iterations, EVP_sha512(), (int)out_len, out) != 1) return EXTERIA_E_CRYPTO;
    return EXTERIA_OK;
}

/* evp has no ige mode, so chaining must use its ecb block primitive */
exteria_status exteria_aes_ige(const uint8_t key[32], const uint8_t iv[32], int encrypt,
                               const uint8_t *in, uint8_t *out, size_t len) {
    EVP_CIPHER_CTX *ctx;
    uint8_t prev_c[16], prev_p[16], block[16], res[16];
    size_t off;
    int outl;
    unsigned i;
    exteria_status status = EXTERIA_E_CRYPTO;
    if (!key || !iv || (len && (!in || !out)) || (len % 16) != 0) return EXTERIA_E_ARG;
    if (len == 0) return EXTERIA_OK;
    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return EXTERIA_E_NOMEM;
    if (EVP_CipherInit_ex(ctx, EVP_aes_256_ecb(), NULL, key, NULL, encrypt ? 1 : 0) != 1) goto done;
    EVP_CIPHER_CTX_set_padding(ctx, 0);
    memcpy(prev_c, iv, 16);
    memcpy(prev_p, iv + 16, 16);
    for (off = 0; off < len; off += 16) {
        memcpy(block, in + off, 16);
        if (encrypt) {
            uint8_t x[16];
            for (i = 0; i < 16; ++i) x[i] = (uint8_t)(block[i] ^ prev_c[i]);
            if (EVP_CipherUpdate(ctx, res, &outl, x, 16) != 1 || outl != 16) goto done;
            for (i = 0; i < 16; ++i) res[i] ^= prev_p[i];
            memcpy(prev_c, res, 16);
            memcpy(prev_p, block, 16);
        } else {
            uint8_t x[16];
            for (i = 0; i < 16; ++i) x[i] = (uint8_t)(block[i] ^ prev_p[i]);
            if (EVP_CipherUpdate(ctx, res, &outl, x, 16) != 1 || outl != 16) goto done;
            for (i = 0; i < 16; ++i) res[i] ^= prev_c[i];
            memcpy(prev_p, res, 16);
            memcpy(prev_c, block, 16);
        }
        memcpy(out + off, res, 16);
    }
    status = EXTERIA_OK;
done:
    exteria_wipe(prev_c, sizeof(prev_c));
    exteria_wipe(prev_p, sizeof(prev_p));
    exteria_wipe(block, sizeof(block));
    exteria_wipe(res, sizeof(res));
    EVP_CIPHER_CTX_free(ctx);
    return status;
}

struct exteria_aes_ctr {
    EVP_CIPHER_CTX *ctx;
};

exteria_aes_ctr *exteria_aes_ctr_new(const uint8_t key[32], const uint8_t iv[16]) {
    exteria_aes_ctr *c;
    if (!key || !iv) return NULL;
    c = (exteria_aes_ctr *)calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->ctx = EVP_CIPHER_CTX_new();
    if (!c->ctx || EVP_EncryptInit_ex(c->ctx, EVP_aes_256_ctr(), NULL, key, iv) != 1) {
        exteria_aes_ctr_free(c);
        return NULL;
    }
    return c;
}

exteria_status exteria_aes_ctr_apply(exteria_aes_ctr *ctr, const uint8_t *in, uint8_t *out, size_t len) {
    size_t done = 0;
    if (!ctr || (len && (!in || !out))) return EXTERIA_E_ARG;
    while (done < len) {
        size_t step = len - done;
        int outl = 0;
        if (step > 0x40000000u) step = 0x40000000u;
        if (EVP_EncryptUpdate(ctr->ctx, out + done, &outl, in + done, (int)step) != 1 || (size_t)outl != step)
            return EXTERIA_E_CRYPTO;
        done += step;
    }
    return EXTERIA_OK;
}

void exteria_aes_ctr_free(exteria_aes_ctr *ctr) {
    if (!ctr) return;
    EVP_CIPHER_CTX_free(ctr->ctx);
    free(ctr);
}

#define BNP(x) ((BIGNUM *)(x))
#define BNC(x) ((const BIGNUM *)(x))

exteria_bn *exteria_bn_from_bin(const uint8_t *be, size_t len) {
    if (len && !be) return NULL;
    if (len > 0x7fffffffu) return NULL;
    return (exteria_bn *)BN_bin2bn(be, (int)len, NULL);
}

exteria_bn *exteria_bn_from_u64(uint64_t value) {
    uint8_t b[8];
    exteria_put_u64be(b, value);
    return exteria_bn_from_bin(b, sizeof(b));
}

void exteria_bn_free(exteria_bn *bn) {
    BN_clear_free(BNP(bn));
}

size_t exteria_bn_bits(const exteria_bn *bn) {
    return (size_t)BN_num_bits(BNC(bn));
}

size_t exteria_bn_bytes(const exteria_bn *bn) {
    return (size_t)BN_num_bytes(BNC(bn));
}

int exteria_bn_cmp(const exteria_bn *a, const exteria_bn *b) {
    return BN_cmp(BNC(a), BNC(b));
}

int exteria_bn_is_zero(const exteria_bn *bn) {
    return BN_is_zero(BNC(bn)) ? 1 : 0;
}

exteria_status exteria_bn_to_bin_padded(const exteria_bn *bn, uint8_t *out, size_t len) {
    if (!bn || !out || len > 0x7fffffffu) return EXTERIA_E_ARG;
    if (exteria_bn_bytes(bn) > len) return EXTERIA_E_LIMIT;
    if (BN_bn2binpad(BNC(bn), out, (int)len) != (int)len) return EXTERIA_E_CRYPTO;
    return EXTERIA_OK;
}

exteria_status exteria_bn_to_bin(const exteria_bn *bn, uint8_t *out, size_t cap, size_t *len) {
    size_t n;
    if (!bn || !len) return EXTERIA_E_ARG;
    n = exteria_bn_bytes(bn);
    *len = n;
    if (n > cap) return EXTERIA_E_LIMIT;
    if (n && (!out || BN_bn2bin(BNC(bn), out) != (int)n)) return EXTERIA_E_CRYPTO;
    return EXTERIA_OK;
}

static exteria_bn *bn_result(BIGNUM *r, int ok) {
    if (!ok) {
        BN_clear_free(r);
        return NULL;
    }
    return (exteria_bn *)r;
}

exteria_bn *exteria_bn_add(const exteria_bn *a, const exteria_bn *b) {
    BIGNUM *r = BN_new();
    if (!r) return NULL;
    return bn_result(r, BN_add(r, BNC(a), BNC(b)));
}

exteria_bn *exteria_bn_sub(const exteria_bn *a, const exteria_bn *b) {
    BIGNUM *r;
    if (BN_cmp(BNC(a), BNC(b)) < 0) return NULL;
    r = BN_new();
    if (!r) return NULL;
    return bn_result(r, BN_sub(r, BNC(a), BNC(b)));
}

exteria_bn *exteria_bn_mul(const exteria_bn *a, const exteria_bn *b) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && BN_mul(r, BNC(a), BNC(b), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

exteria_bn *exteria_bn_mod(const exteria_bn *a, const exteria_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_nnmod(r, BNC(a), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

exteria_bn *exteria_bn_mod_add(const exteria_bn *a, const exteria_bn *b, const exteria_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_mod_add(r, BNC(a), BNC(b), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

exteria_bn *exteria_bn_mod_sub(const exteria_bn *a, const exteria_bn *b, const exteria_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_mod_sub(r, BNC(a), BNC(b), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

exteria_bn *exteria_bn_mod_mul(const exteria_bn *a, const exteria_bn *b, const exteria_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_mod_mul(r, BNC(a), BNC(b), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

exteria_bn *exteria_bn_mod_exp(const exteria_bn *base, const exteria_bn *exp, const exteria_bn *m) {
    BIGNUM *r = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    int ok = r && ctx && !BN_is_zero(BNC(m)) && BN_mod_exp(r, BNC(base), BNC(exp), BNC(m), ctx);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

exteria_bn *exteria_bn_mod_exp_secret(const exteria_bn *base, const exteria_bn *exp, const exteria_bn *m) {
    BIGNUM *r;
    BN_CTX *ctx;
    int ok;
    if (!base || !exp || !m || !BN_is_odd(BNC(m))) return NULL;
    r = BN_new();
    ctx = BN_CTX_new();
    /* dh and srp exponents must not choose a password-dependent multiplication schedule */
    ok = r && ctx && BN_mod_exp_mont_consttime(r, BNC(base), BNC(exp), BNC(m), ctx, NULL);
    BN_CTX_free(ctx);
    if (!r) return NULL;
    return bn_result(r, ok);
}

exteria_bn *exteria_bn_rshift1(const exteria_bn *a) {
    BIGNUM *r = BN_new();
    if (!r) return NULL;
    return bn_result(r, BN_rshift1(r, BNC(a)));
}

uint32_t exteria_bn_mod_word(const exteria_bn *a, uint32_t word) {
    BN_ULONG r;
    if (word == 0) return UINT32_MAX;
    r = BN_mod_word(BNC(a), word);
    if (r == (BN_ULONG)-1) return UINT32_MAX;
    return (uint32_t)r;
}

/* dh validation needs the same minimum 64 rounds with both supported openssl versions */
int exteria_bn_is_prime(const exteria_bn *a) {
    BN_CTX *ctx;
    int prime;
    if (!a) return 0;
    ctx = BN_CTX_new();
    if (!ctx) return 0;
#if OPENSSL_VERSION_NUMBER >= 0x30000000L
    prime = BN_check_prime(BNC(a), ctx, NULL) == 1;
#else
    prime = BN_is_prime_ex(BNC(a), 64, ctx, NULL) == 1;
#endif
    BN_CTX_free(ctx);
    return prime;
}

exteria_status exteria_rsa_public_raw(const uint8_t *n, size_t n_len, uint32_t e,
                                      const uint8_t *in, size_t in_len, uint8_t *out) {
    exteria_bn *bn_n = exteria_bn_from_bin(n, n_len);
    exteria_bn *bn_e = exteria_bn_from_u64(e);
    exteria_bn *bn_in = exteria_bn_from_bin(in, in_len);
    exteria_bn *r = NULL;
    exteria_status status = EXTERIA_E_CRYPTO;
    if (!bn_n || !bn_e || !bn_in) goto done;
    if (exteria_bn_cmp(bn_in, bn_n) >= 0) {
        status = EXTERIA_E_ARG;
        goto done;
    }
    r = exteria_bn_mod_exp(bn_in, bn_e, bn_n);
    if (!r) goto done;
    status = exteria_bn_to_bin_padded(r, out, n_len);
done:
    exteria_bn_free(bn_n);
    exteria_bn_free(bn_e);
    exteria_bn_free(bn_in);
    exteria_bn_free(r);
    return status;
}

struct exteria_digest {
    EVP_MD_CTX *ctx;
    size_t length;
    int done;
};

exteria_digest *exteria_digest_new(int sha256) {
    exteria_digest *digest = calloc(1, sizeof(*digest));
    if (!digest) return NULL;
    digest->ctx = EVP_MD_CTX_new();
    digest->length = sha256 ? 32u : 16u;
    if (!digest->ctx || EVP_DigestInit_ex(digest->ctx, sha256 ? EVP_sha256() : EVP_md5(), NULL) != 1) {
        exteria_digest_free(digest);
        return NULL;
    }
    return digest;
}

exteria_status exteria_digest_update(exteria_digest *digest, const void *data, size_t len) {
    if (!digest || (!data && len)) return EXTERIA_E_ARG;
    if (digest->done) return EXTERIA_E_STATE;
    return EVP_DigestUpdate(digest->ctx, data, len) == 1 ? EXTERIA_OK : EXTERIA_E_CRYPTO;
}

exteria_status exteria_digest_finish(exteria_digest *digest, uint8_t *out, size_t cap) {
    unsigned len = 0;
    if (!digest || !out) return EXTERIA_E_ARG;
    if (digest->done) return EXTERIA_E_STATE;
    if (cap < digest->length) return EXTERIA_E_LIMIT;
    digest->done = 1;
    if (EVP_DigestFinal_ex(digest->ctx, out, &len) != 1 || len != digest->length) return EXTERIA_E_CRYPTO;
    return EXTERIA_OK;
}

void exteria_digest_free(exteria_digest *digest) {
    if (!digest) return;
    EVP_MD_CTX_free(digest->ctx);
    free(digest);
}
