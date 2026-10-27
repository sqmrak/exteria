#include "exteria_tgc_sctp.h"
#include "test_util.h"

/* an INIT packet as a conforming stack writes it, with the checksum computed by an independent crc32c (python): tag 0x11223344, window 131072,
   16 streams each way, first TSN 0x55667788 */
static const uint8_t reference_init[32] = {0x13, 0x88, 0x13, 0x88, 0x00, 0x00, 0x00, 0x00, 0x83, 0xC2, 0xE9, 0xAD, 0x01, 0x00, 0x00, 0x14,
                                           0x11, 0x22, 0x33, 0x44, 0x00, 0x02, 0x00, 0x00, 0x00, 0x10, 0x00, 0x10, 0x55, 0x66, 0x77, 0x88};

static void crc_vectors(void) {
    uint8_t buf[32];
    int i;
    CHECK(exteria_tgc_crc32c((const uint8_t *)"123456789", 9) == 0xE3069283u);
    memset(buf, 0, sizeof(buf));
    CHECK(exteria_tgc_crc32c(buf, 32) == 0x8A9136AAu);
    memset(buf, 0xFF, sizeof(buf));
    CHECK(exteria_tgc_crc32c(buf, 32) == 0x62A8AB43u);
    for (i = 0; i < 32; ++i) buf[i] = (uint8_t)i;
    CHECK(exteria_tgc_crc32c(buf, 32) == 0x46DD794Eu);
    for (i = 0; i < 32; ++i) buf[i] = (uint8_t)(31 - i);
    CHECK(exteria_tgc_crc32c(buf, 32) == 0x113FDB5Cu);
}

typedef struct endpoint {
    exteria_tgc_sctp s;
    int index;
    int open_events;
    int close_events;
    char messages[8][128];
    unsigned message_count;
} endpoint;

typedef struct net {
    endpoint e[2];
    struct { int to; size_t len; uint8_t data[1500]; uint64_t due; } q[512];
    size_t queued;
    uint64_t now;
    unsigned loss;
    unsigned dup;
    unsigned rng;
    uint64_t latency;
    int cut;
} net;

static unsigned rnd(net *n) {
    n->rng = n->rng * 1103515245u + 12345u;
    return (n->rng >> 16) & 0x7FFF;
}

typedef struct side {
    net *n;
    int index;
} side;

static side sides[2];

static void put(net *n, int to, const uint8_t *data, size_t len, uint64_t extra) {
    if (n->queued >= 512 || n->cut) return;
    n->q[n->queued].to = to;
    n->q[n->queued].len = len;
    memcpy(n->q[n->queued].data, data, len);
    n->q[n->queued].due = n->now + n->latency + extra;
    ++n->queued;
}

static void on_send(void *ctx, const uint8_t *packet, size_t len) {
    side *sd = (side *)ctx;
    net *n = sd->n;
    if (n->loss && rnd(n) % 100 < n->loss) return;
    put(n, 1 - sd->index, packet, len, 0);
    if (n->dup && rnd(n) % 100 < n->dup) put(n, 1 - sd->index, packet, len, 7);
}

static void on_channel(void *ctx, int open) {
    side *sd = (side *)ctx;
    if (open) ++sd->n->e[sd->index].open_events;
    else ++sd->n->e[sd->index].close_events;
}

static void on_message(void *ctx, const char *text, size_t len) {
    side *sd = (side *)ctx;
    endpoint *e = &sd->n->e[sd->index];
    CHECK_EQ_INT(strlen(text), len);
    if (e->message_count < 8) snprintf(e->messages[e->message_count++], sizeof(e->messages[0]), "%s", text);
}

