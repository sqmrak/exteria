#include "exteria_mt_handshake.h"

#include <stdlib.h>
#include <string.h>

#include "exteria_arena.h"
#include "exteria_crypto.h"
#include "exteria_random.h"
#include "exteria_tl.h"

#define DEFAULT_ATTEMPTS 3u
#define DH_BITS 2048u
#define DH_MARGIN_BITS 64u
#define INNER_MAX 144u
#define PAD_TOTAL 192u

/* the prime telegram has used for years, matching it skips two primality tests of a 2048 bit number */
static const uint8_t known_prime[256] = {
    0xc7, 0x1c, 0xae, 0xb9, 0xc6, 0xb1, 0xc9, 0x04, 0x8e, 0x6c, 0x52, 0x2f,
    0x70, 0xf1, 0x3f, 0x73, 0x98, 0x0d, 0x40, 0x23, 0x8e, 0x3e, 0x21, 0xc1,
    0x49, 0x34, 0xd0, 0x37, 0x56, 0x3d, 0x93, 0x0f, 0x48, 0x19, 0x8a, 0x0a,
    0xa7, 0xc1, 0x40, 0x58, 0x22, 0x94, 0x93, 0xd2, 0x25, 0x30, 0xf4, 0xdb,
    0xfa, 0x33, 0x6f, 0x6e, 0x0a, 0xc9, 0x25, 0x13, 0x95, 0x43, 0xae, 0xd4,
    0x4c, 0xce, 0x7c, 0x37, 0x20, 0xfd, 0x51, 0xf6, 0x94, 0x58, 0x70, 0x5a,
    0xc6, 0x8c, 0xd4, 0xfe, 0x6b, 0x6b, 0x13, 0xab, 0xdc, 0x97, 0x46, 0x51,
    0x29, 0x69, 0x32, 0x84, 0x54, 0xf1, 0x8f, 0xaf, 0x8c, 0x59, 0x5f, 0x64,
    0x24, 0x77, 0xfe, 0x96, 0xbb, 0x2a, 0x94, 0x1d, 0x5b, 0xcd, 0x1d, 0x4a,
    0xc8, 0xcc, 0x49, 0x88, 0x07, 0x08, 0xfa, 0x9b, 0x37, 0x8e, 0x3c, 0x4f,
    0x3a, 0x90, 0x60, 0xbe, 0xe6, 0x7c, 0xf9, 0xa4, 0xa4, 0xa6, 0x95, 0x81,
    0x10, 0x51, 0x90, 0x7e, 0x16, 0x27, 0x53, 0xb5, 0x6b, 0x0f, 0x6b, 0x41,
    0x0d, 0xba, 0x74, 0xd8, 0xa8, 0x4b, 0x2a, 0x14, 0xb3, 0x14, 0x4e, 0x0e,
    0xf1, 0x28, 0x47, 0x54, 0xfd, 0x17, 0xed, 0x95, 0x0d, 0x59, 0x65, 0xb4,
    0xb9, 0xdd, 0x46, 0x58, 0x2d, 0xb1, 0x17, 0x8d, 0x16, 0x9c, 0x6b, 0xc4,
    0x65, 0xb0, 0xd6, 0xff, 0x9c, 0xa3, 0x92, 0x8f, 0xef, 0x5b, 0x9a, 0xe4,
    0xe4, 0x18, 0xfc, 0x15, 0xe8, 0x3e, 0xbe, 0xa0, 0xf8, 0x7f, 0xa9, 0xff,
    0x5e, 0xed, 0x70, 0x05, 0x0d, 0xed, 0x28, 0x49, 0xf4, 0x7b, 0xf9, 0x59,
    0xd9, 0x56, 0x85, 0x0c, 0xe9, 0x29, 0x85, 0x1f, 0x0d, 0x81, 0x15, 0xf6,
    0x35, 0xb1, 0x05, 0xee, 0x2e, 0x4e, 0x15, 0xd0, 0x4b, 0x24, 0x54, 0xbf,
    0x6f, 0x4f, 0xad, 0xf0, 0x34, 0xb1, 0x04, 0x03, 0x11, 0x9c, 0xd8, 0xe3,
    0xb9, 0x2f, 0xcc, 0x5b,
};

static uint64_t addmod(uint64_t a, uint64_t b, uint64_t m) {
    return a >= m - b ? a - (m - b) : a + b;
}

