#include "fake_mt_server.h"

#include <string.h>

#include <openssl/bn.h>

#include "exteria_crypto.h"
#include "exteria_random.h"
#include "test_util.h"

static const char *PRIME_HEX =
    "c71caeb9c6b1c9048e6c522f70f13f73980d40238e3e21c14934d037563d930f48198a0aa7c14058229493d22530f4dbfa336f6e0ac925139543aed44cce7c37"
    "20fd51f69458705ac68cd4fe6b6b13abdc9746512969328454f18faf8c595f642477fe96bb2a941d5bcd1d4ac8cc49880708fa9b378e3c4f3a9060bee67cf9a4a"
    "4a695811051907e162753b56b0f6b410dba74d8a84b2a14b3144e0ef1284754fd17ed950d5965b4b9dd46582db1178d169c6bc465b0d6ff9ca3928fef5b9ae4e4"
    "18fc15e83ebea0f87fa9ff5eed70050ded2849f47bf959d956850ce929851f0d8115f635b105ee2e4e15d04b2454bf6f4fadf034b10403119cd8e3b92fcc5b";

static const exteria_tl_ctor *ctor_named(const char *name) {
    return exteria_tl_find_ctor_by_name(name);
}

int fake_mt_server_init(fake_mt_server *s) {
    BIGNUM *p = BN_new(), *q = BN_new(), *n = BN_new(), *d = BN_new(), *e = BN_new(), *phi = BN_new(), *t1 = BN_new();
    BN_CTX *ctx = BN_CTX_new();
    uint8_t fp_buf[64];
    size_t pos = 0;
    memset(s, 0, sizeof(*s));
    BN_set_word(e, 65537);
    do {
        BN_generate_prime_ex(p, 1024, 0, NULL, NULL, NULL);
        BN_generate_prime_ex(q, 1024, 0, NULL, NULL, NULL);
        BN_mul(n, p, q, ctx);
    } while (BN_num_bits(n) != 2048);
    BN_sub(t1, p, BN_value_one());
    BN_sub(phi, q, BN_value_one());
    BN_mul(phi, phi, t1, ctx);
    BN_mod_inverse(d, e, phi, ctx);
    BN_bn2binpad(n, s->n_bytes, 256);
    s->rsa_n = n;
    s->rsa_d = d;
    s->key.n = s->n_bytes;
    s->key.n_len = 256;
    s->key.e = 65537;
    exteria_mt_rsa_fingerprint(s->key.n, s->key.n_len, s->key.e, &s->key.fingerprint);
    (void)fp_buf;
    (void)pos;
    {
        long n2 = test_hex(PRIME_HEX, s->prime, sizeof(s->prime));
        if (n2 != 256) return -1;
    }
    s->server_time = 1700000000;
    s->dc_expected = 2;
    s->next_msg_id = 0x6500000000000001ull;
    BN_free(p);
    BN_free(q);
    BN_free(e);
    BN_free(phi);
    BN_free(t1);
    BN_CTX_free(ctx);
    return 0;
}

void fake_mt_server_free(fake_mt_server *s) {
    BN_free((BIGNUM *)s->rsa_n);
    BN_clear_free((BIGNUM *)s->rsa_d);
    memset(s, 0, sizeof(*s));
}

uint64_t fake_mt_server_msg_id(fake_mt_server *s, int is_response) {
    s->next_msg_id += 4;
    return (s->next_msg_id & ~3ull) | (is_response ? 1u : 3u);
}

static int reply(fake_mt_server *s, exteria_tl_value *v, exteria_writer *out) {
    exteria_writer body;
    int st;
    exteria_writer_init(&body, 1 << 16);
    st = exteria_tl_encode(v, &body, NULL);
    if (st == EXTERIA_OK) st = exteria_mt_plain_wrap(fake_mt_server_msg_id(s, 1), body.data, body.len, out);
    exteria_writer_free(&body);
    return st;
}

