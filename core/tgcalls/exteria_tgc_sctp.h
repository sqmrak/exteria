#ifndef EXTERIA_TGC_SCTP_H
#define EXTERIA_TGC_SCTP_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the one data channel of a tgcalls call: SCTP (RFC 4960) over the DTLS session (RFC 8261), with the data channel
   protocol (RFC 8832) on its stream 0 */

#define EXTERIA_TGC_SCTP_PORT 5000
/* the largest packet this sends, so that it fits the 1100 byte limit of one DTLS write */
#define EXTERIA_TGC_SCTP_MAX_PACKET 1100
/* the largest packet taken in: one DTLS datagram */
#define EXTERIA_TGC_SCTP_MAX_INPUT 1500
#define EXTERIA_TGC_SCTP_MAX_COOKIE 400
#define EXTERIA_TGC_SCTP_MAX_MESSAGE 900
#define EXTERIA_TGC_SCTP_WINDOW 16
#define EXTERIA_TGC_SCTP_RX_SLOTS 32
#define EXTERIA_TGC_SCTP_RX_MESSAGE_MAX 16384
#define EXTERIA_TGC_SCTP_CHANNEL_LABEL "data"

typedef enum exteria_tgc_sctp_state {
    EXTERIA_TGC_SCTP_CLOSED,
    EXTERIA_TGC_SCTP_COOKIE_WAIT,
    EXTERIA_TGC_SCTP_COOKIE_ECHOED,
    EXTERIA_TGC_SCTP_ESTABLISHED,
    EXTERIA_TGC_SCTP_FAILED
} exteria_tgc_sctp_state;

typedef struct exteria_tgc_sctp_events {
    void *context;
    /* one SCTP packet for the DTLS session to carry */
    void (*send)(void *context, const uint8_t *packet, size_t len);
    /* the channel opened (true) or the association ended (false) */
    void (*channel)(void *context, int open);
    /* a text message of the other side, NUL terminated, valid during the call */
    void (*message)(void *context, const char *text, size_t len);
} exteria_tgc_sctp_events;

typedef struct exteria_tgc_sctp_chunk {
    uint8_t used;
    uint32_t tsn;
    uint16_t ssn;
    uint32_t ppid;
    uint16_t len;
    uint8_t tries;
    uint64_t sent_ms;
    uint8_t data[EXTERIA_TGC_SCTP_MAX_MESSAGE + 4];
} exteria_tgc_sctp_chunk;

typedef struct exteria_tgc_sctp_rx {
    uint8_t used;
    uint8_t flags;
    uint32_t tsn;
    uint16_t stream;
    uint16_t ssn;
    uint32_t ppid;
    uint16_t len;
    uint8_t data[EXTERIA_TGC_SCTP_MAX_INPUT];
} exteria_tgc_sctp_rx;

typedef struct exteria_tgc_sctp {
    exteria_tgc_sctp_events events;
    exteria_tgc_sctp_state state;
    uint8_t opener;
    uint8_t channel_open;
    uint8_t open_sent;
    uint32_t my_tag;
    uint32_t peer_tag;
    uint32_t my_initial_tsn;
    uint32_t next_tsn;
    uint32_t peer_rwnd;
    uint16_t next_ssn;
    uint8_t cookie[32];
    uint8_t has_cookie;
    uint8_t answered_init;
    /* the other side's INIT or INIT ACK, remembered until the association stands */
    uint32_t peer_initial_tsn;
    uint8_t has_peer_init;
    uint32_t cumulative;        /* the highest TSN received with none missing before it */
    uint8_t cumulative_valid;
    uint8_t need_sack;
    uint32_t dup_tsn[4];
    uint8_t dup_count;
    exteria_tgc_sctp_chunk window[EXTERIA_TGC_SCTP_WINDOW];
    exteria_tgc_sctp_rx rx[EXTERIA_TGC_SCTP_RX_SLOTS];
    uint8_t assembling;
    uint8_t assembly[EXTERIA_TGC_SCTP_RX_MESSAGE_MAX + 1];
    size_t assembly_len;
    uint16_t assembly_stream;
    uint32_t assembly_ppid;
    uint64_t t1_due;
    uint8_t t1_tries;
    uint64_t t3_due;
    uint64_t rto_ms;
    uint8_t t3_tries;
    uint8_t echo[EXTERIA_TGC_SCTP_MAX_COOKIE];
    size_t echo_len;
} exteria_tgc_sctp;

/* is_opener: this side sends the DATA_CHANNEL_OPEN (the side that placed the call). tag and initial_tsn come from
   the owner's random source; neither is zero; EXTERIA_E_ARG otherwise */
exteria_status exteria_tgc_sctp_init(exteria_tgc_sctp *s, int is_opener, uint32_t tag, uint32_t initial_tsn, const uint8_t cookie[32],
                                     const exteria_tgc_sctp_events *events);

/* the DTLS session is up: sends the INIT, which both sides do */
exteria_status exteria_tgc_sctp_start(exteria_tgc_sctp *s, uint64_t now_ms);

/* one packet from the DTLS session; EXTERIA_E_MALFORMED for a bad checksum, a wrong verification tag or a damaged
   chunk; the packet is dropped, which is what SCTP does with such a packet */
exteria_status exteria_tgc_sctp_input(exteria_tgc_sctp *s, const uint8_t *packet, size_t len, uint64_t now_ms);

/* timers: INIT and COOKIE ECHO repeats, retransmission of unacknowledged data, a delayed SACK; every 50 ms or so */
void exteria_tgc_sctp_tick(exteria_tgc_sctp *s, uint64_t now_ms);

/* one text message on the channel, up to EXTERIA_TGC_SCTP_MAX_MESSAGE bytes; EXTERIA_E_STATE until the channel is
   open, EXTERIA_E_LIMIT for a message too long or when the window of unacknowledged data is full */
exteria_status exteria_tgc_sctp_send_text(exteria_tgc_sctp *s, const char *text, size_t len, uint64_t now_ms);

/* sends an ABORT and closes */
void exteria_tgc_sctp_abort(exteria_tgc_sctp *s);

uint32_t exteria_tgc_crc32c(const uint8_t *data, size_t len);

#endif
