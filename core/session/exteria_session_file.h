#ifndef EXTERIA_SESSION_FILE_H
#define EXTERIA_SESSION_FILE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_mt_client.h"

#define EXTERIA_DC_MAX 5
#define EXTERIA_SESSION_FILE_LEN 280
#define EXTERIA_ACCOUNT_FILE_LEN 16

/* production data centers only; null for an id outside 1..EXTERIA_DC_MAX */
const char *exteria_dc_host(int32_t dc_id);
uint16_t exteria_dc_port(void);

/* one file per data center: magic, dc id, auth key, salt, clock offset */
exteria_status exteria_session_pack(int32_t dc_id, const exteria_mt_session_state *session,
                                    uint8_t *out, size_t cap, size_t *len);
/* out is cleared on every failure, an auth key must not survive a rejected file */
exteria_status exteria_session_unpack(const uint8_t *data, size_t len, int32_t expected_dc,
                                      exteria_mt_session_state *out);

/* the file on disk: magic, nonce, the packed session sealed with chacha20-poly1305, tag. the magic and the data
   center are the associated data, so a file moved to another data center slot fails the tag */
#define EXTERIA_SESSION_KEY_LEN 32
#define EXTERIA_SESSION_SEALED_LEN (4 + 12 + EXTERIA_SESSION_FILE_LEN + 16)

exteria_status exteria_session_seal(const uint8_t key[EXTERIA_SESSION_KEY_LEN], int32_t dc_id,
                                    const exteria_mt_session_state *session, uint8_t *out, size_t cap, size_t *len);
/* a sealed file opens with the key, EXTERIA_E_SECURITY when the tag fails. a plain file written before sealing
   existed (EXS1) is still read and *plain is set to 1, so the caller seals it again; sealed files set it to 0.
   out is cleared on every failure */
exteria_status exteria_session_open(const uint8_t key[EXTERIA_SESSION_KEY_LEN], const uint8_t *data, size_t len,
                                    int32_t expected_dc, exteria_mt_session_state *out, int *plain);

/* the signed in account and the data center its session lives on */
exteria_status exteria_account_pack(int32_t dc_id, int64_t account_id, uint8_t *out, size_t cap, size_t *len);
exteria_status exteria_account_unpack(const uint8_t *data, size_t len, int32_t *dc_id, int64_t *account_id);

#endif
