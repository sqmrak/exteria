#include "test_util.h"
#include "exteria_dns.h"

static void test_query(void) {
    uint8_t out[EXTERIA_DNS_QUERY_MAX];
    size_t len = 0;
    static const uint8_t expected[] = {
        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        4, 't', 'i', 'l', 'e', 3, 'o', 'r', 'g', 0, 0x00, 0x01, 0x00, 0x01};
    CHECK_EQ_INT(exteria_dns_query_a("tile.org", 0x1234, out, sizeof(out), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, sizeof(expected));
    CHECK(memcmp(out, expected, sizeof(expected)) == 0);
    /* one trailing dot is the same name */
    CHECK_EQ_INT(exteria_dns_query_a("tile.org.", 0x1234, out, sizeof(out), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, sizeof(expected));
    CHECK(memcmp(out, expected, sizeof(expected)) == 0);
    CHECK_EQ_INT(exteria_dns_query_a("a_b-1.example.com", 1, out, sizeof(out), &len), EXTERIA_OK);
}

static void test_query_rejects(void) {
    uint8_t out[EXTERIA_DNS_QUERY_MAX];
    uint8_t small[16];
    size_t len = 99;
    char long_label[80], long_name[300];
    CHECK_EQ_INT(exteria_dns_query_a("", 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_dns_query_a(".", 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dns_query_a("a..b", 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dns_query_a(".a", 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dns_query_a("a b.org", 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dns_query_a("a/b.org", 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dns_query_a("a\n.org", 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dns_query_a(NULL, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    memset(long_label, 'a', 64);
    long_label[64] = 0;
    CHECK_EQ_INT(exteria_dns_query_a(long_label, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    long_label[63] = 0;
    CHECK_EQ_INT(exteria_dns_query_a(long_label, 1, out, sizeof(out), &len), EXTERIA_OK);
    memset(long_name, 'a', sizeof(long_name));
    for (size_t i = 10; i < sizeof(long_name); i += 11) long_name[i] = '.';
    long_name[299] = 0;
    CHECK_EQ_INT(exteria_dns_query_a(long_name, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dns_query_a("tile.openstreetmap.org", 1, small, sizeof(small), &len), EXTERIA_E_LIMIT);
}

/* the answer of a resolver to "tile.org": the question, a cname through a compression pointer, then the address */
static size_t answer(uint8_t *out, uint16_t id, unsigned flags, unsigned answers, int with_a) {
    size_t at = 0;
    static const uint8_t name[] = {4, 't', 'i', 'l', 'e', 3, 'o', 'r', 'g', 0};
    out[at++] = (uint8_t)(id >> 8);
    out[at++] = (uint8_t)id;
    out[at++] = (uint8_t)(flags >> 8);
    out[at++] = (uint8_t)flags;
    out[at++] = 0; out[at++] = 1;
    out[at++] = (uint8_t)(answers >> 8); out[at++] = (uint8_t)answers;
    out[at++] = 0; out[at++] = 0; out[at++] = 0; out[at++] = 0;
    memcpy(out + at, name, sizeof(name));
    at += sizeof(name);
    out[at++] = 0; out[at++] = 1; out[at++] = 0; out[at++] = 1;
    if (answers >= 1) {
        /* cname with a pointer to the question name */
        out[at++] = 0xC0; out[at++] = 12;
        out[at++] = 0; out[at++] = 5; out[at++] = 0; out[at++] = 1;
        out[at++] = 0; out[at++] = 0; out[at++] = 1; out[at++] = 0;
        out[at++] = 0; out[at++] = 2;
        out[at++] = 0xC0; out[at++] = 12;
    }
    if (answers >= 2) {
        out[at++] = 0xC0; out[at++] = 12;
        out[at++] = 0; out[at++] = with_a ? 1 : 28; out[at++] = 0; out[at++] = 1;
        out[at++] = 0; out[at++] = 0; out[at++] = 0x01; out[at++] = 0x2C;
        out[at++] = 0; out[at++] = with_a ? 4 : 16;
        if (with_a) {
            out[at++] = 199; out[at++] = 232; out[at++] = 173; out[at++] = 91;
        } else {
            memset(out + at, 0, 16);
            at += 16;
        }
    }
    return at;
}

static void test_answer(void) {
    uint8_t msg[EXTERIA_DNS_ANSWER_MAX];
    uint32_t ip = 0, ttl = 0;
    size_t len = answer(msg, 0x1234, 0x8180, 2, 1);
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 0x1234, &ip, &ttl), EXTERIA_OK);
    CHECK_EQ_INT(ip, (199u << 24) | (232u << 16) | (173u << 8) | 91u);
    CHECK_EQ_INT(ttl, 300);
    /* an answer of another query */
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 0x1235, &ip, &ttl), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(ip, 0);
    /* only an aaaa record, or none */
    len = answer(msg, 7, 0x8180, 2, 0);
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 7, &ip, &ttl), EXTERIA_E_NOTFOUND);
    len = answer(msg, 7, 0x8180, 0, 0);
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 7, &ip, &ttl), EXTERIA_E_NOTFOUND);
}

static void test_answer_failures(void) {
    uint8_t msg[EXTERIA_DNS_ANSWER_MAX];
    uint32_t ip = 0, ttl = 0;
    size_t len = answer(msg, 9, 0x8183, 0, 0);
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 9, &ip, &ttl), EXTERIA_E_NOTFOUND);
    len = answer(msg, 9, 0x8182, 0, 0);
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 9, &ip, &ttl), EXTERIA_E_IO);
    len = answer(msg, 9, 0x8380, 2, 1);
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 9, &ip, &ttl), EXTERIA_E_RETRY);
    /* a query, not an answer */
    len = answer(msg, 9, 0x0100, 2, 1);
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 9, &ip, &ttl), EXTERIA_E_MALFORMED);
    /* every cut of a good answer is refused, never read past its end */
    len = answer(msg, 9, 0x8180, 2, 1);
    for (size_t cut = 0; cut < len; ++cut) {
        exteria_status status = exteria_dns_answer_a(msg, cut, 9, &ip, &ttl);
        CHECK(status != EXTERIA_OK);
    }
    /* a record whose data runs past the end */
    len = answer(msg, 9, 0x8180, 2, 1);
    msg[len - 5] = 0xFF;
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 9, &ip, &ttl), EXTERIA_E_MALFORMED);
    /* two questions, reserved label bits, too many records, a name that never ends */
    len = answer(msg, 9, 0x8180, 2, 1);
    msg[5] = 2;
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 9, &ip, &ttl), EXTERIA_E_MALFORMED);
    len = answer(msg, 9, 0x8180, 2, 1);
    msg[12] = 0x80;
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 9, &ip, &ttl), EXTERIA_E_MALFORMED);
    len = answer(msg, 9, 0x8180, 2, 1);
    msg[7] = 200;
    CHECK_EQ_INT(exteria_dns_answer_a(msg, len, 9, &ip, &ttl), EXTERIA_E_MALFORMED);
    memset(msg, 0, sizeof(msg));
    msg[1] = 9; msg[2] = 0x81; msg[3] = 0x80; msg[5] = 1; msg[7] = 1;
    memset(msg + 12, 1, 400);
    memset(msg + 12, 0x01, 400);
    CHECK_EQ_INT(exteria_dns_answer_a(msg, 412, 9, &ip, &ttl), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_dns_answer_a(msg, EXTERIA_DNS_ANSWER_MAX + 1, 9, &ip, &ttl), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_dns_answer_a(NULL, 12, 9, &ip, &ttl), EXTERIA_E_ARG);
}

int main(void) {
    test_query();
    test_query_rejects();
    test_answer();
    test_answer_failures();
    return test_finish("test_dns");
}
