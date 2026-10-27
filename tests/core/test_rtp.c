#include "exteria_rtp.h"
#include "exteria_vp8_rtp.h"
#include "test_util.h"

static void rtp_parse_plain(void) {
    const uint8_t packet[] = {0x80, 0xE5, 0x12, 0x34, 0xAA, 0xBB, 0xCC, 0xDD, 0x01, 0x02, 0x03, 0x04, 0x11, 0x22, 0x33};
    exteria_rtp_header h;
    CHECK_EQ_INT(exteria_rtp_parse(packet, sizeof(packet), &h), EXTERIA_OK);
    CHECK_EQ_INT(h.marker, 1);
    CHECK_EQ_INT(h.payload_type, 0x65);
    CHECK_EQ_INT(h.sequence, 0x1234);
    CHECK(h.timestamp == 0xAABBCCDDu);
    CHECK(h.ssrc == 0x01020304u);
    CHECK_EQ_INT(h.payload_offset, 12);
    CHECK_EQ_INT(h.payload_len, 3);
    /* a header with no media is legal */
    CHECK_EQ_INT(exteria_rtp_parse(packet, 12, &h), EXTERIA_OK);
    CHECK_EQ_INT(h.payload_len, 0);
}

static void rtp_parse_extras(void) {
    /* two csrc, an extension of one word, then padding of two */
    uint8_t packet[12 + 8 + 4 + 4 + 3 + 2] = {0xB2, 0x60, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3};
    exteria_rtp_header h;
    packet[12 + 8] = 0xBE;
    packet[12 + 8 + 1] = 0xDE;
    packet[12 + 8 + 2] = 0;
    packet[12 + 8 + 3] = 1;
    packet[sizeof(packet) - 1] = 2;
    CHECK_EQ_INT(exteria_rtp_parse(packet, sizeof(packet), &h), EXTERIA_OK);
    CHECK_EQ_INT(h.payload_offset, 12 + 8 + 4 + 4);
    CHECK_EQ_INT(h.payload_len, 3);
    /* padding longer than the bytes after the header, and zero padding */
    packet[sizeof(packet) - 1] = 6;
    CHECK_EQ_INT(exteria_rtp_parse(packet, sizeof(packet), &h), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(h.payload_len, 0);
    packet[sizeof(packet) - 1] = 0;
    CHECK_EQ_INT(exteria_rtp_parse(packet, sizeof(packet), &h), EXTERIA_E_MALFORMED);
    /* the extension claims more words than the packet holds */
    packet[sizeof(packet) - 1] = 2;
    packet[12 + 8 + 3] = 200;
    CHECK_EQ_INT(exteria_rtp_parse(packet, sizeof(packet), &h), EXTERIA_E_MALFORMED);
    /* the csrc list runs past the end */
    CHECK_EQ_INT(exteria_rtp_parse(packet, 16, &h), EXTERIA_E_MALFORMED);
}

static void rtp_parse_bad(void) {
    uint8_t packet[16] = {0x80, 0x60};
    exteria_rtp_header h;
    CHECK_EQ_INT(exteria_rtp_parse(packet, 11, &h), EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(exteria_rtp_parse(NULL, 16, &h), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_rtp_parse(packet, 16, NULL), EXTERIA_E_ARG);
    packet[0] = 0x40;
    CHECK_EQ_INT(exteria_rtp_parse(packet, 16, &h), EXTERIA_E_MALFORMED);
    packet[0] = 0xC0;
    CHECK_EQ_INT(exteria_rtp_parse(packet, 16, &h), EXTERIA_E_MALFORMED);
}

static void rtp_write(void) {
    uint8_t out[12];
    const uint8_t want[12] = {0x80, 0xE5, 0xFF, 0xFE, 0x00, 0x00, 0x01, 0x00, 0xDE, 0xAD, 0xBE, 0xEF};
    exteria_rtp_header h;
    CHECK_EQ_INT(exteria_rtp_write_header(out, sizeof(out), 0x65, 1, 0xFFFE, 256, 0xDEADBEEFu), EXTERIA_OK);
    CHECK(memcmp(out, want, 12) == 0);
    CHECK_EQ_INT(exteria_rtp_parse(out, 12, &h), EXTERIA_OK);
    CHECK_EQ_INT(h.sequence, 0xFFFE);
    CHECK_EQ_INT(exteria_rtp_write_header(out, 11, 0x65, 1, 0, 0, 0), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_rtp_write_header(out, 12, 128, 1, 0, 0, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_rtp_write_header(NULL, 12, 1, 1, 0, 0, 0), EXTERIA_E_ARG);
}

static void receive_stats(void) {
    exteria_rtp_receive_stats stats;
    uint8_t block[EXTERIA_RTCP_BLOCK_LEN];
    uint16_t seq;
    exteria_rtp_stats_reset(&stats, 0xAABBCCDDu);
    CHECK_EQ_INT(exteria_rtp_stats_block(&stats, 1000, block), EXTERIA_E_STATE);
    /* ten packets in a row, no loss */
    for (seq = 100; seq < 110; ++seq) exteria_rtp_stats_update(&stats, seq);
    exteria_rtp_stats_update(&stats, 109);
    CHECK_EQ_INT(exteria_rtp_stats_block(&stats, 1000, block), EXTERIA_OK);
    CHECK_EQ_INT(block[0], 0xAA);
    CHECK_EQ_INT(block[3], 0xDD);
    CHECK_EQ_INT(block[4], 0);
    CHECK_EQ_INT(block[7], 0);
    CHECK_EQ_INT(block[11], 109);
    CHECK_EQ_INT(block[19] + block[18] + block[17] + block[16], 0);
    /* two of the next ten never come: a fifth of the interval, 51 of 256, and two lost in all */
    for (seq = 110; seq < 120; ++seq) if (seq != 113 && seq != 114) exteria_rtp_stats_update(&stats, seq);
    CHECK_EQ_INT(exteria_rtp_stats_block(&stats, 2000, block), EXTERIA_OK);
    CHECK_EQ_INT(block[4], 51);
    CHECK_EQ_INT(block[7], 2);
    CHECK_EQ_INT(block[11], 119);
    /* a late packet fills a gap: the total drops, the highest sequence does not move */
    exteria_rtp_stats_update(&stats, 113);
    CHECK_EQ_INT(exteria_rtp_stats_block(&stats, 3000, block), EXTERIA_OK);
    CHECK_EQ_INT(block[4], 0);
    CHECK_EQ_INT(block[7], 1);
    CHECK_EQ_INT(block[11], 119);
    /* the sequence wraps: the extended number goes past 65535 */
    exteria_rtp_stats_reset(&stats, 1);
    exteria_rtp_stats_update(&stats, 65534);
    exteria_rtp_stats_update(&stats, 65535);
    exteria_rtp_stats_update(&stats, 0);
    exteria_rtp_stats_update(&stats, 1);
    CHECK_EQ_INT(exteria_rtp_stats_block(&stats, 1000, block), EXTERIA_OK);
    CHECK_EQ_INT(block[8], 0);
    CHECK_EQ_INT(block[9], 1);
    CHECK_EQ_INT(block[10], 0);
    CHECK_EQ_INT(block[11], 1);
    CHECK_EQ_INT(block[7], 0);
    /* a sender report seen half a second ago comes back as the last SR and a delay of 32768 units of 1/65536 s */
    exteria_rtp_stats_sender_report(&stats, 0x01020304u, 5000);
    CHECK_EQ_INT(exteria_rtp_stats_block(&stats, 5500, block), EXTERIA_OK);
    CHECK_EQ_INT(block[16], 1);
    CHECK_EQ_INT(block[19], 4);
    CHECK_EQ_INT(block[22], 0x80);
    CHECK_EQ_INT(block[23], 0);
}

static void receiver_report(void) {
    uint8_t blocks[2 * EXTERIA_RTCP_BLOCK_LEN], out[8 + 2 * EXTERIA_RTCP_BLOCK_LEN];
    size_t len = 0, i;
    for (i = 0; i < sizeof(blocks); ++i) blocks[i] = (uint8_t)i;
    CHECK_EQ_INT(exteria_rtcp_write_receiver_report(out, sizeof(out), 0x01020304u, blocks, 2, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 56);
    CHECK_EQ_INT(out[0], 0x82);
    CHECK_EQ_INT(out[1], 201);
    CHECK_EQ_INT(out[2], 0);
    CHECK_EQ_INT(out[3], 13);
    CHECK_EQ_INT(out[4], 1);
    CHECK_EQ_INT(out[7], 4);
    CHECK_EQ_INT(out[8], 0);
    CHECK_EQ_INT(out[55], 47);
    CHECK_EQ_INT(exteria_rtcp_write_receiver_report(out, 55, 1, blocks, 2, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_rtcp_write_receiver_report(out, sizeof(out), 1, blocks, 5, &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_rtcp_write_receiver_report(out, sizeof(out), 1, NULL, 1, &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_rtcp_write_receiver_report(out, sizeof(out), 1, NULL, 0, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 8);
    CHECK_EQ_INT(out[0], 0x80);
    CHECK_EQ_INT(out[3], 1);
}

static void rtcp_pli(void) {
    uint8_t out[12];
    const uint8_t want[12] = {0x81, 0xCE, 0x00, 0x02, 0x00, 0x00, 0x00, 0x07, 0x11, 0x22, 0x33, 0x44};
    CHECK_EQ_INT(exteria_rtcp_write_pli(out, sizeof(out), 7, 0x11223344u), EXTERIA_OK);
    CHECK(memcmp(out, want, 12) == 0);
    CHECK_EQ_INT(exteria_rtcp_write_pli(out, 11, 7, 1), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_rtcp_write_pli(NULL, 12, 7, 1), EXTERIA_E_ARG);
}

/* a frame of the given size that passes the depacketizer's checks: the tag of a key frame, its start code, then bytes that
   differ from place to place so a misplaced chunk shows */
static void make_frame(uint8_t *frame, size_t len, int key) {
    size_t i;
    for (i = 0; i < len; ++i) frame[i] = (uint8_t)(i * 31u + 7u);
    frame[0] = (uint8_t)(key ? 0x10 : 0x11);
    if (key && len >= 10) {
        frame[3] = 0x9D;
        frame[4] = 0x01;
        frame[5] = 0x2A;
    }
}

typedef struct packet {
    uint8_t data[EXTERIA_VP8_MAX_PAYLOAD];
    size_t len;
    int marker;
} packet;

static size_t cut(const uint8_t *frame, size_t len, size_t max_payload, uint16_t picture_id, packet *out, size_t out_cap) {
    exteria_vp8_packetizer p;
    size_t count = 0;
    int marker = 0;
    CHECK_EQ_INT(exteria_vp8_packetizer_init(&p, frame, len, max_payload, picture_id, 0), EXTERIA_OK);
    while (count < out_cap) {
        exteria_status s = exteria_vp8_packetizer_next(&p, out[count].data, sizeof(out[count].data), &out[count].len, &marker);
        if (s == EXTERIA_E_EOF) break;
        CHECK_EQ_INT(s, EXTERIA_OK);
        out[count].marker = marker;
        ++count;
    }
    return count;
}

static packet pk[600];
static uint8_t original[EXTERIA_VP8_MAX_FRAME];
static uint8_t storage[EXTERIA_VP8_MAX_FRAME];

static void packetize_shapes(void) {
    static const size_t sizes[] = {10, 11, 1000, 1396, 1397, 1400, 2792, 2793, 5000, 40000, 300000};
    size_t s;
    for (s = 0; s < sizeof(sizes) / sizeof(sizes[0]); ++s) {
        size_t len = sizes[s], n, i, min = 100000, max = 0, total = 0;
        exteria_vp8_depacketizer d;
        exteria_vp8_frame_info info;
        make_frame(original, len, 1);
        n = cut(original, len, 1400, 0x7FFF, pk, 600);
        CHECK(n >= 1);
        CHECK_EQ_INT(exteria_vp8_depacketizer_init(&d, storage, sizeof(storage)), EXTERIA_OK);
        for (i = 0; i < n; ++i) {
            CHECK(pk[i].len <= 1400);
            CHECK_EQ_INT(pk[i].marker, i + 1 == n);
            CHECK_EQ_INT(pk[i].data[0] & 0x10, i == 0 ? 0x10 : 0);
            CHECK_EQ_INT(pk[i].data[0] & 0xC8, 0x80);
            CHECK_EQ_INT(pk[i].data[1], 0x80);
            CHECK_EQ_INT(pk[i].data[2], 0xFF);
            CHECK_EQ_INT(pk[i].data[3], 0xFF);
            if (pk[i].len - 4 < min) min = pk[i].len - 4;
            if (pk[i].len - 4 > max) max = pk[i].len - 4;
            total += pk[i].len - 4;
            CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, (uint16_t)(65530u + i), 9000, pk[i].marker, pk[i].data, pk[i].len, &info), EXTERIA_OK);
            CHECK_EQ_INT(info.ready, i + 1 == n);
        }
        /* the sequence ran across the 16 bit wrap for the larger frames; nothing was dropped */
        CHECK_EQ_INT(total, len);
        CHECK(max - min <= 1);
        CHECK_EQ_INT(info.length, len);
        CHECK_EQ_INT(info.key_frame, 1);
        CHECK(info.timestamp == 9000);
        CHECK(memcmp(storage, original, len) == 0);
        CHECK_EQ_INT(d.need_key_frame, 0);
        CHECK_EQ_INT(d.dropped_frames, 0);
    }
}

static void packetizer_arguments(void) {
    exteria_vp8_packetizer p;
    uint8_t out[1400];
    size_t n = 0;
    int marker = 1;
    make_frame(original, 100, 1);
    CHECK_EQ_INT(exteria_vp8_packetizer_init(NULL, original, 100, 1000, 0, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_vp8_packetizer_init(&p, NULL, 100, 1000, 0, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_vp8_packetizer_init(&p, original, 0, 1000, 0, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_vp8_packetizer_init(&p, original, 100, 15, 0, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_vp8_packetizer_init(&p, original, 100, 1401, 0, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_vp8_packetizer_init(&p, original, EXTERIA_VP8_MAX_FRAME + 1, 1000, 0, 0), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_vp8_packetizer_init(&p, original, 100, 1000, 0x8001, 1), EXTERIA_OK);
    CHECK_EQ_INT(p.picture_id, 1);
    CHECK_EQ_INT(exteria_vp8_packetizer_next(&p, out, 999, &n, &marker), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_vp8_packetizer_next(&p, out, sizeof(out), &n, &marker), EXTERIA_OK);
    /* n is set for a frame nothing else refers to */
    CHECK_EQ_INT(out[0], 0xB0);
    CHECK_EQ_INT(n, 104);
    CHECK_EQ_INT(marker, 1);
    CHECK_EQ_INT(exteria_vp8_packetizer_next(&p, out, sizeof(out), &n, &marker), EXTERIA_E_EOF);
    CHECK_EQ_INT(n, 0);
    CHECK_EQ_INT(marker, 0);
}

static exteria_vp8_frame_info push(exteria_vp8_depacketizer *d, const packet *p, uint16_t seq, uint32_t ts, exteria_status want) {
    exteria_vp8_frame_info info = {0, 0, 0, 0};
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(d, seq, ts, p->marker, p->data, p->len, &info), want);
    return info;
}

static void loss_and_recovery(void) {
    exteria_vp8_depacketizer d;
    exteria_vp8_frame_info info = {0, 0, 0, 0};
    size_t n, i;
    CHECK_EQ_INT(exteria_vp8_depacketizer_init(&d, storage, sizeof(storage)), EXTERIA_OK);
    /* a stream that starts with an inter frame waits for a key frame */
    make_frame(original, 3000, 0);
    n = cut(original, 3000, 1000, 1, pk, 600);
    CHECK_EQ_INT(n, 4);
    for (i = 0; i < n; ++i) info = push(&d, &pk[i], (uint16_t)(100 + i), 3000, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 0);
    CHECK_EQ_INT(d.need_key_frame, 1);
    CHECK_EQ_INT(d.dropped_frames, 1);

    make_frame(original, 3000, 1);
    n = cut(original, 3000, 1000, 2, pk, 600);
    for (i = 0; i < n; ++i) info = push(&d, &pk[i], (uint16_t)(104 + i), 6000, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 1);
    CHECK_EQ_INT(info.key_frame, 1);
    CHECK_EQ_INT(d.need_key_frame, 0);

    /* an inter frame now passes */
    make_frame(original, 1500, 0);
    n = cut(original, 1500, 1000, 3, pk, 600);
    CHECK_EQ_INT(n, 2);
    push(&d, &pk[0], 108, 9000, EXTERIA_OK);
    info = push(&d, &pk[1], 109, 9000, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 1);
    CHECK_EQ_INT(info.key_frame, 0);

    /* the middle packet of the next inter frame is lost: the frame goes, the later packet of it does not complete anything */
    make_frame(original, 3000, 0);
    n = cut(original, 3000, 1000, 4, pk, 600);
    push(&d, &pk[0], 110, 12000, EXTERIA_OK);
    push(&d, &pk[2], 112, 12000, EXTERIA_OK);
    info = push(&d, &pk[3], 113, 12000, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 0);
    CHECK_EQ_INT(d.need_key_frame, 1);
    CHECK_EQ_INT(d.in_frame, 0);
    CHECK_EQ_INT(d.dropped_frames, 2);

    /* a whole frame missing between two good ones also asks for a key frame, and the inter frame after it is held back */
    make_frame(original, 1500, 1);
    n = cut(original, 1500, 1000, 5, pk, 600);
    push(&d, &pk[0], 114, 15000, EXTERIA_OK);
    info = push(&d, &pk[1], 115, 15000, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 1);
    CHECK_EQ_INT(d.need_key_frame, 0);
    make_frame(original, 900, 0);
    n = cut(original, 900, 1000, 6, pk, 600);
    info = push(&d, &pk[0], 120, 21000, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 0);
    CHECK_EQ_INT(d.need_key_frame, 1);
}

static void duplicates_and_order(void) {
    exteria_vp8_depacketizer d;
    exteria_vp8_frame_info info = {0, 0, 0, 0};
    size_t n;
    CHECK_EQ_INT(exteria_vp8_depacketizer_init(&d, storage, sizeof(storage)), EXTERIA_OK);
    make_frame(original, 2000, 1);
    n = cut(original, 2000, 1000, 1, pk, 600);
    CHECK_EQ_INT(n, 3);
    push(&d, &pk[0], 65535, 100, EXTERIA_OK);
    /* a repeat and a late packet change nothing */
    push(&d, &pk[0], 65535, 100, EXTERIA_OK);
    push(&d, &pk[1], 0, 100, EXTERIA_OK);
    push(&d, &pk[0], 65535, 100, EXTERIA_OK);
    info = push(&d, &pk[2], 1, 100, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 1);
    CHECK_EQ_INT(info.length, 2000);
    CHECK(memcmp(storage, original, 2000) == 0);
    CHECK_EQ_INT(d.dropped_frames, 0);
    /* a late packet after the frame is done */
    push(&d, &pk[2], 1, 100, EXTERIA_OK);
    CHECK_EQ_INT(d.need_key_frame, 0);
}

static void frame_in_progress_cut_short(void) {
    exteria_vp8_depacketizer d;
    exteria_vp8_frame_info info = {0, 0, 0, 0};
    size_t n;
    CHECK_EQ_INT(exteria_vp8_depacketizer_init(&d, storage, sizeof(storage)), EXTERIA_OK);
    make_frame(original, 2000, 1);
    n = cut(original, 2000, 1000, 1, pk, 600);
    /* the marker packet never arrives and the next frame starts with the next sequence number */
    push(&d, &pk[0], 10, 100, EXTERIA_OK);
    push(&d, &pk[1], 11, 100, EXTERIA_OK);
    info = push(&d, &pk[0], 12, 200, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 0);
    CHECK_EQ_INT(d.dropped_frames, 1);
    CHECK_EQ_INT(d.need_key_frame, 1);
    /* the timestamp changes in the middle of a frame */
    push(&d, &pk[1], 13, 300, EXTERIA_OK);
    CHECK_EQ_INT(d.in_frame, 0);
    CHECK_EQ_INT(d.dropped_frames, 2);
    (void)n;
}

static void damaged_input(void) {
    exteria_vp8_depacketizer d;
    exteria_vp8_frame_info info = {0, 0, 0, 0};
    uint8_t bad[1400];
    packet one;
    size_t i;
    CHECK_EQ_INT(exteria_vp8_depacketizer_init(&d, storage, sizeof(storage)), EXTERIA_OK);
    memset(bad, 0, sizeof(bad));

    /* reserved bits in the first byte, in the extension byte */
    bad[0] = 0xD0; bad[1] = 0x80; bad[2] = 0x00; bad[3] = 1;
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 1, 1, 1, bad, 4, &info), EXTERIA_E_MALFORMED);
    bad[0] = 0x98;
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 2, 1, 1, bad, 4, &info), EXTERIA_E_MALFORMED);
    bad[0] = 0x90; bad[1] = 0x01;
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 3, 1, 1, bad, 4, &info), EXTERIA_E_MALFORMED);
    /* extensions that end the payload, an empty payload, one byte */
    bad[1] = 0xF0;
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 4, 1, 1, bad, 5, &info), EXTERIA_E_MALFORMED);
    bad[1] = 0x80; bad[2] = 0x80;
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 5, 1, 1, bad, 3, &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 6, 1, 1, bad, 2, &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 7, 1, 1, bad, 1, &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 8, 1, 1, bad, 0, &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 9, 1, 1, NULL, 0, &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(info.ready, 0);

    /* a frame shorter than its tag, a key frame with no start code or too short */
    one.marker = 1;
    one.data[0] = 0x10; one.data[1] = 0x10; one.data[2] = 0x00;
    one.len = 3;
    push(&d, &one, 20, 1, EXTERIA_E_MALFORMED);
    make_frame(original, 100, 1);
    original[4] = 0x02;
    one.data[0] = 0x10;
    memcpy(one.data + 1, original, 100);
    one.len = 101;
    push(&d, &one, 21, 2, EXTERIA_E_MALFORMED);
    one.len = 6;
    original[4] = 0x01;
    memcpy(one.data + 1, original, 5);
    push(&d, &one, 22, 3, EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(d.need_key_frame, 1);
    CHECK_EQ_INT(d.length, 0);

    /* foreign descriptors with every optional field carry the frame after them: I with 15 bits, L, T and K */
    make_frame(original, 100, 1);
    one.data[0] = 0x90;
    one.data[1] = 0xF0;
    one.data[2] = 0x81; one.data[3] = 0x23;
    one.data[4] = 0x55;
    one.data[5] = 0x66;
    memcpy(one.data + 6, original, 100);
    one.len = 106;
    info = push(&d, &one, 23, 4, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 1);
    CHECK_EQ_INT(info.length, 100);
    CHECK(memcmp(storage, original, 100) == 0);
    /* and the one byte picture id, nothing else */
    one.data[0] = 0x90; one.data[1] = 0x80; one.data[2] = 0x42;
    memcpy(one.data + 3, original, 100);
    one.len = 103;
    info = push(&d, &one, 24, 5, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 1);
    CHECK(memcmp(storage, original, 100) == 0);
    /* no extension at all */
    one.data[0] = 0x10;
    memcpy(one.data + 1, original, 100);
    one.len = 101;
    info = push(&d, &one, 25, 6, EXTERIA_OK);
    CHECK_EQ_INT(info.ready, 1);

    /* a frame over the storage is refused and dropped */
    {
        exteria_vp8_depacketizer small;
        uint8_t room[64];
        CHECK_EQ_INT(exteria_vp8_depacketizer_init(&small, room, sizeof(room)), EXTERIA_OK);
        one.data[0] = 0x10;
        memcpy(one.data + 1, original, 100);
        one.len = 101;
        one.marker = 0;
        push(&small, &one, 1, 1, EXTERIA_E_LIMIT);
        CHECK_EQ_INT(small.in_frame, 0);
        CHECK_EQ_INT(small.need_key_frame, 1);
    }
    for (i = 0; i < 1; ++i) CHECK_EQ_INT(d.need_key_frame, 0);
}

static void depacketizer_arguments(void) {
    exteria_vp8_depacketizer d;
    exteria_vp8_frame_info info = {0, 0, 0, 0};
    uint8_t room[16];
    CHECK_EQ_INT(exteria_vp8_depacketizer_init(NULL, room, sizeof(room)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_vp8_depacketizer_init(&d, NULL, sizeof(room)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_vp8_depacketizer_init(&d, room, 9), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_vp8_depacketizer_init(&d, room, EXTERIA_VP8_MAX_FRAME + 1), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_vp8_depacketizer_init(&d, room, sizeof(room)), EXTERIA_OK);
    CHECK_EQ_INT(d.need_key_frame, 1);
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(&d, 1, 1, 1, room, 4, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_vp8_depacketizer_push(NULL, 1, 1, 1, room, 4, &info), EXTERIA_E_ARG);
}

int main(void) {
    rtp_parse_plain();
    rtp_parse_extras();
    rtp_parse_bad();
    rtp_write();
    rtcp_pli();
    receive_stats();
    receiver_report();
    packetize_shapes();
    packetizer_arguments();
    loss_and_recovery();
    duplicates_and_order();
    frame_in_progress_cut_short();
    damaged_input();
    depacketizer_arguments();
    return test_finish("test_rtp");
}
