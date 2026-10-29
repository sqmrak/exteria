#include "exteria_client.h"

#include <string.h>

#include "exteria_tl_ids.h"

static void report(exteria_client *c, exteria_status status, const char *boundary) {
    if (status != EXTERIA_OK && c->events.error) c->events.error(c->events.ctx, status, boundary);
}

static uint64_t request_id(exteria_client *c) {
    if (!++c->request_seq) ++c->request_seq;
    return c->request_seq;
}

static exteria_status send_bytes(void *ctx, const uint8_t *data, size_t len) {
    exteria_client *c = ctx;
    if (c->closing || c->session_error != EXTERIA_OK) return EXTERIA_E_STATE;
    return c->events.send(c->events.ctx, c->config.dc_id, data, len);
}

static void save_session(void *ctx, const exteria_mt_session_state *session) {
    exteria_client *c = ctx;
    c->session_error = c->events.save_session(c->events.ctx, c->config.dc_id, session);
    report(c, c->session_error, "session storage");
}

static exteria_status auth_submit(void *ctx, uint64_t id, const exteria_tl_value *request) {
    exteria_client *c = ctx;
    if (c->closing) return EXTERIA_E_STATE;
    c->auth_local_id = id;
    c->auth_wire_id = request_id(c);
    exteria_status status = exteria_mt_client_submit(&c->mt, c->auth_wire_id, request, 60000);
    if (status != EXTERIA_OK) {
        exteria_status cancelled = exteria_mt_client_cancel(&c->mt, c->auth_wire_id);
        if (cancelled != EXTERIA_E_NOTFOUND) report(c, cancelled, "auth submit cleanup");
        c->auth_wire_id = 0;
    }
    return status;
}

static void auth_cancel(void *ctx, uint64_t id) {
    exteria_client *c = ctx;
    if (id == c->auth_local_id && c->auth_wire_id) {
        exteria_status status = exteria_mt_client_cancel(&c->mt, c->auth_wire_id);
        if (status != EXTERIA_E_NOTFOUND) report(c, status, "auth cancel");
        c->auth_wire_id = 0;
    }
}

static void auth_changed(void *ctx, exteria_auth_state state, exteria_status status,
                          const exteria_tl_value *value, const char *error) {
    exteria_client *c = ctx;
    if (state == EXTERIA_AUTH_AUTHORIZED) {
        int64_t account;
        if (exteria_tl_get_i64(exteria_tl_get(value, "user"), "id", &account) != EXTERIA_OK || account <= 0 ||
            (c->store && c->account != account)) { report(c, EXTERIA_E_SECURITY, "account identity"); return; }
        c->account = account;
        c->authorized = 1;
    }
    if (c->events.auth && !c->closing) c->events.auth(c->events.ctx, state, status, value, error);
}

static int is_updates(const exteria_tl_value *v) {
    const char *type;
    if (!v || v->kind != EXTERIA_TL_V_OBJ) return 0;
    type = exteria_tl_result_type_name(v->u.obj.ctor);
    return type && !strcmp(type, "Updates");
}

static void deliver_signaling(exteria_client *c, const exteria_tl_value *update) {
    int64_t id = 0;
    const uint8_t *data = NULL;
    size_t len = 0;
    if (!c->events.phone_signaling) return;
    if (exteria_tl_get_i64(update, "phone_call_id", &id) != EXTERIA_OK || exteria_tl_get_bytes(update, "data", &data, &len) != EXTERIA_OK || !data || len == 0) return;
    c->events.phone_signaling(c->events.ctx, id, data, len);
}

static int group_call_update(const exteria_tl_value *item) {
    return exteria_tl_is(item, EXTERIA_TL_ID_updateGroupCall) || exteria_tl_is(item, EXTERIA_TL_ID_updateGroupCallParticipants) ||
           exteria_tl_is(item, EXTERIA_TL_ID_updateGroupCallConnection);
}

static void deliver_group_call(exteria_client *c, const exteria_tl_value *item, const exteria_tl_value *container) {
    if (c->events.group_call && group_call_update(item)) c->events.group_call(c->events.ctx, item, container);
}

static void deliver_typing(exteria_client *c, const exteria_tl_value *item) {
    exteria_typing typing;
    if (c->events.typing && exteria_typing_read(item, &typing)) c->events.typing(c->events.ctx, &typing);
}