static void set_nonces(exteria_arena *a, exteria_tl_value *v, const uint8_t *nonce, const uint8_t *server_nonce) {
    exteria_tl_set_bytes(a, v, "nonce", nonce, 16);
    exteria_tl_set_bytes(a, v, "server_nonce", server_nonce, 16);
}

static int make_semiprime(fake_mt_server *s, int prime_value) {
    BIGNUM *p = BN_new(), *q = BN_new();
    uint64_t a, b;
    BN_generate_prime_ex(p, 31, 0, NULL, NULL, NULL);
    BN_generate_prime_ex(q, 31, 0, NULL, NULL, NULL);
    a = BN_get_word(p);
    b = BN_get_word(q);
    s->pq = prime_value ? a : a * b;
    BN_free(p);
    BN_free(q);
    return 0;
}

static void derive_tmp(fake_mt_server *s) {
    uint8_t h1[20], h2[20], h3[20];
    exteria_slice parts[2];
    parts[0].data = s->new_nonce; parts[0].len = 32; parts[1].data = s->server_nonce; parts[1].len = 16;
    exteria_sha1(parts, 2, h1);
    parts[0].data = s->server_nonce; parts[0].len = 16; parts[1].data = s->new_nonce; parts[1].len = 32;
    exteria_sha1(parts, 2, h2);
    parts[0].data = s->new_nonce; parts[0].len = 32; parts[1].data = s->new_nonce; parts[1].len = 32;
    exteria_sha1(parts, 2, h3);
    memcpy(s->tmp_key, h1, 20);
    memcpy(s->tmp_key + 20, h2, 12);
    memcpy(s->tmp_iv, h2 + 12, 8);
    memcpy(s->tmp_iv + 8, h3, 20);
    memcpy(s->tmp_iv + 28, s->new_nonce, 4);
}

static int step_res_pq(fake_mt_server *s, exteria_tl_value *req, exteria_arena *a, exteria_writer *out) {
    const uint8_t *nonce;
    size_t n;
    exteria_tl_value *res, *fps;
    uint8_t pq_be[8];
    int i;
    if (!exteria_tl_is(req, 0xbe7e8ef1u)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_bytes(req, "nonce", &nonce, &n) != EXTERIA_OK || n != 16) return EXTERIA_E_MALFORMED;
    memcpy(s->nonce, nonce, 16);
    exteria_random(s->server_nonce, 16);
    make_semiprime(s, s->mode == FAKE_HS_PRIME_PQ);
    for (i = 0; i < 8; ++i) pq_be[i] = (uint8_t)(s->pq >> (56 - 8 * i));
    res = exteria_tl_new_obj(a, "resPQ");
    exteria_tl_set_bytes(a, res, "nonce", s->nonce, 16);
    exteria_tl_set_bytes(a, res, "server_nonce", s->server_nonce, 16);
    exteria_tl_set_bytes(a, res, "pq", pq_be, 8);
    fps = exteria_tl_new_vec(a, 2);
    exteria_tl_vec_set(fps, 0, exteria_tl_new_i64(a, 0x1111111111111111ll));
    exteria_tl_vec_set(fps, 1, exteria_tl_new_i64(a, (int64_t)(s->mode == FAKE_HS_UNKNOWN_KEY ? 0x2222222222222222ull : s->key.fingerprint)));
    exteria_tl_set(res, "server_public_key_fingerprints", fps);
    return reply(s, res, out);
}

