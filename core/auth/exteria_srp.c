#include "exteria_srp.h"

#include <string.h>

#include "exteria_crypto.h"
#include "exteria_mt_handshake.h"
#include "exteria_random.h"
#include "exteria_tl_ids.h"

static exteria_status parameters(const exteria_tl_value *algo, exteria_slice *s1, exteria_slice *s2,
                                 const uint8_t **prime, int32_t *g) {
    size_t len;
    if (!exteria_tl_is(algo, EXTERIA_TL_ID_passwordKdfAlgoSHA256SHA256PBKDF2HMACSHA512iter100000SHA256ModPow))
        return EXTERIA_E_UNSUPPORTED;
    if (exteria_tl_get_bytes(algo, "salt1", &s1->data, &s1->len) != EXTERIA_OK ||
        exteria_tl_get_bytes(algo, "salt2", &s2->data, &s2->len) != EXTERIA_OK ||
        exteria_tl_get_bytes(algo, "p", prime, &len) != EXTERIA_OK ||
        exteria_tl_get_i32(algo, "g", g) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (!s1->len || !s2->len || s1->len > 1024 || s2->len > 1024 || len != 256) return EXTERIA_E_SECURITY;
    return exteria_mt_check_dh_prime(*prime, len, *g);
}

static exteria_status password_x(exteria_slice s1, exteria_slice s2, const uint8_t *password,
                                 size_t len, uint8_t out[32]) {
    uint8_t h[32], stretched[64];
    exteria_slice parts[3];
    exteria_status status;
    if ((!password && len) || len > 1024) return EXTERIA_E_ARG;
    parts[0] = s1;
    parts[1].data = password; parts[1].len = len;
    parts[2] = s1;
    status = exteria_sha256(parts, 3, h);
    parts[0] = s2;
    parts[1].data = h; parts[1].len = sizeof(h);
    parts[2] = s2;
    if (status == EXTERIA_OK) status = exteria_sha256(parts, 3, h);
    if (status == EXTERIA_OK) status = exteria_pbkdf2_sha512(h, sizeof(h), s1.data, s1.len, 100000, stretched, sizeof(stretched));
    parts[1].data = stretched; parts[1].len = sizeof(stretched);
    if (status == EXTERIA_OK) status = exteria_sha256(parts, 3, out);
    exteria_wipe(h, sizeof(h));
    exteria_wipe(stretched, sizeof(stretched));
    return status;
}

exteria_status exteria_srp_check(const exteria_tl_value *account_password,
                                const uint8_t *password, size_t len, exteria_srp_proof *out) {
    const exteria_tl_value *algo;
    const uint8_t *prime, *server_B;
    size_t B_len;
    int32_t generator;
    exteria_slice s1, s2, parts[6];
    exteria_bn *p = NULL, *g = NULL, *B = NULL, *a = NULL, *A = NULL, *x = NULL;
    exteria_bn *k = NULL, *u = NULL, *v = NULL, *kv = NULL, *t = NULL, *ux = NULL, *exp = NULL, *S = NULL;
    uint8_t gp[256] = {0}, bp[256], entropy[256], xh[32], kh[32], uh[32], sp[256], K[32], h1[32], h2[32];
    exteria_status status;
    size_t i;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!account_password || (!password && len) || len > 1024) return EXTERIA_E_ARG;
    algo = exteria_tl_get(account_password, "current_algo");
    status = parameters(algo, &s1, &s2, &prime, &generator);
    if (status != EXTERIA_OK) return status;
    if (exteria_tl_get_bytes(account_password, "srp_B", &server_B, &B_len) != EXTERIA_OK ||
        !B_len || B_len > 256 || exteria_tl_get_i64(account_password, "srp_id", &out->id) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    gp[255] = (uint8_t)generator;
    status = password_x(s1, s2, password, len, xh);
    if (status != EXTERIA_OK) goto done;
    status = exteria_random(entropy, sizeof(entropy));
    if (status != EXTERIA_OK) goto done;
    p = exteria_bn_from_bin(prime, 256); g = exteria_bn_from_u64((uint64_t)generator);
    B = exteria_bn_from_bin(server_B, B_len); a = exteria_bn_from_bin(entropy, 256); x = exteria_bn_from_bin(xh, 32);
    if (!p || !g || !B || !a || !x) { status = EXTERIA_E_NOMEM; goto done; }
    if (exteria_bn_is_zero(B) || exteria_bn_cmp(B, p) >= 0 || exteria_bn_is_zero(a)) { status = EXTERIA_E_SECURITY; goto done; }
    A = exteria_bn_mod_exp_secret(g, a, p);
    if (!A) { status = EXTERIA_E_CRYPTO; goto done; }
    status = exteria_bn_to_bin_padded(A, out->A, 256);
    if (status == EXTERIA_OK) status = exteria_mt_check_dh_value(prime, 256, out->A, 256);
    if (status != EXTERIA_OK) goto done;
    status = exteria_bn_to_bin_padded(B, bp, 256);
    parts[0].data = prime; parts[0].len = 256; parts[1].data = gp; parts[1].len = 256;
    if (status == EXTERIA_OK) status = exteria_sha256(parts, 2, kh);
    parts[0].data = out->A; parts[1].data = bp;
    if (status == EXTERIA_OK) status = exteria_sha256(parts, 2, uh);
    if (status != EXTERIA_OK) goto done;
    k = exteria_bn_from_bin(kh, 32); u = exteria_bn_from_bin(uh, 32);
    if (!k || !u) { status = EXTERIA_E_NOMEM; goto done; }
    if (exteria_bn_is_zero(u)) { status = EXTERIA_E_SECURITY; goto done; }
    v = exteria_bn_mod_exp_secret(g, x, p);
    if (v) kv = exteria_bn_mod_mul(k, v, p);
    if (kv) t = exteria_bn_mod_sub(B, kv, p);
    if (t) ux = exteria_bn_mul(u, x);
    if (ux) exp = exteria_bn_add(a, ux);
    if (!exp) { status = EXTERIA_E_CRYPTO; goto done; }
    status = exteria_bn_to_bin_padded(t, sp, 256);
    if (status == EXTERIA_OK) status = exteria_mt_check_dh_value(prime, 256, sp, 256);
    if (status != EXTERIA_OK) goto done;
    S = exteria_bn_mod_exp_secret(t, exp, p);
    if (!S) { status = EXTERIA_E_CRYPTO; goto done; }
    status = exteria_bn_to_bin_padded(S, sp, 256);
    if (status == EXTERIA_OK) status = exteria_sha256_one(sp, 256, K);
    if (status == EXTERIA_OK) status = exteria_sha256_one(prime, 256, h1);
    if (status == EXTERIA_OK) status = exteria_sha256_one(gp, 256, h2);
    for (i = 0; i < 32; ++i) kh[i] = h1[i] ^ h2[i];
    if (status == EXTERIA_OK) status = exteria_sha256_one(s1.data, s1.len, h1);
    if (status == EXTERIA_OK) status = exteria_sha256_one(s2.data, s2.len, h2);
    parts[0].data = kh; parts[0].len = 32; parts[1].data = h1; parts[1].len = 32;
    parts[2].data = h2; parts[2].len = 32; parts[3].data = out->A; parts[3].len = 256;
    parts[4].data = bp; parts[4].len = 256; parts[5].data = K; parts[5].len = 32;
    if (status == EXTERIA_OK) status = exteria_sha256(parts, 6, out->M1);
done:
    exteria_bn_free(p); exteria_bn_free(g); exteria_bn_free(B); exteria_bn_free(a); exteria_bn_free(A); exteria_bn_free(x);
    exteria_bn_free(k); exteria_bn_free(u); exteria_bn_free(v); exteria_bn_free(kv); exteria_bn_free(t);
    exteria_bn_free(ux); exteria_bn_free(exp); exteria_bn_free(S);
    exteria_wipe(entropy, sizeof(entropy)); exteria_wipe(xh, sizeof(xh)); exteria_wipe(sp, sizeof(sp));
    exteria_wipe(K, sizeof(K)); exteria_wipe(h1, sizeof(h1)); exteria_wipe(h2, sizeof(h2));
    if (status != EXTERIA_OK) exteria_wipe(out, sizeof(*out));
    return status;
}

exteria_status exteria_srp_verifier(const exteria_tl_value *algo, const uint8_t *password, size_t len,
                                   exteria_arena *arena, exteria_tl_value **new_algo, uint8_t verifier[256]) {
    exteria_slice s1, s2;
    const uint8_t *prime;
    int32_t generator;
    uint8_t salt[1056], xh[32];
    exteria_bn *p = NULL, *g = NULL, *x = NULL, *v = NULL;
    exteria_tl_value *result;
    exteria_status status;
    if (!new_algo || !verifier) return EXTERIA_E_ARG;
    *new_algo = NULL;
    memset(verifier, 0, 256);
    if (!arena || (!password && len) || len > 1024) return EXTERIA_E_ARG;
    status = parameters(algo, &s1, &s2, &prime, &generator);
    if (status != EXTERIA_OK) return status;
    memcpy(salt, s1.data, s1.len);
    status = exteria_random(salt + s1.len, 32);
    s1.data = salt; s1.len += 32;
    if (status == EXTERIA_OK) status = password_x(s1, s2, password, len, xh);
    if (status != EXTERIA_OK) goto done;
    p = exteria_bn_from_bin(prime, 256); g = exteria_bn_from_u64((uint64_t)generator); x = exteria_bn_from_bin(xh, 32);
    if (!p || !g || !x) { status = EXTERIA_E_NOMEM; goto done; }
    v = exteria_bn_mod_exp_secret(g, x, p);
    if (!v) { status = EXTERIA_E_CRYPTO; goto done; }
    status = exteria_bn_to_bin_padded(v, verifier, 256);
    if (status != EXTERIA_OK) goto done;
    result = exteria_tl_new_obj(arena, algo->u.obj.ctor->name);
    if (!result) { status = EXTERIA_E_NOMEM; goto done; }
    status = exteria_tl_set_bytes(arena, result, "salt1", salt, s1.len);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, result, "salt2", s2.data, s2.len);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, result, "g", generator);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, result, "p", prime, 256);
    if (status == EXTERIA_OK) *new_algo = result;
done:
    exteria_bn_free(p); exteria_bn_free(g); exteria_bn_free(x); exteria_bn_free(v);
    exteria_wipe(salt, sizeof(salt)); exteria_wipe(xh, sizeof(xh));
    if (status != EXTERIA_OK) exteria_wipe(verifier, 256);
    return status;
}
