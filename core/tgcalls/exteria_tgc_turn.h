#ifndef EXTERIA_TGC_TURN_H
#define EXTERIA_TGC_TURN_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the part of a TURN client (RFC 5766, over UDP, with the long term credentials of RFC 5389) that a call needs */

#define EXTERIA_TGC_TURN_USERNAME_MAX 128
#define EXTERIA_TGC_TURN_PASSWORD_MAX 128
#define EXTERIA_TGC_TURN_REALM_MAX 128
#define EXTERIA_TGC_TURN_NONCE_MAX 128
#define EXTERIA_TGC_TURN_MAX_PERMISSIONS 24
#define EXTERIA_TGC_TURN_MAX_REQUESTS 8
#define EXTERIA_TGC_TURN_MAX_MESSAGE 600
/* the largest datagram wrapped in a Send indication: a Send indication adds a 20 byte header and two attributes (12 and 4 bytes of their own) to it */
#define EXTERIA_TGC_TURN_MAX_PAYLOAD 1200
#define EXTERIA_TGC_TURN_WRAP_OVERHEAD 36

typedef enum exteria_tgc_turn_state {
    EXTERIA_TGC_TURN_IDLE = 0,
    EXTERIA_TGC_TURN_ALLOCATING,
    EXTERIA_TGC_TURN_READY,
    EXTERIA_TGC_TURN_FAILED
} exteria_tgc_turn_state;

typedef struct exteria_tgc_turn_events {
    void *context;
    /* a datagram for the TURN server */
    void (*send)(void *context, const uint8_t *data, size_t len);
    /* optional: one line of what the client does, for the log of a call; never holds the password or the key */
    void (*trace)(void *context, const char *line);
} exteria_tgc_turn_events;

typedef struct exteria_tgc_turn_request {
    uint8_t used;
    uint8_t kind;               /* 1 allocate, 2 refresh, 3 permission */
    uint8_t authenticated;
    uint8_t tries;
    uint8_t permission;         /* the slot a permission request is for */
    uint8_t txid[12];
    uint16_t len;
    uint8_t message[EXTERIA_TGC_TURN_MAX_MESSAGE];
    uint64_t last_tx_ms;
} exteria_tgc_turn_request;

typedef struct exteria_tgc_turn_permission {
    uint8_t state;              /* 0 wanted, 1 asked, 2 granted, 3 refused */
    uint8_t renewing;
    uint32_t ip;
    uint64_t granted_ms;
} exteria_tgc_turn_permission;

typedef struct exteria_tgc_turn {
    exteria_tgc_turn_events events;
    uint32_t server_ip;
    uint16_t server_port;
    char username[EXTERIA_TGC_TURN_USERNAME_MAX];
    char password[EXTERIA_TGC_TURN_PASSWORD_MAX];
    exteria_tgc_turn_state state;
    char realm[EXTERIA_TGC_TURN_REALM_MAX];
    uint8_t nonce[EXTERIA_TGC_TURN_NONCE_MAX];
    size_t nonce_len;
    uint8_t key[16];
    uint8_t has_key;
    uint32_t relay_ip;
    uint16_t relay_port;
    uint32_t mapped_ip;
    uint16_t mapped_port;
    uint32_t lifetime_s;
    uint64_t refresh_due_ms;
    uint8_t started;
    unsigned data_in, data_out;
    exteria_tgc_turn_request requests[EXTERIA_TGC_TURN_MAX_REQUESTS];
    exteria_tgc_turn_permission permissions[EXTERIA_TGC_TURN_MAX_PERMISSIONS];
} exteria_tgc_turn;

typedef enum exteria_tgc_turn_kind {
    EXTERIA_TGC_TURN_INPUT_NONE = 0,    /* the packet was for the client itself, or was dropped */
    EXTERIA_TGC_TURN_INPUT_READY,       /* the allocation just succeeded: the relay address is known */
    EXTERIA_TGC_TURN_INPUT_DATA         /* a datagram of the other phone: peer_ip, peer_port and data */
} exteria_tgc_turn_kind;

typedef struct exteria_tgc_turn_output {
    exteria_tgc_turn_kind kind;
    uint32_t peer_ip;
    uint16_t peer_port;
    const uint8_t *data;
    size_t len;
} exteria_tgc_turn_output;

/* EXTERIA_E_ARG for a missing address, port or name, or names too long for the fields */
exteria_status exteria_tgc_turn_init(exteria_tgc_turn *t, uint32_t server_ip, uint16_t server_port, const char *username, const char *password,
                                     const exteria_tgc_turn_events *events);

/* the allocation, its refresh, the permissions and the retransmissions of all of those; call it every 50 ms or so */
void exteria_tgc_turn_tick(exteria_tgc_turn *t, uint64_t now_ms);

/* a datagram from the server. out is always initialised */
exteria_status exteria_tgc_turn_input(exteria_tgc_turn *t, const uint8_t *packet, size_t len, uint64_t now_ms, exteria_tgc_turn_output *out);

int exteria_tgc_turn_ready(const exteria_tgc_turn *t);
/* the relayed address and the address the server saw this client at; false before the allocation succeeded */
int exteria_tgc_turn_relayed(const exteria_tgc_turn *t, uint32_t *relay_ip, uint16_t *relay_port, uint32_t *mapped_ip, uint16_t *mapped_port);

/* wants a permission for ip */
int exteria_tgc_turn_permit(exteria_tgc_turn *t, uint32_t ip);

/* a Send indication for payload to ip:port; EXTERIA_E_STATE when the allocation is not ready, EXTERIA_E_LIMIT for
   a payload over EXTERIA_TGC_TURN_MAX_PAYLOAD or a buffer that is too small */
exteria_status exteria_tgc_turn_wrap(exteria_tgc_turn *t, uint32_t ip, uint16_t port, const uint8_t *payload, size_t len, uint8_t *out, size_t capacity,
                                     size_t *out_len);

#endif
