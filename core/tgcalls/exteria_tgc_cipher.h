#ifndef EXTERIA_TGC_CIPHER_H
#define EXTERIA_TGC_CIPHER_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the encryption of the signaling data of a tgcalls call: what travels in phone.sendSignalingData and
   updatePhoneCallSignalingData */

#define EXTERIA_TGC_KEY_LEN 256
#define EXTERIA_TGC_MSG_KEY_LEN 16
#define EXTERIA_TGC_COUNTER_LEN 4
/* the largest plain message either side sends */
#define EXTERIA_TGC_SIGNAL_MAX 16384
#define EXTERIA_TGC_PACKET_MAX (EXTERIA_TGC_MSG_KEY_LEN + EXTERIA_TGC_COUNTER_LEN + EXTERIA_TGC_SIGNAL_MAX)
/* the 22 bits of counter after the two flag bits; tgcalls masks them off an incoming counter and a sender never reaches them */
#define EXTERIA_TGC_COUNTER_MAX 0x3FFFFFFFu

typedef struct exteria_tgc_cipher {
    uint8_t key[EXTERIA_TGC_KEY_LEN];
    uint8_t out_shift;
    uint8_t in_shift;
    uint32_t sent;
    uint32_t highest;
    uint64_t window;
} exteria_tgc_cipher;

/* key is the 256 byte call key. is_outgoing is true on the side that placed the call */
exteria_status exteria_tgc_cipher_init(exteria_tgc_cipher *c, const uint8_t key[EXTERIA_TGC_KEY_LEN], int is_outgoing);

/* writes the sealed packet of plain to out and its length to out_len; EXTERIA_E_LIMIT for an empty or oversized
   message or too small a buffer, EXTERIA_E_STATE once the counter is used up */
exteria_status exteria_tgc_cipher_seal(exteria_tgc_cipher *c, const uint8_t *plain, size_t plain_len, uint8_t *out, size_t capacity,
                                       size_t *out_len);

/* opens a sealed packet */
exteria_status exteria_tgc_cipher_open(exteria_tgc_cipher *c, const uint8_t *packet, size_t packet_len, uint8_t *out, size_t capacity,
                                       size_t *out_len);

void exteria_tgc_cipher_wipe(exteria_tgc_cipher *c);

#endif
