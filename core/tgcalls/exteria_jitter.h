#ifndef EXTERIA_JITTER_H
#define EXTERIA_JITTER_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the buffer between the network and the speaker for the audio of a call: Opus packets arrive out of order, late,
   twice or not at all, and the speaker wants one in order whenever it runs low */

#define EXTERIA_JITTER_SLOTS 32
#define EXTERIA_JITTER_MAX_PACKET 1280
#define EXTERIA_JITTER_UNDERRUN_READS 10

typedef struct exteria_jitter_slot {
    uint8_t used;
    uint16_t sequence;
    uint16_t len;
    uint8_t data[EXTERIA_JITTER_MAX_PACKET];
} exteria_jitter_slot;

typedef struct exteria_jitter {
    exteria_jitter_slot slots[EXTERIA_JITTER_SLOTS];
    uint16_t expected;
    uint8_t has_expected;
    uint8_t playing;
    uint8_t target;
    unsigned count;
    unsigned empty_reads;
    unsigned late;
    unsigned duplicates;
    unsigned lost;
    unsigned resets;
} exteria_jitter;

typedef enum exteria_jitter_kind {
    EXTERIA_JITTER_EMPTY,   /* nothing to play: still filling, or the packets stopped */
    EXTERIA_JITTER_FRAME,   /* the next packet, copied out */
    EXTERIA_JITTER_LOST     /* the next packet never came; later ones did */
} exteria_jitter_kind;

/* target is the number of packets to hold before playing starts, from 1 to 16 (EXTERIA_E_ARG otherwise) */
exteria_status exteria_jitter_init(exteria_jitter *j, unsigned target);

/* a packet by its sequence number */
exteria_status exteria_jitter_put(exteria_jitter *j, uint16_t sequence, const uint8_t *data, size_t len);

/* the next packet for the speaker. out takes up to capacity bytes (EXTERIA_JITTER_MAX_PACKET is always enough) and len the length */
exteria_jitter_kind exteria_jitter_get(exteria_jitter *j, uint8_t *out, size_t capacity, size_t *len);

#endif