static int step_dh_params(fake_mt_server *s, exteria_tl_value *req, exteria_arena *a, exteria_writer *out) {
    const uint8_t *enc, *p_bytes, *q_bytes;
    size_t enc_len, p_len, q_len;
    int64_t fp;
    uint8_t m[256], temp_key[32], digest[32], iv[32] = { 0 }, data_with_hash[224], rev[192];
    exteria_slice parts[2];
    BIGNUM *c, *r;
    BN_CTX *ctx;
    exteria_tl_value *inner, *answer;
    exteria_arena parse;
    size_t consumed, i;
    exteria_writer buf;
    uint8_t dh_a[256];
    BIGNUM *bg, *bp, *ba, *bga;
    const uint8_t *nn;
    size_t nn_len;
    int32_t dc = 0;
    if (exteria_tl_get_bytes(req, "encrypted_data", &enc, &enc_len) != EXTERIA_OK || enc_len != 256) return EXTERIA_E_MALFORMED;
    exteria_tl_get_bytes(req, "p", &p_bytes, &p_len);
    exteria_tl_get_bytes(req, "q", &q_bytes, &q_len);
    exteria_tl_get_i64(req, "public_key_fingerprint", &fp);
    if ((uint64_t)fp != s->key.fingerprint) return EXTERIA_E_SECURITY;
    if (p_len != 4 || q_len != 4) return EXTERIA_E_MALFORMED;
    ctx = BN_CTX_new();
    c = BN_bin2bn(enc, 256, NULL);
    r = BN_new();
    BN_mod_exp(r, c, (BIGNUM *)s->rsa_d, (BIGNUM *)s->rsa_n, ctx);
    BN_bn2binpad(r, m, 256);
    BN_free(c);
    BN_free(r);
    {
        uint8_t aes_encrypted[224];
        memcpy(aes_encrypted, m + 32, 224);
        exteria_sha256_one(aes_encrypted, 224, digest);
        for (i = 0; i < 32; ++i) temp_key[i] = (uint8_t)(m[i] ^ digest[i]);
        exteria_aes_ige(temp_key, iv, 0, aes_encrypted, data_with_hash, 224);
    }
    for (i = 0; i < 192; ++i) rev[i] = data_with_hash[191 - i];
    parts[0].data = temp_key; parts[0].len = 32; parts[1].data = rev; parts[1].len = 192;
    exteria_sha256(parts, 2, digest);
    if (memcmp(digest, data_with_hash + 192, 32) != 0) {
        BN_CTX_free(ctx);
        return EXTERIA_E_SECURITY;
    }
    exteria_arena_init(&parse, 65536);
    if (exteria_tl_decode(&parse, NULL, ctor_named("p_q_inner_data_dc")->result, rev, 192, &consumed, &inner) != EXTERIA_OK) {
        exteria_arena_free(&parse);
        BN_CTX_free(ctx);
        return EXTERIA_E_MALFORMED;
    }
    exteria_tl_get_bytes(inner, "new_nonce", &nn, &nn_len);
    memcpy(s->new_nonce, nn, 32);
    exteria_tl_get_i32(inner, "dc", &dc);
    exteria_arena_free(&parse);
    if (dc != s->dc_expected) {
        BN_CTX_free(ctx);
        return EXTERIA_E_SECURITY;
    }
    derive_tmp(s);
    if (s->mode == FAKE_HS_PARAMS_FAIL) {
        exteria_tl_value *fail = exteria_tl_new_obj(a, "server_DH_params_fail");
        uint8_t hash[20];
        set_nonces(a, fail, s->nonce, s->server_nonce);
        exteria_sha1_one(s->new_nonce, 32, hash);
        exteria_tl_set_bytes(a, fail, "new_nonce_hash", hash + 4, 16);
        BN_CTX_free(ctx);
        return reply(s, fail, out);
    }
    bp = BN_bin2bn(s->prime, 256, NULL);
    bg = BN_new();
    BN_set_word(bg, 3);
    exteria_random(dh_a, 256);
    memcpy(s->dh_a, dh_a, 256);
    ba = BN_bin2bn(dh_a, 256, NULL);
    bga = BN_new();
    BN_mod_exp(bga, bg, ba, bp, ctx);
    if (s->mode == FAKE_HS_SMALL_GA) BN_set_word(bga, 5);
    if (s->mode == FAKE_HS_COMPOSITE_PRIME) {
        BN_sub_word(bp, 2);
        BN_bn2binpad(bp, s->prime, 256);
        BN_add_word(bp, 2);
    }
    s->g_a_len = (size_t)BN_num_bytes(bga);
    BN_bn2bin(bga, s->g_a);
    BN_free(bg);
    BN_free(bp);
    BN_free(ba);
    BN_free(bga);
    BN_CTX_free(ctx);
    answer = exteria_tl_new_obj(a, "server_DH_inner_data");
    set_nonces(a, answer, s->nonce, s->server_nonce);
    if (s->mode == FAKE_HS_BAD_SERVER_NONCE) {
        uint8_t wrong[16];
        exteria_random(wrong, 16);
        exteria_tl_set_bytes(a, answer, "server_nonce", wrong, 16);
    }
    exteria_tl_set_i32(a, answer, "g", 3);
    exteria_tl_set_bytes(a, answer, "dh_prime", s->prime, 256);
    exteria_tl_set_bytes(a, answer, "g_a", s->g_a, s->g_a_len);
    exteria_tl_set_i32(a, answer, "server_time", s->server_time);
    exteria_writer_init(&buf, 1024);
    exteria_wr_zero(&buf, 20);
    exteria_tl_encode(answer, &buf, NULL);
    {
        size_t dl = buf.len - 20, pad = (16 - buf.len % 16) % 16;
        uint8_t hash[20];
        exteria_sha1_one(buf.data + 20, dl, hash);
        memcpy(buf.data, hash, 20);
        exteria_wr_zero(&buf, pad);
        exteria_aes_ige(s->tmp_key, s->tmp_iv, 1, buf.data, buf.data, buf.len);
    }
    {
        exteria_tl_value *res = exteria_tl_new_obj(a, "server_DH_params_ok");
        int st;
        set_nonces(a, res, s->nonce, s->server_nonce);
        exteria_tl_set_bytes(a, res, "encrypted_answer", buf.data, buf.len);
        exteria_writer_free(&buf);
        st = reply(s, res, out);
        return st;
    }
}

