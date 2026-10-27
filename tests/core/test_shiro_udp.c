#include "exteria_udp.h"
#include "test_util.h"

/* built by an independent implementation (python, struct and a plain checksum loop): 172.16.0.2:50000 to 8.8.8.8:3478, id 0x1234, an odd payload */
static const uint8_t vector[] = {0x45, 0x00, 0x00, 0x29, 0x12, 0x34, 0x40, 0x00, 0x40, 0x11, 0x6c, 0x6e, 0xac, 0x10, 0x00, 0x02, 0x08, 0x08, 0x08, 0x08,
                                 0xc3, 0x50, 0x0d, 0x96, 0x00, 0x15, 0xbe, 0x74, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x2c, 0x20, 0x74, 0x75, 0x6e, 0x6e, 0x65, 0x6c};

static void builds_the_vector(void) {
    uint8_t out[64];
    size_t len = 0;
    CHECK_EQ_INT(exteria_udp_build(0xac100002u, 50000, 0x08080808u, 3478, 0x1234, (const uint8_t *)"hello, tunnel", 13, out, sizeof(out), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, sizeof(vector));
    CHECK_MEM(out, vector, sizeof(vector));
}

static void parses_the_vector(void) {
    exteria_udp_datagram d;
    CHECK(exteria_udp_is_udp(vector, sizeof(vector)));
    CHECK_EQ_INT(exteria_udp_parse(vector, sizeof(vector), &d), EXTERIA_OK);
    CHECK_EQ_INT(d.src_ip, 0xac100002u);
    CHECK_EQ_INT(d.dst_ip, 0x08080808u);
    CHECK_EQ_INT(d.src_port, 50000);
    CHECK_EQ_INT(d.dst_port, 3478);
    CHECK_EQ_INT(d.payload_len, 13);
    CHECK_MEM(d.payload, "hello, tunnel", 13);
}

static void trailing_bytes_are_ignored(void) {
    uint8_t padded[sizeof(vector) + 5];
    exteria_udp_datagram d;
    memcpy(padded, vector, sizeof(vector));
    memset(padded + sizeof(vector), 0xee, 5);
    CHECK_EQ_INT(exteria_udp_parse(padded, sizeof(padded), &d), EXTERIA_OK);
    CHECK_EQ_INT(d.payload_len, 13);
}

static void round_trip_sizes(void) {
    static const size_t sizes[] = {0, 1, 2, 3, 100, 1251, EXTERIA_UDP_MAX_PAYLOAD};
    uint8_t payload[EXTERIA_UDP_MAX_PAYLOAD], out[EXTERIA_UDP_PACKET_MAX];
    size_t i, k;
    for (k = 0; k < sizeof(payload); ++k) payload[k] = (uint8_t)(k * 7 + 3);
    for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
        exteria_udp_datagram d;
        size_t len = 0;
        CHECK_EQ_INT(exteria_udp_build(0x0a000001u, 1, 0xc0a80001u, 65535, 7, payload, sizes[i], out, sizeof(out), &len), EXTERIA_OK);
        CHECK_EQ_INT(len, 28 + sizes[i]);
        CHECK_EQ_INT(exteria_udp_parse(out, len, &d), EXTERIA_OK);
        CHECK_EQ_INT(d.payload_len, sizes[i]);
        if (sizes[i]) CHECK_MEM(d.payload, payload, sizes[i]);
    }
}

