#include "exteria_blake2s.h"
#include "exteria_crypto.h"
#include "shiro_vectors.h"
#include "test_util.h"

static void pattern(uint8_t *out, size_t n, unsigned seed) {
    size_t i;
    for (i = 0; i < n; ++i) out[i] = (uint8_t)((i * 7 + seed) & 0xFF);
}

static void blake2s_against_hashlib(void) {
    size_t i;
    for (i = 0; i < sizeof(blake_vectors) / sizeof(blake_vectors[0]); ++i) {
        const blake_vector *v = &blake_vectors[i];
        uint8_t data[1000], out[32], key[32];
        exteria_blake2s_ctx ctx;
        size_t pos, step;
        pattern(data, v->data_len, 5);
        memcpy(key, v->key, sizeof(key));
        CHECK_EQ_INT(exteria_blake2s(out, v->out_len, v->key_len ? key : NULL, v->key_len, data, v->data_len), EXTERIA_OK);
        CHECK_MEM(out, v->expect, v->out_len);
        /* the same input in pieces of every awkward size, since the block boundary decides when the buffer is compressed */
        for (step = 1; step <= 130; step += 17) {
            CHECK_EQ_INT(exteria_blake2s_init(&ctx, v->out_len, v->key_len ? key : NULL, v->key_len), EXTERIA_OK);
            for (pos = 0; pos < v->data_len; pos += step) exteria_blake2s_update(&ctx, data + pos, v->data_len - pos < step ? v->data_len - pos : step);
            exteria_blake2s_final(&ctx, out);
            CHECK_MEM(out, v->expect, v->out_len);
        }
    }
}

static void blake2s_rfc_abc(void) {
    /* RFC 7693 appendix B */
    static const uint8_t expect[32] = {0x50, 0x8c, 0x5e, 0x8c, 0x32, 0x7c, 0x14, 0xe2, 0xe1, 0xa7, 0x2b, 0xa3, 0x4e, 0xeb, 0x45, 0x2f,
                                       0x37, 0x45, 0x8b, 0x20, 0x9e, 0xd6, 0x3a, 0x29, 0x4d, 0x99, 0x9b, 0x4c, 0x86, 0x67, 0x59, 0x82};
    uint8_t out[32];
    CHECK_EQ_INT(exteria_blake2s(out, 32, NULL, 0, "abc", 3), EXTERIA_OK);
    CHECK_MEM(out, expect, 32);
}