static int step_client_params(fake_mt_server *s, exteria_tl_value *req, exteria_arena *a, exteria_writer *out) {
    const uint8_t *enc, *gb;
    size_t enc_len, gb_len, dl;
    uint8_t *plain;
    exteria_arena parse;
    exteria_tl_value *inner;
    size_t consumed, i;
    BIGNUM *bgb, *ba, *bp, *bk;
    BN_CTX *ctx;
    uint8_t key[256], aux[20], hash[20], buf[41];
    exteria_slice part;
    uint8_t marker = 1;
    const char *res_name = "dh_gen_ok", *field = "new_nonce_hash1";
    exteria_tl_value *res;
    if (exteria_tl_get_bytes(req, "encrypted_data", &enc, &enc_len) != EXTERIA_OK || enc_len % 16 || enc_len < 48) return EXTERIA_E_MALFORMED;
    plain = (uint8_t *)malloc(enc_len);
    exteria_aes_ige(s->tmp_key, s->tmp_iv, 0, enc, plain, enc_len);
    exteria_arena_init(&parse, 65536);
    if (exteria_tl_decode(&parse, NULL, ctor_named("client_DH_inner_data")->result, plain + 20, enc_len - 20, &consumed, &inner) != EXTERIA_OK) {
        free(plain);
        exteria_arena_free(&parse);
        return EXTERIA_E_MALFORMED;
    }
    dl = consumed;
    exteria_sha1_one(plain + 20, dl, hash);
    if (memcmp(hash, plain, 20) != 0) {
        free(plain);
        exteria_arena_free(&parse);
        return EXTERIA_E_SECURITY;
    }
    exteria_tl_get_bytes(inner, "g_b", &gb, &gb_len);
    ctx = BN_CTX_new();
    bgb = BN_bin2bn(gb, (int)gb_len, NULL);
    ba = BN_bin2bn(s->dh_a, 256, NULL);
    bp = BN_bin2bn(s->prime, 256, NULL);
    bk = BN_new();
    BN_mod_exp(bk, bgb, ba, bp, ctx);
    BN_bn2binpad(bk, key, 256);
    BN_free(bgb); BN_free(ba); BN_free(bp); BN_free(bk);
    BN_CTX_free(ctx);
    free(plain);
    exteria_arena_free(&parse);
    exteria_mt_auth_key_set(&s->auth_key, key);
    s->have_key = 1;
    s->salt = 0;
    for (i = 0; i < 8; ++i) s->salt |= (uint64_t)(s->new_nonce[i] ^ s->server_nonce[i]) << (8 * i);
    exteria_sha1_one(key, 256, aux);
    if (s->mode == FAKE_HS_ALWAYS_RETRY || (s->mode == FAKE_HS_RETRY_ONCE && s->retries_left > 0)) {
        marker = 2;
        res_name = "dh_gen_retry";
        field = "new_nonce_hash2";
        s->retries_left--;
    } else if (s->mode == FAKE_HS_FAIL) {
        marker = 3;
        res_name = "dh_gen_fail";
        field = "new_nonce_hash3";
    }
    memcpy(buf, s->new_nonce, 32);
    buf[32] = marker;
    memcpy(buf + 33, aux, 8);
    part.data = buf;
    part.len = sizeof(buf);
    exteria_sha1(&part, 1, hash);
    if (s->mode == FAKE_HS_BAD_NEW_NONCE_HASH) hash[10] ^= 1;
    res = exteria_tl_new_obj(a, res_name);
    set_nonces(a, res, s->nonce, s->server_nonce);
    exteria_tl_set_bytes(a, res, field, hash + 4, 16);
    return reply(s, res, out);
}

