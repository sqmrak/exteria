#ifndef EXTERIA_MT_TRANSPORT_H
#define EXTERIA_MT_TRANSPORT_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_bytes.h"
#include "exteria_crypto.h"
#include "exteria_status.h"

#define EXTERIA_MT_MAX_FRAME (2u * 1024u * 1024u)
#define EXTERIA_MT_SECRET_LEN 16

typedef enum exteria_mt_transport_kind {
    EXTERIA_MT_ABRIDGED = 1,
    EXTERIA_MT_INTERMEDIATE = 2,
    EXTERIA_MT_PADDED_INTERMEDIATE = 3
} exteria_mt_transport_kind;

typedef enum exteria_mt_frame_kind {
    EXTERIA_MT_FRAME_DATA = 1,
    EXTERIA_MT_FRAME_QUICK_ACK,
    EXTERIA_MT_FRAME_ERROR
} exteria_mt_frame_kind;

typedef struct exteria_mt_frame {
    exteria_mt_frame_kind kind;
    const uint8_t *data;
    size_t len;
    uint32_t quick_ack;
    int32_t error_code;
} exteria_mt_frame;

typedef struct exteria_mt_obfuscation {
    int enabled;
    int has_secret;
    uint8_t secret[EXTERIA_MT_SECRET_LEN];
    int16_t dc_id;
} exteria_mt_obfuscation;

typedef struct exteria_mt_transport {
    exteria_mt_transport_kind kind;
    int server_side;
    int synced;
    exteria_mt_obfuscation obf;
    exteria_aes_ctr *enc;
    exteria_aes_ctr *dec;
    exteria_writer rx;
    size_t rx_pos;
} exteria_mt_transport;

void exteria_mt_transport_init(exteria_mt_transport *t);
void exteria_mt_transport_free(exteria_mt_transport *t);

exteria_status exteria_mt_transport_start(exteria_mt_transport *t, exteria_mt_transport_kind kind,
                                          const exteria_mt_obfuscation *obf, exteria_writer *out);
exteria_status exteria_mt_transport_start_server(exteria_mt_transport *t, const uint8_t *secret);

exteria_status exteria_mt_transport_wrap(exteria_mt_transport *t, const uint8_t *payload, size_t len,
                                         int request_quick_ack, exteria_writer *out);
exteria_status exteria_mt_transport_feed(exteria_mt_transport *t, const uint8_t *data, size_t len);
/* returned frames alias rx, so another feed or next call can invalidate them */
exteria_status exteria_mt_transport_next(exteria_mt_transport *t, exteria_mt_frame *frame);

int exteria_mt_transport_padded(const exteria_mt_transport *t);

#endif