static void deliver_read_outbox(exteria_client *c, const exteria_tl_value *item) {
    exteria_peer peer;
    int32_t max_id = 0;
    int64_t channel = 0;
    if (!c->events.read_outbox) return;
    if (exteria_tl_is(item, EXTERIA_TL_ID_updateReadHistoryOutbox)) {
        if (exteria_peer_from_tl(exteria_tl_get(item, "peer"), &peer) != EXTERIA_OK || exteria_tl_get_i32(item, "max_id", &max_id) != EXTERIA_OK) return;
    } else if (exteria_tl_is(item, EXTERIA_TL_ID_updateReadChannelOutbox)) {
        if (exteria_tl_get_i64(item, "channel_id", &channel) != EXTERIA_OK || exteria_tl_get_i32(item, "max_id", &max_id) != EXTERIA_OK) return;
        peer.kind = 3;
        peer.id = channel;
    } else return;
    if (max_id > 0 && peer.id > 0) c->events.read_outbox(c->events.ctx, peer.kind, peer.id, max_id);
}

static void deliver_draft(exteria_client *c, const exteria_tl_value *item) {
    if (c->events.draft && exteria_tl_is(item, EXTERIA_TL_ID_updateDraftMessage)) c->events.draft(c->events.ctx, item);
}

static int folder_update(const exteria_tl_value *value) {
    return exteria_tl_is(value, EXTERIA_TL_ID_updateDialogFilter) || exteria_tl_is(value, EXTERIA_TL_ID_updateDialogFilterOrder) ||
           exteria_tl_is(value, EXTERIA_TL_ID_updateDialogFilters);
}

/* calls, typing and folder changes have no stored message row */
static void dispatch_live_updates(exteria_client *c, const exteria_tl_value *v) {
    const exteria_tl_value *one = exteria_tl_get(v, "update"), *vec = exteria_tl_get(v, "updates");
    uint32_t i;
    int folders = folder_update(one);
    if (c->closing) return;
    if (exteria_tl_is(one, EXTERIA_TL_ID_updatePhoneCall) && c->events.phone_call) c->events.phone_call(c->events.ctx, exteria_tl_get(one, "phone_call"));
    if (exteria_tl_is(one, EXTERIA_TL_ID_updatePhoneCallSignalingData)) deliver_signaling(c, one);
    deliver_typing(c, one);
    deliver_read_outbox(c, one);
    deliver_draft(c, one);
    deliver_group_call(c, one, v);
    for (i = 0; vec && vec->kind == EXTERIA_TL_V_VEC && i < vec->u.vec.count; ++i) {
        const exteria_tl_value *item = vec->u.vec.items[i];
        if (exteria_tl_is(item, EXTERIA_TL_ID_updatePhoneCall) && c->events.phone_call) c->events.phone_call(c->events.ctx, exteria_tl_get(item, "phone_call"));
        if (exteria_tl_is(item, EXTERIA_TL_ID_updatePhoneCallSignalingData)) deliver_signaling(c, item);
        deliver_typing(c, item);
        deliver_read_outbox(c, item);
        deliver_draft(c, item);
        deliver_group_call(c, item, v);
        if (folder_update(item)) folders = 1;
    }
    if (folders && c->events.folders_changed) c->events.folders_changed(c->events.ctx);
}

static void notify_changed(exteria_client *c) {
    if (c->events.changed && !c->closing) c->events.changed(c->events.ctx);
}

static void notify_changed_quiet(exteria_client *c, int quiet) {
    c->change_quiet = quiet;
    notify_changed(c);
    c->change_quiet = 0;
}