/* shift and add keeps every intermediate below m, 128 bit products do not exist on armv7 */
static uint64_t mulmod(uint64_t a, uint64_t b, uint64_t m) {
    uint64_t r = 0;
    a %= m;
    while (b) {
        if (b & 1u) r = addmod(r, a, m);
        a = addmod(a, a, m);
        b >>= 1;
    }
    return r;
}

static uint64_t gcd64(uint64_t a, uint64_t b) {
    while (b) {
        uint64_t t = a % b;
        a = b;
        b = t;
    }
    return a;
}

static uint64_t absdiff(uint64_t a, uint64_t b) {
    return a > b ? a - b : b - a;
}

/* batching gcd calls keeps pq factorization cheap on armv7 */
static uint64_t rho(uint64_t n, uint64_t c, uint64_t *budget) {
    uint64_t x = 2, y = 2, ys = 2, q = 1, g = 1, r = 1;
    const uint64_t m = 128;
    do {
        uint64_t k = 0, i;
        x = y;
        for (i = 0; i < r; ++i) y = addmod(mulmod(y, y, n), c, n);
        do {
            uint64_t steps = r - k < m ? r - k : m;
            ys = y;
            for (i = 0; i < steps; ++i) {
                y = addmod(mulmod(y, y, n), c, n);
                q = mulmod(q, absdiff(x, y), n);
            }
            if (*budget < steps) return 0;
            *budget -= steps;
            g = gcd64(q, n);
            k += m;
        } while (k < r && g == 1);
        r *= 2;
    } while (g == 1);
    if (g == n) {
        do {
            ys = addmod(mulmod(ys, ys, n), c, n);
            g = gcd64(absdiff(x, ys), n);
        } while (g == 1);
    }
    return g == n ? 0 : g;
}

exteria_status exteria_mt_factor_pq(uint64_t pq, uint32_t *p, uint32_t *q) {
    uint64_t budget = 1u << 20;
    uint64_t c, f = 0;
    if (!p || !q) return EXTERIA_E_ARG;
    *p = 0;
    *q = 0;
    if (pq < 6) return EXTERIA_E_ARG;
    if ((pq & 1u) == 0) {
        f = 2;
    } else {
        /* rho never ends on a prime, and the server picks this number, so a prime must not cost the client seconds */
        exteria_bn *whole = exteria_bn_from_u64(pq);
        int prime = whole && exteria_bn_is_prime(whole);
        exteria_bn_free(whole);
        if (!whole) return EXTERIA_E_NOMEM;
        if (prime) return EXTERIA_E_MALFORMED;
        for (c = 1; c < 64 && f == 0; ++c) f = rho(pq, c, &budget);
    }
    if (f == 0) return EXTERIA_E_LIMIT;
    {
        uint64_t other = pq / f;
        uint64_t lo = f < other ? f : other;
        uint64_t hi = f < other ? other : f;
        if (lo * hi != pq || hi > 0xffffffffu) return EXTERIA_E_MALFORMED;
        *p = (uint32_t)lo;
        *q = (uint32_t)hi;
    }
    return EXTERIA_OK;
}

exteria_status exteria_mt_check_dh_prime(const uint8_t *prime, size_t len, uint32_t g) {
    exteria_bn *p = NULL, *half = NULL, *gb = NULL, *r = NULL, *one = NULL;
    exteria_status status = EXTERIA_E_SECURITY;
    if (!prime || g < 2 || g > 7 || len != DH_BITS / 8) return EXTERIA_E_SECURITY;
    if ((prime[0] & 0x80) == 0) return EXTERIA_E_SECURITY;
    p = exteria_bn_from_bin(prime, len);
    if (!p) return EXTERIA_E_NOMEM;
    half = exteria_bn_rshift1(p);
    if (!half) {
        status = EXTERIA_E_NOMEM;
        goto done;
    }
    if (memcmp(prime, known_prime, sizeof(known_prime)) != 0) {
        if (!exteria_bn_is_prime(p) || !exteria_bn_is_prime(half)) goto done;
    }
    /* g must generate the subgroup of prime order (p - 1) / 2 or the key leaks one bit */
    gb = exteria_bn_from_u64(g);
    one = exteria_bn_from_u64(1);
    if (!gb || !one) {
        status = EXTERIA_E_NOMEM;
        goto done;
    }
    r = exteria_bn_mod_exp(gb, half, p);
    if (!r) {
        status = EXTERIA_E_CRYPTO;
        goto done;
    }
    if (exteria_bn_cmp(r, one) == 0) status = EXTERIA_OK;
done:
    exteria_bn_free(p);
    exteria_bn_free(half);
    exteria_bn_free(gb);
    exteria_bn_free(r);
    exteria_bn_free(one);
    return status;
}

