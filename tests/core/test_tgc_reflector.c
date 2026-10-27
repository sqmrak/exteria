#include "exteria_tgc_reflector.h"
#include "test_util.h"

static const uint8_t peer_tag[16] = {0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0xEE, 0xEE, 0xEE, 0xEE};

static void hello(void) {
    exteria_tgc_reflector r;
    uint8_t out[64];
    size_t n = 0;
    static const uint8_t want_udp[40] = {0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x78, 0x56, 0x34, 0x12,
                                         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE, 0xFF, 0xFF, 0xFF,
                                         0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7B};
    CHECK_EQ_INT(exteria_tgc_reflector_init(&r, 3, peer_tag, 0x12345678u, 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_reflector_hello(&r, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 40);
    CHECK_MEM(out, want_udp, 40);
    CHECK_EQ_INT(exteria_tgc_reflector_hello(&r, out, 39, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(n, 0);
    /* over a stream the hello is the 16 byte address and a zero word */
    CHECK_EQ_INT(exteria_tgc_reflector_init(&r, 3, peer_tag, 0x12345678u, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_reflector_hello(&r, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 20);
    CHECK_MEM(out, want_udp, 16);
    CHECK_EQ_INT(out[16], 0);
    CHECK_EQ_INT(exteria_tgc_reflector_init(&r, 0, peer_tag, 1, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_reflector_init(&r, 1, peer_tag, 0, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_reflector_init(&r, 1, NULL, 1, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_reflector_init(NULL, 1, peer_tag, 1, 0), EXTERIA_E_ARG);
}

static void wrap_and_unwrap(void) {
    exteria_tgc_reflector a, b;
    uint8_t out[EXTERIA_TGC_REFLECTOR_MAX_DATAGRAM], payload[1500];
    size_t n = 0, plen = 0, i;
    uint32_t sender = 0;
    const uint8_t *got = NULL;
    static const uint8_t want[32] = {0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x44, 0x33, 0x22, 0x11,
                                     0x78, 0x56, 0x34, 0x12, 0x00, 0x00, 0x00, 0x05, 'h', 'e', 'l', 'l', 'o', 0, 0, 0};
    exteria_tgc_reflector_init(&a, 2, peer_tag, 0x12345678u, 0);
    exteria_tgc_reflector_init(&b, 2, peer_tag, 0x11223344u, 0);
    CHECK_EQ_INT(exteria_tgc_reflector_wrap(&a, 0x11223344u, (const uint8_t *)"hello", 5, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 32);
    CHECK_MEM(out, want, 32);
    /* the other phone reads it: the sender's tag and the five bytes, with the padding left out */
    CHECK_EQ_INT(b.ready, 0);
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&b, out, n, &sender, &got, &plen), EXTERIA_OK);
    CHECK_EQ_INT(b.ready, 1);
    CHECK(sender == 0x12345678u);
    CHECK_EQ_INT(plen, 5);
    CHECK(got == out + 24 && memcmp(got, "hello", 5) == 0);
    /* sizes around the padding, and the largest payload */
    for (i = 0; i < sizeof(payload); ++i) payload[i] = (uint8_t)(i * 7u);
    {
        static const size_t sizes[] = {1, 2, 3, 4, 5, 1499, 1500};
        size_t s;
        for (s = 0; s < sizeof(sizes) / sizeof(sizes[0]); ++s) {
            CHECK_EQ_INT(exteria_tgc_reflector_wrap(&a, 7, payload, sizes[s], out, sizeof(out), &n), EXTERIA_OK);
            CHECK_EQ_INT(n % 4, 0);
            CHECK_EQ_INT(n, (24 + sizes[s] + 3) / 4 * 4);
            CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&b, out, n, &sender, &got, &plen), EXTERIA_OK);
            CHECK_EQ_INT(plen, sizes[s]);
            CHECK(memcmp(got, payload, plen) == 0);
        }
    }
    CHECK_EQ_INT(exteria_tgc_reflector_wrap(&a, 7, payload, 1501, out, sizeof(out), &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_reflector_wrap(&a, 7, payload, 0, out, sizeof(out), &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_reflector_wrap(&a, 7, payload, 5, out, 31, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_reflector_wrap(&a, 0, payload, 5, out, sizeof(out), &n), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_reflector_wrap(NULL, 7, payload, 5, out, sizeof(out), &n), EXTERIA_E_ARG);
}

static void unwrap_rules(void) {
    exteria_tgc_reflector r;
    uint8_t pkt[64];
    uint32_t sender = 9;
    const uint8_t *got = (const uint8_t *)1;
    size_t plen = 9;
    exteria_tgc_reflector_init(&r, 1, peer_tag, 5, 0);
    /* a packet of another connection, too short, empty */
    memset(pkt, 0, sizeof(pkt));
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 40, &sender, &got, &plen), EXTERIA_E_MALFORMED);
    CHECK(sender == 0 && got == NULL && plen == 0);
    CHECK_EQ_INT(r.ready, 0);
    memcpy(pkt, peer_tag, 12);
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 15, &sender, &got, &plen), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(r.ready, 0);
    /* only the first 12 bytes name the connection: the tag after them may be anything */
    memset(pkt + 12, 0x77, 4);
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 16, &sender, &got, &plen), EXTERIA_OK);
    CHECK_EQ_INT(r.ready, 1);
    CHECK(got == NULL && plen == 0);
    /* a body of twelve 0xFF bytes is a ping or a hello answer: ready, no payload */
    r.ready = 0;
    memset(pkt + 16, 0xFF, 12);
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 40, &sender, &got, &plen), EXTERIA_OK);
    CHECK(got == NULL && r.ready == 1);
    /* eight bytes or fewer after the address carry nothing */
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 24, &sender, &got, &plen), EXTERIA_OK);
    CHECK(got == NULL);
    /* a size that reaches past the packet; a zero sender tag; a zero size */
    memset(pkt + 16, 0, 16);
    pkt[16] = 1;
    pkt[23] = 100;
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 40, &sender, &got, &plen), EXTERIA_E_MALFORMED);
    pkt[23] = 16;
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 40, &sender, &got, &plen), EXTERIA_OK);
    CHECK_EQ_INT(plen, 16);
    pkt[23] = 17;
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 40, &sender, &got, &plen), EXTERIA_E_MALFORMED);
    pkt[23] = 0;
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 40, &sender, &got, &plen), EXTERIA_OK);
    CHECK(got == NULL);
    pkt[16] = 0;
    pkt[23] = 8;
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, pkt, 40, &sender, &got, &plen), EXTERIA_OK);
    CHECK(got == NULL && sender == 0);
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(NULL, pkt, 40, &sender, &got, &plen), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_reflector_unwrap(&r, NULL, 40, &sender, &got, &plen), EXTERIA_E_ARG);
}

