#ifndef EXTERIA_WG_H
#define EXTERIA_WG_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the initiating side of WireGuard (Noise IKpsk2 over curve25519, ChaCha20-Poly1305 and BLAKE2s) with the framing
   options of AmneziaWG */

#define EXTERIA_WG_KEY_LEN 32
#define EXTERIA_WG_INITIATION_LEN 148
#define EXTERIA_WG_RESPONSE_LEN 92
#define EXTERIA_WG_HEADER_LEN 16
#define EXTERIA_WG_TAG_LEN 16
#define EXTERIA_WG_REPLAY_BITS 256
/* the largest IP packet the tunnel carries */
#define EXTERIA_WG_MAX_PLAIN 1500
#define EXTERIA_WG_MAX_DATAGRAM (EXTERIA_WG_HEADER_LEN + EXTERIA_WG_MAX_PLAIN + 16 + EXTERIA_WG_TAG_LEN)
#define EXTERIA_WG_MAX_JUNK 32
#define EXTERIA_WG_MAX_JUNK_LEN 1400
#define EXTERIA_WG_MAX_PREFIX 1024
#define EXTERIA_WG_SIGNATURES 5
/* the timers of the protocol (WireGuard whitepaper, section 6.1) */
#define EXTERIA_WG_REKEY_AFTER_MS 120000u
#define EXTERIA_WG_REJECT_AFTER_MS 180000u
#define EXTERIA_WG_KEEPALIVE_MS 25000u

typedef struct exteria_wg_config {
    uint8_t private_key[EXTERIA_WG_KEY_LEN];
    uint8_t peer_public[EXTERIA_WG_KEY_LEN];
    uint8_t preshared[EXTERIA_WG_KEY_LEN];      /* all zeros when the peer has none */
    uint8_t reserved[3];
    int has_reserved;
    uint16_t junk_count, junk_min, junk_max;
    uint16_t s1, s2;                            /* random bytes in front of the initiation, and in front of the response the peer sends */
    uint32_t h1, h2, h4;                        /* type field of the initiation, the response and the data message; 0 keeps 1, 2 and 4 */
    /* texts such as "<b 0x4142><r 8><t>" that become datagrams of their own; NULL or empty ones are skipped; they
       must outlive the handshake call */
    const char *signature[EXTERIA_WG_SIGNATURES];
} exteria_wg_config;

/* the sizes and counts must be inside their limits and the keys must not be zero */
exteria_status exteria_wg_config_check(const exteria_wg_config *config);

/* a signature text turned into bytes: <b 0x..> literal bytes, <r N> N random bytes (up to 1024), <t> the unix time
   in seconds as 4 bytes little endian, <c> a counter field (4 bytes, value 1) */
exteria_status exteria_wg_signature_render(const char *spec, uint32_t unix_seconds, uint8_t *out, size_t cap, size_t *len);

typedef struct exteria_wg_session {
    int active;
    uint8_t send_key[EXTERIA_WG_KEY_LEN];
    uint8_t recv_key[EXTERIA_WG_KEY_LEN];
    uint32_t local_index;
    uint32_t remote_index;
    uint32_t data_type;
    uint8_t reserved[3];
    int has_reserved;
    uint64_t send_counter;
    int received_any;
    uint64_t recv_max;
    uint64_t recv_window[EXTERIA_WG_REPLAY_BITS / 64];
    uint64_t born_ms;                           /* the monotonic time the keys were made */
} exteria_wg_session;

typedef struct exteria_wg_handshake {
    int pending;
    exteria_wg_config config;
    uint8_t static_public[EXTERIA_WG_KEY_LEN];
    uint8_t mac1_key[EXTERIA_WG_KEY_LEN];
    uint8_t ephemeral_private[EXTERIA_WG_KEY_LEN];
    uint8_t chain[EXTERIA_WG_KEY_LEN];
    uint8_t hash[EXTERIA_WG_KEY_LEN];
    uint32_t local_index;
} exteria_wg_handshake;

/* one datagram to send; called in order: the signatures, then the junk, then the initiation */
typedef void (*exteria_wg_emit)(void *context, const uint8_t *data, size_t len);

/* builds the initiation and hands every datagram to emit. unix_seconds and nanos stamp the message (TAI64N) */
exteria_status exteria_wg_handshake_begin(exteria_wg_handshake *hs, const exteria_wg_config *config, uint64_t unix_seconds, uint32_t nanos,
                                          exteria_wg_emit emit, void *context);

/* a datagram that may be the answer */
exteria_status exteria_wg_handshake_finish(exteria_wg_handshake *hs, const uint8_t *packet, size_t len, uint64_t now_ms, exteria_wg_session *session);

/* wipes keys and state */
void exteria_wg_handshake_clear(exteria_wg_handshake *hs);
void exteria_wg_session_clear(exteria_wg_session *session);

/* one IP packet (or none, for a keepalive) into a data datagram; the plain text is padded with zeros to a multiple
   of 16 bytes as the protocol does, so the IP total length field has to be what tells where the packet ends. out
   needs EXTERIA_WG_MAX_DATAGRAM bytes */
exteria_status exteria_wg_seal(exteria_wg_session *session, const uint8_t *plain, size_t len, uint8_t *out, size_t cap, size_t *out_len);

/* a datagram of the peer; EXTERIA_E_MALFORMED when it is not a data message for this session, EXTERIA_E_RETRY for
   a counter that was seen or is too old */
exteria_status exteria_wg_open(exteria_wg_session *session, const uint8_t *packet, size_t len, uint8_t *plain, size_t cap, size_t *plain_len);

/* the age of the keys in milliseconds on the monotonic clock the owner uses */
uint64_t exteria_wg_session_age_ms(const exteria_wg_session *session, uint64_t now_ms);

#endif
