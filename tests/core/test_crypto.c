#include "test_util.h"

#include "exteria_arena.h"
#include "exteria_bytes.h"
#include "exteria_crypto.h"
#include "exteria_random.h"

static void test_hashes(void) {
    uint8_t out[32], want[32];
    exteria_slice parts[2];
    CHECK_EQ_INT(exteria_sha1_one("abc", 3, out), EXTERIA_OK);
    test_hex("a9993e364706816aba3e25717850c26c9cd0d89d", want, sizeof(want));
    CHECK_MEM(out, want, 20);
    CHECK_EQ_INT(exteria_sha256_one("abc", 3, out), EXTERIA_OK);
    test_hex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", want, sizeof(want));
    CHECK_MEM(out, want, 32);
    parts[0].data = (const uint8_t *)"a";
    parts[0].len = 1;
    parts[1].data = (const uint8_t *)"bc";
    parts[1].len = 2;
    CHECK_EQ_INT(exteria_sha256(parts, 2, out), EXTERIA_OK);
    CHECK_MEM(out, want, 32);
    CHECK_EQ_INT(exteria_md5(parts, 2, out), EXTERIA_OK);
    test_hex("900150983cd24fb0d6963f7d28e17f72", want, sizeof(want));
    CHECK_MEM(out, want, 16);
    parts[0].len = 0;
    parts[1].len = 0;
    CHECK_EQ_INT(exteria_sha1(parts, 2, out), EXTERIA_OK);
    test_hex("da39a3ee5e6b4b0d3255bfef95601890afd80709", want, sizeof(want));
    CHECK_MEM(out, want, 20);
    CHECK_EQ_INT(exteria_sha1(NULL, 1, out), EXTERIA_E_ARG);
}

static void test_pbkdf2(void) {
    uint8_t out[64], want[64];
    CHECK_EQ_INT(exteria_pbkdf2_sha512((const uint8_t *)"password", 8, (const uint8_t *)"salt", 4, 1, out, 64), EXTERIA_OK);
    test_hex("867f70cf1ade02cff3752599a3a53dc4af34c7a669815ae5d513554e1c8cf252"
             "c02d470a285a0501bad999bfe943c08f050235d7d68b1da55e63f73b60a57fce", want, sizeof(want));
    CHECK_MEM(out, want, 64);
    CHECK_EQ_INT(exteria_pbkdf2_sha512((const uint8_t *)"p", 1, (const uint8_t *)"s", 1, 0, out, 64), EXTERIA_E_ARG);
}

static void test_ige(void) {
    uint8_t key[32], iv[32], pt[48], ct[48], want[48], buf[48];
    test_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", key, 32);
    test_hex("404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f", iv, 32);
    test_hex("030a11181f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ff060d141b222930373e454c", pt, 48);
    test_hex("feeae482577680900f741a7f544223043c54c1ad2038d946625855808e1e231d6a8a661e0ea0faaa7ddf7754a4fc8f52", want, 48);
    CHECK_EQ_INT(exteria_aes_ige(key, iv, 1, pt, ct, 48), EXTERIA_OK);
    CHECK_MEM(ct, want, 48);
    CHECK_EQ_INT(exteria_aes_ige(key, iv, 0, ct, buf, 48), EXTERIA_OK);
    CHECK_MEM(buf, pt, 48);
    memcpy(buf, pt, 48);
    CHECK_EQ_INT(exteria_aes_ige(key, iv, 1, buf, buf, 48), EXTERIA_OK);
    CHECK_MEM(buf, want, 48);
    CHECK_EQ_INT(exteria_aes_ige(key, iv, 1, pt, ct, 40), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_aes_ige(key, iv, 1, pt, ct, 0), EXTERIA_OK);
}

static void test_ctr(void) {
    uint8_t key[32], iv[16], pt[16], want[16], out[16], half[16];
    exteria_aes_ctr *c;
    test_hex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4", key, 32);
    test_hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", iv, 16);
    test_hex("6bc1bee22e409f96e93d7e117393172a", pt, 16);
    test_hex("601ec313775789a5b7a7f504bbf3d228", want, 16);
    c = exteria_aes_ctr_new(key, iv);
    CHECK(c != NULL);
    CHECK_EQ_INT(exteria_aes_ctr_apply(c, pt, out, 16), EXTERIA_OK);
    CHECK_MEM(out, want, 16);
    exteria_aes_ctr_free(c);
    /* socket chunk boundaries must not change the obfuscation keystream */
    c = exteria_aes_ctr_new(key, iv);
    CHECK_EQ_INT(exteria_aes_ctr_apply(c, pt, half, 5), EXTERIA_OK);
    CHECK_EQ_INT(exteria_aes_ctr_apply(c, pt + 5, half + 5, 11), EXTERIA_OK);
    CHECK_MEM(half, want, 16);
    exteria_aes_ctr_free(c);
}