static void rpc_result(void *ctx, uint64_t id, const exteria_mt_rpc_result *r) {
    exteria_client *c = ctx;
    exteria_status status;
    if (c->closing) return;
    if (id == c->auth_wire_id) {
        uint64_t local_id = c->auth_local_id;
        c->auth_wire_id = 0;
        c->auth.server_time_offset_ms = c->mt.time_offset_ms;
        status = exteria_auth_result(&c->auth, local_id, r);
        if (status != EXTERIA_E_RPC) report(c, status, "auth");
    } else if (id == c->sync_id) {
        c->sync_id = 0;
        status = r->status;
        if (status == EXTERIA_OK) status = c->sync_method == EXTERIA_TL_ID_updates_getState ?
            exteria_updates_state(&c->updates, r->value) : exteria_updates_difference(&c->updates, c->sync_channel, r->value);
        if (status != EXTERIA_OK) {
            c->sync_suspended = 1;
            report(c, status, "updates difference");
        } else {
            if (c->sync_again) {
                c->sync_again = 0;
                report(c, exteria_updates_need(&c->updates, 0), "updates recovery");
            }
            notify_changed(c);
            if (c->updates.needs_history && c->events.recover_history) c->events.recover_history(c->events.ctx, c->sync_channel);
        }
    } else if (id == c->outbox_id) {
        c->outbox_id = 0;
        status = r->status;
        if (status == EXTERIA_OK) status = exteria_updates_sent(&c->updates, c->outbox_random, r->value);
        if (status != EXTERIA_OK && status != EXTERIA_E_RETRY) {
            exteria_status saved = exteria_store_outbox_set(c->store, c->outbox_random, EXTERIA_OUTBOX_FAILED, 0, (int32_t)status);
            report(c, saved, "outbox storage");
            report(c, status, "outbox send");
        }
        notify_changed(c);
    } else {
        if (c->store && r->status == EXTERIA_OK) {
            status = is_updates(r->value) ? exteria_updates_apply(&c->updates, r->value) :
                                          exteria_updates_cache(&c->updates, r->value);
            if (status != EXTERIA_E_RETRY) report(c, status, "rpc cache");
            if (status == EXTERIA_OK) {
                c->change_rpc_cache = !is_updates(r->value);
                notify_changed(c);
                c->change_rpc_cache = 0;
            }
            if (is_updates(r->value)) dispatch_live_updates(c, r->value);
        }
        if (c->events.result) c->events.result(c->events.ctx, id, r);
    }
}

static void update(void *ctx, const exteria_tl_value *v) {
    exteria_client *c = ctx;
    exteria_status status;
    const exteria_tl_value *vec = exteria_tl_get(v, "updates");
    const exteria_tl_value *one = exteria_tl_get(v, "update");
    uint32_t i;
    if (c->auth.qr) {
        int token = exteria_tl_is(one, EXTERIA_TL_ID_updateLoginToken);
        if (vec && vec->kind == EXTERIA_TL_V_VEC)
            for (i = 0; i < vec->u.vec.count; ++i) if (exteria_tl_is(vec->u.vec.items[i], EXTERIA_TL_ID_updateLoginToken)) token = 1;
        if (token) report(c, exteria_auth_qr_refresh(&c->auth), "qr refresh");
    }
    if (!c->store || !c->authorized || c->closing) return;
    if (c->sync_id) c->sync_again = 1;
    status = exteria_updates_apply(&c->updates, v);
    if (status != EXTERIA_E_RETRY) report(c, status, "updates transaction");
    if (status == EXTERIA_OK) notify_changed_quiet(c, exteria_updates_quiet(v));
    dispatch_live_updates(c, v);
}

static void lost(void *ctx, exteria_status reason) {
    exteria_client *c = ctx;
    report(c, exteria_updates_need(&c->updates, 0), "updates recovery");
    report(c, reason, "updates decode");
}

static void new_session(void *ctx) {
    exteria_client *c = ctx;
    report(c, exteria_updates_need(&c->updates, 0), "updates recovery");
}

static exteria_status init_transport(exteria_client *c) {
    exteria_mt_session_state restored;
    exteria_mt_client_events events;
    exteria_mt_client_config config = c->config;
    exteria_status status;
    memset(&events, 0, sizeof(events));
    memset(&restored, 0, sizeof(restored));
    events.ctx = c;
    events.send_checked = send_bytes;
    events.rpc_result = rpc_result;
    events.update = update;
    events.update_lost = lost;
    events.new_session = new_session;
    events.session_changed = save_session;
    status = c->events.load_session(c->events.ctx, c->config.dc_id, &restored);
    if (status != EXTERIA_OK && status != EXTERIA_E_NOTFOUND) { exteria_wipe(&restored, sizeof(restored)); return status; }
    config.restore = status == EXTERIA_OK ? &restored : NULL;
    status = exteria_mt_client_init(&c->mt, &config, &events);
    exteria_wipe(&restored, sizeof(restored));
    return status;
}