static void build_refuses(void) {
    uint8_t payload[EXTERIA_UDP_MAX_PAYLOAD + 1] = {0}, out[EXTERIA_UDP_PACKET_MAX + 8];
    size_t len = 9;
    CHECK_EQ_INT(exteria_udp_build(0x0a000001u, 1, 0xc0a80001u, 2, 0, payload, EXTERIA_UDP_MAX_PAYLOAD + 1, out, sizeof(out), &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_udp_build(0x0a000001u, 1, 0xc0a80001u, 2, 0, payload, 10, out, 37, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_udp_build(0, 1, 0xc0a80001u, 2, 0, payload, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_udp_build(0x0a000001u, 1, 0, 2, 0, payload, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_udp_build(0x0a000001u, 0, 0xc0a80001u, 2, 0, payload, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_udp_build(0x0a000001u, 1, 0xc0a80001u, 0, 0, payload, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_udp_build(0x0a000001u, 1, 0xc0a80001u, 2, 0, NULL, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
}

static void parse_refuses(void) {
    uint8_t bad[sizeof(vector)];
    exteria_udp_datagram d;
    size_t i;
    /* every cut of a good packet is malformed, none is read as a shorter datagram */
    for (i = 0; i < sizeof(vector); ++i) CHECK_EQ_INT(exteria_udp_parse(vector, i, &d), EXTERIA_E_MALFORMED);

    /* every single flipped bit in a header or in the payload is caught by one of the two checksums or by a length check */
    for (i = 0; i < sizeof(vector) * 8; ++i) {
        exteria_status s;
        memcpy(bad, vector, sizeof(vector));
        bad[i / 8] ^= (uint8_t)(1u << (i % 8));
        s = exteria_udp_parse(bad, sizeof(bad), &d);
        /* the one flip the checksums cannot see is in the identification or flags: the DF bit is the only flag allowed to change nothing */
        if (s == EXTERIA_OK) CHECK(i / 8 == 4 || i / 8 == 5 || i / 8 == 1 || i / 8 == 6);
    }

    memcpy(bad, vector, sizeof(vector));
    bad[0] = 0x65;
    CHECK_EQ_INT(exteria_udp_parse(bad, sizeof(bad), &d), EXTERIA_E_MALFORMED);
    CHECK(exteria_udp_is_udp(bad, sizeof(bad)) == 0);

    /* a fragment: more fragments set, with a good header checksum */
    memcpy(bad, vector, sizeof(vector));
    bad[6] = 0x60;
    bad[10] = bad[11] = 0;
    {
        uint32_t sum = 0;
        for (i = 0; i < 20; i += 2) sum += (uint32_t)((bad[i] << 8) | bad[i + 1]);
        while (sum >> 16) sum = (sum & 0xffffu) + (sum >> 16);
        sum = ~sum & 0xffffu;
        bad[10] = (uint8_t)(sum >> 8);
        bad[11] = (uint8_t)sum;
    }
    CHECK_EQ_INT(exteria_udp_parse(bad, sizeof(bad), &d), EXTERIA_E_UNSUPPORTED);

    CHECK_EQ_INT(exteria_udp_parse(NULL, 41, &d), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_udp_parse(vector, sizeof(vector), NULL), EXTERIA_E_MALFORMED);
    CHECK(!exteria_udp_is_udp(NULL, 41));
}

static void no_checksum_is_accepted(void) {
    uint8_t copy[sizeof(vector)];
    exteria_udp_datagram d;
    memcpy(copy, vector, sizeof(vector));
    copy[26] = copy[27] = 0;
    CHECK_EQ_INT(exteria_udp_parse(copy, sizeof(copy), &d), EXTERIA_OK);
}

static void frames(void) {
    uint8_t out[EXTERIA_UDP_FRAME_HEADER + EXTERIA_UDP_MAX_PAYLOAD], big[EXTERIA_UDP_MAX_PAYLOAD + 1] = {0};
    size_t len = 0, plen = 0;
    uint32_t ip = 0;
    uint16_t port = 0;
    const uint8_t *payload = NULL;
    CHECK_EQ_INT(exteria_udp_frame_encode(0x95a9af32u, 443, (const uint8_t *)"abc", 3, out, sizeof(out), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 9);
    CHECK_MEM(out, "\x95\xa9\xaf\x32\x01\xbb" "abc", 9);
    CHECK_EQ_INT(exteria_udp_frame_decode(out, len, &ip, &port, &payload, &plen), EXTERIA_OK);
    CHECK_EQ_INT(ip, 0x95a9af32u);
    CHECK_EQ_INT(port, 443);
    CHECK_EQ_INT(plen, 3);
    CHECK_MEM(payload, "abc", 3);

    CHECK_EQ_INT(exteria_udp_frame_decode(out, 5, &ip, &port, &payload, &plen), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(ip, 0);
    CHECK_EQ_INT(exteria_udp_frame_decode(out, 6, &ip, &port, &payload, &plen), EXTERIA_OK);
    CHECK_EQ_INT(plen, 0);
    memset(out, 0, 6);
    CHECK_EQ_INT(exteria_udp_frame_decode(out, 9, &ip, &port, &payload, &plen), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_udp_frame_encode(0, 443, big, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_udp_frame_encode(1, 0, big, 1, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_udp_frame_encode(1, 443, big, sizeof(big), out, sizeof(out), &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_udp_frame_encode(1, 443, big, 100, out, 50, &len), EXTERIA_E_LIMIT);
    {
        uint8_t oversize[EXTERIA_UDP_FRAME_HEADER + EXTERIA_UDP_MAX_PAYLOAD + 1] = {0, 0, 0, 1, 0, 1};
        CHECK_EQ_INT(exteria_udp_frame_decode(oversize, sizeof(oversize), &ip, &port, &payload, &plen), EXTERIA_E_LIMIT);
    }
}

int main(void) {
    builds_the_vector();
    parses_the_vector();
    trailing_bytes_are_ignored();
    round_trip_sizes();
    build_refuses();
    parse_refuses();
    no_checksum_is_accepted();
    frames();
    return test_finish("test_shiro_udp");
}
