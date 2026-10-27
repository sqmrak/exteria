#include "test_util.h"
#include "exteria_client.h"
#include "exteria_tl_ids.h"

typedef struct fixture {
    exteria_client client;
    exteria_mt_transport server;
    exteria_mt_session_state session;
    exteria_clock clock;
    uint64_t now;
    uint64_t reply_id;
    unsigned changes;
    unsigned errors;
    exteria_auth_state auth_state;
    exteria_status save_error;
    unsigned calls;
    unsigned folders;
    int64_t last_call;
} fixture;

static uint64_t time_now(void *ctx) { return ((fixture *)ctx)->now; }
static exteria_status send_bytes(void *ctx, int32_t dc, const uint8_t *bytes, size_t len) {
    fixture *f = ctx;
    CHECK_EQ_INT(dc, f->client.config.dc_id);
    return exteria_mt_transport_feed(&f->server, bytes, len);
}
static exteria_status load(void *ctx, int32_t dc, exteria_mt_session_state *session) {
    fixture *f = ctx;
    CHECK(dc > 0);
    *session = f->session;
    return EXTERIA_OK;
}
static exteria_status save(void *ctx, int32_t dc, const exteria_mt_session_state *session) {
    fixture *f = ctx;
    CHECK(dc > 0);
    if (f->save_error) return f->save_error;
    f->session = *session;
    return EXTERIA_OK;
}
static void changed(void *ctx) { ++((fixture *)ctx)->changes; }
static void error(void *ctx, exteria_status status, const char *boundary) {
    fixture *f = ctx;
    CHECK(status != EXTERIA_OK && boundary != NULL);
    ++f->errors;
}
static void folders_changed(void *ctx) { ++((fixture *)ctx)->folders; }
static void on_call(void *ctx, const exteria_tl_value *call) {
    fixture *f = ctx;
    CHECK(exteria_tl_is(call, EXTERIA_TL_ID_phoneCallRequested));
    exteria_tl_get_i64(call, "id", &f->last_call);
    ++f->calls;
}
static void auth(void *ctx, exteria_auth_state state, exteria_status status, const exteria_tl_value *value, const char *text) {
    fixture *f = ctx;
    (void)status; (void)value; (void)text;
    f->auth_state = state;
}
static void start(fixture *f, int first) {
    exteria_client_events events;
    exteria_mt_client_config config;
    unsigned i;
    if (first) {
        memset(f, 0, sizeof(*f));
        f->now = UINT64_C(1700000000000);
        for (i = 0; i < 256; ++i) f->session.auth_key[i] = (uint8_t)i;
        f->session.server_salt = 123;
    }
    f->reply_id = (f->now / 1000u << 32) | 1u;
    f->clock.realtime_ms = time_now; f->clock.monotonic_ms = time_now; f->clock.ctx = f;
    memset(&events, 0, sizeof(events)); memset(&config, 0, sizeof(config));
    events.ctx = f; events.send = send_bytes; events.load_session = load; events.save_session = save;
    events.auth = auth; events.changed = changed; events.error = error; events.phone_call = on_call; events.folders_changed = folders_changed;
    config.dc_id = 2; config.api_id = 12345; config.clock = &f->clock; config.transport = EXTERIA_MT_INTERMEDIATE;
    exteria_mt_transport_init(&f->server);
    CHECK_EQ_INT(exteria_mt_transport_start_server(&f->server, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_init(&f->client, &config, "0123456789abcdef0123456789abcdef", &events), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_connect(&f->client), EXTERIA_OK);
}
static void stop(fixture *f) {
    exteria_client_free(&f->client);
    exteria_mt_transport_free(&f->server);
}
static uint64_t pop(fixture *f, exteria_arena *arena, exteria_tl_value **request) {
    exteria_mt_frame frame;
    exteria_mt_header h;
    exteria_writer plain;
    const uint8_t *body;
    size_t len;
    CHECK_EQ_INT(exteria_mt_transport_next(&f->server, &frame), EXTERIA_OK);
    exteria_writer_init(&plain, 2u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_mt_decrypt(&f->client.mt.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(arena, NULL, EXTERIA_TL_REF_ANY, body, len, request), EXTERIA_OK);
    while (exteria_tl_is(*request, EXTERIA_TL_ID_invokeWithLayer) || exteria_tl_is(*request, EXTERIA_TL_ID_initConnection))
        *request = (exteria_tl_value *)exteria_tl_get(*request, "query");
    exteria_writer_free(&plain);
    return h.msg_id;
}
static void reply(fixture *f, uint64_t msg_id, const exteria_tl_value *value) {
    exteria_mt_header h;
    exteria_writer body, enc, wire;
    exteria_writer_init(&body, 1u << 20); exteria_writer_init(&enc, 1u << 20); exteria_writer_init(&wire, 1u << 20);
    CHECK_EQ_INT(exteria_wr_u32le(&body, EXTERIA_TL_ID_rpc_result), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wr_u64le(&body, msg_id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(value, &body, NULL), EXTERIA_OK);
    h.msg_id = f->reply_id; f->reply_id += 4;
    h.salt = f->client.mt.salt; h.session_id = f->client.mt.session_id; h.seq_no = 1;
    CHECK_EQ_INT(exteria_mt_encrypt(&f->client.mt.key, 0, &h, body.data, body.len, &enc), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_transport_wrap(&f->server, enc.data, enc.len, 0, &wire), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_feed(&f->client, wire.data, wire.len), EXTERIA_OK);
    /* acknowledgements must not be mistaken for the next application request */
    { exteria_mt_frame frame; CHECK_EQ_INT(exteria_mt_transport_next(&f->server, &frame), EXTERIA_OK); }
    exteria_writer_free(&body); exteria_writer_free(&enc); exteria_writer_free(&wire);
}
/* a message the server starts, such as an update, which is not the answer to a request */
static void push(fixture *f, const exteria_tl_value *value) {
    exteria_mt_header h;
    exteria_writer body, enc, wire;
    exteria_writer_init(&body, 1u << 20); exteria_writer_init(&enc, 1u << 20); exteria_writer_init(&wire, 1u << 20);
    CHECK_EQ_INT(exteria_tl_encode(value, &body, NULL), EXTERIA_OK);
    h.msg_id = f->reply_id; f->reply_id += 4;
    h.salt = f->client.mt.salt; h.session_id = f->client.mt.session_id; h.seq_no = 1;
    CHECK_EQ_INT(exteria_mt_encrypt(&f->client.mt.key, 0, &h, body.data, body.len, &enc), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_transport_wrap(&f->server, enc.data, enc.len, 0, &wire), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_feed(&f->client, wire.data, wire.len), EXTERIA_OK);
    { exteria_mt_frame frame; CHECK_EQ_INT(exteria_mt_transport_next(&f->server, &frame), EXTERIA_OK); }
    exteria_writer_free(&body); exteria_writer_free(&enc); exteria_writer_free(&wire);
}
static exteria_tl_value *call_update(exteria_arena *a, int64_t id, int with_call) {
    exteria_tl_value *short_update = exteria_tl_new_obj(a, "updateShort"), *update = exteria_tl_new_obj(a, "updatePhoneCall");
    exteria_tl_value *call = exteria_tl_new_obj(a, with_call ? "phoneCallRequested" : "phoneCallEmpty");
    CHECK_EQ_INT(exteria_tl_set_i64(a, call, "id", id), EXTERIA_OK);
    if (with_call) {
        exteria_tl_value *proto = exteria_tl_new_obj(a, "phoneCallProtocol");
        uint8_t hash[32] = {0};
        CHECK_EQ_INT(exteria_tl_set_i64(a, call, "access_hash", 5), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(a, call, "date", 100), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i64(a, call, "admin_id", 7), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i64(a, call, "participant_id", 1), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_bytes(a, call, "g_a_hash", hash, 32), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(a, proto, "min_layer", 65), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(a, proto, "max_layer", 92), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(proto, "library_versions", exteria_tl_new_vec(a, 0)), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(call, "protocol", proto), EXTERIA_OK);
    }
    CHECK_EQ_INT(exteria_tl_set(update, "phone_call", call), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(short_update, "update", update), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, short_update, "date", 100), EXTERIA_OK);
    return short_update;
}
static exteria_tl_value *send_request(exteria_arena *a, int64_t random_id) {
    exteria_tl_value *v = exteria_tl_new_obj(a, "messages.sendMessage"), *peer = exteria_tl_new_obj(a, "inputPeerUser");
    CHECK_EQ_INT(exteria_tl_set_i64(a, peer, "user_id", 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(a, peer, "access_hash", INT64_MIN + 17), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(v, "peer", peer), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(a, v, "random_id", random_id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(a, v, "message", "hello offline"), EXTERIA_OK);
    return v;
}
static exteria_tl_value *sent(exteria_arena *a, int32_t id, int32_t pts) {
    exteria_tl_value *v = exteria_tl_new_obj(a, "updateShortSentMessage");
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "pts", pts), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "pts_count", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "date", 101), EXTERIA_OK);
    return v;
}

static exteria_tl_value *migrate_error(exteria_arena *a, const char *text) {
    exteria_tl_value *v = exteria_tl_new_obj(a, "rpc_error");
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "error_code", 303), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(a, v, "error_message", text), EXTERIA_OK);
    return v;
}