static net *make_net(void) {
    net *n = (net *)calloc(1, sizeof(*n));
    uint8_t cookie_a[32], cookie_b[32];
    exteria_tgc_sctp_events ev;
    int i;
    for (i = 0; i < 32; ++i) {
        cookie_a[i] = (uint8_t)(i + 1);
        cookie_b[i] = (uint8_t)(0xA0 + i);
    }
    n->rng = 777;
    n->latency = 10;
    for (i = 0; i < 2; ++i) {
        sides[i].n = n;
        sides[i].index = i;
        memset(&ev, 0, sizeof(ev));
        ev.context = &sides[i];
        ev.send = on_send;
        ev.channel = on_channel;
        ev.message = on_message;
        n->e[i].index = i;
        CHECK_EQ_INT(exteria_tgc_sctp_init(&n->e[i].s, i == 0, i == 0 ? 0x1000AAAAu : 0x2000BBBBu, i == 0 ? 100 : 5000, i == 0 ? cookie_a : cookie_b, &ev), EXTERIA_OK);
    }
    return n;
}

static void run(net *n, uint64_t ms) {
    uint64_t end = n->now + ms;
    while (n->now < end) {
        size_t i = 0;
        n->now += 5;
        while (i < n->queued) {
            int to;
            size_t len;
            uint8_t data[1500];
            if (n->q[i].due > n->now) {
                ++i;
                continue;
            }
            to = n->q[i].to;
            len = n->q[i].len;
            memcpy(data, n->q[i].data, len);
            memmove(&n->q[i], &n->q[i + 1], (n->queued - i - 1) * sizeof(n->q[0]));
            --n->queued;
            exteria_tgc_sctp_input(&n->e[to].s, data, len, n->now);
            i = 0;
        }
        exteria_tgc_sctp_tick(&n->e[0].s, n->now);
        exteria_tgc_sctp_tick(&n->e[1].s, n->now);
    }
}

static uint8_t captured[1500];
static size_t captured_len;
static void capture(void *ctx, const uint8_t *packet, size_t len) {
    (void)ctx;
    memcpy(captured, packet, len);
    captured_len = len;
}

