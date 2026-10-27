#ifndef EXTERIA_TGC_STUN_H
#define EXTERIA_TGC_STUN_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* STUN binding messages (RFC 5389 and 8445) as ICE connectivity checks use them */

#define EXTERIA_STUN_HEADER_LEN 20
#define EXTERIA_STUN_TXID_LEN 12
#define EXTERIA_STUN_MAX_MESSAGE 1200
#define EXTERIA_STUN_MAX_USERNAME 128

#define EXTERIA_STUN_BINDING_REQUEST 0x0001
#define EXTERIA_STUN_BINDING_SUCCESS 0x0101
#define EXTERIA_STUN_BINDING_ERROR 0x0111
#define EXTERIA_STUN_BINDING_INDICATION 0x0011

#define EXTERIA_STUN_ERROR_ROLE_CONFLICT 487
#define EXTERIA_STUN_ERROR_UNAUTHORIZED 401
#define EXTERIA_STUN_ERROR_BAD_REQUEST 400

typedef struct exteria_stun {
    uint16_t type;
    uint8_t txid[EXTERIA_STUN_TXID_LEN];
    uint8_t has_username;
    char username[EXTERIA_STUN_MAX_USERNAME + 1];
    uint8_t has_priority;
    uint32_t priority;
    uint8_t use_candidate;
    uint8_t has_controlling;
    uint64_t controlling;
    uint8_t has_controlled;
    uint64_t controlled;
    uint8_t has_mapped;
    uint8_t mapped_ipv6;
    uint16_t mapped_port;
    uint8_t mapped_address[16];
    uint8_t has_error;
    uint16_t error_code;
    /* where in the message the integrity and fingerprint attributes start (zero when absent), for the checks below */
    uint16_t integrity_offset;
    uint16_t fingerprint_offset;
} exteria_stun;

/* true when the datagram can be a STUN message: at least a header, the two top bits clear, the magic cookie in
   place */
int exteria_stun_looks_like(const uint8_t *data, size_t len);

/* reads one message */
exteria_status exteria_stun_parse(const uint8_t *data, size_t len, exteria_stun *out);

/* verifies MESSAGE-INTEGRITY with key (the ICE password) and FINGERPRINT */
exteria_status exteria_stun_check_integrity(const uint8_t *data, size_t len, const exteria_stun *m, const uint8_t *key, size_t key_len);
exteria_status exteria_stun_check_fingerprint(const uint8_t *data, size_t len, const exteria_stun *m);

/* what to write: the fields set in the struct, in the order a check carries them */
exteria_status exteria_stun_write(const exteria_stun *m, const uint8_t *key, size_t key_len, int with_fingerprint, uint8_t *out, size_t capacity,
                                  size_t *len);

uint32_t exteria_stun_crc32(const uint8_t *data, size_t len);

#endif
