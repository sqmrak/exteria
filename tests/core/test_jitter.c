#include "exteria_jitter.h"
#include "test_util.h"

static exteria_jitter j;
static uint8_t out[EXTERIA_JITTER_MAX_PACKET];

static void put(uint16_t seq, uint8_t tag, exteria_status want) {
    uint8_t data[4] = {tag, tag, tag, tag};
    CHECK_EQ_INT(exteria_jitter_put(&j, seq, data, 4), want);
}

static exteria_jitter_kind get(uint8_t *tag) {
    size_t n = 0;
    exteria_jitter_kind k = exteria_jitter_get(&j, out, sizeof(out), &n);
    if (k == EXTERIA_JITTER_FRAME) {
        CHECK_EQ_INT(n, 4);
        if (tag) *tag = out[0];
    } else {
        CHECK_EQ_INT(n, 0);
    }
    return k;
}

static void fills_then_plays_in_order(void) {
    uint8_t tag = 0;
    CHECK_EQ_INT(exteria_jitter_init(&j, 3), EXTERIA_OK);
    CHECK_EQ_INT(get(NULL), EXTERIA_JITTER_EMPTY);
    put(100, 1, EXTERIA_OK);
    put(101, 2, EXTERIA_OK);
    /* below the target nothing plays yet */
    CHECK_EQ_INT(get(NULL), EXTERIA_JITTER_EMPTY);
    put(102, 3, EXTERIA_OK);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(tag, 1);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(tag, 2);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(tag, 3);
    CHECK_EQ_INT(j.count, 0);
}

static void reordering_is_undone(void) {
    uint8_t tag = 0;
    unsigned i;
    CHECK_EQ_INT(exteria_jitter_init(&j, 3), EXTERIA_OK);
    put(10, 10, EXTERIA_OK);
    put(12, 12, EXTERIA_OK);
    put(11, 11, EXTERIA_OK);
    put(14, 14, EXTERIA_OK);
    put(13, 13, EXTERIA_OK);
    for (i = 0; i < 5; ++i) {
        CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
        CHECK_EQ_INT(tag, 10 + i);
    }
    CHECK_EQ_INT(j.lost, 0);
}

static void loss_is_reported_when_later_packets_wait(void) {
    uint8_t tag = 0;
    CHECK_EQ_INT(exteria_jitter_init(&j, 2), EXTERIA_OK);
    put(1, 1, EXTERIA_OK);
    put(2, 2, EXTERIA_OK);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    /* 3 and 4 never come, 5 does: the reader is told twice that a packet is lost, and then gets 5 */
    put(5, 5, EXTERIA_OK);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(tag, 2);
    CHECK_EQ_INT(get(NULL), EXTERIA_JITTER_LOST);
    CHECK_EQ_INT(get(NULL), EXTERIA_JITTER_LOST);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(tag, 5);
    CHECK_EQ_INT(j.lost, 2);
    /* a late packet of the ones given up is ignored */
    put(3, 3, EXTERIA_E_RETRY);
    CHECK_EQ_INT(j.late, 1);
    CHECK_EQ_INT(j.count, 0);
}

static void duplicates_and_late(void) {
    uint8_t tag = 0;
    CHECK_EQ_INT(exteria_jitter_init(&j, 1), EXTERIA_OK);
    put(50, 1, EXTERIA_OK);
    put(50, 9, EXTERIA_E_RETRY);
    put(51, 2, EXTERIA_OK);
    put(51, 9, EXTERIA_E_RETRY);
    CHECK_EQ_INT(j.duplicates, 2);
    CHECK_EQ_INT(j.count, 2);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(tag, 1);
    put(50, 9, EXTERIA_E_RETRY);
    CHECK_EQ_INT(j.late, 1);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(tag, 2);
}

static void sequence_wraps(void) {
    uint8_t tag = 0;
    uint16_t seq;
    unsigned i;
    CHECK_EQ_INT(exteria_jitter_init(&j, 2), EXTERIA_OK);
    for (seq = 65530, i = 0; i < 12; ++seq, ++i) put(seq, (uint8_t)i, EXTERIA_OK);
    /* the 32 slots hold the whole run across the wrap, and it plays in order */
    for (i = 0; i < 12; ++i) {
        CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
        CHECK_EQ_INT(tag, i);
    }
    /* a packet from before the wrap arriving late is late, not far ahead */
    put(65535, 9, EXTERIA_E_RETRY);
    CHECK_EQ_INT(j.resets, 0);
}

static void far_jump_and_underrun_restart(void) {
    uint8_t tag = 0;
    unsigned i;
    CHECK_EQ_INT(exteria_jitter_init(&j, 2), EXTERIA_OK);
    put(1, 1, EXTERIA_OK);
    put(2, 2, EXTERIA_OK);
    put(3, 3, EXTERIA_OK);
    /* the sender jumps 40 ahead: what was buffered is dropped, and the new run fills afresh before it plays */
    put(43, 43, EXTERIA_OK);
    CHECK_EQ_INT(j.resets, 1);
    CHECK_EQ_INT(j.count, 1);
    CHECK_EQ_INT(get(NULL), EXTERIA_JITTER_EMPTY);
    put(44, 44, EXTERIA_OK);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(tag, 43);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(get(NULL), EXTERIA_JITTER_EMPTY);
    /* the packets stop: after ten empty reads the buffer starts over, and the next arrivals set the sequence */
    for (i = 0; i < EXTERIA_JITTER_UNDERRUN_READS; ++i) CHECK_EQ_INT(get(NULL), EXTERIA_JITTER_EMPTY);
    CHECK_EQ_INT(j.playing, 0);
    CHECK_EQ_INT(j.has_expected, 0);
    put(900, 1, EXTERIA_OK);
    put(901, 2, EXTERIA_OK);
    CHECK_EQ_INT(get(&tag), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(tag, 1);
}

static void limits_and_arguments(void) {
    uint8_t big[EXTERIA_JITTER_MAX_PACKET + 1] = {0};
    size_t n = 7;
    CHECK_EQ_INT(exteria_jitter_init(NULL, 3), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_jitter_init(&j, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_jitter_init(&j, 17), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_jitter_init(&j, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_jitter_put(&j, 1, big, EXTERIA_JITTER_MAX_PACKET + 1), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_jitter_put(&j, 1, big, 0), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_jitter_put(&j, 1, NULL, 4), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_jitter_put(NULL, 1, big, 4), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_jitter_put(&j, 1, big, EXTERIA_JITTER_MAX_PACKET), EXTERIA_OK);
    /* the largest packet is copied whole; a buffer smaller than the largest is refused */
    CHECK_EQ_INT(exteria_jitter_get(&j, out, EXTERIA_JITTER_MAX_PACKET - 1, &n), EXTERIA_JITTER_EMPTY);
    CHECK_EQ_INT(n, 0);
    CHECK_EQ_INT(exteria_jitter_get(&j, out, sizeof(out), &n), EXTERIA_JITTER_FRAME);
    CHECK_EQ_INT(n, EXTERIA_JITTER_MAX_PACKET);
    CHECK_EQ_INT(exteria_jitter_get(NULL, out, sizeof(out), &n), EXTERIA_JITTER_EMPTY);
}

int main(void) {
    fills_then_plays_in_order();
    reordering_is_undone();
    loss_is_reported_when_later_packets_wait();
    duplicates_and_late();
    sequence_wraps();
    far_jump_and_underrun_restart();
    limits_and_arguments();
    return test_finish("test_jitter");
}