exteria_status exteria_mt_check_dh_value(const uint8_t *prime, size_t prime_len, const uint8_t *value, size_t value_len) {
    exteria_bn *p = exteria_bn_from_bin(prime, prime_len);
    exteria_bn *v = exteria_bn_from_bin(value, value_len);
    exteria_bn *diff = NULL;
    exteria_status status = EXTERIA_E_SECURITY;
    if (!p || !v) {
        status = EXTERIA_E_NOMEM;
        goto done;
    }
    if (exteria_bn_bits(v) < DH_BITS - DH_MARGIN_BITS || exteria_bn_cmp(v, p) >= 0) goto done;
    diff = exteria_bn_sub(p, v);
    if (!diff) goto done;
    if (exteria_bn_bits(diff) >= DH_BITS - DH_MARGIN_BITS) status = EXTERIA_OK;
done:
    exteria_bn_free(p);
    exteria_bn_free(v);
    exteria_bn_free(diff);
    return status;
}

/* rsa_pad from the mtproto docs: the plaintext is mixed with a one time key so a bare rsa operation never sees structured data */
exteria_status exteria_mt_rsa_pad_encrypt(const exteria_mt_rsa_key *key, const uint8_t *data, size_t len,
                                          uint8_t out[256]) {
    uint8_t padded[PAD_TOTAL], reversed[PAD_TOTAL];
    uint8_t temp_key[32], iv[32], digest[32], block[256], enc[PAD_TOTAL + 32];
    exteria_slice parts[2];
    exteria_status s;
    size_t i;
    if (!key || !data || !out || len == 0 || len > INNER_MAX || key->n_len != 256) return EXTERIA_E_ARG;
    memcpy(padded, data, len);
    s = exteria_random(padded + len, PAD_TOTAL - len);
    if (s != EXTERIA_OK) return s;
    for (i = 0; i < PAD_TOTAL; ++i) reversed[i] = padded[PAD_TOTAL - 1 - i];
    memset(iv, 0, sizeof(iv));
    for (;;) {
        s = exteria_random(temp_key, sizeof(temp_key));
        if (s != EXTERIA_OK) return s;
        parts[0].data = temp_key;
        parts[0].len = 32;
        parts[1].data = padded;
        parts[1].len = PAD_TOTAL;
        s = exteria_sha256(parts, 2, digest);
        if (s != EXTERIA_OK) return s;
        memcpy(enc, reversed, PAD_TOTAL);
        memcpy(enc + PAD_TOTAL, digest, 32);
        s = exteria_aes_ige(temp_key, iv, 1, enc, enc, sizeof(enc));
        if (s != EXTERIA_OK) return s;
        s = exteria_sha256_one(enc, sizeof(enc), digest);
        if (s != EXTERIA_OK) return s;
        for (i = 0; i < 32; ++i) block[i] = (uint8_t)(temp_key[i] ^ digest[i]);
        memcpy(block + 32, enc, sizeof(enc));
        /* the number handed to rsa has to be below the modulus or the server cannot recover it */
        if (memcmp(block, key->n, 256) < 0) break;
    }
    s = exteria_rsa_public_raw(key->n, key->n_len, key->e, block, sizeof(block), out);
    exteria_wipe(temp_key, sizeof(temp_key));
    exteria_wipe(padded, sizeof(padded));
    exteria_wipe(reversed, sizeof(reversed));
    exteria_wipe(block, sizeof(block));
    return s;
}

void exteria_mt_hs_init(exteria_mt_handshake *hs, const exteria_mt_hs_config *config) {
    size_t count = 0;
    memset(hs, 0, sizeof(*hs));
    hs->config = *config;
    if (!config->keys) {
        hs->config.keys = exteria_mt_default_keys(config->is_test, &count);
        hs->config.key_count = count;
    }
    if (!hs->config.clock) hs->config.clock = &exteria_system_clock;
    if (hs->config.max_attempts == 0) hs->config.max_attempts = DEFAULT_ATTEMPTS;
}

