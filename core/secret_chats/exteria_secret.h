#ifndef EXTERIA_SECRET_H
#define EXTERIA_SECRET_H

#include "exteria_mt_msg.h"
#include "exteria_tl.h"

#define EXTERIA_SECRET_LAYER 151
#define EXTERIA_SECRET_MESSAGE_MAX (1024u * 1024u)

typedef struct exteria_secret_dh {
    uint8_t prime[256];
    uint8_t exponent[256];
    uint8_t public_value[256];
    uint32_t generator;
} exteria_secret_dh;

typedef struct exteria_secret_state {
    exteria_mt_auth_key key;
    exteria_mt_auth_key previous;
    exteria_mt_auth_key future;
    exteria_secret_dh dh;
    uint8_t visualization[36];
    int initiator;
    int32_t remote_layer;
    int32_t in_count;
    int32_t out_count;
    int32_t remote_ack;
    int32_t mt2_first_in;
    int32_t ttl;
    uint32_t key_uses;
    uint64_t key_created;
    int64_t exchange;
    int rekey_state;
    int discarded;
} exteria_secret_state;

exteria_status exteria_secret_dh_begin(exteria_secret_dh *dh, const uint8_t prime[256], uint32_t generator,
                                      const uint8_t *server_random, size_t random_len);
exteria_status exteria_secret_dh_finish(const exteria_secret_dh *dh, const uint8_t *peer_public, size_t len,
                                       exteria_mt_auth_key *out);
exteria_status exteria_secret_init(exteria_secret_state *s, int initiator, const exteria_secret_dh *dh,
                                  const exteria_mt_auth_key *key, uint64_t time_seconds);
void exteria_secret_free(exteria_secret_state *s);
/* persisting the sequence with its packet prevents reuse after a crash */
exteria_status exteria_secret_seal(const exteria_secret_state *s, const exteria_tl_value *message,
                                  exteria_writer *out, exteria_secret_state *next);
exteria_status exteria_secret_open(const exteria_secret_state *s, const uint8_t *packet, size_t len,
                                  exteria_arena *arena, exteria_tl_value **message, exteria_secret_state *next);
int exteria_secret_rekey_due(const exteria_secret_state *s, uint64_t time_seconds);
exteria_status exteria_secret_rekey_start(const exteria_secret_state *s, exteria_arena *arena,
                                         exteria_tl_value **action, exteria_secret_state *next);
exteria_status exteria_secret_action(const exteria_secret_state *s, const exteria_tl_value *action,
                                    uint64_t time_seconds, exteria_arena *arena,
                                    exteria_tl_value **response, exteria_secret_state *next);
exteria_status exteria_secret_file_fingerprint(const uint8_t key[32], const uint8_t iv[32], uint32_t *out);
uint64_t exteria_secret_expiry(int32_t ttl, uint64_t read_at, uint32_t media_duration);

#endif
