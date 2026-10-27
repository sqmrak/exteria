#include "test_util.h"
#include "exteria_srp.h"
#include "exteria_crypto.h"
#include "srp_vectors.h"

#include <openssl/bn.h>
#include <openssl/evp.h>

static void hash(const void *data, size_t len, uint8_t out[32]) {
    unsigned result_len = 0;
    CHECK_EQ_INT(EVP_Digest(data, len, out, &result_len, EVP_sha256(), NULL), 1);
    CHECK_EQ_INT(result_len, 32);
}

static exteria_tl_value *algorithm(exteria_arena *a) {
    exteria_tl_value *v = exteria_tl_new_obj(a, "passwordKdfAlgoSHA256SHA256PBKDF2HMACSHA512iter100000SHA256ModPow");
    CHECK_EQ_INT(exteria_tl_set_bytes(a, v, "salt1", srp_salt1, sizeof(srp_salt1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(a, v, "salt2", srp_salt2, sizeof(srp_salt2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(a, v, "p", srp_prime, sizeof(srp_prime)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "g", 3), EXTERIA_OK);
    return v;
}

static void verify_server(const exteria_srp_proof *proof) {
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM *p = BN_bin2bn(srp_prime, 256, NULL), *v = BN_bin2bn(srp_v, 256, NULL);
    BIGNUM *b = BN_bin2bn(srp_b, 256, NULL), *A = BN_bin2bn(proof->A, 256, NULL);
    BIGNUM *u, *vu = BN_new(), *t = BN_new(), *S = BN_new();
    uint8_t joined[512], uh[32], padded[256], K[32], gp[256] = {0};
    uint8_t h1[32], h2[32], salt_hash1[32], salt_hash2[32], m[672], expected[32];
    size_t i;
    memcpy(joined, proof->A, 256);
    memcpy(joined + 256, srp_B, 256);
    hash(joined, sizeof(joined), uh);
    u = BN_bin2bn(uh, 32, NULL);
    CHECK_EQ_INT(BN_mod_exp(vu, v, u, p, ctx), 1);
    CHECK_EQ_INT(BN_mod_mul(t, A, vu, p, ctx), 1);
    CHECK_EQ_INT(BN_mod_exp(S, t, b, p, ctx), 1);
    CHECK_EQ_INT(BN_bn2binpad(S, padded, 256), 256);
    hash(padded, 256, K);
    gp[255] = 3;
    hash(srp_prime, 256, h1); hash(gp, 256, h2);
    for (i = 0; i < 32; ++i) m[i] = h1[i] ^ h2[i];
    hash(srp_salt1, sizeof(srp_salt1), salt_hash1);
    hash(srp_salt2, sizeof(srp_salt2), salt_hash2);
    memcpy(m + 32, salt_hash1, 32); memcpy(m + 64, salt_hash2, 32);
    memcpy(m + 96, proof->A, 256); memcpy(m + 352, srp_B, 256); memcpy(m + 608, K, 32);
    hash(m, 640, expected);
    CHECK_MEM(proof->M1, expected, 32);
    BN_free(p); BN_free(v); BN_free(b); BN_free(A); BN_free(u); BN_free(vu); BN_free(t); BN_free(S); BN_CTX_free(ctx);
}

int main(void) {
    exteria_arena a;
    exteria_srp_proof proof, zero;
    exteria_tl_value *algo, *info, *next;
    uint8_t verifier[256], buf[256], h1[32], h2[32], stretched[64], xh[32], salt[1056];
    const uint8_t *new_salt;
    size_t salt_len;
    BIGNUM *p, *g, *x, *v;
    BN_CTX *ctx;
    exteria_arena_init(&a, 1024u * 1024u);
    algo = algorithm(&a);
    info = exteria_tl_new_obj(&a, "account.password");
    CHECK_EQ_INT(exteria_tl_set(info, "current_algo", algo), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&a, info, "srp_B", srp_B, sizeof(srp_B)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&a, info, "srp_id", INT64_MIN + 35), EXTERIA_OK);
    CHECK_EQ_INT(exteria_srp_check(info, srp_password, sizeof(srp_password), &proof), EXTERIA_OK);
    CHECK_EQ_INT(proof.id, INT64_MIN + 35);
    verify_server(&proof);
    CHECK_EQ_INT(exteria_srp_verifier(algo, srp_password, sizeof(srp_password), &a, &next, verifier), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_bytes(next, "salt1", &new_salt, &salt_len), EXTERIA_OK);
    CHECK_EQ_INT(salt_len, sizeof(srp_salt1) + 32);
    memcpy(salt, new_salt, salt_len);
    memcpy(buf, salt, salt_len); memcpy(buf + salt_len, srp_password, sizeof(srp_password));
    memcpy(buf + salt_len + sizeof(srp_password), salt, salt_len);
    hash(buf, 2 * salt_len + sizeof(srp_password), h1);
    memcpy(buf, srp_salt2, sizeof(srp_salt2)); memcpy(buf + sizeof(srp_salt2), h1, 32);
    memcpy(buf + sizeof(srp_salt2) + 32, srp_salt2, sizeof(srp_salt2));
    hash(buf, 2 * sizeof(srp_salt2) + 32, h2);
    CHECK_EQ_INT(PKCS5_PBKDF2_HMAC((const char *)h2, 32, salt, (int)salt_len, 100000, EVP_sha512(), 64, stretched), 1);
    memcpy(buf, srp_salt2, sizeof(srp_salt2)); memcpy(buf + sizeof(srp_salt2), stretched, 64);
    memcpy(buf + sizeof(srp_salt2) + 64, srp_salt2, sizeof(srp_salt2));
    hash(buf, 2 * sizeof(srp_salt2) + 64, xh);
    p = BN_bin2bn(srp_prime, 256, NULL); g = BN_new(); x = BN_bin2bn(xh, 32, NULL); v = BN_new(); ctx = BN_CTX_new();
    CHECK_EQ_INT(BN_set_word(g, 3), 1);
    CHECK_EQ_INT(BN_mod_exp(v, g, x, p, ctx), 1);
    CHECK_EQ_INT(BN_bn2binpad(v, buf, 256), 256);
    CHECK_MEM(buf, verifier, 256);
    BN_free(p); BN_free(g); BN_free(x); BN_free(v); BN_CTX_free(ctx);
    memset(&zero, 0, sizeof(zero));
    CHECK_EQ_INT(exteria_tl_set_bytes(&a, info, "srp_B", srp_prime, sizeof(srp_prime)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_srp_check(info, srp_password, sizeof(srp_password), &proof), EXTERIA_E_SECURITY);
    CHECK_MEM(&proof, &zero, sizeof(proof));
    memset(buf, 0, sizeof(buf));
    CHECK_EQ_INT(exteria_tl_set_bytes(&a, info, "srp_B", buf, sizeof(buf)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_srp_check(info, srp_password, sizeof(srp_password), &proof), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, algo, "g", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_srp_check(info, srp_password, sizeof(srp_password), &proof), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_srp_check(info, NULL, 1025, &proof), EXTERIA_E_ARG);
    exteria_arena_free(&a);
    return test_finish("test_srp");
}