static void test_hmac_and_aes128(void) {
    /* RFC 2202 cases 1, 2 and 6 */
    uint8_t key[80], want[20], out[20], big[EXTERIA_HMAC_MAX_MESSAGE + 1];
    exteria_slice parts[2];
    memset(key, 0x0b, 20);
    parts[0].data = (const uint8_t *)"Hi ";
    parts[0].len = 3;
    parts[1].data = (const uint8_t *)"There";
    parts[1].len = 5;
    test_hex("b617318655057264e28bc0b6fb378c8ef146be00", want, 20);
    CHECK_EQ_INT(exteria_hmac_sha1(key, 20, parts, 2, out), EXTERIA_OK);
    CHECK_MEM(out, want, 20);
    parts[0].data = (const uint8_t *)"what do ya want for nothing?";
    parts[0].len = 28;
    test_hex("effcdf6ae5eb2fa2d27416d5f184df9c259a7c79", want, 20);
    CHECK_EQ_INT(exteria_hmac_sha1((const uint8_t *)"Jefe", 4, parts, 1, out), EXTERIA_OK);
    CHECK_MEM(out, want, 20);
    memset(key, 0xaa, 80);
    parts[0].data = (const uint8_t *)"Test Using Larger Than Block-Size Key - Hash Key First";
    parts[0].len = 54;
    test_hex("aa4ae5e15272d00e95705637ce8a3b55ed402112", want, 20);
    CHECK_EQ_INT(exteria_hmac_sha1(key, 80, parts, 1, out), EXTERIA_OK);
    CHECK_MEM(out, want, 20);
    /* the join is bounded */
    memset(big, 1, sizeof(big));
    parts[0].data = big;
    parts[0].len = sizeof(big);
    CHECK_EQ_INT(exteria_hmac_sha1(key, 80, parts, 1, out), EXTERIA_E_LIMIT);
    parts[0].len = EXTERIA_HMAC_MAX_MESSAGE;
    CHECK_EQ_INT(exteria_hmac_sha1(key, 80, parts, 1, out), EXTERIA_OK);
    CHECK_EQ_INT(exteria_hmac_sha1(NULL, 4, parts, 1, out), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_hmac_sha1(key, 80, parts, 1, NULL), EXTERIA_E_ARG);

    /* NIST SP 800-38A F.5.1, both blocks in one call, then in place */
    {
        uint8_t k[16], iv[16], pt[32], ct[32], got[32];
        test_hex("2b7e151628aed2a6abf7158809cf4f3c", k, 16);
        test_hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", iv, 16);
        test_hex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51", pt, 32);
        test_hex("874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff", ct, 32);
        CHECK_EQ_INT(exteria_aes128_ctr(k, iv, pt, got, 32), EXTERIA_OK);
        CHECK_MEM(got, ct, 32);
        memcpy(got, pt, 32);
        CHECK_EQ_INT(exteria_aes128_ctr(k, iv, got, got, 32), EXTERIA_OK);
        CHECK_MEM(got, ct, 32);
        CHECK_EQ_INT(exteria_aes128_ctr(k, iv, pt, got, 0), EXTERIA_OK);
        CHECK_EQ_INT(exteria_aes128_ctr(NULL, iv, pt, got, 16), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_aes128_ctr(k, iv, NULL, got, 16), EXTERIA_E_ARG);
    }
}