void exteria_mt_hs_wipe(exteria_mt_handshake *hs) {
    exteria_wipe(hs->new_nonce, sizeof(hs->new_nonce));
    exteria_wipe(hs->tmp_key, sizeof(hs->tmp_key));
    exteria_wipe(hs->tmp_iv, sizeof(hs->tmp_iv));
    exteria_wipe(hs->auth_key, sizeof(hs->auth_key));
}

static uint64_t clock_ms(const exteria_mt_handshake *hs) {
    return hs->config.clock->realtime_ms(hs->config.clock->ctx);
}

static exteria_status fail(exteria_mt_handshake *hs, exteria_status s) {
    hs->state = EXTERIA_MT_HS_FAILED;
    exteria_mt_hs_wipe(hs);
    return s;
}

static exteria_status send_plain(exteria_mt_handshake *hs, exteria_tl_value *request, exteria_writer *out) {
    exteria_writer body;
    exteria_status s;
    exteria_writer_init(&body, 4096);
    s = exteria_tl_encode(request, &body, NULL);
    if (s == EXTERIA_OK) {
        uint64_t id = exteria_mt_next_msg_id(clock_ms(hs), &hs->last_msg_id);
        s = exteria_mt_plain_wrap(id, body.data, body.len, out);
    }
    exteria_writer_free(&body);
    return s;
}

exteria_status exteria_mt_hs_start(exteria_mt_handshake *hs, exteria_writer *out) {
    exteria_arena a;
    exteria_tl_value *req;
    exteria_status s;
    if (!hs || !out) return EXTERIA_E_ARG;
    if (hs->state == EXTERIA_MT_HS_DONE) return EXTERIA_E_STATE;
    if (hs->config.key_count == 0 || !hs->config.keys) return EXTERIA_E_ARG;
    if (hs->state == EXTERIA_MT_HS_IDLE || hs->state == EXTERIA_MT_HS_FAILED) hs->attempts = 0;
    exteria_mt_hs_wipe(hs);
    s = exteria_random(hs->nonce, sizeof(hs->nonce));
    if (s != EXTERIA_OK) return fail(hs, s);
    exteria_arena_init(&a, 8192);
    req = exteria_tl_new_obj(&a, "req_pq_multi");
    s = req ? exteria_tl_set_bytes(&a, req, "nonce", hs->nonce, sizeof(hs->nonce)) : EXTERIA_E_NOMEM;
    if (s == EXTERIA_OK) s = send_plain(hs, req, out);
    exteria_arena_free(&a);
    if (s != EXTERIA_OK) return fail(hs, s);
    hs->state = EXTERIA_MT_HS_WAIT_RES_PQ;
    return EXTERIA_OK;
}

static exteria_status expect_nonces(const exteria_tl_value *v, const uint8_t *nonce, const uint8_t *server_nonce) {
    const uint8_t *p;
    size_t n;
    if (exteria_tl_get_bytes(v, "nonce", &p, &n) != EXTERIA_OK || n != 16) return EXTERIA_E_MALFORMED;
    if (!exteria_ct_equal(p, nonce, 16)) return EXTERIA_E_SECURITY;
    if (server_nonce) {
        if (exteria_tl_get_bytes(v, "server_nonce", &p, &n) != EXTERIA_OK || n != 16) return EXTERIA_E_MALFORMED;
        if (!exteria_ct_equal(p, server_nonce, 16)) return EXTERIA_E_SECURITY;
    }
    return EXTERIA_OK;
}

static uint16_t ref_of(const char *ctor) {
    const exteria_tl_ctor *c = exteria_tl_find_ctor_by_name(ctor);
    return c ? c->result : EXTERIA_TL_REF_ANY;
}