static void init_packet_matches_reference(void) {
    exteria_tgc_sctp s;
    exteria_tgc_sctp_events ev;
    uint8_t cookie[32] = {1};
    memset(&ev, 0, sizeof(ev));
    ev.send = capture;
    CHECK_EQ_INT(exteria_tgc_sctp_init(&s, 1, 0x11223344u, 0x55667788u, cookie, &ev), EXTERIA_OK);
    captured_len = 0;
    CHECK_EQ_INT(exteria_tgc_sctp_start(&s, 0), EXTERIA_OK);
    CHECK_EQ_INT(captured_len, 32);
    CHECK_MEM(captured, reference_init, 32);
    CHECK_EQ_INT(s.state, EXTERIA_TGC_SCTP_COOKIE_WAIT);
    CHECK_EQ_INT(exteria_tgc_sctp_start(&s, 0), EXTERIA_E_STATE);
    /* the INIT is repeated on the timer, with growing gaps, and the association fails after many tries */
    captured_len = 0;
    exteria_tgc_sctp_tick(&s, 999);
    CHECK_EQ_INT(captured_len, 0);
    exteria_tgc_sctp_tick(&s, 1000);
    CHECK_EQ_INT(captured_len, 32);
    {
        uint64_t t = 1000;
        int sent = 1;
        while (s.state == EXTERIA_TGC_SCTP_COOKIE_WAIT && t < 200000) {
            t += 100;
            captured_len = 0;
            exteria_tgc_sctp_tick(&s, t);
            if (captured_len) ++sent;
        }
        CHECK_EQ_INT(s.state, EXTERIA_TGC_SCTP_FAILED);
        CHECK(sent >= 10 && sent <= 14);
    }
    CHECK_EQ_INT(exteria_tgc_sctp_init(NULL, 1, 1, 1, cookie, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_sctp_init(&s, 1, 0, 1, cookie, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_sctp_init(&s, 1, 1, 1, NULL, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_sctp_init(&s, 1, 1, 1, cookie, NULL), EXTERIA_E_ARG);
}

static void both_start_together(void) {
    net *n = make_net();
    exteria_tgc_sctp_start(&n->e[0].s, 0);
    exteria_tgc_sctp_start(&n->e[1].s, 0);
    run(n, 3000);
    CHECK_EQ_INT(n->e[0].s.state, EXTERIA_TGC_SCTP_ESTABLISHED);
    CHECK_EQ_INT(n->e[1].s.state, EXTERIA_TGC_SCTP_ESTABLISHED);
    /* the opener sent the OPEN, the other side acknowledged it: the channel is open on both ends, once */
    CHECK_EQ_INT(n->e[0].open_events, 1);
    CHECK_EQ_INT(n->e[1].open_events, 1);
    CHECK_EQ_INT(exteria_tgc_sctp_send_text(&n->e[0].s, "{\"@type\":\"MediaState\"}", 22, n->now), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_sctp_send_text(&n->e[1].s, "reply", 5, n->now), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_sctp_send_text(&n->e[1].s, "", 0, n->now), EXTERIA_OK);
    run(n, 500);
    CHECK_EQ_INT(n->e[1].message_count, 1);
    CHECK(strcmp(n->e[1].messages[0], "{\"@type\":\"MediaState\"}") == 0);
    CHECK_EQ_INT(n->e[0].message_count, 2);
    CHECK(strcmp(n->e[0].messages[0], "reply") == 0 && strcmp(n->e[0].messages[1], "") == 0);
    /* everything was acknowledged: no timer runs */
    CHECK_EQ_INT(n->e[0].s.t3_due, 0);
    CHECK_EQ_INT(n->e[1].s.t3_due, 0);
    free(n);
}

static void one_side_starts_late(void) {
    /* the acker's DTLS comes up a second after the opener's: the opener's INIT is answered all the same, and the acker's own INIT after it */
    net *n = make_net();
    exteria_tgc_sctp_start(&n->e[0].s, 0);
    run(n, 1000);
    exteria_tgc_sctp_start(&n->e[1].s, n->now);
    run(n, 3000);
    CHECK_EQ_INT(n->e[0].s.state, EXTERIA_TGC_SCTP_ESTABLISHED);
    CHECK_EQ_INT(n->e[1].s.state, EXTERIA_TGC_SCTP_ESTABLISHED);
    CHECK_EQ_INT(n->e[0].open_events, 1);
    CHECK_EQ_INT(n->e[1].open_events, 1);
    free(n);
}

static void loss_duplication_and_latency(void) {
    unsigned loss;
    for (loss = 10; loss <= 40; loss += 15) {
        net *n = make_net();
        int i, got = 0;
        n->loss = loss;
        n->dup = 10;
        n->latency = 40;
        exteria_tgc_sctp_start(&n->e[0].s, 0);
        exteria_tgc_sctp_start(&n->e[1].s, 0);
        run(n, 60000);
        CHECK_EQ_INT(n->e[0].s.state, EXTERIA_TGC_SCTP_ESTABLISHED);
        CHECK_EQ_INT(n->e[1].s.state, EXTERIA_TGC_SCTP_ESTABLISHED);
        CHECK_EQ_INT(n->e[0].open_events, 1);
        for (i = 0; i < 6; ++i) {
            char text[32];
            snprintf(text, sizeof(text), "message %d", i);
            CHECK_EQ_INT(exteria_tgc_sctp_send_text(&n->e[0].s, text, strlen(text), n->now), EXTERIA_OK);
        }
        run(n, 60000);
        for (i = 0; i < (int)n->e[1].message_count; ++i) {
            char want[32];
            snprintf(want, sizeof(want), "message %d", i);
            if (strcmp(n->e[1].messages[i], want) == 0) ++got;
        }
        /* every message arrives once and in order, whatever the network did to the packets */
        CHECK_EQ_INT(n->e[1].message_count, 6);
        CHECK_EQ_INT(got, 6);
        free(n);
    }
}

static void window_and_limits(void) {
    net *n = make_net();
    char big[EXTERIA_TGC_SCTP_MAX_MESSAGE + 1];
    int i;
    CHECK_EQ_INT(exteria_tgc_sctp_send_text(&n->e[0].s, "x", 1, 0), EXTERIA_E_STATE);
    exteria_tgc_sctp_start(&n->e[0].s, 0);
    exteria_tgc_sctp_start(&n->e[1].s, 0);
    run(n, 3000);
    memset(big, 'a', sizeof(big));
    CHECK_EQ_INT(exteria_tgc_sctp_send_text(&n->e[0].s, big, sizeof(big), n->now), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_sctp_send_text(&n->e[0].s, big, EXTERIA_TGC_SCTP_MAX_MESSAGE, n->now), EXTERIA_OK);
    run(n, 500);
    CHECK_EQ_INT(n->e[1].message_count, 1);
    CHECK_EQ_INT(strlen(n->e[1].messages[0]), sizeof(n->e[1].messages[0]) - 1);
    /* with the network cut the window fills and then refuses */
    n->cut = 1;
    for (i = 0; i < EXTERIA_TGC_SCTP_WINDOW; ++i) {
        if (exteria_tgc_sctp_send_text(&n->e[0].s, "m", 1, n->now) != EXTERIA_OK) break;
    }
    CHECK_EQ_INT(exteria_tgc_sctp_send_text(&n->e[0].s, "m", 1, n->now), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_sctp_send_text(NULL, "m", 1, n->now), EXTERIA_E_ARG);
    /* the retransmissions back off and give up: the association fails and the channel closes */
    run(n, 400000);
    CHECK_EQ_INT(n->e[0].s.state, EXTERIA_TGC_SCTP_FAILED);
    CHECK_EQ_INT(n->e[0].close_events, 1);
    free(n);
}

static void abort_and_shutdown(void) {
    net *n = make_net();
    exteria_tgc_sctp_start(&n->e[0].s, 0);
    exteria_tgc_sctp_start(&n->e[1].s, 0);
    run(n, 3000);
    exteria_tgc_sctp_abort(&n->e[0].s);
    run(n, 500);
    CHECK_EQ_INT(n->e[0].s.state, EXTERIA_TGC_SCTP_CLOSED);
    CHECK_EQ_INT(n->e[1].s.state, EXTERIA_TGC_SCTP_FAILED);
    CHECK_EQ_INT(n->e[0].close_events, 1);
    CHECK_EQ_INT(n->e[1].close_events, 1);
    CHECK_EQ_INT(exteria_tgc_sctp_send_text(&n->e[1].s, "x", 1, n->now), EXTERIA_E_STATE);
    free(n);
}

/* packets written by hand, as a stack with other habits would */
static size_t build(uint8_t *out, uint32_t tag, const uint8_t *chunks, size_t chunks_len) {
    uint32_t crc;
    out[0] = 0x13; out[1] = 0x88; out[2] = 0x13; out[3] = 0x88;
    out[4] = (uint8_t)(tag >> 24); out[5] = (uint8_t)(tag >> 16); out[6] = (uint8_t)(tag >> 8); out[7] = (uint8_t)tag;
    memset(out + 8, 0, 4);
    memcpy(out + 12, chunks, chunks_len);
    crc = exteria_tgc_crc32c(out, 12 + chunks_len);
    out[8] = (uint8_t)crc; out[9] = (uint8_t)(crc >> 8); out[10] = (uint8_t)(crc >> 16); out[11] = (uint8_t)(crc >> 24);
    return 12 + chunks_len;
}

static size_t data_chunk(uint8_t *out, uint8_t flags, uint32_t tsn, uint16_t ssn, uint32_t ppid, const char *text) {
    size_t n = strlen(text), len = 16 + n, padded = (len + 3) & ~(size_t)3;
    memset(out, 0, padded);
    out[0] = 0; out[1] = flags; out[2] = (uint8_t)(len >> 8); out[3] = (uint8_t)len;
    out[4] = (uint8_t)(tsn >> 24); out[5] = (uint8_t)(tsn >> 16); out[6] = (uint8_t)(tsn >> 8); out[7] = (uint8_t)tsn;
    out[8] = 0; out[9] = 0; out[10] = (uint8_t)(ssn >> 8); out[11] = (uint8_t)ssn;
    out[12] = (uint8_t)(ppid >> 24); out[13] = (uint8_t)(ppid >> 16); out[14] = (uint8_t)(ppid >> 8); out[15] = (uint8_t)ppid;
    memcpy(out + 16, text, n);
    return padded;
}

static uint8_t sent_packets[16][1500];
static size_t sent_lens[16];
static unsigned sent_count;
static void record(void *ctx, const uint8_t *packet, size_t len) {
    (void)ctx;
    if (sent_count < 16) {
        memcpy(sent_packets[sent_count], packet, len);
        sent_lens[sent_count++] = len;
    }
}
static char got_text[8][600];
static unsigned got_count;
static void record_message(void *ctx, const char *text, size_t len) {
    (void)ctx;
    (void)len;
    if (got_count < 8) snprintf(got_text[got_count++], sizeof(got_text[0]), "%s", text);
}

/* a peer that is already established with this side, set up by hand: this side is the acker with tag 0x2000BBBB */
static void established_acker(exteria_tgc_sctp *s) {
    exteria_tgc_sctp_events ev;
    uint8_t cookie[32], buf[1500], chunks[64];
    size_t n;
    int i;
    for (i = 0; i < 32; ++i) cookie[i] = (uint8_t)(0xA0 + i);
    memset(&ev, 0, sizeof(ev));
    ev.send = record;
    ev.message = record_message;
    CHECK_EQ_INT(exteria_tgc_sctp_init(s, 0, 0x2000BBBBu, 5000, cookie, &ev), EXTERIA_OK);
    sent_count = 0;
    got_count = 0;
    /* INIT from the peer: tag 0x0A0B0C0D, window 100000, first TSN 1000 */
    memset(chunks, 0, sizeof(chunks));
    chunks[0] = 1; chunks[3] = 20;
    chunks[4] = 0x0A; chunks[5] = 0x0B; chunks[6] = 0x0C; chunks[7] = 0x0D;
    chunks[10] = 0x86; chunks[11] = 0xA0;
    chunks[13] = 0x10; chunks[15] = 0x10;
    chunks[18] = 0x03; chunks[19] = 0xE8;
    n = build(buf, 0, chunks, 20);
    CHECK_EQ_INT(exteria_tgc_sctp_input(s, buf, n, 0), EXTERIA_OK);
    CHECK_EQ_INT(sent_count, 1);
    CHECK_EQ_INT(sent_packets[0][12], 2);   /* INIT ACK */
    CHECK(memcmp(sent_packets[0] + 4, "\x0A\x0B\x0C\x0D", 4) == 0);
    /* the cookie echo with the cookie from that INIT ACK opens it, and the COOKIE ACK answers */
    memset(chunks, 0, sizeof(chunks));
    chunks[0] = 10; chunks[3] = 36;
    memcpy(chunks + 4, cookie, 32);
    n = build(buf, 0x2000BBBBu, chunks, 36);
    CHECK_EQ_INT(exteria_tgc_sctp_input(s, buf, n, 0), EXTERIA_OK);
    CHECK_EQ_INT(s->state, EXTERIA_TGC_SCTP_ESTABLISHED);
    CHECK_EQ_INT(sent_count, 2);
    CHECK_EQ_INT(sent_packets[1][12], 11);
    sent_count = 0;
}

static void raw_peer_data_handling(void) {
    exteria_tgc_sctp s;
    uint8_t buf[1500], chunks[1500];
    size_t n, c;
    established_acker(&s);
    /* the channel is opened by the peer's OPEN message (ppid 50), in TSN 1000 */
    {
        uint8_t open[16 + 12 + 4];
        memset(open, 0, sizeof(open));
        open[0] = 0x03;
        open[9] = 4;
        memcpy(open + 12, "data", 4);
        c = 0;
        chunks[c] = 0; chunks[c + 1] = 0x03; chunks[c + 2] = 0; chunks[c + 3] = 16 + 16;
        chunks[c + 4] = 0; chunks[c + 5] = 0; chunks[c + 6] = 0x03; chunks[c + 7] = 0xE8;
        memset(chunks + c + 8, 0, 4);
        chunks[c + 11] = 0;
        chunks[c + 12] = 0; chunks[c + 13] = 0; chunks[c + 14] = 0; chunks[c + 15] = 50;
        memcpy(chunks + c + 16, open, 16);
        n = build(buf, 0x2000BBBBu, chunks, 32);
    }
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 10), EXTERIA_OK);
    CHECK_EQ_INT(s.channel_open, 1);
    /* a SACK for TSN 1000 and the ACK of the channel, which is DATA on stream 0 with ppid 50 and the single byte 2 */
    CHECK(sent_count >= 2);
    {
        int saw_sack = 0, saw_ack = 0;
        unsigned i;
        for (i = 0; i < sent_count; ++i) {
            if (sent_packets[i][12] == 3) {
                saw_sack = 1;
                CHECK_EQ_INT(sent_packets[i][16] << 24 | sent_packets[i][17] << 16 | sent_packets[i][18] << 8 | sent_packets[i][19], 1000);
            }
            if (sent_packets[i][12] == 0 && sent_lens[i] >= 12 + 16 + 1 && sent_packets[i][12 + 16] == 2 && sent_packets[i][12 + 15] == 50) saw_ack = 1;
        }
        CHECK(saw_sack && saw_ack);
    }
    sent_count = 0;

    /* a message in three fragments arriving 1004, 1002, 1003 (the first fragment is 1002): held until the missing one comes */
    c = data_chunk(chunks, 0x02, 1002, 1, 51, "first-");
    n = build(buf, 0x2000BBBBu, chunks, c);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 20), EXTERIA_OK);
    c = data_chunk(chunks, 0x01, 1004, 1, 51, "last");
    n = build(buf, 0x2000BBBBu, chunks, c);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 21), EXTERIA_OK);
    c = data_chunk(chunks, 0x00, 1003, 1, 51, "middle-");
    n = build(buf, 0x2000BBBBu, chunks, c);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 22), EXTERIA_OK);
    CHECK_EQ_INT(got_count, 0);
    /* TSN 1001 completes the run: a one chunk message, then the three fragments in order */
    c = data_chunk(chunks, 0x03, 1001, 0, 51, "one");
    n = build(buf, 0x2000BBBBu, chunks, c);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 23), EXTERIA_OK);
    CHECK_EQ_INT(got_count, 2);
    CHECK(strcmp(got_text[0], "one") == 0);
    CHECK(strcmp(got_text[1], "first-middle-last") == 0);
    /* the last SACK reports the cumulative TSN 1004, no gap blocks and no duplicates (counts at bytes 24 and 26 of the packet) */
    {
        const uint8_t *sack = sent_packets[sent_count - 1];
        CHECK_EQ_INT(sack[12], 3);
        CHECK_EQ_INT(sack[16] << 24 | sack[17] << 16 | sack[18] << 8 | sack[19], 1004);
        CHECK_EQ_INT(sack[24] << 8 | sack[25], 0);
        CHECK_EQ_INT(sack[26] << 8 | sack[27], 0);
    }
    /* a repeat is reported as a duplicate and delivers nothing new */
    got_count = 0;
    sent_count = 0;
    c = data_chunk(chunks, 0x03, 1001, 0, 51, "one");
    n = build(buf, 0x2000BBBBu, chunks, c);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 24), EXTERIA_OK);
    CHECK_EQ_INT(got_count, 0);
    CHECK_EQ_INT(sent_count, 1);
    CHECK_EQ_INT(sent_packets[0][26] << 8 | sent_packets[0][27], 1);
    CHECK_EQ_INT(sent_packets[0][28] << 24 | sent_packets[0][29] << 16 | sent_packets[0][30] << 8 | sent_packets[0][31], 1001);
    /* a gap: TSN 1007 with 1005 and 1006 missing is stored and reported as one gap block, offsets 3 to 3 above the cumulative TSN 1004 */
    sent_count = 0;
    c = data_chunk(chunks, 0x03, 1007, 2, 51, "later");
    n = build(buf, 0x2000BBBBu, chunks, c);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 25), EXTERIA_OK);
    CHECK_EQ_INT(got_count, 0);
    {
        const uint8_t *sack = sent_packets[0];
        CHECK_EQ_INT(sack[16] << 24 | sack[17] << 16 | sack[18] << 8 | sack[19], 1004);
        CHECK_EQ_INT(sack[24] << 8 | sack[25], 1);
        CHECK_EQ_INT(sack[26] << 8 | sack[27], 0);
        CHECK_EQ_INT(sack[28] << 8 | sack[29], 3);
        CHECK_EQ_INT(sack[30] << 8 | sack[31], 3);
    }
    /* the missing TSNs arrive: the stored one is delivered after them, in order */
    c = data_chunk(chunks, 0x03, 1005, 3, 51, "five");
    n = build(buf, 0x2000BBBBu, chunks, c);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 26), EXTERIA_OK);
    c = data_chunk(chunks, 0x03, 1006, 4, 51, "six");
    n = build(buf, 0x2000BBBBu, chunks, c);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 27), EXTERIA_OK);
    CHECK_EQ_INT(got_count, 3);
    CHECK(strcmp(got_text[0], "five") == 0 && strcmp(got_text[1], "six") == 0 && strcmp(got_text[2], "later") == 0);
}