static void blake2s_bad_arguments(void) {
    uint8_t out[32], key[33] = {0};
    exteria_blake2s_ctx ctx;
    CHECK_EQ_INT(exteria_blake2s_init(&ctx, 0, NULL, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_blake2s_init(&ctx, 33, NULL, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_blake2s_init(&ctx, 32, key, 33), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_blake2s_init(&ctx, 32, NULL, 4), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_blake2s(NULL, 32, NULL, 0, "a", 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_blake2s(out, 32, NULL, 0, NULL, 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_blake2s_hmac(out, key, 65, "a", 1), EXTERIA_E_ARG);
}

static void hmac_against_python(void) {
    size_t i;
    for (i = 0; i < sizeof(hmac_vectors) / sizeof(hmac_vectors[0]); ++i) {
        const hmac_vector *v = &hmac_vectors[i];
        uint8_t data[300], out[32];
        pattern(data, v->data_len, 11);
        CHECK_EQ_INT(exteria_blake2s_hmac(out, v->key_len ? v->key : NULL, v->key_len, data, v->data_len), EXTERIA_OK);
        CHECK_MEM(out, v->expect, 32);
    }
}

static void x25519_vectors_agree(void) {
    size_t i;
    for (i = 0; i < sizeof(x25519_vectors) / sizeof(x25519_vectors[0]); ++i) {
        const x25519_vector *v = &x25519_vectors[i];
        uint8_t pub[32], shared[32];
        CHECK_EQ_INT(exteria_x25519_public(v->priv, pub), EXTERIA_OK);
        CHECK_MEM(pub, v->pub, 32);
        CHECK_EQ_INT(exteria_x25519_shared(v->priv, v->peer, shared), EXTERIA_OK);
        CHECK_MEM(shared, v->shared, 32);
    }
}

static void x25519_rejects_small_order(void) {
    uint8_t priv[32], zero[32] = {0}, one[32] = {1}, out[32];
    pattern(priv, 32, 40);
    /* the all zero point and the point of order one give an all zero secret, which would make the handshake keys public */
    memset(out, 0xAA, sizeof(out));
    CHECK_EQ_INT(exteria_x25519_shared(priv, zero, out), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(out[0], 0);
    CHECK_EQ_INT(exteria_x25519_shared(priv, one, out), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_x25519_shared(NULL, one, out), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_x25519_public(priv, NULL), EXTERIA_E_ARG);
}

static void aead_vectors_agree(void) {
    size_t i;
    for (i = 0; i < sizeof(aead_vectors) / sizeof(aead_vectors[0]); ++i) {
        const aead_vector *v = &aead_vectors[i];
        uint8_t out[200], tag[16], back[200];
        CHECK_EQ_INT(exteria_chacha20poly1305_seal(v->key, v->nonce, v->ad_len ? v->ad : NULL, v->ad_len, v->plain, v->len, out, tag), EXTERIA_OK);
        CHECK_MEM(out, v->cipher, v->len);
        CHECK_MEM(tag, v->tag, 16);
        CHECK_EQ_INT(exteria_chacha20poly1305_open(v->key, v->nonce, v->ad_len ? v->ad : NULL, v->ad_len, v->cipher, v->len, back, v->tag), EXTERIA_OK);
        CHECK_MEM(back, v->plain, v->len);
        /* in place, as the transport path uses it */
        memcpy(back, v->cipher, v->len);
        CHECK_EQ_INT(exteria_chacha20poly1305_open(v->key, v->nonce, v->ad_len ? v->ad : NULL, v->ad_len, back, v->len, back, v->tag), EXTERIA_OK);
        CHECK_MEM(back, v->plain, v->len);
    }
}

static void aead_detects_tampering(void) {
    const aead_vector *v = &aead_vectors[4];
    uint8_t out[200], bad_tag[16], bad_ad[64], bad_nonce[12], bad_cipher[200];
    size_t i;
    memcpy(bad_tag, v->tag, 16);
    bad_tag[15] ^= 1;
    memset(out, 0x55, sizeof(out));
    CHECK_EQ_INT(exteria_chacha20poly1305_open(v->key, v->nonce, v->ad, v->ad_len, v->cipher, v->len, out, bad_tag), EXTERIA_E_SECURITY);
    for (i = 0; i < v->len; ++i) CHECK_EQ_INT(out[i], 0);
    memcpy(bad_ad, v->ad, sizeof(bad_ad));
    bad_ad[0] ^= 1;
    CHECK_EQ_INT(exteria_chacha20poly1305_open(v->key, v->nonce, bad_ad, v->ad_len, v->cipher, v->len, out, v->tag), EXTERIA_E_SECURITY);
    memcpy(bad_nonce, v->nonce, 12);
    bad_nonce[11] ^= 1;
    CHECK_EQ_INT(exteria_chacha20poly1305_open(v->key, bad_nonce, v->ad, v->ad_len, v->cipher, v->len, out, v->tag), EXTERIA_E_SECURITY);
    memcpy(bad_cipher, v->cipher, sizeof(bad_cipher));
    bad_cipher[0] ^= 0x80;
    CHECK_EQ_INT(exteria_chacha20poly1305_open(v->key, v->nonce, v->ad, v->ad_len, bad_cipher, v->len, out, v->tag), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_chacha20poly1305_open(NULL, v->nonce, v->ad, v->ad_len, v->cipher, v->len, out, v->tag), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_chacha20poly1305_open(v->key, v->nonce, v->ad, v->ad_len, v->cipher, v->len, out, NULL), EXTERIA_E_ARG);
}

int main(void) {
    blake2s_against_hashlib();
    blake2s_rfc_abc();
    blake2s_bad_arguments();
    hmac_against_python();
    x25519_vectors_agree();
    x25519_rejects_small_order();
    aead_vectors_agree();
    aead_detects_tampering();
    return test_finish("test_shiro_crypto");
}
