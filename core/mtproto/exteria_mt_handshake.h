#ifndef EXTERIA_MT_HANDSHAKE_H
#define EXTERIA_MT_HANDSHAKE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_bytes.h"
#include "exteria_clock.h"
#include "exteria_mt_keys.h"
#include "exteria_mt_msg.h"
#include "exteria_status.h"

typedef enum exteria_mt_hs_state {
    EXTERIA_MT_HS_IDLE = 0,
    EXTERIA_MT_HS_WAIT_RES_PQ,
    EXTERIA_MT_HS_WAIT_DH_PARAMS,
    EXTERIA_MT_HS_WAIT_DH_ANSWER,
    EXTERIA_MT_HS_DONE,
    EXTERIA_MT_HS_FAILED
} exteria_mt_hs_state;

typedef struct exteria_mt_hs_config {
    int dc_id;
    int is_test;
    const exteria_mt_rsa_key *keys;
    size_t key_count;
    const exteria_clock *clock;
    unsigned max_attempts;
} exteria_mt_hs_config;

typedef struct exteria_mt_hs_result {
    exteria_mt_auth_key key;
    uint64_t server_salt;
    int64_t time_offset_ms;
} exteria_mt_hs_result;

typedef struct exteria_mt_handshake {
    exteria_mt_hs_config config;
    exteria_mt_hs_state state;
    unsigned attempts;
    uint64_t last_msg_id;
    uint8_t nonce[16];
    uint8_t server_nonce[16];
    uint8_t new_nonce[32];
    uint8_t tmp_key[32];
    uint8_t tmp_iv[32];
    uint8_t auth_key[256];
    int64_t server_time;
    uint64_t salt;
    int64_t time_offset_ms;
    uint64_t key_fingerprint;
    exteria_mt_hs_result result;
} exteria_mt_handshake;

void exteria_mt_hs_init(exteria_mt_handshake *hs, const exteria_mt_hs_config *config);
void exteria_mt_hs_wipe(exteria_mt_handshake *hs);

exteria_status exteria_mt_hs_start(exteria_mt_handshake *hs, exteria_writer *out);
exteria_status exteria_mt_hs_receive(exteria_mt_handshake *hs, const uint8_t *packet, size_t len, int allow_padding,
                                     exteria_writer *out);
const exteria_mt_hs_result *exteria_mt_hs_result_get(const exteria_mt_handshake *hs);

exteria_status exteria_mt_factor_pq(uint64_t pq, uint32_t *p, uint32_t *q);
exteria_status exteria_mt_check_dh_prime(const uint8_t *prime, size_t len, uint32_t g);
exteria_status exteria_mt_check_dh_value(const uint8_t *prime, size_t prime_len, const uint8_t *value, size_t value_len);
exteria_status exteria_mt_rsa_pad_encrypt(const exteria_mt_rsa_key *key, const uint8_t *data, size_t len,
                                          uint8_t out[256]);

#endif