static void raw_peer_rejections(void) {
    exteria_tgc_sctp s;
    uint8_t buf[1500], chunks[64];
    size_t n;
    established_acker(&s);
    sent_count = 0;
    /* a damaged checksum, the wrong tag, the wrong ports, short packets, a chunk that runs past the end */
    n = build(buf, 0x2000BBBBu, (const uint8_t *)"\x04\x00\x00\x08\x00\x00\x00\x00", 8);
    buf[8] ^= 0x01;
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 1), EXTERIA_E_MALFORMED);
    n = build(buf, 0x12345678u, (const uint8_t *)"\x04\x00\x00\x08\x00\x00\x00\x00", 8);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 1), EXTERIA_E_MALFORMED);
    n = build(buf, 0x2000BBBBu, (const uint8_t *)"\x04\x00\x00\x08\x00\x00\x00\x00", 8);
    buf[1] = 0x89;
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 1), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, 15, 1), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, 0, 1), EXTERIA_E_MALFORMED);
    n = build(buf, 0x2000BBBBu, (const uint8_t *)"\x04\x00\x00\x40\x00\x00\x00\x00", 8);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 1), EXTERIA_E_MALFORMED);
    n = build(buf, 0x2000BBBBu, (const uint8_t *)"\x04\x00\x00\x02\x00\x00\x00\x00", 8);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 1), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(sent_count, 0);
    /* a heartbeat is echoed back as an acknowledgement with the same body */
    memset(chunks, 0, sizeof(chunks));
    chunks[0] = 4; chunks[3] = 12;
    chunks[4] = 0x00; chunks[5] = 0x01; chunks[6] = 0x00; chunks[7] = 0x08;
    memcpy(chunks + 8, "pong", 4);
    n = build(buf, 0x2000BBBBu, chunks, 12);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 2), EXTERIA_OK);
    CHECK_EQ_INT(sent_count, 1);
    CHECK_EQ_INT(sent_packets[0][12], 5);
    CHECK(memcmp(sent_packets[0] + 12 + 4, chunks + 4, 8) == 0);
    /* an unknown chunk type with the skip bit is ignored and the next chunk still counts; one without it ends the packet */
    sent_count = 0;
    memset(chunks, 0, sizeof(chunks));
    chunks[0] = 0xC0; chunks[3] = 8;
    chunks[8] = 4; chunks[11] = 12;
    chunks[12] = 0x00; chunks[13] = 0x01; chunks[14] = 0x00; chunks[15] = 0x08;
    memcpy(chunks + 16, "ping", 4);
    n = build(buf, 0x2000BBBBu, chunks, 20);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 3), EXTERIA_OK);
    CHECK_EQ_INT(sent_count, 1);
    sent_count = 0;
    chunks[0] = 0x80;
    n = build(buf, 0x2000BBBBu, chunks, 20);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, buf, n, 3), EXTERIA_OK);
    CHECK_EQ_INT(sent_count, 0);
    /* a cookie echo with a wrong cookie opens nothing: a fresh endpoint stays closed */
    {
        exteria_tgc_sctp t;
        exteria_tgc_sctp_events ev;
        uint8_t cookie[32] = {5};
        memset(&ev, 0, sizeof(ev));
        ev.send = record;
        exteria_tgc_sctp_init(&t, 0, 0x3000CCCCu, 1, cookie, &ev);
        memset(chunks, 0, sizeof(chunks));
        chunks[0] = 10; chunks[3] = 36;
        n = build(buf, 0x3000CCCCu, chunks, 36);
        CHECK_EQ_INT(exteria_tgc_sctp_input(&t, buf, n, 0), EXTERIA_OK);
        CHECK_EQ_INT(t.state, EXTERIA_TGC_SCTP_CLOSED);
        /* nor does an INIT with a window below the minimum, or with no streams, or with tag zero, or one with a nonzero header tag */
        memset(chunks, 0, sizeof(chunks));
        chunks[0] = 1; chunks[3] = 20;
        chunks[4] = 1; chunks[7] = 1;
        chunks[10] = 0x01; chunks[11] = 0x00;
        chunks[13] = 1; chunks[15] = 1;
        sent_count = 0;
        n = build(buf, 0, chunks, 20);
        CHECK_EQ_INT(exteria_tgc_sctp_input(&t, buf, n, 0), EXTERIA_OK);
        CHECK_EQ_INT(sent_count, 0);
        chunks[10] = 0x10;
        chunks[13] = 0;
        n = build(buf, 0, chunks, 20);
        CHECK_EQ_INT(exteria_tgc_sctp_input(&t, buf, n, 0), EXTERIA_OK);
        CHECK_EQ_INT(sent_count, 0);
        chunks[13] = 1;
        chunks[4] = 0; chunks[5] = 0; chunks[6] = 0; chunks[7] = 0;
        n = build(buf, 0, chunks, 20);
        CHECK_EQ_INT(exteria_tgc_sctp_input(&t, buf, n, 0), EXTERIA_OK);
        CHECK_EQ_INT(sent_count, 0);
        chunks[7] = 1;
        n = build(buf, 5, chunks, 20);
        CHECK_EQ_INT(exteria_tgc_sctp_input(&t, buf, n, 0), EXTERIA_OK);
        CHECK_EQ_INT(sent_count, 0);
        n = build(buf, 0, chunks, 20);
        CHECK_EQ_INT(exteria_tgc_sctp_input(&t, buf, n, 0), EXTERIA_OK);
        CHECK_EQ_INT(sent_count, 1);
    }
    CHECK_EQ_INT(exteria_tgc_sctp_input(NULL, buf, 20, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_sctp_input(&s, NULL, 20, 0), EXTERIA_E_ARG);
}

int main(void) {
    crc_vectors();
    init_packet_matches_reference();
    both_start_together();
    one_side_starts_late();
    loss_duplication_and_latency();
    window_and_limits();
    abort_and_shutdown();
    raw_peer_data_handling();
    raw_peer_rejections();
    return test_finish("test_tgc_sctp");
}
