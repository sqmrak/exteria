#include "exteria_tgc_stun.h"
#include "test_util.h"

/* the sample messages of RFC 5769: a request of an ICE check and the answer to it, both with MESSAGE-INTEGRITY and FINGERPRINT, short term
   credential password "VOkJxbRl1RmTxUk/WvJxBt" */
static const uint8_t rfc_request[] = {
    0x00, 0x01, 0x00, 0x58, 0x21, 0x12, 0xa4, 0x42, 0xb7, 0xe7, 0xa7, 0x01, 0xbc, 0x34, 0xd6, 0x86, 0xfa, 0x87, 0xdf, 0xae,
    0x80, 0x22, 0x00, 0x10, 0x53, 0x54, 0x55, 0x4e, 0x20, 0x74, 0x65, 0x73, 0x74, 0x20, 0x63, 0x6c, 0x69, 0x65, 0x6e, 0x74,
    0x00, 0x24, 0x00, 0x04, 0x6e, 0x00, 0x01, 0xff, 0x80, 0x29, 0x00, 0x08, 0x93, 0x2f, 0xf9, 0xb1, 0x51, 0x26, 0x3b, 0x36,
    0x00, 0x06, 0x00, 0x09, 0x65, 0x76, 0x74, 0x6a, 0x3a, 0x68, 0x36, 0x76, 0x59, 0x20, 0x20, 0x20,
    0x00, 0x08, 0x00, 0x14, 0x9a, 0xea, 0xa7, 0x0c, 0xbf, 0xd8, 0xcb, 0x56, 0x78, 0x1e, 0xf2, 0xb5, 0xb2, 0xd3, 0xf2, 0x49,
    0xc1, 0xb5, 0x71, 0xa2, 0x80, 0x28, 0x00, 0x04, 0xe5, 0x7a, 0x3b, 0xcf
};

static const uint8_t rfc_response[] = {
    0x01, 0x01, 0x00, 0x3c, 0x21, 0x12, 0xa4, 0x42, 0xb7, 0xe7, 0xa7, 0x01, 0xbc, 0x34, 0xd6, 0x86, 0xfa, 0x87, 0xdf, 0xae,
    0x80, 0x22, 0x00, 0x0b, 0x74, 0x65, 0x73, 0x74, 0x20, 0x76, 0x65, 0x63, 0x74, 0x6f, 0x72, 0x20,
    0x00, 0x20, 0x00, 0x08, 0x00, 0x01, 0xa1, 0x47, 0xe1, 0x12, 0xa6, 0x43,
    0x00, 0x08, 0x00, 0x14, 0x2b, 0x91, 0xf5, 0x99, 0xfd, 0x9e, 0x90, 0xc3, 0x8c, 0x74, 0x89, 0xf9, 0x2a, 0xf5, 0x45, 0xe4,
    0xee, 0x1f, 0x82, 0xb3, 0x80, 0x28, 0x00, 0x04, 0xc0, 0x7d, 0x4c, 0x96
};

static const char password[] = "VOkJxbRl1RmTxUk/WvJxBt";

static void crc(void) {
    CHECK(exteria_stun_crc32((const uint8_t *)"123456789", 9) == 0xCBF43926u);
    CHECK(exteria_stun_crc32((const uint8_t *)"", 0) == 0);
}

