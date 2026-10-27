#ifndef EXTERIA_FAKE_MT_SERVER_H
#define EXTERIA_FAKE_MT_SERVER_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_arena.h"
#include "exteria_bytes.h"
#include "exteria_mt_keys.h"
#include "exteria_mt_msg.h"
#include "exteria_tl.h"

typedef enum fake_hs_mode {
    FAKE_HS_NORMAL = 0,
    FAKE_HS_RETRY_ONCE,
    FAKE_HS_ALWAYS_RETRY,
    FAKE_HS_FAIL,
    FAKE_HS_BAD_SERVER_NONCE,
    FAKE_HS_BAD_NEW_NONCE_HASH,
    FAKE_HS_COMPOSITE_PRIME,
    FAKE_HS_SMALL_GA,
    FAKE_HS_PARAMS_FAIL,
    FAKE_HS_PRIME_PQ,
    FAKE_HS_UNKNOWN_KEY
} fake_hs_mode;

typedef struct fake_mt_server {
    void *rsa_n;
    void *rsa_d;
    uint8_t n_bytes[256];
    exteria_mt_rsa_key key;
    fake_hs_mode mode;
    int retries_left;
    int dc_expected;
    int32_t server_time;
    uint8_t nonce[16];
    uint8_t server_nonce[16];
    uint8_t new_nonce[32];
    uint8_t tmp_key[32];
    uint8_t tmp_iv[32];
    uint8_t dh_a[256];
    uint8_t prime[256];
    uint8_t g_a[256];
    size_t g_a_len;
    uint64_t pq;
    int step;
    uint64_t next_msg_id;
    exteria_mt_auth_key auth_key;
    int have_key;
    uint64_t salt;
    uint64_t session_id;
    uint64_t last_client_msg_id;
    uint32_t server_seq;
} fake_mt_server;

int fake_mt_server_init(fake_mt_server *s);
void fake_mt_server_free(fake_mt_server *s);

int fake_mt_server_handshake(fake_mt_server *s, const uint8_t *packet, size_t len, exteria_writer *out);

int fake_mt_server_decrypt(fake_mt_server *s, const uint8_t *packet, size_t len, exteria_writer *plain,
                           exteria_mt_header *h, const uint8_t **body, size_t *body_len);
int fake_mt_server_encrypt(fake_mt_server *s, uint64_t msg_id, int content_related, const uint8_t *body, size_t len,
                           exteria_writer *out);
uint64_t fake_mt_server_msg_id(fake_mt_server *s, int is_response);

#endif
