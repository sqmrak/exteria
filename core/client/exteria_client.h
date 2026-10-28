#ifndef EXTERIA_CLIENT_H
#define EXTERIA_CLIENT_H

#include "exteria_auth.h"
#include "exteria_typing.h"
#include "exteria_updates.h"

typedef struct exteria_client_events {
    void *ctx;
    exteria_status (*send)(void *ctx, int32_t dc, const uint8_t *data, size_t len);
    exteria_status (*load_session)(void *ctx, int32_t dc, exteria_mt_session_state *session);
    exteria_status (*save_session)(void *ctx, int32_t dc, const exteria_mt_session_state *session);
    void (*auth)(void *ctx, exteria_auth_state state, exteria_status status,
                 const exteria_tl_value *value, const char *error);
    void (*result)(void *ctx, uint64_t id, const exteria_mt_rpc_result *result);
    void (*changed)(void *ctx);
    void (*recover_history)(void *ctx, int64_t channel);
    /* a PhoneCall carried by an updatePhoneCall, in a push or in the answer to a call request; valid only during the callback */
    void (*phone_call)(void *ctx, const exteria_tl_value *phone_call);
    /* the signaling bytes of the other phone in an updatePhoneCallSignalingData; valid only during the callback */
    void (*phone_signaling)(void *ctx, int64_t phone_call_id, const uint8_t *data, size_t len);
    void (*error)(void *ctx, exteria_status status, const char *boundary);
    /* someone starts or stops typing, recording or sending something in a chat; live only, never kept */
    void (*typing)(void *ctx, const exteria_typing *typing);
    /* the other side read our messages of a chat up to max_id (updateReadHistoryOutbox, updateReadChannelOutbox);
       peer_kind is 1 for a user, 2 for a basic group, 3 for a channel; live only */
    void (*read_outbox)(void *ctx, int32_t peer_kind, int64_t peer_id, int32_t max_id);
    /* the draft of a chat changed, here or on another client (updateDraftMessage); read it with exteria_draft_update_read, valid only during the callback;
       live only, the account keeps the draft */
    void (*draft)(void *ctx, const exteria_tl_value *update);
    /* folder rules or their order changed on another client; one event per update container */
    void (*folders_changed)(void *ctx);
} exteria_client_events;

typedef struct exteria_client {
    exteria_mt_client mt;
    exteria_auth auth;
    exteria_updates updates;
    exteria_client_events events;
    exteria_mt_client_config config;
    exteria_store *store;
    int64_t account;
    uint64_t request_seq;
    uint64_t auth_wire_id;
    uint64_t auth_local_id;
    uint64_t sync_id;
    int64_t sync_channel;
    uint32_t sync_method;
    uint64_t outbox_id;
    int64_t outbox_random;
    int sync_suspended;
    int sync_again;
    /* set while the changed event of a quiet container runs (see exteria_updates_quiet); the event handler may read it */
    int change_quiet;
    int change_rpc_cache;
    int authorized;
    int closing;
    exteria_status session_error;
} exteria_client;

exteria_status exteria_client_init(exteria_client *c, const exteria_mt_client_config *config,
                                  const char *api_hash, const exteria_client_events *events);
void exteria_client_free(exteria_client *c);
/* client callbacks can still access the store during teardown */
exteria_status exteria_client_attach_store(exteria_client *c, exteria_store *store, int64_t account_id);
exteria_status exteria_client_connect(exteria_client *c);
void exteria_client_disconnected(exteria_client *c);
exteria_status exteria_client_migrate(exteria_client *c, int32_t dc);
exteria_status exteria_client_feed(exteria_client *c, const uint8_t *data, size_t len);
exteria_status exteria_client_tick(exteria_client *c, uint32_t *next_ms);
exteria_status exteria_client_request(exteria_client *c, const exteria_tl_value *request,
                                     uint32_t timeout_ms, uint64_t *id);
exteria_status exteria_client_send(exteria_client *c, exteria_peer peer, const exteria_tl_value *request);
void exteria_client_resume_sync(exteria_client *c);

#endif