static exteria_status handle_res_pq(exteria_mt_handshake *hs, exteria_tl_value *v, exteria_arena *a, exteria_writer *out) {
    const uint8_t *pq_bytes, *sn;
    size_t pq_len, sn_len, i;
    const exteria_tl_value *fps;
    const exteria_mt_rsa_key *key = NULL;
    uint64_t pq = 0;
    uint32_t p, q;
    uint8_t p_be[4], q_be[4], enc[256];
    exteria_tl_value *inner, *req;
    exteria_writer inner_bytes;
    exteria_status s;
    if (!exteria_tl_is(v, 0x05162463u)) return EXTERIA_E_MALFORMED;
    s = expect_nonces(v, hs->nonce, NULL);
    if (s != EXTERIA_OK) return s;
    if (exteria_tl_get_bytes(v, "server_nonce", &sn, &sn_len) != EXTERIA_OK || sn_len != 16) return EXTERIA_E_MALFORMED;
    memcpy(hs->server_nonce, sn, 16);
    if (exteria_tl_get_bytes(v, "pq", &pq_bytes, &pq_len) != EXTERIA_OK || pq_len == 0 || pq_len > 8) return EXTERIA_E_MALFORMED;
    for (i = 0; i < pq_len; ++i) pq = (pq << 8) | pq_bytes[i];
    if (exteria_tl_get_vec(v, "server_public_key_fingerprints", &fps) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < fps->u.vec.count && !key; ++i) {
        key = exteria_mt_find_key(hs->config.keys, hs->config.key_count, (uint64_t)fps->u.vec.items[i]->u.i64);
    }
    if (!key) return EXTERIA_E_UNSUPPORTED;
    hs->key_fingerprint = key->fingerprint;
    s = exteria_mt_factor_pq(pq, &p, &q);
    if (s != EXTERIA_OK) return s;
    exteria_put_u32be(p_be, p);
    exteria_put_u32be(q_be, q);
    s = exteria_random(hs->new_nonce, sizeof(hs->new_nonce));
    if (s != EXTERIA_OK) return s;
    inner = exteria_tl_new_obj(a, "p_q_inner_data_dc");
    if (!inner) return EXTERIA_E_NOMEM;
    s = exteria_tl_set_bytes(a, inner, "pq", pq_bytes, pq_len);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, inner, "p", p_be, 4);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, inner, "q", q_be, 4);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, inner, "nonce", hs->nonce, 16);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, inner, "server_nonce", hs->server_nonce, 16);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, inner, "new_nonce", hs->new_nonce, 32);
    /* test dc ids must not overlap production ids in the rsa handshake */
    if (s == EXTERIA_OK) s = exteria_tl_set_i32(a, inner, "dc", hs->config.dc_id + (hs->config.is_test ? 10000 : 0));
    if (s != EXTERIA_OK) return s;
    exteria_writer_init(&inner_bytes, 512);
    s = exteria_tl_encode(inner, &inner_bytes, NULL);
    if (s == EXTERIA_OK) s = exteria_mt_rsa_pad_encrypt(key, inner_bytes.data, inner_bytes.len, enc);
    exteria_writer_free(&inner_bytes);
    if (s != EXTERIA_OK) return s;
    req = exteria_tl_new_obj(a, "req_DH_params");
    if (!req) return EXTERIA_E_NOMEM;
    s = exteria_tl_set_bytes(a, req, "nonce", hs->nonce, 16);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, req, "server_nonce", hs->server_nonce, 16);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, req, "p", p_be, 4);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, req, "q", q_be, 4);
    if (s == EXTERIA_OK) s = exteria_tl_set_i64(a, req, "public_key_fingerprint", (int64_t)key->fingerprint);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, req, "encrypted_data", enc, sizeof(enc));
    if (s != EXTERIA_OK) return s;
    s = send_plain(hs, req, out);
    if (s != EXTERIA_OK) return s;
    hs->state = EXTERIA_MT_HS_WAIT_DH_PARAMS;
    return EXTERIA_OK;
}

static exteria_status derive_tmp_key(exteria_mt_handshake *hs) {
    uint8_t h1[20], h2[20], h3[20];
    exteria_slice parts[2];
    exteria_status s;
    parts[0].data = hs->new_nonce;
    parts[0].len = 32;
    parts[1].data = hs->server_nonce;
    parts[1].len = 16;
    s = exteria_sha1(parts, 2, h1);
    if (s != EXTERIA_OK) return s;
    parts[0].data = hs->server_nonce;
    parts[0].len = 16;
    parts[1].data = hs->new_nonce;
    parts[1].len = 32;
    s = exteria_sha1(parts, 2, h2);
    if (s != EXTERIA_OK) return s;
    parts[0].data = hs->new_nonce;
    parts[0].len = 32;
    parts[1].data = hs->new_nonce;
    parts[1].len = 32;
    s = exteria_sha1(parts, 2, h3);
    if (s != EXTERIA_OK) return s;
    memcpy(hs->tmp_key, h1, 20);
    memcpy(hs->tmp_key + 20, h2, 12);
    memcpy(hs->tmp_iv, h2 + 12, 8);
    memcpy(hs->tmp_iv + 8, h3, 20);
    memcpy(hs->tmp_iv + 28, hs->new_nonce, 4);
    return EXTERIA_OK;
}

