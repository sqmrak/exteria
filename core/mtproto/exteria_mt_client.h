#ifndef EXTERIA_MT_CLIENT_H
#define EXTERIA_MT_CLIENT_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_arena.h"
#include "exteria_bytes.h"
#include "exteria_clock.h"
#include "exteria_mt_handshake.h"
#include "exteria_mt_msg.h"
#include "exteria_mt_transport.h"
#include "exteria_status.h"
#include "exteria_tl.h"

#define EXTERIA_MT_ACK_MAX 256
#define EXTERIA_MT_SEEN_MAX 1024
#define EXTERIA_MT_CONTAINER_RING 16
#define EXTERIA_MT_CONTAINER_INNER 64

typedef enum exteria_mt_client_state {
    EXTERIA_MT_CLIENT_DISCONNECTED = 0,
    EXTERIA_MT_CLIENT_HANDSHAKE,
    EXTERIA_MT_CLIENT_READY,
    EXTERIA_MT_CLIENT_DEAD
} exteria_mt_client_state;

typedef struct exteria_mt_session_state {
    uint8_t auth_key[EXTERIA_MT_AUTH_KEY_LEN];
    uint64_t server_salt;
    int64_t time_offset_ms;
} exteria_mt_session_state;

typedef struct exteria_mt_rpc_result {
    exteria_status status;
    const exteria_tl_value *value;
    int32_t error_code;
    const char *error_text;
    uint64_t msg_id;
} exteria_mt_rpc_result;

typedef struct exteria_mt_client_events {
    void *ctx;
    void (*send)(void *ctx, const uint8_t *data, size_t len);
    void (*rpc_result)(void *ctx, uint64_t request_id, const exteria_mt_rpc_result *result);
    /* the decode arena is freed after delivery, retained updates need a copy */
    void (*update)(void *ctx, const exteria_tl_value *updates);
    /* an undecodable update leaves a gap that needs a difference request */
    void (*update_lost)(void *ctx, exteria_status reason);
    /* the server started a fresh session for this key, events sent before it may be missing */
    void (*new_session)(void *ctx);
    void (*state)(void *ctx, exteria_mt_client_state state, exteria_status reason);
    /* reconnect must restore the same key, salt and clock offset */
    void (*session_changed)(void *ctx, const exteria_mt_session_state *session);
    exteria_status (*send_checked)(void *ctx, const uint8_t *data, size_t len);
} exteria_mt_client_events;

typedef struct exteria_mt_client_config {
    int dc_id;
    int is_test;
    exteria_mt_transport_kind transport;
    exteria_mt_obfuscation obfuscation;
    const exteria_clock *clock;
    const exteria_mt_rsa_key *keys;
    size_t key_count;
    const exteria_mt_session_state *restore;
    int32_t api_id;
    const char *device_model;
    const char *system_version;
    const char *app_version;
    const char *system_lang_code;
    const char *lang_pack;
    const char *lang_code;
    uint32_t max_pending;
    uint32_t result_arena_limit;
    uint32_t ping_interval_ms;
    uint32_t pong_timeout_ms;
} exteria_mt_client_config;

typedef struct exteria_mt_pending exteria_mt_pending;

typedef struct exteria_mt_container_rec {
    uint64_t id;
    uint32_t count;
    uint64_t inner[EXTERIA_MT_CONTAINER_INNER];
} exteria_mt_container_rec;

typedef struct exteria_mt_salt {
    int32_t since;
    int32_t until;
    uint64_t value;
} exteria_mt_salt;

typedef struct exteria_mt_client {
    exteria_mt_client_config config;
    exteria_mt_client_events events;
    exteria_mt_client_state state;
    exteria_mt_transport transport;
    exteria_mt_handshake handshake;
    exteria_mt_auth_key key;
    int has_key;
    uint64_t salt;
    exteria_mt_salt salts[64];
    uint32_t salt_count;
    int64_t time_offset_ms;
    uint64_t session_id;
    uint64_t last_msg_id;
    uint32_t seq_count;
    exteria_mt_pending *pending;
    uint32_t pending_count;
    uint32_t pending_cap;
    uint64_t acks[EXTERIA_MT_ACK_MAX];
    uint32_t ack_count;
    uint64_t seen[EXTERIA_MT_SEEN_MAX];
    uint32_t seen_pos;
    exteria_mt_container_rec containers[EXTERIA_MT_CONTAINER_RING];
    uint32_t container_pos;
    int init_confirmed;
    uint8_t *init_prefix;
    size_t init_prefix_len;
    uint64_t last_rx_ms;
    uint64_t ping_id;
    uint64_t ping_sent_ms;
    int awaiting_pong;
    int32_t transport_error;
    /* the constructor of the message being handled when the link last failed, for the log */
    uint32_t last_ctor;
    /* why the last frame from the server was refused, and a number that goes with it (the gap to the server's clock in
       milliseconds for a message time, otherwise zero), for the log */
    const char *security_note;
    int64_t security_value;
    /* set once a frame of this link has been accepted, which tells a link that works from one that connects and fails */
    int heard;
    int in_feed;
    int flush_wanted;
    unsigned operation_depth;
    int closing;
} exteria_mt_client;

exteria_status exteria_mt_client_init(exteria_mt_client *c, const exteria_mt_client_config *config,
                                      const exteria_mt_client_events *events);
/* teardown must resolve pending requests instead of leaving their owners waiting */
void exteria_mt_client_free(exteria_mt_client *c);

exteria_status exteria_mt_client_connect(exteria_mt_client *c);
/* a socket failure must not discard requests needed after reconnect */
void exteria_mt_client_disconnected(exteria_mt_client *c);
exteria_status exteria_mt_client_feed(exteria_mt_client *c, const uint8_t *data, size_t len);

exteria_status exteria_mt_client_submit(exteria_mt_client *c, uint64_t request_id, const exteria_tl_value *request,
                                        uint32_t timeout_ms);
exteria_status exteria_mt_client_cancel(exteria_mt_client *c, uint64_t request_id);

uint32_t exteria_mt_client_tick(exteria_mt_client *c);

int exteria_mt_client_get_session(const exteria_mt_client *c, exteria_mt_session_state *out);
int32_t exteria_mt_client_transport_error(const exteria_mt_client *c);
uint32_t exteria_mt_client_last_ctor(const exteria_mt_client *c);
/* the reason the last frame was refused as unsafe, null when none was, and its number */
const char *exteria_mt_client_security_note(const exteria_mt_client *c, int64_t *value);
/* whether this link has accepted a frame from the server since it connected */
int exteria_mt_client_heard(const exteria_mt_client *c);
#define EXTERIA_MT_PING_INTERVAL_DEFAULT 30000u
/* how long a quiet link waits before it pings, kept between 10 and 300 seconds */
void exteria_mt_client_set_ping_interval(exteria_mt_client *c, uint32_t interval_ms);
uint32_t exteria_mt_client_ping_interval(const exteria_mt_client *c);
uint32_t exteria_mt_client_pending_count(const exteria_mt_client *c);

void exteria_mt_rpc_error_split(const char *text, char *name, size_t name_cap, int32_t *number);

#endif
