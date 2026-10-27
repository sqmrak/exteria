#include "test_util.h"
#include "exteria_faketls.h"

static void hex(const char *text, uint8_t *out, size_t n) {
    size_t i;
    for (i = 0; i < n; ++i) {
        unsigned v;
        sscanf(text + 2 * i, "%2x", &v);
        out[i] = (uint8_t)v;
    }
}

static void test_hmac(void) {
    uint8_t key[131], want[32], got[32];
    exteria_slice part;
    memset(key, 0x0b, 20);
    part.data = (const uint8_t *)"Hi There";
    part.len = 8;
    CHECK_EQ_INT(exteria_faketls_hmac(key, 20, &part, 1, got), EXTERIA_OK);
    hex("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", want, 32);
    CHECK(!memcmp(got, want, 32));
    part.data = (const uint8_t *)"what do ya want for nothing?";
    part.len = 28;
    CHECK_EQ_INT(exteria_faketls_hmac((const uint8_t *)"Jefe", 4, &part, 1, got), EXTERIA_OK);
    hex("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", want, 32);
    CHECK(!memcmp(got, want, 32));
    /* a key longer than the block is hashed first, and the message may come in parts */
    memset(key, 0xaa, sizeof(key));
    {
        exteria_slice two[2];
        two[0].data = (const uint8_t *)"Test Using Larger Than Block-Size";
        two[0].len = 33;
        two[1].data = (const uint8_t *)" Key - Hash Key First";
        two[1].len = 21;
        CHECK_EQ_INT(exteria_faketls_hmac(key, sizeof(key), two, 2, got), EXTERIA_OK);
        hex("60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54", want, 32);
        CHECK(!memcmp(got, want, 32));
    }
    CHECK_EQ_INT(exteria_faketls_hmac(key, 4, &part, 0, got), EXTERIA_E_ARG);
}

static void entropy_of(uint8_t entropy[EXTERIA_FAKETLS_ENTROPY_LEN], uint8_t seed) {
    size_t i;
    for (i = 0; i < EXTERIA_FAKETLS_ENTROPY_LEN; ++i) entropy[i] = (uint8_t)(seed + i * 7);
}

/* the extensions of a hello must add up to the end of the record */
static void check_structure(const uint8_t *hello, const char *domain) {
    size_t at = 5 + 4 + 2 + 32;
    size_t n, end = EXTERIA_FAKETLS_HELLO_LEN;
    int saw_sni = 0, saw_padding = 0;
    CHECK_EQ_INT(hello[0], 0x16);
    CHECK_EQ_INT(hello[3] << 8 | hello[4], EXTERIA_FAKETLS_HELLO_LEN - 5);
    CHECK_EQ_INT(hello[5], 0x01);
    CHECK_EQ_INT(hello[6] << 16 | hello[7] << 8 | hello[8], EXTERIA_FAKETLS_HELLO_LEN - 9);
    CHECK_EQ_INT(hello[at], 32);
    at += 1 + 32;
    n = (size_t)hello[at] << 8 | hello[at + 1];
    CHECK_EQ_INT(n, 32);
    at += 2 + n;
    CHECK_EQ_INT(hello[at], 1);
    CHECK_EQ_INT(hello[at + 1], 0);
    at += 2;
    n = (size_t)hello[at] << 8 | hello[at + 1];
    at += 2;
    CHECK_EQ_INT(at + n, end);
    while (at + 4 <= end) {
        unsigned type = (unsigned)hello[at] << 8 | hello[at + 1];
        size_t len = (size_t)hello[at + 2] << 8 | hello[at + 3];
        CHECK(at + 4 + len <= end);
        if (type == 0x0000) {
            size_t name_len = (size_t)hello[at + 7] << 8 | hello[at + 8];
            CHECK_EQ_INT(len, name_len + 5);
            CHECK(name_len == strlen(domain) && !memcmp(hello + at + 9, domain, name_len));
            saw_sni = 1;
        }
        if (type == 0x0015) saw_padding = 1;
        at += 4 + len;
    }
    CHECK_EQ_INT(at, end);
    CHECK(saw_sni && saw_padding);
}