exteria_status exteria_client_init(exteria_client *c, const exteria_mt_client_config *config,
                                  const char *api_hash, const exteria_client_events *events) {
    exteria_auth_events auth_events;
    exteria_status status;
    if (!c) return EXTERIA_E_ARG;
    memset(c, 0, sizeof(*c));
    if (!config || config->api_id <= 0 || config->dc_id <= 0 || !events || !events->send ||
        !events->load_session || !events->save_session) return EXTERIA_E_ARG;
    c->config = *config;
    c->config.restore = NULL;
    c->events = *events;
    if (!c->config.clock) c->config.clock = &exteria_system_clock;
    auth_events.ctx = c;
    auth_events.submit = auth_submit;
    auth_events.cancel = auth_cancel;
    auth_events.changed = auth_changed;
    status = exteria_auth_init(&c->auth, config->api_id, api_hash, config->clock, &auth_events);
    if (status == EXTERIA_OK) status = init_transport(c);
    if (status != EXTERIA_OK) exteria_client_free(c);
    return status;
}

void exteria_client_free(exteria_client *c) {
    if (!c || c->closing) return;
    c->closing = 1;
    exteria_auth_free(&c->auth);
    exteria_mt_client_free(&c->mt);
    c->store = NULL;
    c->authorized = 0;
}

exteria_status exteria_client_attach_store(exteria_client *c, exteria_store *store, int64_t account_id) {
    exteria_status status;
    if (!c || !store || account_id <= 0 || c->closing || c->outbox_id || c->sync_id ||
        (c->account && c->account != account_id)) return EXTERIA_E_STATE;
    status = exteria_store_outbox_recover(store);
    if (status == EXTERIA_OK) status = exteria_updates_init(&c->updates, store, account_id);
    if (status == EXTERIA_OK) { c->store = store; c->account = account_id; c->authorized = 1; }
    return status;
}

exteria_status exteria_client_connect(exteria_client *c) {
    if (!c || c->closing || c->session_error != EXTERIA_OK) return EXTERIA_E_STATE;
    exteria_status status = exteria_mt_client_connect(&c->mt);
    if (status == EXTERIA_OK && c->mt.state == EXTERIA_MT_CLIENT_READY &&
        c->auth.state == EXTERIA_AUTH_MIGRATE && c->config.dc_id == c->auth.migrate_dc)
        status = exteria_auth_resume(&c->auth);
    return status;
}

void exteria_client_disconnected(exteria_client *c) {
    if (!c || c->closing) return;
    exteria_mt_client_disconnected(&c->mt);
    new_session(c);
}

exteria_status exteria_client_migrate(exteria_client *c, int32_t dc) {
    exteria_status status;
    if (!c || dc <= 0 || c->closing || c->mt.operation_depth || c->auth.state != EXTERIA_AUTH_MIGRATE ||
        dc != c->auth.migrate_dc) return EXTERIA_E_STATE;
    c->auth_wire_id = 0;
    exteria_mt_client_free(&c->mt);
    c->config.dc_id = dc;
    /* the obfuscation header names the data center it is sent to */
    if (c->config.obfuscation.enabled) c->config.obfuscation.dc_id = (int16_t)dc;
    c->session_error = EXTERIA_OK;
    status = init_transport(c);
    return status;
}

exteria_status exteria_client_feed(exteria_client *c, const uint8_t *data, size_t len) {
    exteria_status status;
    if (!c || c->closing) return EXTERIA_E_STATE;
    status = exteria_mt_client_feed(&c->mt, data, len);
    if (c->session_error != EXTERIA_OK) { exteria_client_disconnected(c); return c->session_error; }
    if (status == EXTERIA_OK && c->mt.state == EXTERIA_MT_CLIENT_READY &&
        c->auth.state == EXTERIA_AUTH_MIGRATE && c->config.dc_id == c->auth.migrate_dc)
        status = exteria_auth_resume(&c->auth);
    return status;
}

exteria_status exteria_client_request(exteria_client *c, const exteria_tl_value *request,
                                     uint32_t timeout_ms, uint64_t *id) {
    if (!id) return EXTERIA_E_ARG;
    *id = 0;
    if (!c || c->closing || !request) return EXTERIA_E_STATE;
    *id = request_id(c);
    return exteria_mt_client_submit(&c->mt, *id, request, timeout_ms);
}