int fake_mt_server_handshake(fake_mt_server *s, const uint8_t *packet, size_t len, exteria_writer *out) {
    exteria_arena a;
    exteria_tl_value *req = NULL;
    uint64_t id;
    const uint8_t *body;
    size_t body_len;
    int st = exteria_mt_plain_unwrap(packet, len, 1, &id, &body, &body_len);
    if (st != EXTERIA_OK) return st;
    if ((id & 3) != 0) return EXTERIA_E_MALFORMED;
    exteria_arena_init(&a, 1 << 20);
    st = exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, body, body_len, &req);
    if (st == EXTERIA_OK) {
        switch (exteria_tl_id(req)) {
        case 0xbe7e8ef1u: st = step_res_pq(s, req, &a, out); break;
        case 0xd712e4beu: st = step_dh_params(s, req, &a, out); break;
        case 0xf5045f1fu: st = step_client_params(s, req, &a, out); break;
        default: st = EXTERIA_E_UNSUPPORTED;
        }
    }
    exteria_arena_free(&a);
    return st;
}

int fake_mt_server_decrypt(fake_mt_server *s, const uint8_t *packet, size_t len, exteria_writer *plain,
                           exteria_mt_header *h, const uint8_t **body, size_t *body_len) {
    return exteria_mt_decrypt(&s->auth_key, 1, 1, packet, len, plain, h, body, body_len);
}

int fake_mt_server_encrypt(fake_mt_server *s, uint64_t msg_id, int content_related, const uint8_t *body, size_t len,
                           exteria_writer *out) {
    exteria_mt_header h;
    h.salt = s->salt;
    h.session_id = s->session_id;
    h.msg_id = msg_id;
    h.seq_no = (int32_t)(s->server_seq * 2u + (content_related ? 1u : 0u));
    if (content_related) s->server_seq++;
    return exteria_mt_encrypt(&s->auth_key, 0, &h, body, len, out);
}
