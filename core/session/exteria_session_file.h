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

/* the signed in account and the data center its session lives on */
exteria_status exteria_account_pack(int32_t dc_id, int64_t account_id, uint8_t *out, size_t cap, size_t *len);
exteria_status exteria_account_unpack(const uint8_t *data, size_t len, int32_t *dc_id, int64_t *account_id);

#endif