exteria_status exteria_client_send(exteria_client *c, exteria_peer peer, const exteria_tl_value *request) {
    exteria_status status;
    if (!c || !c->store || !c->authorized || c->closing) return EXTERIA_E_STATE;
    status = exteria_store_outbox_add(c->store, peer, request);
    if (status == EXTERIA_OK) notify_changed(c);
    return status;
}

void exteria_client_resume_sync(exteria_client *c) {
    if (c) c->sync_suspended = 0;
}

static exteria_status sync_start(exteria_client *c, exteria_arena *arena) {
    exteria_tl_value *channel = NULL, *request, *chat;
    exteria_status status;
    int64_t hash;
    int64_t id = c->updates.gap_channel;
    if (id) {
        exteria_peer peer = {3, id};
        status = exteria_store_get(c->store, EXTERIA_RECORD_CHAT, peer, id, arena, &chat);
        if (status == EXTERIA_OK) status = exteria_tl_get_i64(chat, "access_hash", &hash);
        if (status != EXTERIA_OK) return status;
        channel = exteria_tl_new_obj(arena, "inputChannel");
        status = channel ? exteria_tl_set_i64(arena, channel, "channel_id", id) : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, channel, "access_hash", hash);
        if (status != EXTERIA_OK) return status;
    }
    status = exteria_updates_request(&c->updates, id, channel, arena, &request);
    if (status != EXTERIA_OK) return status;
    c->sync_channel = id;
    c->sync_method = exteria_tl_id(request);
    c->sync_id = request_id(c);
    status = exteria_mt_client_submit(&c->mt, c->sync_id, request, 60000);
    if (status != EXTERIA_OK) c->sync_id = 0;
    return status;
}

static exteria_status outbox_start(exteria_client *c, exteria_arena *arena) {
    exteria_outbox_item item;
    exteria_status status = exteria_store_outbox_next(c->store, arena, &item);
    if (status == EXTERIA_E_NOTFOUND) return EXTERIA_OK;
    if (status != EXTERIA_OK) return status;
    status = exteria_store_outbox_set(c->store, item.random_id, EXTERIA_OUTBOX_SENDING, 0, 0);
    if (status != EXTERIA_OK) return status;
    c->outbox_random = item.random_id;
    c->outbox_id = request_id(c);
    status = exteria_mt_client_submit(&c->mt, c->outbox_id, item.request, 60000);
    if (status != EXTERIA_OK) {
        c->outbox_id = 0;
        exteria_status saved = exteria_store_outbox_set(c->store, item.random_id, EXTERIA_OUTBOX_PENDING, 0, 0);
        if (saved != EXTERIA_OK) return saved;
    }
    return status;
}

exteria_status exteria_client_tick(exteria_client *c, uint32_t *next_ms) {
    exteria_arena arena;
    exteria_status status;
    if (!next_ms) return EXTERIA_E_ARG;
    *next_ms = UINT32_MAX;
    if (!c || c->closing) return EXTERIA_E_STATE;
    *next_ms = exteria_mt_client_tick(&c->mt);
    status = exteria_auth_tick(&c->auth);
    if (status != EXTERIA_OK) return status;
    {
        uint32_t auth_next = exteria_auth_next_ms(&c->auth);
        if (auth_next < *next_ms) *next_ms = auth_next;
    }
    if (c->closing || c->session_error != EXTERIA_OK) return EXTERIA_E_STATE;
    if (c->mt.state == EXTERIA_MT_CLIENT_READY && c->store && c->authorized) {
        exteria_arena_init(&arena, 16u * 1024u * 1024u);
        if (c->updates.needs_difference && !c->sync_id && !c->sync_suspended) {
            status = sync_start(c, &arena);
            if (status != EXTERIA_OK) {
                c->sync_suspended = 1;
                if (status == EXTERIA_E_NOTFOUND && c->events.recover_history) c->events.recover_history(c->events.ctx, c->updates.gap_channel);
                else report(c, status, "updates request");
            }
        }
        if (status == EXTERIA_OK && !c->outbox_id) status = outbox_start(c, &arena);
        exteria_arena_free(&arena);
    }
    return status;
}