/* encrypted padding carries no length, so only a matching sha1 can locate the inner object */
static exteria_status open_answer(exteria_mt_handshake *hs, exteria_arena *a, const uint8_t *enc, size_t enc_len,
                                  const uint8_t **data, size_t *data_len) {
    uint8_t digest[20];
    uint8_t *plain = (uint8_t *)exteria_arena_alloc(a, enc_len);
    size_t i;
    exteria_status s;
    if (!plain) return EXTERIA_E_NOMEM;
    s = exteria_aes_ige(hs->tmp_key, hs->tmp_iv, 0, enc, plain, enc_len);
    if (s != EXTERIA_OK) return s;
    for (i = 0; i < 16; ++i) {
        s = exteria_sha1_one(plain + 20, enc_len - 20 - i, digest);
        if (s != EXTERIA_OK) return s;
        if (exteria_ct_equal(digest, plain, 20)) {
            *data = plain + 20;
            *data_len = enc_len - 20 - i;
            return EXTERIA_OK;
        }
    }
    return EXTERIA_E_SECURITY;
}

static exteria_status build_client_params(exteria_mt_handshake *hs, exteria_arena *a, const uint8_t *g_b, size_t g_b_len,
                                          exteria_writer *out) {
    exteria_tl_value *inner = exteria_tl_new_obj(a, "client_DH_inner_data");
    exteria_tl_value *req;
    exteria_writer buf;
    uint8_t digest[20];
    size_t data_len, pad;
    exteria_status s;
    if (!inner) return EXTERIA_E_NOMEM;
    s = exteria_tl_set_bytes(a, inner, "nonce", hs->nonce, 16);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, inner, "server_nonce", hs->server_nonce, 16);
    if (s == EXTERIA_OK) s = exteria_tl_set_i64(a, inner, "retry_id", 0);
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, inner, "g_b", g_b, g_b_len);
    if (s != EXTERIA_OK) return s;
    exteria_writer_init(&buf, 1024);
    s = exteria_wr_zero(&buf, 20);
    if (s == EXTERIA_OK) s = exteria_tl_encode(inner, &buf, NULL);
    if (s == EXTERIA_OK) {
        data_len = buf.len - 20;
        pad = (16u - buf.len % 16u) % 16u;
        s = exteria_sha1_one(buf.data + 20, data_len, digest);
        if (s == EXTERIA_OK) {
            memcpy(buf.data, digest, 20);
            s = exteria_wr_zero(&buf, pad);
        }
        if (s == EXTERIA_OK && pad) s = exteria_random(buf.data + buf.len - pad, pad);
        if (s == EXTERIA_OK) s = exteria_aes_ige(hs->tmp_key, hs->tmp_iv, 1, buf.data, buf.data, buf.len);
    }
    if (s == EXTERIA_OK) {
        req = exteria_tl_new_obj(a, "set_client_DH_params");
        s = req ? exteria_tl_set_bytes(a, req, "nonce", hs->nonce, 16) : EXTERIA_E_NOMEM;
        if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, req, "server_nonce", hs->server_nonce, 16);
        if (s == EXTERIA_OK) s = exteria_tl_set_bytes(a, req, "encrypted_data", buf.data, buf.len);
        if (s == EXTERIA_OK) s = send_plain(hs, req, out);
    }
    exteria_writer_free(&buf);
    return s;
}