static void hosts_and_candidates(void) {
    char host[64], sdp[512];
    uint8_t id = 0;
    uint32_t tag = 0, prio = 0;
    uint16_t port = 0;
    exteria_tgc_reflector r;
    CHECK_EQ_INT(exteria_tgc_reflector_host(12, 4294967295u, host, sizeof(host)), EXTERIA_OK);
    CHECK(strcmp(host, "reflector-12-4294967295.reflector") == 0);
    CHECK_EQ_INT(exteria_tgc_reflector_host(12, 5, host, 17), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_reflector_host(0, 5, host, sizeof(host)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_reflector_host(1, 0, host, sizeof(host)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_reflector_parse_host("reflector-12-4294967295.reflector", &id, &tag), EXTERIA_OK);
    CHECK(id == 12 && tag == 4294967295u);
    CHECK_EQ_INT(exteria_tgc_reflector_parse_host("reflector-255-1.reflector", &id, &tag), EXTERIA_OK);
    {
        static const char *bad[] = {"", "reflector-0-5.reflector", "reflector-256-5.reflector", "reflector-1-0.reflector", "reflector-1-4294967296.reflector",
                                    "reflector-1-5.reflecto", "reflector-1-5.reflectors", "reflector--5.reflector", "reflector-1-.reflector",
                                    "reflector-1a-5.reflector", "Reflector-1-5.reflector", "reflector-1-5", "reflector-1-5.reflector ", "x.reflector",
                                    "reflector-1-12345678901.reflector", "reflector-1-5-6.reflector", "reflector-+1-5.reflector"};
        size_t i;
        for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
            CHECK_EQ_INT(exteria_tgc_reflector_parse_host(bad[i], &id, &tag), EXTERIA_E_MALFORMED);
            CHECK(id == 0 && tag == 0);
        }
    }

    exteria_tgc_reflector_init(&r, 2, peer_tag, 123456, 0);
    CHECK_EQ_INT(exteria_tgc_reflector_candidate_sdp(&r, 599, 41885439u, "abCd", sdp, sizeof(sdp)), EXTERIA_OK);
    CHECK(strcmp(sdp, "candidate:2 1 udp 41885439 reflector-2-123456.reflector 599 typ relay generation 0 ufrag abCd network-id 1 network-cost 10") == 0);
    /* what is written reads back */
    CHECK_EQ_INT(exteria_tgc_reflector_parse_candidate(sdp, &id, &tag, &port, &prio), EXTERIA_OK);
    CHECK(id == 2 && tag == 123456 && port == 599 && prio == 41885439u);
    CHECK_EQ_INT(exteria_tgc_reflector_candidate_sdp(&r, 599, 1, "u", sdp, 20), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_reflector_candidate_sdp(&r, 0, 1, "u", sdp, sizeof(sdp)), EXTERIA_E_ARG);
    /* the form libwebrtc writes, with raddr and the rest, the a= prefix, extra spaces and upper case protocol */
    CHECK_EQ_INT(exteria_tgc_reflector_parse_candidate("candidate:3 1 udp 41885439 reflector-7-99.reflector 599 typ relay raddr 0.0.0.0 rport 0 generation 0 ufrag x", &id, &tag, &port, &prio), EXTERIA_OK);
    CHECK(id == 7 && tag == 99);
    CHECK_EQ_INT(exteria_tgc_reflector_parse_candidate("a=candidate:3   1 UDP 5 reflector-7-99.reflector 600 typ relay", &id, &tag, &port, &prio), EXTERIA_OK);
    CHECK(port == 600 && prio == 5);
    {
        static const char *bad[] = {
            "", "candidate:3 1 udp 5 reflector-7-99.reflector 600 typ host", "candidate:3 2 udp 5 reflector-7-99.reflector 600 typ relay",
            "candidate:3 1 tcp 5 reflector-7-99.reflector 600 typ relay", "candidate:3 1 udp 5 192.168.0.1 600 typ relay",
            "candidate:3 1 udp 5 reflector-7-99.reflector 0 typ relay", "candidate:3 1 udp 5 reflector-7-99.reflector 70000 typ relay",
            "candidate:3 1 udp x reflector-7-99.reflector 600 typ relay", "candidate:3 1 udp 5 reflector-7-99.reflector 600 type relay",
            "candidate: 1 udp 5 reflector-7-99.reflector 600 typ relay", "cand:3 1 udp 5 reflector-7-99.reflector 600 typ relay",
            "candidate:3 1 udp 5 reflector-7-99.reflector 600 typ", "candidate:3 1 udp 99999999999 reflector-7-99.reflector 600 typ relay"
        };
        size_t i;
        for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
            exteria_status s = exteria_tgc_reflector_parse_candidate(bad[i], &id, &tag, &port, &prio);
            if (s != EXTERIA_E_MALFORMED) fprintf(stderr, "  input: %s\n", bad[i]);
            CHECK_EQ_INT(s, EXTERIA_E_MALFORMED);
            CHECK(id == 0 && tag == 0 && port == 0 && prio == 0);
        }
    }
    {
        char longline[1100];
        memset(longline, 'a', sizeof(longline) - 1);
        longline[sizeof(longline) - 1] = '\0';
        CHECK_EQ_INT(exteria_tgc_reflector_parse_candidate(longline, &id, &tag, &port, &prio), EXTERIA_E_MALFORMED);
    }
}