static void test_bn(void) {
    exteria_bn *a = exteria_bn_from_u64(0xffffffffffffffffull);
    exteria_bn *b = exteria_bn_from_u64(3);
    exteria_bn *m = exteria_bn_from_u64(1000000007ull);
    exteria_bn *r;
    uint8_t out[16];
    size_t len = 0;
    CHECK(a && b && m);
    CHECK_EQ_INT(exteria_bn_bits(a), 64);
    r = exteria_bn_mod_exp(b, a, m);
    CHECK(r != NULL);
    /* python pow supplies a result independent of the bn adapter */
    CHECK_EQ_INT(exteria_bn_to_bin(r, out, sizeof(out), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 4);
    CHECK_EQ_INT(exteria_get_u32be(out), 0x02172a51u);
    exteria_bn_free(r);
    r = exteria_bn_sub(a, b);
    CHECK(r != NULL);
    CHECK_EQ_INT(exteria_bn_mod_word(r, 1000), 612);
    exteria_bn_free(r);
    CHECK(exteria_bn_sub(b, a) == NULL);
    exteria_bn_free(a);
    a = exteria_bn_from_u64(2305843009213693951ull);
    CHECK(exteria_bn_is_prime(a));
    exteria_bn_free(a);
    a = exteria_bn_from_u64(2305843009213693953ull);
    CHECK(!exteria_bn_is_prime(a));
    CHECK_EQ_INT(exteria_bn_to_bin_padded(a, out, 4), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_bn_to_bin_padded(a, out, 16), EXTERIA_OK);
    CHECK_EQ_INT(out[8], 0x20);
    exteria_bn_free(a);
    exteria_bn_free(b);
    exteria_bn_free(m);
}

static void test_rsa_raw(void) {
    uint8_t n[2] = { 0x0c, 0xa1 };
    uint8_t in[2] = { 0x00, 0x41 };
    uint8_t out[2];
    CHECK_EQ_INT(exteria_rsa_public_raw(n, 2, 17, in, 2, out), EXTERIA_OK);
    CHECK_EQ_INT(out[0] * 256 + out[1], 2790);
    in[0] = 0x0c;
    in[1] = 0xa1;
    CHECK_EQ_INT(exteria_rsa_public_raw(n, 2, 17, in, 2, out), EXTERIA_E_ARG);
}

static void test_bytes(void) {
    exteria_reader r;
    exteria_writer w;
    uint8_t buf[6] = { 1, 2, 3, 4, 5, 6 };
    exteria_arena a;
    uint8_t *p;
    exteria_reader_init(&r, buf, sizeof(buf));
    CHECK_EQ_INT(exteria_rd_u32le(&r), 0x04030201u);
    CHECK_EQ_INT(exteria_rd_u32le(&r), 0);
    CHECK_EQ_INT(r.status, EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(exteria_rd_u8(&r), 0);
    exteria_writer_init(&w, 8);
    CHECK_EQ_INT(exteria_wr_u32le(&w, 0xaabbccddu), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wr_u32be(&w, 0x01020304u), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wr_u8(&w, 9), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(w.len, 8);
    CHECK_EQ_INT(w.data[0], 0xdd);
    CHECK_EQ_INT(w.data[4], 1);
    exteria_writer_free(&w);
    CHECK(exteria_ct_equal("abcd", "abcd", 4));
    CHECK(!exteria_ct_equal("abcd", "abce", 4));
    exteria_arena_init(&a, 100);
    p = (uint8_t *)exteria_arena_alloc(&a, 60);
    CHECK(p != NULL);
    CHECK(exteria_arena_alloc(&a, 60) == NULL);
    CHECK(exteria_arena_alloc(&a, 30) != NULL);
    exteria_arena_free(&a);
}

static void test_random(void) {
    uint8_t a[32], b[32];
    CHECK_EQ_INT(exteria_random(a, sizeof(a)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_random(b, sizeof(b)), EXTERIA_OK);
    CHECK(memcmp(a, b, sizeof(a)) != 0);
}

static void test_prime_boundaries(void) {
    static const uint64_t values[] = { 0, 1, 2, 3, 4, 561, 1105, 1729, 3215031751ull, 65537 };
    static const int prime[] = { 0, 0, 1, 1, 0, 0, 0, 0, 0, 1 };
    unsigned i;
    CHECK_EQ_INT(exteria_bn_is_prime(NULL), 0);
    for (i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
        exteria_bn *n = exteria_bn_from_u64(values[i]);
        CHECK(n != NULL);
        CHECK_EQ_INT(exteria_bn_is_prime(n), prime[i]);
        exteria_bn_free(n);
    }
}

int main(void) {
    test_hashes();
    test_pbkdf2();
    test_ige();
    test_ctr();
    test_hmac_and_aes128();
    test_bn();
    test_prime_boundaries();
    test_rsa_raw();
    test_bytes();
    test_random();
    return test_finish("test_crypto");
}