static void test_hello(void) {
    uint8_t secret[16], entropy[EXTERIA_FAKETLS_ENTROPY_LEN], hello[EXTERIA_FAKETLS_HELLO_LEN], random[32], zeroed[EXTERIA_FAKETLS_HELLO_LEN], digest[32];
    exteria_slice part;
    char longest[EXTERIA_FAKETLS_DOMAIN_MAX + 2];
    size_t i;
    memset(secret, 0x5a, sizeof(secret));
    entropy_of(entropy, 3);
    CHECK_EQ_INT(exteria_faketls_hello(secret, "video.vkcommt.space", 0x12345678u, entropy, hello, random), EXTERIA_OK);
    check_structure(hello, "video.vkcommt.space");
    CHECK(!memcmp(hello + 11, random, 32));
    /* the random field is the HMAC of the hello with the field zeroed, with the clock in its last four bytes */
    memcpy(zeroed, hello, sizeof(zeroed));
    memset(zeroed + 11, 0, 32);
    part.data = zeroed;
    part.len = sizeof(zeroed);
    CHECK_EQ_INT(exteria_faketls_hmac(secret, 16, &part, 1, digest), EXTERIA_OK);
    CHECK_EQ_INT(random[28] ^ digest[28], 0x78);
    CHECK_EQ_INT(random[29] ^ digest[29], 0x56);
    CHECK_EQ_INT(random[30] ^ digest[30], 0x34);
    CHECK_EQ_INT(random[31] ^ digest[31], 0x12);
    CHECK(!memcmp(random, digest, 28));
    /* the session id and the key share come from the entropy, and the clock changes the field alone */
    CHECK(!memcmp(hello + 44, entropy, 32));
    {
        uint8_t other[EXTERIA_FAKETLS_HELLO_LEN], other_random[32];
        CHECK_EQ_INT(exteria_faketls_hello(secret, "video.vkcommt.space", 0x12345679u, entropy, other, other_random), EXTERIA_OK);
        CHECK(!memcmp(hello + 43, other + 43, EXTERIA_FAKETLS_HELLO_LEN - 43) || memcmp(random, other_random, 32) != 0);
    }
    /* the longest domain still fits */
    for (i = 0; i < EXTERIA_FAKETLS_DOMAIN_MAX; ++i) longest[i] = (char)(i % 20 == 19 ? '.' : 'a');
    longest[EXTERIA_FAKETLS_DOMAIN_MAX] = 0;
    CHECK_EQ_INT(exteria_faketls_hello(secret, longest, 1, entropy, hello, random), EXTERIA_OK);
    check_structure(hello, longest);
    longest[EXTERIA_FAKETLS_DOMAIN_MAX] = 'a';
    longest[EXTERIA_FAKETLS_DOMAIN_MAX + 1] = 0;
    CHECK_EQ_INT(exteria_faketls_hello(secret, longest, 1, entropy, hello, random), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_faketls_hello(secret, "", 1, entropy, hello, random), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_faketls_hello(secret, "a b", 1, entropy, hello, random), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_faketls_hello(secret, "a/b", 1, entropy, hello, random), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_faketls_hello(secret, NULL, 1, entropy, hello, random), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_faketls_hello(NULL, "a.b", 1, entropy, hello, random), EXTERIA_E_ARG);
}

/* a reply as a proxy that holds the secret builds it */
static size_t make_reply(const uint8_t secret[16], const uint8_t random[32], uint8_t *reply, size_t hello_len, size_t app_len) {
    exteria_slice parts[2];
    uint8_t digest[32];
    size_t at = 0, i;
    reply[0] = 0x16; reply[1] = 3; reply[2] = 3;
    reply[3] = (uint8_t)(hello_len >> 8); reply[4] = (uint8_t)hello_len;
    for (i = 0; i < hello_len; ++i) reply[5 + i] = (uint8_t)(i * 13);
    reply[5] = 2;
    memset(reply + 11, 0, 32);
    at = 5 + hello_len;
    memcpy(reply + at, "\x14\x03\x03\x00\x01\x01", 6);
    at += 6;
    reply[at] = 0x17; reply[at + 1] = 3; reply[at + 2] = 3;
    reply[at + 3] = (uint8_t)(app_len >> 8); reply[at + 4] = (uint8_t)app_len;
    for (i = 0; i < app_len; ++i) reply[at + 5 + i] = (uint8_t)(i * 29);
    at += 5 + app_len;
    parts[0].data = random;
    parts[0].len = 32;
    parts[1].data = reply;
    parts[1].len = at;
    CHECK_EQ_INT(exteria_faketls_hmac(secret, 16, parts, 2, digest), EXTERIA_OK);
    memcpy(reply + 11, digest, 32);
    return at;
}