static void server_ids(void) {
    int64_t ids[5] = {500, -3, 77, 9000000000ll, 76};
    uint8_t out[5];
    CHECK_EQ_INT(exteria_tgc_reflector_server_ids(ids, 5, out), EXTERIA_OK);
    CHECK_EQ_INT(out[0], 4);
    CHECK_EQ_INT(out[1], 1);
    CHECK_EQ_INT(out[2], 3);
    CHECK_EQ_INT(out[3], 5);
    CHECK_EQ_INT(out[4], 2);
    CHECK_EQ_INT(exteria_tgc_reflector_server_ids(ids, 0, out), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_reflector_server_ids(NULL, 1, out), EXTERIA_E_ARG);
    {
        static int64_t many[256];
        static uint8_t numbers[256];
        size_t i;
        for (i = 0; i < 256; ++i) many[i] = (int64_t)i;
        CHECK_EQ_INT(exteria_tgc_reflector_server_ids(many, 256, numbers), EXTERIA_E_LIMIT);
        CHECK_EQ_INT(exteria_tgc_reflector_server_ids(many, 255, numbers), EXTERIA_OK);
        CHECK_EQ_INT(numbers[254], 255);
    }
}

static void tcp_framing(void) {
    uint8_t out[64], reader_in[200];
    size_t n = 0, m = 0, i;
    static exteria_tgc_tcp_reader rd;
    const uint8_t *frame = NULL;
    CHECK_EQ_INT(exteria_tgc_tcp_frame((const uint8_t *)"abc", 3, 1, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 11);
    CHECK_MEM(out, "\xEE\xEE\xEE\xEE\x03\x00\x00\x00" "abc", 11);
    CHECK_EQ_INT(exteria_tgc_tcp_frame((const uint8_t *)"abc", 3, 0, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 7);
    CHECK_EQ_INT(exteria_tgc_tcp_frame((const uint8_t *)"abc", 3, 1, out, 10, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_tcp_frame((const uint8_t *)"abc", 0, 0, out, sizeof(out), &n), EXTERIA_E_LIMIT);

    /* two frames arrive in pieces of any size */
    memcpy(reader_in, "\x05\x00\x00\x00" "hello" "\x02\x00\x00\x00" "hi", 15);
    for (i = 0; i < 15; ++i) {
        CHECK_EQ_INT(exteria_tgc_tcp_reader_push(&rd, reader_in + i, 1), EXTERIA_OK);
        if (i == 8) {
            CHECK_EQ_INT(exteria_tgc_tcp_reader_next(&rd, &frame, &m), EXTERIA_OK);
            CHECK_EQ_INT(m, 5);
            CHECK(memcmp(frame, "hello", 5) == 0);
        } else if (i == 14) {
            CHECK_EQ_INT(exteria_tgc_tcp_reader_next(&rd, &frame, &m), EXTERIA_OK);
            CHECK_EQ_INT(m, 2);
            CHECK(memcmp(frame, "hi", 2) == 0);
        } else {
            CHECK_EQ_INT(exteria_tgc_tcp_reader_next(&rd, &frame, &m), EXTERIA_E_RETRY);
        }
    }
    CHECK_EQ_INT(exteria_tgc_tcp_reader_next(&rd, &frame, &m), EXTERIA_E_RETRY);
    CHECK_EQ_INT(rd.used, 0);
    /* both in one push */
    CHECK_EQ_INT(exteria_tgc_tcp_reader_push(&rd, reader_in, 15), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_tcp_reader_next(&rd, &frame, &m), EXTERIA_OK);
    CHECK_EQ_INT(m, 5);
    CHECK_EQ_INT(exteria_tgc_tcp_reader_next(&rd, &frame, &m), EXTERIA_OK);
    CHECK_EQ_INT(m, 2);
    CHECK_EQ_INT(exteria_tgc_tcp_reader_next(&rd, &frame, &m), EXTERIA_E_RETRY);
    /* a zero length and a length past the limit end the stream */
    memset(reader_in, 0, 8);
    CHECK_EQ_INT(exteria_tgc_tcp_reader_push(&rd, reader_in, 4), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_tcp_reader_next(&rd, &frame, &m), EXTERIA_E_MALFORMED);
    memset(&rd, 0, sizeof(rd));
    memcpy(reader_in, "\x00\x00\x01\x00", 4);
    CHECK_EQ_INT(exteria_tgc_tcp_reader_push(&rd, reader_in, 4), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_tcp_reader_next(&rd, &frame, &m), EXTERIA_E_MALFORMED);
    /* a push past the buffer is refused */
    memset(&rd, 0, sizeof(rd));
    {
        static uint8_t big[EXTERIA_TGC_TCP_MAX_FRAME + 5];
        CHECK_EQ_INT(exteria_tgc_tcp_reader_push(&rd, big, sizeof(big)), EXTERIA_E_LIMIT);
        CHECK_EQ_INT(exteria_tgc_tcp_reader_push(&rd, big, EXTERIA_TGC_TCP_MAX_FRAME + 4), EXTERIA_OK);
    }
    CHECK_EQ_INT(exteria_tgc_tcp_reader_push(NULL, reader_in, 4), EXTERIA_E_ARG);
}

int main(void) {
    hello();
    wrap_and_unwrap();
    unwrap_rules();
    hosts_and_candidates();
    server_ids();
    tcp_framing();
    return test_finish("test_tgc_reflector");
}