/* a phone that lives on another data center must resend the code request there, with that dc in the obfuscation header */
static void test_auth_migrate(void) {
    fixture f;
    exteria_arena a;
    exteria_tl_value *request;
    uint64_t msg_id;
    const char *phone;
    size_t phone_len;
    exteria_arena_init(&a, 8u * 1024u * 1024u);
    start(&f, 1);
    CHECK_EQ_INT(exteria_auth_phone(&f.client.auth, "+79991234567", NULL), EXTERIA_OK);
    msg_id = pop(&f, &a, &request);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_auth_sendCode));
    reply(&f, msg_id, migrate_error(&a, "PHONE_MIGRATE_4"));
    CHECK_EQ_INT(f.auth_state, EXTERIA_AUTH_MIGRATE);
    CHECK_EQ_INT(f.client.auth.migrate_dc, 4);
    CHECK_EQ_INT(exteria_client_migrate(&f.client, 3), EXTERIA_E_STATE);

    f.client.config.obfuscation.enabled = 1;
    f.client.config.obfuscation.dc_id = 2;
    exteria_mt_transport_free(&f.server);
    exteria_mt_transport_init(&f.server);
    CHECK_EQ_INT(exteria_mt_transport_start_server(&f.server, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_migrate(&f.client, 4), EXTERIA_OK);
    CHECK_EQ_INT(f.client.config.dc_id, 4);
    CHECK_EQ_INT(f.client.config.obfuscation.dc_id, 4);
    CHECK_EQ_INT(exteria_client_connect(&f.client), EXTERIA_OK);
    CHECK_EQ_INT(f.server.obf.dc_id, 4);
    msg_id = pop(&f, &a, &request);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_auth_sendCode));
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "phone_number", (const uint8_t **)&phone, &phone_len), EXTERIA_OK);
    CHECK_EQ_INT(phone_len, 12);
    CHECK(memcmp(phone, "+79991234567", phone_len) == 0);
    (void)msg_id;
    CHECK_EQ_INT(f.errors, 0);
    stop(&f);
    exteria_wipe(&f.session, sizeof(f.session));
    exteria_arena_free(&a);
}