static exteria_status handle_dh_params(exteria_mt_handshake *hs, exteria_tl_value *v, exteria_arena *a, exteria_writer *out) {
    const uint8_t *enc, *answer, *prime, *ga;
    size_t enc_len, answer_len, prime_len, ga_len, gb_len = 0, i;
    exteria_tl_value *inner = NULL;
    size_t consumed = 0;
    int32_t g = 0, server_time = 0;
    uint8_t b[256], gb_bytes[256], key_bytes[256];
    exteria_bn *bn_p = NULL, *bn_ga = NULL, *bn_b = NULL, *bn_g = NULL, *bn_gb = NULL, *bn_key = NULL;
    exteria_status s;
    if (exteria_tl_is(v, 0x79cb045du)) {
        s = expect_nonces(v, hs->nonce, hs->server_nonce);
        return s == EXTERIA_OK ? EXTERIA_E_SECURITY : s;
    }
    if (!exteria_tl_is(v, 0xd0e8075cu)) return EXTERIA_E_MALFORMED;
    s = expect_nonces(v, hs->nonce, hs->server_nonce);
    if (s != EXTERIA_OK) return s;
    if (exteria_tl_get_bytes(v, "encrypted_answer", &enc, &enc_len) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (enc_len < 48 || enc_len > 1024 || enc_len % 16) return EXTERIA_E_MALFORMED;
    s = derive_tmp_key(hs);
    if (s != EXTERIA_OK) return s;
    s = open_answer(hs, a, enc, enc_len, &answer, &answer_len);
    if (s != EXTERIA_OK) return s;
    s = exteria_tl_decode(a, NULL, ref_of("server_DH_inner_data"), answer, answer_len, &consumed, &inner);
    if (s != EXTERIA_OK) return s == EXTERIA_E_TRUNCATED ? EXTERIA_E_MALFORMED : s;
    s = expect_nonces(inner, hs->nonce, hs->server_nonce);
    if (s != EXTERIA_OK) return s;
    if (exteria_tl_get_i32(inner, "g", &g) != EXTERIA_OK || exteria_tl_get_i32(inner, "server_time", &server_time) != EXTERIA_OK ||
        exteria_tl_get_bytes(inner, "dh_prime", &prime, &prime_len) != EXTERIA_OK ||
        exteria_tl_get_bytes(inner, "g_a", &ga, &ga_len) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    s = exteria_mt_check_dh_prime(prime, prime_len, (uint32_t)g);
    if (s != EXTERIA_OK) return s;
    s = exteria_mt_check_dh_value(prime, prime_len, ga, ga_len);
    if (s != EXTERIA_OK) return s;
    s = exteria_random(b, sizeof(b));
    if (s != EXTERIA_OK) return s;
    bn_p = exteria_bn_from_bin(prime, prime_len);
    bn_ga = exteria_bn_from_bin(ga, ga_len);
    bn_b = exteria_bn_from_bin(b, sizeof(b));
    bn_g = exteria_bn_from_u64((uint32_t)g);
    exteria_wipe(b, sizeof(b));
    if (!bn_p || !bn_ga || !bn_b || !bn_g) {
        s = EXTERIA_E_NOMEM;
        goto done;
    }
    bn_gb = exteria_bn_mod_exp_secret(bn_g, bn_b, bn_p);
    bn_key = exteria_bn_mod_exp_secret(bn_ga, bn_b, bn_p);
    if (!bn_gb || !bn_key) {
        s = EXTERIA_E_CRYPTO;
        goto done;
    }
    s = exteria_bn_to_bin(bn_gb, gb_bytes, sizeof(gb_bytes), &gb_len);
    if (s == EXTERIA_OK) s = exteria_bn_to_bin_padded(bn_key, key_bytes, sizeof(key_bytes));
    if (s != EXTERIA_OK) goto done;
    /* the g_b sent back is range checked too, a small value would let the server pick the key */
    s = exteria_mt_check_dh_value(prime, prime_len, gb_bytes, gb_len);
    if (s != EXTERIA_OK) goto done;
    memcpy(hs->auth_key, key_bytes, sizeof(key_bytes));
    s = build_client_params(hs, a, gb_bytes, gb_len, out);
    if (s != EXTERIA_OK) goto done;
    hs->server_time = server_time;
    hs->time_offset_ms = (int64_t)server_time * 1000 - (int64_t)clock_ms(hs);
    hs->salt = 0;
    for (i = 0; i < 8; ++i) hs->salt |= (uint64_t)(hs->new_nonce[i] ^ hs->server_nonce[i]) << (8 * i);
    hs->state = EXTERIA_MT_HS_WAIT_DH_ANSWER;
done:
    exteria_bn_free(bn_p);
    exteria_bn_free(bn_ga);
    exteria_bn_free(bn_b);
    exteria_bn_free(bn_g);
    exteria_bn_free(bn_gb);
    exteria_bn_free(bn_key);
    exteria_wipe(key_bytes, sizeof(key_bytes));
    return s;
}

static exteria_status handle_dh_answer(exteria_mt_handshake *hs, exteria_tl_value *v, int *restart) {
    uint8_t buf[32 + 1 + 8], digest[20];
    exteria_slice part;
    const char *field;
    uint8_t marker;
    const uint8_t *hash;
    size_t hash_len;
    exteria_status s;
    *restart = 0;
    switch (exteria_tl_id(v)) {
    case 0x3bcbf734u: marker = 1; field = "new_nonce_hash1"; break;
    case 0x46dc1fb9u: marker = 2; field = "new_nonce_hash2"; break;
    case 0xa69dae02u: marker = 3; field = "new_nonce_hash3"; break;
    default: return EXTERIA_E_MALFORMED;
    }
    s = expect_nonces(v, hs->nonce, hs->server_nonce);
    if (s != EXTERIA_OK) return s;
    if (exteria_tl_get_bytes(v, field, &hash, &hash_len) != EXTERIA_OK || hash_len != 16) return EXTERIA_E_MALFORMED;
    s = exteria_sha1_one(hs->auth_key, sizeof(hs->auth_key), digest);
    if (s != EXTERIA_OK) return s;
    memcpy(buf, hs->new_nonce, 32);
    buf[32] = marker;
    memcpy(buf + 33, digest, 8);
    part.data = buf;
    part.len = sizeof(buf);
    s = exteria_sha1(&part, 1, digest);
    if (s != EXTERIA_OK) return s;
    if (!exteria_ct_equal(digest + 4, hash, 16)) return EXTERIA_E_SECURITY;
    if (marker != 1) {
        *restart = 1;
        return EXTERIA_OK;
    }
    s = exteria_mt_auth_key_set(&hs->result.key, hs->auth_key);
    if (s != EXTERIA_OK) return s;
    hs->result.server_salt = hs->salt;
    hs->result.time_offset_ms = hs->time_offset_ms;
    hs->state = EXTERIA_MT_HS_DONE;
    exteria_mt_hs_wipe(hs);
    return EXTERIA_OK;
}

exteria_status exteria_mt_hs_receive(exteria_mt_handshake *hs, const uint8_t *packet, size_t len, int allow_padding,
                                     exteria_writer *out) {
    exteria_arena a;
    exteria_tl_value *v = NULL;
    uint64_t msg_id;
    const uint8_t *body;
    size_t body_len;
    exteria_status s;
    uint16_t ref;
    int restart = 0;
    if (!hs || !packet || !out) return EXTERIA_E_ARG;
    if (hs->state < EXTERIA_MT_HS_WAIT_RES_PQ || hs->state > EXTERIA_MT_HS_WAIT_DH_ANSWER) return EXTERIA_E_STATE;
    s = exteria_mt_plain_unwrap(packet, len, allow_padding, &msg_id, &body, &body_len);
    if (s != EXTERIA_OK) return fail(hs, s);
    /* accepting an even id would admit a client message as a server reply */
    if ((msg_id & 1u) == 0) return fail(hs, EXTERIA_E_MALFORMED);
    switch (hs->state) {
    case EXTERIA_MT_HS_WAIT_RES_PQ: ref = ref_of("resPQ"); break;
    case EXTERIA_MT_HS_WAIT_DH_PARAMS: ref = ref_of("server_DH_params_ok"); break;
    default: ref = ref_of("dh_gen_ok"); break;
    }
    exteria_arena_init(&a, 256 * 1024);
    s = exteria_tl_decode_all(&a, NULL, ref, body, body_len, &v);
    if (s == EXTERIA_E_TRUNCATED) s = EXTERIA_E_MALFORMED;
    if (s == EXTERIA_OK) {
        if (hs->state == EXTERIA_MT_HS_WAIT_RES_PQ) {
            s = handle_res_pq(hs, v, &a, out);
        } else if (hs->state == EXTERIA_MT_HS_WAIT_DH_PARAMS) {
            s = handle_dh_params(hs, v, &a, out);
        } else {
            s = handle_dh_answer(hs, v, &restart);
            /* retry and fail both mean the server wants a fresh exchange, bounded so a broken server cannot loop us */
            if (s == EXTERIA_OK && restart) {
                if (++hs->attempts >= hs->config.max_attempts) s = EXTERIA_E_LIMIT;
                else s = exteria_mt_hs_start(hs, out);
            }
        }
    }
    exteria_arena_free(&a);
    if (s != EXTERIA_OK) return fail(hs, s);
    return EXTERIA_OK;
}

const exteria_mt_hs_result *exteria_mt_hs_result_get(const exteria_mt_handshake *hs) {
    return hs->state == EXTERIA_MT_HS_DONE ? &hs->result : NULL;
}