static void test_reply(void) {
    uint8_t secret[16], other[16], random[32], reply[4096];
    size_t total, len, cut, seen = 0;
    memset(secret, 0x21, sizeof(secret));
    memset(other, 0x22, sizeof(other));
    memset(random, 0x77, sizeof(random));
    len = make_reply(secret, random, reply, 90, 120);
    CHECK_EQ_INT(exteria_faketls_check_reply(secret, random, reply, len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_faketls_check_reply(other, random, reply, len), EXTERIA_E_SECURITY);
    random[0] ^= 1;
    CHECK_EQ_INT(exteria_faketls_check_reply(secret, random, reply, len), EXTERIA_E_SECURITY);
    random[0] ^= 1;
    reply[len - 1] ^= 1;
    CHECK_EQ_INT(exteria_faketls_check_reply(secret, random, reply, len), EXTERIA_E_SECURITY);
    reply[len - 1] ^= 1;
    reply[20] ^= 1;
    CHECK_EQ_INT(exteria_faketls_check_reply(secret, random, reply, len), EXTERIA_E_SECURITY);
    reply[20] ^= 1;
    CHECK_EQ_INT(exteria_faketls_check_reply(secret, random, reply, len - 1), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_faketls_check_reply(secret, random, reply, len + 0), EXTERIA_OK);
    /* the progress of a reply that arrives in pieces */
    for (cut = 0; cut < len; ++cut) {
        exteria_status status = exteria_faketls_reply_progress(reply, cut, &total);
        CHECK_EQ_INT(status, EXTERIA_E_RETRY);
        CHECK(total <= len);
        ++seen;
    }
    CHECK_EQ_INT(exteria_faketls_reply_progress(reply, len, &total), EXTERIA_OK);
    CHECK_EQ_INT(total, len);
    CHECK(seen == len);
    /* more than the reply is not a reply to check, but its first three records are complete */
    reply[len] = 0x17;
    CHECK_EQ_INT(exteria_faketls_reply_progress(reply, len + 1, &total), EXTERIA_OK);
    CHECK_EQ_INT(total, len);
    /* not a server hello, not the version, a change cipher spec that is not, an application record that is not */
    reply[0] = 0x15;
    CHECK_EQ_INT(exteria_faketls_reply_progress(reply, len, &total), EXTERIA_E_MALFORMED);
    reply[0] = 0x16;
    reply[2] = 1;
    CHECK_EQ_INT(exteria_faketls_reply_progress(reply, len, &total), EXTERIA_E_MALFORMED);
    reply[2] = 3;
    reply[5 + 90] = 0x15;
    CHECK_EQ_INT(exteria_faketls_reply_progress(reply, len, &total), EXTERIA_E_MALFORMED);
    reply[5 + 90] = 0x14;
    reply[5 + 90 + 6] = 0x16;
    CHECK_EQ_INT(exteria_faketls_reply_progress(reply, len, &total), EXTERIA_E_MALFORMED);
    /* a hello too short to hold a random field, or a record longer than TLS allows */
    memset(reply, 0, 16);
    reply[0] = 0x16; reply[1] = 3; reply[2] = 3; reply[3] = 0; reply[4] = 10;
    CHECK_EQ_INT(exteria_faketls_reply_progress(reply, 15, &total), EXTERIA_E_MALFORMED);
    reply[3] = 0x7f; reply[4] = 0xff;
    CHECK_EQ_INT(exteria_faketls_reply_progress(reply, 15, &total), EXTERIA_E_MALFORMED);
}

static void test_stream(void) {
    uint8_t data[7000], out[7100], back[7100];
    exteria_writer w;
    exteria_faketls_reader r;
    size_t i, got, produced = 0, step, at;
    for (i = 0; i < sizeof(data); ++i) data[i] = (uint8_t)(i * 31 + 5);
    exteria_writer_init(&w, 1u << 20);
    CHECK_EQ_INT(exteria_faketls_wrap(data, sizeof(data), &w), EXTERIA_OK);
    /* 7000 bytes is three records of at most 2878, each with its header */
    CHECK_EQ_INT(w.len, sizeof(data) + 3 * 5);
    CHECK_EQ_INT(w.data[0], 0x17);
    CHECK_EQ_INT(w.data[3] << 8 | w.data[4], EXTERIA_FAKETLS_RECORD_MAX);
    CHECK_EQ_INT(exteria_faketls_wrap(NULL, 0, &w), EXTERIA_OK);
    CHECK_EQ_INT(exteria_faketls_wrap(NULL, 1, &w), EXTERIA_E_ARG);
    /* the same bytes in every cut, one at a time included */
    for (step = 1; step <= 7; step += (step == 1 ? 1 : 2)) {
        exteria_faketls_reader_init(&r);
        produced = 0;
        for (at = 0; at < w.len; at += step) {
            size_t n = w.len - at < step ? w.len - at : step;
            CHECK_EQ_INT(exteria_faketls_unwrap(&r, w.data + at, n, out, sizeof(out), &got), EXTERIA_OK);
            CHECK(got <= n);
            memcpy(back + produced, out, got);
            produced += got;
        }
        CHECK_EQ_INT(produced, sizeof(data));
        CHECK(!memcmp(back, data, sizeof(data)));
    }
    exteria_writer_free(&w);
    /* a change cipher spec between records is skipped, and an empty application record gives nothing */
    {
        const uint8_t mixed[] = {0x14, 3, 3, 0, 1, 1, 0x17, 3, 3, 0, 0, 0x17, 3, 3, 0, 3, 'a', 'b', 'c'};
        exteria_faketls_reader_init(&r);
        CHECK_EQ_INT(exteria_faketls_unwrap(&r, mixed, sizeof(mixed), out, sizeof(out), &got), EXTERIA_OK);
        CHECK_EQ_INT(got, 3);
        CHECK(!memcmp(out, "abc", 3));
    }
    /* an alert, a handshake record, a wrong version, a record that is too long, and an output that cannot hold the input */
    {
        const uint8_t alert[] = {0x15, 3, 3, 0, 2, 2, 0x28};
        const uint8_t shake[] = {0x16, 3, 3, 0, 1, 0};
        const uint8_t old[] = {0x17, 3, 1, 0, 1, 0};
        const uint8_t huge[] = {0x17, 3, 3, 0xff, 0xff, 0};
        exteria_faketls_reader_init(&r);
        CHECK_EQ_INT(exteria_faketls_unwrap(&r, alert, sizeof(alert), out, sizeof(out), &got), EXTERIA_E_MALFORMED);
        exteria_faketls_reader_init(&r);
        CHECK_EQ_INT(exteria_faketls_unwrap(&r, shake, sizeof(shake), out, sizeof(out), &got), EXTERIA_E_MALFORMED);
        exteria_faketls_reader_init(&r);
        CHECK_EQ_INT(exteria_faketls_unwrap(&r, old, sizeof(old), out, sizeof(out), &got), EXTERIA_E_MALFORMED);
        exteria_faketls_reader_init(&r);
        CHECK_EQ_INT(exteria_faketls_unwrap(&r, huge, sizeof(huge), out, sizeof(out), &got), EXTERIA_E_MALFORMED);
        exteria_faketls_reader_init(&r);
        CHECK_EQ_INT(exteria_faketls_unwrap(&r, alert, sizeof(alert), out, 3, &got), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_faketls_unwrap(&r, alert, 0, out, 0, &got), EXTERIA_OK);
    }
}

int main(void) {
    test_hmac();
    test_hello();
    test_reply();
    test_stream();
    return test_finish("test_faketls");
}
