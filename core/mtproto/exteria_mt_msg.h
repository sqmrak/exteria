#ifndef EXTERIA_MT_MSG_H
#define EXTERIA_MT_MSG_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_bytes.h"
#include "exteria_status.h"

#define EXTERIA_MT_AUTH_KEY_LEN 256

typedef struct exteria_mt_auth_key {
    uint8_t key[EXTERIA_MT_AUTH_KEY_LEN];
    uint64_t id;
} exteria_mt_auth_key;

typedef struct exteria_mt_header {
    uint64_t salt;
    uint64_t session_id;
    uint64_t msg_id;
    int32_t seq_no;
} exteria_mt_header;

/* ids count up from the last one issued, a clock step back must not repeat or lower an id */
uint64_t exteria_mt_next_msg_id(uint64_t unix_ms, uint64_t *last_msg_id);

exteria_status exteria_mt_auth_key_set(exteria_mt_auth_key *k, const uint8_t key[EXTERIA_MT_AUTH_KEY_LEN]);

exteria_status exteria_mt_key_schedule(const exteria_mt_auth_key *k, unsigned x,
                                       const uint8_t msg_key[16], uint8_t aes_key[32], uint8_t aes_iv[32]);
exteria_status exteria_mt_message_key(const exteria_mt_auth_key *k, unsigned x, const uint8_t *plain,
                                      size_t len, uint8_t msg_key[16]);
exteria_status exteria_mt_plain_wrap(uint64_t msg_id, const uint8_t *body, size_t len, exteria_writer *out);
exteria_status exteria_mt_plain_unwrap(const uint8_t *packet, size_t len, int allow_padding,
                                       uint64_t *msg_id, const uint8_t **body, size_t *body_len);

/* separate key slices prevent replay in the opposite direction */
exteria_status exteria_mt_encrypt(const exteria_mt_auth_key *k, int from_client, const exteria_mt_header *h,
                                  const uint8_t *body, size_t len, exteria_writer *out);
/* body aliases plain, which must stay alive until the caller finishes parsing */
exteria_status exteria_mt_decrypt(const exteria_mt_auth_key *k, int from_client, int allow_padding,
                                  const uint8_t *packet, size_t len, exteria_writer *plain,
                                  exteria_mt_header *h, const uint8_t **body, size_t *body_len);

#endif