int main(void) {
    fixture f;
    exteria_arena a;
    exteria_store *s;
    exteria_tl_value *request, *v;
    exteria_peer peer = {1, 2};
    exteria_cursor cursor;
    uint32_t ms;
    uint64_t msg_id;
    int64_t random_id;
    exteria_arena_init(&a, 8u * 1024u * 1024u);
    start(&f, 1);
    CHECK_EQ_INT(exteria_store_open(&s, ":memory:", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_attach_store(&f.client, s, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_tick(&f.client, &ms), EXTERIA_OK);
    msg_id = pop(&f, &a, &request);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_updates_getState));
    v = exteria_tl_new_obj(&a, "updates.state");
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "pts", 10), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "qts", 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "seq", 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "date", 100), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "unread_count", 0), EXTERIA_OK);
    reply(&f, msg_id, v);
    CHECK_EQ_INT(exteria_client_send(&f.client, peer, send_request(&a, INT64_MIN + 90)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_tick(&f.client, &ms), EXTERIA_OK);
    msg_id = pop(&f, &a, &request);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_messages_sendMessage));
    CHECK_EQ_INT(exteria_tl_get_i64(request, "random_id", &random_id), EXTERIA_OK);
    CHECK_EQ_INT(random_id, INT64_MIN + 90);
    reply(&f, msg_id, sent(&a, 42, 11));
    CHECK_EQ_INT(exteria_store_cursor_get(s, 0, &cursor), EXTERIA_OK);
    CHECK_EQ_INT(cursor.pts, 11);
    /* a call that rings reaches the app as it came; the update does not move the cursor */
    push(&f, call_update(&a, 4001, 1));
    CHECK_EQ_INT(f.calls, 1);
    CHECK_EQ_INT(f.last_call, 4001);
    CHECK_EQ_INT(exteria_store_cursor_get(s, 0, &cursor), EXTERIA_OK);
    CHECK_EQ_INT(cursor.pts, 11);
    {
        exteria_tl_value *update = exteria_tl_new_obj(&a, "updateShort");
        exteria_tl_value *filters = exteria_tl_new_obj(&a, "updateDialogFilters");
        CHECK_EQ_INT(exteria_tl_set(update, "update", filters), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(&a, update, "date", 100), EXTERIA_OK);
        push(&f, update);
        CHECK_EQ_INT(f.folders, 1);
        f.client.events.folders_changed = NULL;
        push(&f, update);
        CHECK_EQ_INT(f.folders, 1);
    }
    CHECK_EQ_INT(exteria_client_send(&f.client, peer, send_request(&a, INT64_MIN + 91)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_tick(&f.client, &ms), EXTERIA_OK);
    msg_id = pop(&f, &a, &request);
    CHECK_EQ_INT(exteria_tl_get_i64(request, "random_id", &random_id), EXTERIA_OK);
    CHECK_EQ_INT(random_id, INT64_MIN + 91);
    stop(&f);
    start(&f, 0);
    CHECK_EQ_INT(exteria_client_attach_store(&f.client, s, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_client_tick(&f.client, &ms), EXTERIA_OK);
    msg_id = pop(&f, &a, &request);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_updates_getDifference));
    v = exteria_tl_new_obj(&a, "updates.differenceEmpty");
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "date", 101), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "seq", 1), EXTERIA_OK);
    { uint64_t out_msg = pop(&f, &a, &request);
      CHECK_EQ_INT(exteria_tl_get_i64(request, "random_id", &random_id), EXTERIA_OK);
      CHECK_EQ_INT(random_id, INT64_MIN + 91);
      reply(&f, msg_id, v);
      reply(&f, out_msg, sent(&a, 43, 12)); }
    CHECK_EQ_INT(exteria_store_cursor_get(s, 0, &cursor), EXTERIA_OK);
    CHECK_EQ_INT(cursor.pts, 12);
    CHECK_EQ_INT(f.errors, 0);
    stop(&f);
    CHECK_EQ_INT(exteria_store_close(s), EXTERIA_OK);
    exteria_arena_free(&a);
    exteria_wipe(&f.session, sizeof(f.session));
    test_auth_migrate();
    return test_finish("test_client");
}