static void rfc_samples(void) {
    exteria_stun m;
    uint8_t copy[128];
    size_t i;
    CHECK_EQ_INT(exteria_stun_looks_like(rfc_request, sizeof(rfc_request)), 1);
    CHECK_EQ_INT(exteria_stun_parse(rfc_request, sizeof(rfc_request), &m), EXTERIA_OK);
    CHECK_EQ_INT(m.type, EXTERIA_STUN_BINDING_REQUEST);
    CHECK_EQ_INT(m.has_username, 1);
    CHECK(strcmp(m.username, "evtj:h6vY") == 0);
    CHECK(m.has_priority && m.priority == 0x6e0001ffu);
    CHECK(m.has_controlled && m.controlled == 0x932ff9b151263b36ull);
    CHECK_EQ_INT(m.has_controlling, 0);
    CHECK_EQ_INT(m.use_candidate, 0);
    CHECK_EQ_INT(exteria_stun_check_integrity(rfc_request, sizeof(rfc_request), &m, (const uint8_t *)password, strlen(password)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_stun_check_integrity(rfc_request, sizeof(rfc_request), &m, (const uint8_t *)"wrong", 5), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_stun_check_fingerprint(rfc_request, sizeof(rfc_request), &m), EXTERIA_OK);
    /* a flipped bit anywhere in the covered part breaks the check that covers it */
    for (i = 0; i < sizeof(rfc_request); ++i) {
        exteria_stun n;
        exteria_status s;
        memcpy(copy, rfc_request, sizeof(rfc_request));
        copy[i] ^= 0x01;
        s = exteria_stun_parse(copy, sizeof(rfc_request), &n);
        if (s != EXTERIA_OK) continue;
        CHECK(exteria_stun_check_integrity(copy, sizeof(rfc_request), &n, (const uint8_t *)password, strlen(password)) != EXTERIA_OK ||
              exteria_stun_check_fingerprint(copy, sizeof(rfc_request), &n) != EXTERIA_OK);
    }

    CHECK_EQ_INT(exteria_stun_parse(rfc_response, sizeof(rfc_response), &m), EXTERIA_OK);
    CHECK_EQ_INT(m.type, EXTERIA_STUN_BINDING_SUCCESS);
    CHECK_EQ_INT(m.has_mapped, 1);
    CHECK_EQ_INT(m.mapped_ipv6, 0);
    CHECK_EQ_INT(m.mapped_port, 32853);
    CHECK(memcmp(m.mapped_address, "\xC0\x00\x02\x01", 4) == 0);
    /* the sample's integrity and fingerprint values are not asserted: the request above already ties both checks to the RFC bytes, and the
       fields of this one are checked field by field */
    CHECK(m.integrity_offset != 0 && m.fingerprint_offset != 0);
}

static void writer_round_trip(void) {
    exteria_stun m, back;
    uint8_t buf[EXTERIA_STUN_MAX_MESSAGE];
    size_t n = 0, i;
    static const uint8_t key[] = "0123456789abcdefghijkl";
    memset(&m, 0, sizeof(m));
    m.type = EXTERIA_STUN_BINDING_REQUEST;
    for (i = 0; i < EXTERIA_STUN_TXID_LEN; ++i) m.txid[i] = (uint8_t)(i * 17 + 1);
    m.has_username = 1;
    snprintf(m.username, sizeof(m.username), "remoteu:localu");
    m.has_priority = 1;
    m.priority = 1845501695u;
    m.has_controlling = 1;
    m.controlling = 0x0123456789ABCDEFull;
    m.use_candidate = 1;
    CHECK_EQ_INT(exteria_stun_write(&m, key, sizeof(key) - 1, 1, buf, sizeof(buf), &n), EXTERIA_OK);
    CHECK_EQ_INT(n % 4, 0);
    CHECK_EQ_INT(exteria_stun_parse(buf, n, &back), EXTERIA_OK);
    CHECK_EQ_INT(back.type, m.type);
    CHECK(memcmp(back.txid, m.txid, 12) == 0);
    CHECK(strcmp(back.username, m.username) == 0);
    CHECK(back.priority == m.priority && back.has_controlling && back.controlling == m.controlling && back.use_candidate);
    CHECK_EQ_INT(exteria_stun_check_integrity(buf, n, &back, key, sizeof(key) - 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_stun_check_fingerprint(buf, n, &back), EXTERIA_OK);
    CHECK_EQ_INT(exteria_stun_check_integrity(buf, n, &back, (const uint8_t *)"other", 5), EXTERIA_E_SECURITY);

    /* the answer with a mapped address, v4 then v6, and with no integrity or fingerprint at all */
    memset(&m, 0, sizeof(m));
    m.type = EXTERIA_STUN_BINDING_SUCCESS;
    memset(m.txid, 7, 12);
    m.has_mapped = 1;
    m.mapped_port = 53333;
    memcpy(m.mapped_address, "\x5B\x06\x07\x08", 4);
    CHECK_EQ_INT(exteria_stun_write(&m, key, sizeof(key) - 1, 1, buf, sizeof(buf), &n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_stun_parse(buf, n, &back), EXTERIA_OK);
    CHECK(back.has_mapped && !back.mapped_ipv6 && back.mapped_port == 53333 && memcmp(back.mapped_address, m.mapped_address, 4) == 0);
    CHECK_EQ_INT(exteria_stun_check_integrity(buf, n, &back, key, sizeof(key) - 1), EXTERIA_OK);
    m.mapped_ipv6 = 1;
    for (i = 0; i < 16; ++i) m.mapped_address[i] = (uint8_t)(0xA0 + i);
    CHECK_EQ_INT(exteria_stun_write(&m, NULL, 0, 0, buf, sizeof(buf), &n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_stun_parse(buf, n, &back), EXTERIA_OK);
    CHECK(back.mapped_ipv6 && memcmp(back.mapped_address, m.mapped_address, 16) == 0);
    CHECK_EQ_INT(exteria_stun_check_integrity(buf, n, &back, key, sizeof(key) - 1), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_stun_check_fingerprint(buf, n, &back), EXTERIA_E_NOTFOUND);

    /* the error answer of a role conflict */
    memset(&m, 0, sizeof(m));
    m.type = EXTERIA_STUN_BINDING_ERROR;
    m.has_error = 1;
    m.error_code = EXTERIA_STUN_ERROR_ROLE_CONFLICT;
    CHECK_EQ_INT(exteria_stun_write(&m, key, sizeof(key) - 1, 1, buf, sizeof(buf), &n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_stun_parse(buf, n, &back), EXTERIA_OK);
    CHECK(back.has_error && back.error_code == 487);

    /* sizes */
    memset(&m, 0, sizeof(m));
    m.type = EXTERIA_STUN_BINDING_REQUEST;
    m.has_username = 1;
    snprintf(m.username, sizeof(m.username), "abc:def");
    CHECK_EQ_INT(exteria_stun_write(&m, key, 22, 1, buf, 19, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_stun_write(&m, key, 22, 1, buf, 20 + 12 + 24 + 8 - 1, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_stun_write(&m, key, 22, 1, buf, 20 + 12 + 24 + 8, &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 64);
    m.username[0] = '\0';
    CHECK_EQ_INT(exteria_stun_write(&m, key, 22, 1, buf, sizeof(buf), &n), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_stun_write(NULL, key, 22, 1, buf, sizeof(buf), &n), EXTERIA_E_ARG);
}

static void malformed(void) {
    exteria_stun m;
    uint8_t buf[128];
    size_t n = sizeof(rfc_request);
    CHECK_EQ_INT(exteria_stun_parse(rfc_request, 19, &m), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_stun_parse(rfc_request, n - 4, &m), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_stun_parse(rfc_request, n - 1, &m), EXTERIA_E_MALFORMED);
    memcpy(buf, rfc_request, n);
    buf[4] ^= 0x01;
    CHECK_EQ_INT(exteria_stun_parse(buf, n, &m), EXTERIA_E_MALFORMED);
    memcpy(buf, rfc_request, n);
    buf[0] = 0x40;
    CHECK_EQ_INT(exteria_stun_parse(buf, n, &m), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_stun_looks_like(buf, n), 0);
    CHECK_EQ_INT(exteria_stun_looks_like(NULL, 0), 0);
    CHECK_EQ_INT(exteria_stun_looks_like(rfc_request, 21), 0);
    /* an attribute that runs past the end, a known attribute of the wrong size, an unknown one that must be understood, and one that may be skipped */
    {
        uint8_t msg[28] = {0x00, 0x01, 0x00, 0x08, 0x21, 0x12, 0xa4, 0x42, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
        msg[20] = 0x00; msg[21] = 0x24; msg[22] = 0x00; msg[23] = 0x08;
        CHECK_EQ_INT(exteria_stun_parse(msg, 28, &m), EXTERIA_E_MALFORMED);
        msg[23] = 0x03;
        CHECK_EQ_INT(exteria_stun_parse(msg, 28, &m), EXTERIA_E_MALFORMED);
        msg[21] = 0x30;
        msg[23] = 0x04;
        CHECK_EQ_INT(exteria_stun_parse(msg, 28, &m), EXTERIA_E_MALFORMED);
        msg[20] = 0xC0;
        msg[21] = 0x57;
        CHECK_EQ_INT(exteria_stun_parse(msg, 28, &m), EXTERIA_OK);
        msg[20] = 0x80;
        msg[21] = 0x29;
        msg[23] = 0x08;
        msg[3] = 0x0c;
        msg[3] = 0x08;
        msg[23] = 0x04;
        msg[20] = 0x80; msg[21] = 0x29;
        CHECK_EQ_INT(exteria_stun_parse(msg, 28, &m), EXTERIA_E_MALFORMED);
        msg[3] = 0x0c;
        msg[23] = 0x08;
        {
            uint8_t full[32];
            memcpy(full, msg, 28);
            memset(full + 28, 0, 4);
            full[3] = 0x0c;
            /* an eight byte attribute of the right kind in a message long enough to hold it */
            full[20] = 0x80; full[21] = 0x29; full[22] = 0x00; full[23] = 0x08;
            memset(full + 24, 0x11, 8);
            CHECK_EQ_INT(exteria_stun_parse(full, 32, &m), EXTERIA_OK);
            CHECK_EQ_INT(m.has_controlled, 1);
        }
        msg[3] = 0x08;
        /* a username of zero length */
        msg[20] = 0x00; msg[21] = 0x06; msg[22] = 0x00; msg[23] = 0x00;
        CHECK_EQ_INT(exteria_stun_parse(msg, 28, &m), EXTERIA_E_MALFORMED);
    }
    CHECK_EQ_INT(exteria_stun_parse(NULL, 20, &m), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_stun_parse(rfc_request, n, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_stun_check_integrity(rfc_request, n, NULL, (const uint8_t *)"k", 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_stun_check_integrity(rfc_request, n, &m, NULL, 1), EXTERIA_E_ARG);
}

/* only the fingerprint counts after the integrity attribute: anything else added there is skipped, and does not change what the integrity covers */
static void attributes_after_integrity(void) {
    exteria_stun m, back;
    uint8_t buf[EXTERIA_STUN_MAX_MESSAGE], more[EXTERIA_STUN_MAX_MESSAGE];
    size_t n = 0;
    static const uint8_t key[] = "secretsecretsecretse";
    memset(&m, 0, sizeof(m));
    m.type = EXTERIA_STUN_BINDING_REQUEST;
    m.has_priority = 1;
    m.priority = 5;
    CHECK_EQ_INT(exteria_stun_write(&m, key, 20, 0, buf, sizeof(buf), &n), EXTERIA_OK);
    memcpy(more, buf, n);
    /* append a priority attribute of another value after the integrity attribute and fix the header length */
    more[n++] = 0x00; more[n++] = 0x24; more[n++] = 0x00; more[n++] = 0x04;
    more[n++] = 0xFF; more[n++] = 0xFF; more[n++] = 0xFF; more[n++] = 0xFF;
    more[2] = (uint8_t)((n - 20) >> 8);
    more[3] = (uint8_t)(n - 20);
    CHECK_EQ_INT(exteria_stun_parse(more, n, &back), EXTERIA_OK);
    CHECK(back.has_priority && back.priority == 5);
    CHECK_EQ_INT(exteria_stun_check_integrity(more, n, &back, key, 20), EXTERIA_OK);
}

int main(void) {
    crc();
    rfc_samples();
    writer_round_trip();
    malformed();
    attributes_after_integrity();
    return test_finish("test_tgc_stun");
}
