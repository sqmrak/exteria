#include "test_util.h"
#include "exteria_session_file.h"

static void fill_session(exteria_mt_session_state *s) {
    unsigned i;
    for (i = 0; i < EXTERIA_MT_AUTH_KEY_LEN; ++i) s->auth_key[i] = (uint8_t)(i * 7u + 1u);
    s->server_salt = UINT64_C(0x1122334455667788);
    s->time_offset_ms = -4321;
}

static void test_dc_table(void) {
    int32_t dc;
    CHECK(exteria_dc_host(0) == NULL);
    CHECK(exteria_dc_host(EXTERIA_DC_MAX + 1) == NULL);
    CHECK(exteria_dc_host(-1) == NULL);
    for (dc = 1; dc <= EXTERIA_DC_MAX; ++dc) CHECK(exteria_dc_host(dc) != NULL && exteria_dc_host(dc)[0] != 0);
    CHECK(strcmp(exteria_dc_host(2), "149.154.167.51") == 0);
    CHECK_EQ_INT(exteria_dc_port(), 443);
}

static void test_session_round_trip(void) {
    exteria_mt_session_state in, out;
    uint8_t buf[EXTERIA_SESSION_FILE_LEN];
    size_t len = 0;
    memset(&in, 0, sizeof(in));
    fill_session(&in);
    CHECK_EQ_INT(exteria_session_pack(4, &in, buf, sizeof(buf), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, EXTERIA_SESSION_FILE_LEN);
    CHECK_EQ_INT(exteria_session_unpack(buf, len, 4, &out), EXTERIA_OK);
    CHECK_MEM(out.auth_key, in.auth_key, EXTERIA_MT_AUTH_KEY_LEN);
    CHECK(out.server_salt == in.server_salt);
    CHECK(out.time_offset_ms == in.time_offset_ms);
}

static void test_session_rejects(void) {
    exteria_mt_session_state in, out;
    uint8_t buf[EXTERIA_SESSION_FILE_LEN + 1];
    size_t len = 0, i;
    memset(&in, 0, sizeof(in));
    fill_session(&in);
    CHECK_EQ_INT(exteria_session_pack(2, &in, buf, sizeof(buf), &len), EXTERIA_OK);

    CHECK_EQ_INT(exteria_session_pack(0, &in, buf, sizeof(buf), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_session_pack(2, &in, buf, EXTERIA_SESSION_FILE_LEN - 1, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_session_pack(2, &in, buf, sizeof(buf), &len), EXTERIA_OK);

    /* a file for another data center, a short file and a long file are all rejected and leave no key behind */
    CHECK_EQ_INT(exteria_session_unpack(buf, len, 3, &out), EXTERIA_E_MALFORMED);
    for (i = 0; i < sizeof(out.auth_key); ++i) CHECK_EQ_INT(out.auth_key[i], 0);
    CHECK_EQ_INT(exteria_session_unpack(buf, len - 1, 2, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_session_unpack(buf, len + 1, 2, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_session_unpack(buf, 0, 2, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_session_unpack(buf, len, 9, &out), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_session_unpack(NULL, len, 2, &out), EXTERIA_E_ARG);
    buf[0] ^= 1;
    CHECK_EQ_INT(exteria_session_unpack(buf, len, 2, &out), EXTERIA_E_MALFORMED);
}

static void fill_key(uint8_t key[EXTERIA_SESSION_KEY_LEN], uint8_t seed) {
    unsigned i;
    for (i = 0; i < EXTERIA_SESSION_KEY_LEN; ++i) key[i] = (uint8_t)(seed + i);
}

static void test_sealed_round_trip(void) {
    exteria_mt_session_state in, out;
    uint8_t key[EXTERIA_SESSION_KEY_LEN], a[EXTERIA_SESSION_SEALED_LEN], b[EXTERIA_SESSION_SEALED_LEN];
    size_t len = 0, i;
    int plain = 7;
    memset(&in, 0, sizeof(in));
    fill_session(&in);
    fill_key(key, 1);
    CHECK_EQ_INT(exteria_session_seal(key, 3, &in, a, sizeof(a), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, EXTERIA_SESSION_SEALED_LEN);
    /* the auth key must not appear in the file */
    for (i = 0; i + EXTERIA_MT_AUTH_KEY_LEN <= len; ++i) CHECK(memcmp(a + i, in.auth_key, 16) != 0);
    CHECK_EQ_INT(exteria_session_open(key, a, len, 3, &out, &plain), EXTERIA_OK);
    CHECK_EQ_INT(plain, 0);
    CHECK_MEM(out.auth_key, in.auth_key, EXTERIA_MT_AUTH_KEY_LEN);
    CHECK(out.server_salt == in.server_salt);
    CHECK(out.time_offset_ms == in.time_offset_ms);
    /* a fresh nonce per file */
    CHECK_EQ_INT(exteria_session_seal(key, 3, &in, b, sizeof(b), &len), EXTERIA_OK);
    CHECK(memcmp(a + 4, b + 4, 12) != 0);
    CHECK_EQ_INT(exteria_session_seal(key, 3, &in, b, EXTERIA_SESSION_SEALED_LEN - 1, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_session_seal(key, 0, &in, b, sizeof(b), &len), EXTERIA_E_ARG);
}

static void test_sealed_rejects(void) {
    exteria_mt_session_state in, out;
    uint8_t key[EXTERIA_SESSION_KEY_LEN], other[EXTERIA_SESSION_KEY_LEN];
    uint8_t buf[EXTERIA_SESSION_SEALED_LEN + 1];
    size_t len = 0, i, at;
    int plain = 0;
    memset(&in, 0, sizeof(in));
    fill_session(&in);
    fill_key(key, 1);
    fill_key(other, 2);
    CHECK_EQ_INT(exteria_session_seal(key, 2, &in, buf, sizeof(buf), &len), EXTERIA_OK);

    CHECK_EQ_INT(exteria_session_open(other, buf, len, 2, &out, &plain), EXTERIA_E_SECURITY);
    for (i = 0; i < sizeof(out.auth_key); ++i) CHECK_EQ_INT(out.auth_key[i], 0);
    /* a file copied into another data center slot */
    CHECK_EQ_INT(exteria_session_open(key, buf, len, 4, &out, &plain), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_session_open(key, buf, len - 1, 2, &out, &plain), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_session_open(key, buf, len + 1, 2, &out, &plain), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_session_open(key, buf, 0, 2, &out, &plain), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_session_open(key, buf, len, 9, &out, &plain), EXTERIA_E_ARG);
    /* one flipped bit anywhere past the magic: nonce, ciphertext or tag */
    for (at = 4; at < len; at += 13) {
        buf[at] ^= 0x10;
        CHECK_EQ_INT(exteria_session_open(key, buf, len, 2, &out, &plain), EXTERIA_E_SECURITY);
        for (i = 0; i < sizeof(out.auth_key); ++i) CHECK_EQ_INT(out.auth_key[i], 0);
        buf[at] ^= 0x10;
    }
    buf[0] ^= 1;
    CHECK_EQ_INT(exteria_session_open(key, buf, len, 2, &out, &plain), EXTERIA_E_MALFORMED);
}

static void test_plain_file_still_opens(void) {
    exteria_mt_session_state in, out;
    uint8_t key[EXTERIA_SESSION_KEY_LEN], buf[EXTERIA_SESSION_FILE_LEN];
    size_t len = 0;
    int plain = 0;
    memset(&in, 0, sizeof(in));
    fill_session(&in);
    fill_key(key, 1);
    CHECK_EQ_INT(exteria_session_pack(5, &in, buf, sizeof(buf), &len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_session_open(key, buf, len, 5, &out, &plain), EXTERIA_OK);
    CHECK_EQ_INT(plain, 1);
    CHECK_MEM(out.auth_key, in.auth_key, EXTERIA_MT_AUTH_KEY_LEN);
    CHECK_EQ_INT(exteria_session_open(key, buf, len, 4, &out, &plain), EXTERIA_E_MALFORMED);
}

static void test_account(void) {
    uint8_t buf[EXTERIA_ACCOUNT_FILE_LEN];
    size_t len = 0;
    int32_t dc = 0;
    int64_t account = 0;
    CHECK_EQ_INT(exteria_account_pack(5, INT64_C(7000000000), buf, sizeof(buf), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, EXTERIA_ACCOUNT_FILE_LEN);
    CHECK_EQ_INT(exteria_account_unpack(buf, len, &dc, &account), EXTERIA_OK);
    CHECK_EQ_INT(dc, 5);
    CHECK(account == INT64_C(7000000000));

    CHECK_EQ_INT(exteria_account_pack(5, 0, buf, sizeof(buf), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_account_pack(6, 1, buf, sizeof(buf), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_account_pack(5, 1, buf, EXTERIA_ACCOUNT_FILE_LEN - 1, &len), EXTERIA_E_LIMIT);

    CHECK_EQ_INT(exteria_account_pack(1, 42, buf, sizeof(buf), &len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_account_unpack(buf, len - 1, &dc, &account), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(dc, 0);
    CHECK_EQ_INT(account, 0);
    exteria_put_u32le(buf + 4, 0);
    CHECK_EQ_INT(exteria_account_unpack(buf, len, &dc, &account), EXTERIA_E_MALFORMED);
    exteria_put_u32le(buf + 4, 1);
    exteria_put_u64le(buf + 8, (uint64_t)-5);
    CHECK_EQ_INT(exteria_account_unpack(buf, len, &dc, &account), EXTERIA_E_MALFORMED);
}

int main(void) {
    test_dc_table();
    test_session_round_trip();
    test_session_rejects();
    test_sealed_round_trip();
    test_sealed_rejects();
    test_plain_file_still_opens();
    test_account();
    if (g_failures) {
        fprintf(stderr, "test_session_file: %d of %d checks failed\n", g_failures, g_checks);
        return 1;
    }
    printf("test_session_file: %d checks passed\n", g_checks);
    return 0;
}
