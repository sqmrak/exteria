#include "exteria_jitter.h"

#include <string.h>

exteria_status exteria_jitter_init(exteria_jitter *j, unsigned target) {
    if (!j) return EXTERIA_E_ARG;
    memset(j, 0, sizeof(*j));
    if (target < 1 || target > 16) return EXTERIA_E_ARG;
    j->target = (uint8_t)target;
    return EXTERIA_OK;
}

static void restart(exteria_jitter *j) {
    memset(j->slots, 0, sizeof(j->slots));
    j->count = 0;
    j->empty_reads = 0;
    j->playing = 0;
    j->has_expected = 0;
}

exteria_status exteria_jitter_put(exteria_jitter *j, uint16_t sequence, const uint8_t *data, size_t len) {
    exteria_jitter_slot *slot;
    int16_t ahead;
    if (!j || !data) return EXTERIA_E_ARG;
    if (len == 0 || len > EXTERIA_JITTER_MAX_PACKET) return EXTERIA_E_LIMIT;
    if (!j->has_expected) {
        j->expected = sequence;
        j->has_expected = 1;
    }
    ahead = (int16_t)(uint16_t)(sequence - j->expected);
    if (ahead < 0) {
        ++j->late;
        return EXTERIA_E_RETRY;
    }
    if (ahead >= EXTERIA_JITTER_SLOTS) {
        /* the sender jumped, or the stream began again: nothing buffered fits any more */
        restart(j);
        ++j->resets;
        j->expected = sequence;
        j->has_expected = 1;
    }
    slot = &j->slots[sequence % EXTERIA_JITTER_SLOTS];
    if (slot->used) {
        ++j->duplicates;
        return EXTERIA_E_RETRY;
    }
    slot->used = 1;
    slot->sequence = sequence;
    slot->len = (uint16_t)len;
    memcpy(slot->data, data, len);
    ++j->count;
    if (!j->playing && j->count >= j->target) j->playing = 1;
    return EXTERIA_OK;
}

exteria_jitter_kind exteria_jitter_get(exteria_jitter *j, uint8_t *out, size_t capacity, size_t *len) {
    exteria_jitter_slot *slot;
    if (len) *len = 0;
    if (!j || !out || !len || capacity < EXTERIA_JITTER_MAX_PACKET || !j->playing) return EXTERIA_JITTER_EMPTY;
    slot = &j->slots[j->expected % EXTERIA_JITTER_SLOTS];
    if (slot->used && slot->sequence == j->expected) {
        memcpy(out, slot->data, slot->len);
        *len = slot->len;
        slot->used = 0;
        --j->count;
        ++j->expected;
        j->empty_reads = 0;
        return EXTERIA_JITTER_FRAME;
    }
    if (j->count > 0) {
        ++j->lost;
        ++j->expected;
        j->empty_reads = 0;
        return EXTERIA_JITTER_LOST;
    }
    if (++j->empty_reads >= EXTERIA_JITTER_UNDERRUN_READS) restart(j);
    return EXTERIA_JITTER_EMPTY;
}
