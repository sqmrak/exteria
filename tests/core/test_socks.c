#include "exteria_socks.h"
#include "test_util.h"

static void fragmented_reply(void) {
    exteria_socks s;
    exteria_writer out;
    size_t consumed, i;
    const uint8_t greeting[] = {5, 1, 0};
    const uint8_t method[] = {5, 0};
    const uint8_t request[] = {5, 1, 0, 1, 127, 0, 0, 1, 1, 187};
    const uint8_t reply[] = {5, 0, 0, 3, 3, 'p', 'x', 'y', 1, 187, 0xaa, 0xbb};
    exteria_writer_init(&out, 1024);
    CHECK_EQ_INT(exteria_socks_start(&s, "127.0.0.1", 443, NULL, NULL, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.len, sizeof(greeting));
    CHECK_MEM(out.data, greeting, sizeof(greeting));
    out.len = 0;
    for (i = 0; i < sizeof(method); ++i) {
        CHECK_EQ_INT(exteria_socks_feed(&s, method + i, 1, &consumed, &out), EXTERIA_OK);
        CHECK_EQ_INT(consumed, 1);
    }
    CHECK_EQ_INT(s.state, EXTERIA_SOCKS_CONNECT);
    CHECK_EQ_INT(out.len, sizeof(request));
    CHECK_MEM(out.data, request, sizeof(request));
    out.len = 0;
    for (i = 0; i < 9; ++i) {
        CHECK_EQ_INT(exteria_socks_feed(&s, reply + i, 1, &consumed, &out), EXTERIA_OK);
        CHECK_EQ_INT(consumed, 1);
        CHECK_EQ_INT(s.state, EXTERIA_SOCKS_CONNECT);
    }
    CHECK_EQ_INT(exteria_socks_feed(&s, reply + 9, 3, &consumed, &out), EXTERIA_OK);
    CHECK_EQ_INT(consumed, 1);
    CHECK_EQ_INT(s.state, EXTERIA_SOCKS_READY);
    CHECK_EQ_INT(out.len, 0);
    exteria_socks_free(&s);
    exteria_writer_free(&out);
}

static void credentials_and_rejection(void) {
    exteria_socks s;
    exteria_writer out;
    size_t consumed, i;
    const uint8_t credentials[] = {1, 1, 'u', 1, 'p'};
    const uint8_t method[] = {5, 2};
    const uint8_t authenticated[] = {1, 0};
    const uint8_t downgrade[] = {5, 0};
    const uint8_t malformed[][5] = {
        {5, 0, 1, 1, 0}, {5, 0, 0, 2, 0}, {5, 0, 0, 3, 0}, {4, 0, 0, 1, 0}, {5, 5, 0, 1, 0}
    };
    exteria_writer_init(&out, 1024);
    CHECK_EQ_INT(exteria_socks_start(&s, "::1", 443, "u", "p", &out), EXTERIA_OK);
    CHECK_EQ_INT(out.data[2], 2);
    out.len = 0;
    CHECK_EQ_INT(exteria_socks_feed(&s, method, sizeof(method), &consumed, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.len, sizeof(credentials));
    CHECK_MEM(out.data, credentials, sizeof(credentials));
    for (i = 0; i < sizeof(s.credentials); ++i) CHECK_EQ_INT(s.credentials[i], 0);
    out.len = 0;
    CHECK_EQ_INT(exteria_socks_feed(&s, authenticated, sizeof(authenticated), &consumed, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.len, 22);
    CHECK_EQ_INT(out.data[3], 4);
    exteria_socks_free(&s);
    out.len = 0;
    CHECK_EQ_INT(exteria_socks_start(&s, "proxy.example", 443, "u", "p", &out), EXTERIA_OK);
    CHECK_EQ_INT(exteria_socks_feed(&s, downgrade, sizeof(downgrade), &consumed, &out), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(s.state, EXTERIA_SOCKS_FAILED);
    for (i = 0; i < sizeof(s.credentials); ++i) CHECK_EQ_INT(s.credentials[i], 0);
    exteria_socks_free(&s);
    for (i = 0; i < sizeof(malformed) / sizeof(malformed[0]); ++i) {
        out.len = 0;
        CHECK_EQ_INT(exteria_socks_start(&s, "proxy.example", 443, NULL, NULL, &out), EXTERIA_OK);
        CHECK_EQ_INT(exteria_socks_feed(&s, downgrade, sizeof(downgrade), &consumed, &out), EXTERIA_OK);
        CHECK(exteria_socks_feed(&s, malformed[i], sizeof(malformed[i]), &consumed, &out) != EXTERIA_OK);
        CHECK_EQ_INT(s.state, EXTERIA_SOCKS_FAILED);
        exteria_socks_free(&s);
    }
    out.len = 0;
    CHECK_EQ_INT(exteria_socks_start(&s, "bad host", 443, NULL, NULL, &out), EXTERIA_E_ARG);
    CHECK_EQ_INT(out.len, 0);
    exteria_writer_free(&out);
}

int main(void) {
    fragmented_reply();
    credentials_and_rejection();
    return test_finish("socks");
}
