#include "test_util.h"

#include <zlib.h>

#include "exteria_mt_client.h"
#include "exteria_tl_ids.h"

#define CONTAINER_ID 0x73f1f8dcu

typedef struct client_fixture {
    exteria_mt_client client;
    exteria_mt_transport server;
    exteria_clock clock;
    uint64_t now;
    uint64_t server_id;
    unsigned results;
    unsigned updates;
    unsigned lost;
    unsigned sessions;
    uint64_t request_id;
    exteria_status result_status;
    exteria_status state_reason;
    uint32_t result_ctor;
    uint32_t vector_count;
    int32_t error_code;
    char error_text[64];
    int free_on_result;
} client_fixture;

static uint64_t fixture_time(void *ctx) {
    return ((client_fixture *)ctx)->now;
}

static void sent(void *ctx, const uint8_t *data, size_t len) {
    client_fixture *f = ctx;
    CHECK_EQ_INT(exteria_mt_transport_feed(&f->server, data, len), EXTERIA_OK);
}

static void result(void *ctx, uint64_t request_id, const exteria_mt_rpc_result *r) {
    client_fixture *f = ctx;
    f->results++;
    f->request_id = request_id;
    f->result_status = r->status;
    f->result_ctor = exteria_tl_id(r->value);
    f->vector_count = r->value && r->value->kind == EXTERIA_TL_V_VEC ? r->value->u.vec.count : UINT32_MAX;
    f->error_code = r->error_code;
    if (r->error_text) snprintf(f->error_text, sizeof(f->error_text), "%s", r->error_text);
    if (f->free_on_result) exteria_mt_client_free(&f->client);
}

static void update(void *ctx, const exteria_tl_value *v) {
    client_fixture *f = ctx;
    CHECK_EQ_INT(exteria_tl_id(v), EXTERIA_TL_ID_updatesTooLong);
    f->updates++;
}

static void lost(void *ctx, exteria_status reason) {
    client_fixture *f = ctx;
    CHECK(reason != EXTERIA_OK);
    f->lost++;
}

static void session(void *ctx) {
    ((client_fixture *)ctx)->sessions++;
}

static void state(void *ctx, exteria_mt_client_state st, exteria_status reason) {
    client_fixture *f = ctx;
    (void)st;
    f->state_reason = reason;
}

static void fixture_init(client_fixture *f, size_t arena_limit) {
    exteria_mt_client_config config;
    exteria_mt_client_events events;
    exteria_mt_session_state restore;
    unsigned i;
    memset(f, 0, sizeof(*f));
    memset(&config, 0, sizeof(config));
    memset(&events, 0, sizeof(events));
    memset(&restore, 0, sizeof(restore));
    f->now = 1700000000123ull;
    f->server_id = (1700000000ull << 32) | 1u;
    f->clock.realtime_ms = fixture_time;
    f->clock.monotonic_ms = fixture_time;
    f->clock.ctx = f;
    for (i = 0; i < sizeof(restore.auth_key); ++i) restore.auth_key[i] = (uint8_t)i;
    restore.server_salt = 123456789;
    config.clock = &f->clock;
    config.restore = &restore;
    config.transport = EXTERIA_MT_INTERMEDIATE;
    config.result_arena_limit = (uint32_t)arena_limit;
    events.ctx = f;
    events.send = sent;
    events.rpc_result = result;
    events.update = update;
    events.update_lost = lost;
    events.new_session = session;
    events.state = state;
    exteria_mt_transport_init(&f->server);
    CHECK_EQ_INT(exteria_mt_transport_start_server(&f->server, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_client_init(&f->client, &config, &events), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_client_connect(&f->client), EXTERIA_OK);
}

static void fixture_free(client_fixture *f) {
    exteria_mt_client_free(&f->client);
    exteria_mt_transport_free(&f->server);
}

static uint64_t submit(client_fixture *f, uint64_t id, int vector, uint32_t timeout) {
    exteria_arena a;
    exteria_tl_value *request;
    exteria_mt_frame frame;
    exteria_mt_header h;
    exteria_writer plain;
    const uint8_t *body;
    size_t len;
    exteria_arena_init(&a, 16384);
    request = exteria_tl_new_obj(&a, vector ? "messages.receivedMessages" : "account.updateStatus");
    CHECK(request != NULL);
    if (vector) CHECK_EQ_INT(exteria_tl_set_i32(&a, request, "max_id", 1), EXTERIA_OK);
    else CHECK_EQ_INT(exteria_tl_set(request, "offline", exteria_tl_new_obj(&a, "boolFalse")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_client_submit(&f->client, id, request, timeout), EXTERIA_OK);
    exteria_arena_free(&a);
    CHECK_EQ_INT(exteria_mt_transport_next(&f->server, &frame), EXTERIA_OK);
    CHECK_EQ_INT(frame.kind, EXTERIA_MT_FRAME_DATA);
    exteria_writer_init(&plain, 1 << 20);
    CHECK_EQ_INT(exteria_mt_decrypt(&f->client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), EXTERIA_OK);
    CHECK_EQ_INT(h.session_id, f->client.session_id);
    CHECK_EQ_INT(h.seq_no & 1, 1);
    CHECK_EQ_INT(exteria_get_u32le(body), vector ? EXTERIA_TL_ID_messages_receivedMessages : EXTERIA_TL_ID_account_updateStatus);
    exteria_writer_free(&plain);
    return h.msg_id;
}

/* a frame from the server built with any key, salt and session id, and with one byte of the ciphertext flipped when tamper is set */
static exteria_status receive_as(client_fixture *f, const exteria_mt_auth_key *key, uint64_t salt, uint64_t session_id,
                                 const uint8_t *body, size_t len, uint64_t msg_id, int32_t seq_no, int fragmented, int tamper) {
    exteria_mt_header h;
    exteria_writer enc, wire;
    exteria_status s;
    size_t pos;
    h.salt = salt;
    h.session_id = session_id;
    h.msg_id = msg_id;
    h.seq_no = seq_no;
    exteria_writer_init(&enc, 1 << 20);
    exteria_writer_init(&wire, 1 << 20);
    CHECK_EQ_INT(exteria_mt_encrypt(key, 0, &h, body, len, &enc), EXTERIA_OK);
    if (tamper) enc.data[40] ^= 1;
    CHECK_EQ_INT(exteria_mt_transport_wrap(&f->server, enc.data, enc.len, 0, &wire), EXTERIA_OK);
    s = EXTERIA_OK;
    if (fragmented) {
        for (pos = 0; pos < wire.len && s == EXTERIA_OK; ++pos) {
            s = exteria_mt_client_feed(&f->client, wire.data + pos, 1);
        }
    } else s = exteria_mt_client_feed(&f->client, wire.data, wire.len);
    exteria_writer_free(&enc);
    exteria_writer_free(&wire);
    return s;
}

static exteria_status receive(client_fixture *f, const uint8_t *body, size_t len,
                               uint64_t msg_id, int32_t seq_no, int fragmented) {
    return receive_as(f, &f->client.key, f->client.salt, f->client.session_id, body, len, msg_id, seq_no, fragmented, 0);
}

static void drain_acks(client_fixture *f, unsigned expected) {
    exteria_mt_frame frame;
    unsigned got = 0;
    exteria_status s;
    while ((s = exteria_mt_transport_next(&f->server, &frame)) == EXTERIA_OK) {
        exteria_writer plain;
        exteria_mt_header h;
        const uint8_t *body;
        size_t len;
        exteria_tl_value *v;
        const exteria_tl_value *ids;
        exteria_arena a;
        exteria_writer_init(&plain, 1 << 20);
        exteria_arena_init(&a, 1 << 20);
        CHECK_EQ_INT(exteria_mt_decrypt(&f->client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), EXTERIA_OK);
        CHECK_EQ_INT(h.seq_no & 1, 0);
        CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, body, len, &v), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_id(v), EXTERIA_TL_ID_msgs_ack);
        CHECK_EQ_INT(exteria_tl_get_vec(v, "msg_ids", &ids), EXTERIA_OK);
        got += ids->u.vec.count;
        exteria_arena_free(&a);
        exteria_writer_free(&plain);
    }
    CHECK_EQ_INT(s, EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(got, expected);
}

static void gzip_body(const uint8_t *data, size_t len, int trailing, exteria_writer *out) {
    uint8_t packed[8192];
    z_stream z;
    exteria_arena a;
    exteria_tl_value *v;
    size_t n;
    memset(&z, 0, sizeof(z));
    CHECK_EQ_INT(deflateInit2(&z, 6, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY), Z_OK);
    z.next_in = (Bytef *)(uintptr_t)data;
    z.avail_in = (uInt)len;
    z.next_out = packed;
    z.avail_out = sizeof(packed) - 1;
    CHECK_EQ_INT(deflate(&z, Z_FINISH), Z_STREAM_END);
    n = sizeof(packed) - 1 - z.avail_out;
    CHECK_EQ_INT(deflateEnd(&z), Z_OK);
    if (trailing) packed[n++] = 0xff;
    exteria_arena_init(&a, 1 << 20);
    v = exteria_tl_new_obj(&a, "gzip_packed");
    CHECK_EQ_INT(exteria_tl_set_bytes(&a, v, "packed_data", packed, n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(v, out, NULL), EXTERIA_OK);
    exteria_arena_free(&a);
}

static void test_rpc_gzip(void) {
    unsigned mode;
    for (mode = 0; mode < 4; ++mode) {
        client_fixture f;
        uint64_t request_id;
        exteria_writer rpc, packed, value;
        uint8_t raw[8];
        int vector = (int)(mode & 1u);
        fixture_init(&f, 0);
        request_id = submit(&f, 41, vector, 5000);
        exteria_writer_init(&rpc, 1 << 20);
        exteria_writer_init(&packed, 1 << 20);
        exteria_writer_init(&value, 1 << 20);
        exteria_put_u32le(raw, vector ? 0x1cb5c415u : EXTERIA_TL_ID_boolTrue);
        exteria_put_u32le(raw + 4, 0);
        CHECK_EQ_INT(exteria_wr_u32le(&rpc, EXTERIA_TL_ID_rpc_result), EXTERIA_OK);
        CHECK_EQ_INT(exteria_wr_u64le(&rpc, request_id), EXTERIA_OK);
        if (mode < 2) {
            CHECK_EQ_INT(exteria_wr_bytes(&rpc, raw, vector ? 8 : 4), EXTERIA_OK);
            gzip_body(rpc.data, rpc.len, 0, &packed);
            CHECK_EQ_INT(receive(&f, packed.data, packed.len, f.server_id, 0, 1), EXTERIA_OK);
        } else {
            gzip_body(raw, vector ? 8 : 4, 0, &value);
            CHECK_EQ_INT(exteria_wr_bytes(&rpc, value.data, value.len), EXTERIA_OK);
            CHECK_EQ_INT(receive(&f, rpc.data, rpc.len, f.server_id, 1, 1), EXTERIA_OK);
            drain_acks(&f, 1);
        }
        CHECK_EQ_INT(f.results, 1);
        CHECK_EQ_INT(f.request_id, 41);
        CHECK_EQ_INT(f.result_status, EXTERIA_OK);
        CHECK_EQ_INT(vector ? f.vector_count : f.result_ctor, vector ? 0 : EXTERIA_TL_ID_boolTrue);
        CHECK_EQ_INT(exteria_mt_client_pending_count(&f.client), 0);
        exteria_writer_free(&rpc);
        exteria_writer_free(&packed);
        exteria_writer_free(&value);
        fixture_free(&f);
    }
}

static void test_rpc_error(void) {
    client_fixture f;
    exteria_arena a;
    exteria_tl_value *v;
    exteria_writer rpc, error, packed;
    uint64_t request;
    fixture_init(&f, 0);
    request = submit(&f, 42, 0, 5000);
    exteria_arena_init(&a, 16384);
    exteria_writer_init(&rpc, 16384);
    exteria_writer_init(&error, 16384);
    exteria_writer_init(&packed, 16384);
    v = exteria_tl_new_obj(&a, "rpc_error");
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "error_code", 303), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&a, v, "error_message", "PHONE_MIGRATE_4"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(v, &error, NULL), EXTERIA_OK);
    gzip_body(error.data, error.len, 0, &packed);
    CHECK_EQ_INT(exteria_wr_u32le(&rpc, EXTERIA_TL_ID_rpc_result), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wr_u64le(&rpc, request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wr_bytes(&rpc, packed.data, packed.len), EXTERIA_OK);
    CHECK_EQ_INT(receive(&f, rpc.data, rpc.len, f.server_id, 1, 0), EXTERIA_OK);
    CHECK_EQ_INT(f.results, 1);
    CHECK_EQ_INT(f.result_status, EXTERIA_E_RPC);
    CHECK_EQ_INT(f.error_code, 303);
    CHECK(strcmp(f.error_text, "PHONE_MIGRATE_4") == 0);
    exteria_writer_free(&rpc);
    exteria_writer_free(&error);
    exteria_writer_free(&packed);
    exteria_arena_free(&a);
    fixture_free(&f);
}

static void container_begin(exteria_writer *w, uint32_t count) {
    exteria_writer_init(w, 1 << 20);
    CHECK_EQ_INT(exteria_wr_u32le(w, CONTAINER_ID), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wr_u32le(w, count), EXTERIA_OK);
}

static void container_item(exteria_writer *w, uint64_t id, int32_t seq, const uint8_t *body, size_t len) {
    CHECK_EQ_INT(exteria_wr_u64le(w, id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wr_u32le(w, (uint32_t)seq), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wr_u32le(w, (uint32_t)len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wr_bytes(w, body, len), EXTERIA_OK);
}

static void test_container(void) {
    client_fixture f;
    exteria_writer w;
    uint8_t body[4];
    uint64_t outer;
    unsigned i;
    fixture_init(&f, 0);
    exteria_put_u32le(body, EXTERIA_TL_ID_updatesTooLong);
    container_begin(&w, 1024);
    for (i = 0; i < 1024; ++i) container_item(&w, f.server_id + i * 4u, 1, body, sizeof(body));
    outer = f.server_id + 1024u * 4u;
    CHECK_EQ_INT(receive(&f, w.data, w.len, outer, 0, 0), EXTERIA_OK);
    CHECK_EQ_INT(f.updates, 1024);
    drain_acks(&f, 1024);
    CHECK_EQ_INT(receive(&f, w.data, w.len, outer, 0, 0), EXTERIA_OK);
    CHECK_EQ_INT(f.updates, 1024);
    CHECK_EQ_INT(receive(&f, body, sizeof(body), f.server_id, 1, 0), EXTERIA_OK);
    CHECK_EQ_INT(f.updates, 1024);
    exteria_writer_free(&w);
    fixture_free(&f);
}

static void test_bad_container(void) {
    unsigned mode;
    for (mode = 0; mode < 9; ++mode) {
        client_fixture f;
        exteria_writer w;
        uint8_t body[8];
        uint64_t outer;
        fixture_init(&f, 0);
        outer = f.server_id + 20;
        exteria_put_u32le(body, EXTERIA_TL_ID_updatesTooLong);
        exteria_put_u32le(body + 4, 0);
        container_begin(&w, mode == 0 ? 1025 : 1);
        container_item(&w, f.server_id, 1, body, 4);
        if (mode == 1) CHECK_EQ_INT(exteria_wr_u32le(&w, 0), EXTERIA_OK);
        if (mode == 2) exteria_put_u64le(w.data + 8, outer);
        if (mode == 3) exteria_put_u64le(w.data + 8, f.server_id & ~3ull);
        if (mode == 4) exteria_put_u32le(w.data + 16, UINT32_MAX);
        if (mode == 5) exteria_put_u32le(w.data + 20, 8);
        if (mode == 6) exteria_put_u32le(w.data + 24, CONTAINER_ID);
        if (mode == 7) {
            exteria_put_u32le(w.data + 4, 2);
            container_item(&w, outer, 1, body, 4);
        }
        CHECK_EQ_INT(receive(&f, w.data, w.len, outer, mode == 8 ? 1 : 0, 0), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(f.client.state, EXTERIA_MT_CLIENT_DEAD);
        CHECK_EQ_INT(f.updates, 0);
        exteria_writer_free(&w);
        fixture_free(&f);
    }
}

static void test_gzip_limits(void) {
    unsigned mode;
    for (mode = 0; mode < 5; ++mode) {
        client_fixture f;
        exteria_writer packed, twice;
        uint8_t body[8192];
        fixture_init(&f, mode == 3 ? 64 : 0);
        memset(body, 0, sizeof(body));
        exteria_put_u32le(body, EXTERIA_TL_ID_updatesTooLong);
        exteria_writer_init(&packed, 1 << 20);
        exteria_writer_init(&twice, 1 << 20);
        gzip_body(body, mode == 3 ? sizeof(body) : 4, mode == 1, &packed);
        if (mode == 2) {
            gzip_body(packed.data, packed.len, 0, &twice);
            CHECK_EQ_INT(receive(&f, twice.data, twice.len, f.server_id, 0, 0), EXTERIA_E_MALFORMED);
        } else {
            if (mode == 4) packed.data[packed.len - 5] ^= 0xff;
            CHECK_EQ_INT(receive(&f, packed.data, packed.len, f.server_id, 0, 0),
                         mode == 0 ? EXTERIA_OK : mode == 3 ? EXTERIA_E_LIMIT : EXTERIA_E_MALFORMED);
        }
        CHECK_EQ_INT(f.updates, mode == 0 ? 1 : 0);
        exteria_writer_free(&packed);
        exteria_writer_free(&twice);
        fixture_free(&f);
    }
}

/* the server sends large updates gzipped as content messages, which carry an odd seq_no and need an ack */
static void test_gzip_content_message(void) {
    client_fixture f;
    exteria_writer packed;
    uint8_t body[4];
    fixture_init(&f, 0);
    exteria_put_u32le(body, EXTERIA_TL_ID_updatesTooLong);
    exteria_writer_init(&packed, 1 << 20);
    gzip_body(body, sizeof(body), 0, &packed);
    CHECK_EQ_INT(receive(&f, packed.data, packed.len, f.server_id, 1, 0), EXTERIA_OK);
    CHECK_EQ_INT(f.updates, 1);
    CHECK(f.client.state != EXTERIA_MT_CLIENT_DEAD);
    drain_acks(&f, 1);
    exteria_writer_free(&packed);
    fixture_free(&f);
}

static void test_replay_window(void) {
    client_fixture f;
    uint8_t body[4];
    unsigned i;
    fixture_init(&f, 0);
    exteria_put_u32le(body, EXTERIA_TL_ID_updatesTooLong);
    for (i = 0; i < EXTERIA_MT_SEEN_MAX + 2; ++i) {
        CHECK_EQ_INT(receive(&f, body, sizeof(body), f.server_id + 4u * i, 0, 0), EXTERIA_OK);
    }
    CHECK_EQ_INT(f.updates, EXTERIA_MT_SEEN_MAX + 2);
    CHECK_EQ_INT(receive(&f, body, sizeof(body), f.server_id, 0, 0), EXTERIA_OK);
    CHECK_EQ_INT(f.updates, EXTERIA_MT_SEEN_MAX + 2);
    fixture_free(&f);
}

static void test_timeout_cancel(void) {
    client_fixture f;
    fixture_init(&f, 0);
    (void)submit(&f, 43, 0, 100);
    f.now += 99;
    CHECK_EQ_INT(exteria_mt_client_tick(&f.client), 1);
    CHECK_EQ_INT(f.results, 0);
    f.now++;
    (void)exteria_mt_client_tick(&f.client);
    CHECK_EQ_INT(f.result_status, EXTERIA_E_TIMEOUT);
    CHECK_EQ_INT(f.results, 1);
    (void)submit(&f, 44, 0, 100);
    CHECK_EQ_INT(exteria_mt_client_cancel(&f.client, 44), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_client_cancel(&f.client, 44), EXTERIA_E_NOTFOUND);
    f.now += 100;
    (void)exteria_mt_client_tick(&f.client);
    CHECK_EQ_INT(f.results, 1);
    fixture_free(&f);
}

/* the ping a quiet link sends names a disconnect delay of the interval plus 45 seconds, so a longer background interval does not get the link dropped */
static int32_t next_ping_delay(client_fixture *f) {
    exteria_mt_frame frame;
    exteria_mt_header h;
    exteria_writer plain;
    const uint8_t *body;
    size_t len;
    exteria_arena a;
    exteria_tl_value *v;
    int32_t delay = -1;
    if (exteria_mt_transport_next(&f->server, &frame) != EXTERIA_OK) return -1;
    exteria_writer_init(&plain, 1 << 20);
    exteria_arena_init(&a, 1 << 20);
    CHECK_EQ_INT(exteria_mt_decrypt(&f->client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, body, len, &v), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(v), EXTERIA_TL_ID_ping_delay_disconnect);
    CHECK_EQ_INT(exteria_tl_get_i32(v, "disconnect_delay", &delay), EXTERIA_OK);
    exteria_arena_free(&a);
    exteria_writer_free(&plain);
    return delay;
}

static void test_ping_interval(void) {
    client_fixture f;
    exteria_mt_frame frame;
    uint32_t wait;
    fixture_init(&f, 0);
    CHECK_EQ_INT(exteria_mt_client_ping_interval(&f.client), 30000);
    exteria_mt_client_set_ping_interval(&f.client, 5);
    CHECK_EQ_INT(exteria_mt_client_ping_interval(&f.client), 10000);
    exteria_mt_client_set_ping_interval(&f.client, 4000000);
    CHECK_EQ_INT(exteria_mt_client_ping_interval(&f.client), 300000);
    exteria_mt_client_set_ping_interval(&f.client, 60000);
    wait = exteria_mt_client_tick(&f.client);
    CHECK(wait > 30000 && wait <= 60000);
    CHECK_EQ_INT(exteria_mt_transport_next(&f.server, &frame), EXTERIA_E_TRUNCATED);
    f.now += wait;
    (void)exteria_mt_client_tick(&f.client);
    CHECK_EQ_INT(next_ping_delay(&f), 60 + 45);
    exteria_mt_client_set_ping_interval(&f.client, 30000);
    fixture_free(&f);
    exteria_mt_client_set_ping_interval(NULL, 60000);
    CHECK_EQ_INT(exteria_mt_client_ping_interval(NULL), 0);
}

static void test_state_request(void) {
    const unsigned counts[] = { 0, 257, 8192, 8193 };
    unsigned k;
    for (k = 0; k < sizeof(counts) / sizeof(counts[0]); ++k) {
        client_fixture f;
        exteria_arena a;
        exteria_writer w, plain;
        exteria_tl_value *req, *reply;
        exteria_mt_frame frame;
        exteria_mt_header h;
        int64_t ids[8193];
        const uint8_t *body, *info;
        size_t len, info_len;
        unsigned i;
        fixture_init(&f, 0);
        exteria_arena_init(&a, 1 << 20);
        exteria_writer_init(&w, 1 << 20);
        exteria_writer_init(&plain, 1 << 20);
        req = exteria_tl_new_obj(&a, "msgs_state_req");
        for (i = 0; i < counts[k]; ++i) ids[i] = (int64_t)(f.server_id + i * 4u);
        CHECK_EQ_INT(exteria_tl_set_i64_vec(&a, req, "msg_ids", ids, counts[k]), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_encode(req, &w, NULL), EXTERIA_OK);
        CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + 40000, 0, 0),
                     counts[k] > 8192 ? EXTERIA_E_LIMIT : EXTERIA_OK);
        if (counts[k] <= 8192) {
            CHECK_EQ_INT(exteria_mt_transport_next(&f.server, &frame), EXTERIA_OK);
            CHECK_EQ_INT(exteria_mt_decrypt(&f.client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, body, len, &reply), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_id(reply), EXTERIA_TL_ID_msgs_state_info);
            CHECK_EQ_INT(exteria_tl_get_bytes(reply, "info", &info, &info_len), EXTERIA_OK);
            CHECK_EQ_INT(info_len, counts[k]);
            for (i = 0; i < info_len; ++i) CHECK_EQ_INT(info[i], 1);
        }
        exteria_writer_free(&w);
        exteria_writer_free(&plain);
        exteria_arena_free(&a);
        fixture_free(&f);
    }
}

static void test_receive_errors(void) {
    unsigned mode;
    for (mode = 0; mode < 5; ++mode) {
        client_fixture f;
        uint8_t body[12];
        fixture_init(&f, 0);
        memset(body, 0, sizeof(body));
        exteria_put_u32le(body, mode == 0 ? EXTERIA_TL_ID_rpc_result :
                              mode == 1 ? EXTERIA_TL_ID_pong :
                              mode == 2 ? 0xdeadbeefu : EXTERIA_TL_ID_updatesTooLong);
        CHECK_EQ_INT(receive(&f, body, mode == 0 ? 12 : 4,
                            mode == 3 ? f.server_id & ~3ull : f.server_id,
                            mode == 4 ? -1 : 0, 0), mode == 2 ? EXTERIA_OK : EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(f.lost, mode == 2 ? 1 : 0);
        CHECK_EQ_INT(f.updates, 0);
        CHECK_EQ_INT(f.state_reason, mode == 2 ? EXTERIA_OK : EXTERIA_E_MALFORMED);
        fixture_free(&f);
    }
}

static void test_unpack_limits(void) {
    uint8_t body[4096];
    unsigned mode;
    for (mode = 0; mode < 4; ++mode) {
        exteria_writer packed, plain;
        memset(body, 0x42, sizeof(body));
        exteria_writer_init(&packed, 16384);
        exteria_writer_init(&plain, mode == 1 ? sizeof(body) + 3 : sizeof(body) + 4);
        CHECK_EQ_INT(exteria_wr_u32le(&plain, 0x12345678), EXTERIA_OK);
        gzip_body(body, sizeof(body), mode == 2, &packed);
        if (mode == 3) CHECK_EQ_INT(exteria_wr_u32le(&packed, 0), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_unpack_gzip(packed.data, packed.len, &plain), mode == 0 ? EXTERIA_OK : mode == 1 ? EXTERIA_E_LIMIT : EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(plain.len, mode == 0 ? sizeof(body) + 4 : 4);
        CHECK_EQ_INT(exteria_get_u32le(plain.data), 0x12345678);
        if (mode == 0) CHECK_MEM(plain.data + 4, body, sizeof(body));
        exteria_writer_free(&packed);
        exteria_writer_free(&plain);
    }
}

static uint64_t outgoing_id(client_fixture *f, uint64_t *session_id) {
    exteria_mt_frame frame;
    exteria_mt_header h;
    exteria_writer plain;
    const uint8_t *body;
    size_t len;
    CHECK_EQ_INT(exteria_mt_transport_next(&f->server, &frame), EXTERIA_OK);
    exteria_writer_init(&plain, 1u << 20);
    CHECK_EQ_INT(exteria_mt_decrypt(&f->client.key, 1, 0, frame.data, frame.len, &plain, &h, &body, &len), EXTERIA_OK);
    if (session_id) *session_id = h.session_id;
    exteria_writer_free(&plain);
    return h.msg_id;
}

static void test_reconnect_services(void) {
    client_fixture f;
    exteria_arena a;
    exteria_tl_value *v;
    exteria_writer w;
    uint64_t id, new_id, session_id, old_session;
    unsigned i;
    fixture_init(&f, 1u << 20);
    exteria_arena_init(&a, 1u << 20);
    exteria_writer_init(&w, 1u << 20);
    id = submit(&f, 80, 0, 0);
    v = exteria_tl_new_obj(&a, "msg_resend_req");
    { int64_t requested = (int64_t)id; CHECK_EQ_INT(exteria_tl_set_i64_vec(&a, v, "msg_ids", &requested, 1), EXTERIA_OK); }
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    for (i = 0; i < 7; ++i) {
        CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + i * 4u, 0, 0), EXTERIA_OK);
        CHECK_EQ_INT(outgoing_id(&f, NULL), id);
    }
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + i * 4u, 0, 0), EXTERIA_OK);
    CHECK_EQ_INT(f.result_status, EXTERIA_E_LIMIT);
    CHECK_EQ_INT(f.client.pending_count, 0);
    id = submit(&f, 81, 0, 10000);
    old_session = f.client.session_id;
    w.len = 0;
    v = exteria_tl_new_obj(&a, "bad_msg_notification");
    CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "bad_msg_id", (int64_t)id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "bad_msg_seqno", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "error_code", 17), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id - (3600ull << 32), 0, 0), EXTERIA_OK);
    new_id = outgoing_id(&f, &session_id);
    CHECK(session_id != old_session);
    CHECK(new_id < id);
    CHECK_EQ_INT(new_id >> 32, (id >> 32) - 3600u);
    w.len = 0;
    v = exteria_tl_new_obj(&a, "bad_server_salt");
    CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "bad_msg_id", (int64_t)new_id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "bad_msg_seqno", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "error_code", 48), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "new_server_salt", 987654321), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id - (3600ull << 32) + 4, 0, 0), EXTERIA_OK);
    CHECK_EQ_INT(outgoing_id(&f, NULL), new_id);
    CHECK_EQ_INT(f.client.salt, 987654321);
    exteria_mt_client_disconnected(&f.client);
    exteria_mt_transport_free(&f.server);
    exteria_mt_transport_init(&f.server);
    CHECK_EQ_INT(exteria_mt_transport_start_server(&f.server, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_client_connect(&f.client), EXTERIA_OK);
    (void)outgoing_id(&f, &session_id);
    CHECK(session_id != old_session);
    exteria_writer_free(&w);
    exteria_arena_free(&a);
    fixture_free(&f);
}

/* a frame the client refuses says which check it failed, so a link that connects and fails at once can be told from the log */
static void test_refusals(void) {
    unsigned mode;
    static const char *const expected[] = {"auth key id", "session id", "message time", "message time", "server salt", "message key"};
    for (mode = 0; mode < 6; ++mode) {
        client_fixture f;
        exteria_mt_auth_key other;
        uint8_t other_bytes[EXTERIA_MT_AUTH_KEY_LEN], body[4];
        const exteria_mt_auth_key *key = &f.client.key;
        uint64_t salt, session_id, msg_id;
        int64_t value = 7;
        const char *note;
        unsigned i;
        fixture_init(&f, 0);
        salt = f.client.salt;
        session_id = f.client.session_id;
        msg_id = f.server_id;
        for (i = 0; i < sizeof(other_bytes); ++i) other_bytes[i] = (uint8_t)(i * 3u + 1u);
        CHECK_EQ_INT(exteria_mt_auth_key_set(&other, other_bytes), EXTERIA_OK);
        exteria_put_u32le(body, EXTERIA_TL_ID_updatesTooLong);
        CHECK(exteria_mt_client_security_note(&f.client, &value) == NULL);
        CHECK_EQ_INT(value, 0);
        if (mode == 0) key = &other;
        if (mode == 1) session_id ^= 1;
        if (mode == 2) msg_id += 3600ull << 32;
        if (mode == 3) msg_id -= 3600ull << 32;
        if (mode == 4) salt ^= 0x55;
        CHECK_EQ_INT(receive_as(&f, key, salt, session_id, body, sizeof(body), msg_id, 1, 0, mode == 5), EXTERIA_E_SECURITY);
        note = exteria_mt_client_security_note(&f.client, &value);
        CHECK(note != NULL && strcmp(note, expected[mode]) == 0);
        /* the gap to the server's clock is kept in milliseconds with its sign; a wrong key or session carries none */
        if (mode == 2) CHECK(value > 3500000 && value < 3700000);
        if (mode == 3) CHECK(value < -3500000 && value > -3700000);
        if (mode == 0 || mode == 1 || mode == 5) CHECK_EQ_INT(value, 0);
        CHECK_EQ_INT(exteria_mt_client_heard(&f.client), 0);
        fixture_free(&f);
    }
}

/* after a pause the stored salt is stale, and the server answers in one container whose salt is the new one, as
   the real one does */
static void test_container_with_new_salt(void) {
    unsigned mode;
    for (mode = 0; mode < 3; ++mode) {
        client_fixture f;
        exteria_arena a;
        exteria_tl_value *v;
        exteria_writer item, w;
        uint8_t other[4];
        int64_t value = 0;
        exteria_status s;
        fixture_init(&f, 0);
        exteria_arena_init(&a, 16384);
        exteria_writer_init(&item, 16384);
        exteria_put_u32le(other, EXTERIA_TL_ID_updatesTooLong);
        if (mode == 0) {
            v = exteria_tl_new_obj(&a, "new_session_created");
            CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "first_msg_id", 1), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "unique_id", 2), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "server_salt", 987654321), EXTERIA_OK);
        } else {
            v = exteria_tl_new_obj(&a, "bad_server_salt");
            CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "bad_msg_id", 1), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "bad_msg_seqno", 1), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "error_code", 48), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "new_server_salt", 987654321), EXTERIA_OK);
        }
        CHECK_EQ_INT(exteria_tl_encode(v, &item, NULL), EXTERIA_OK);
        container_begin(&w, 2);
        container_item(&w, f.server_id, 1, other, sizeof(other));
        if (mode == 2) container_item(&w, f.server_id + 4, 1, other, sizeof(other));
        else container_item(&w, f.server_id + 4, 0, item.data, item.len);
        s = receive_as(&f, &f.client.key, f.client.salt ^ 0x55, f.client.session_id, w.data, w.len, f.server_id + 8, 0, 0, 0);
        if (mode == 2) {
            CHECK_EQ_INT(s, EXTERIA_E_SECURITY);
            CHECK(exteria_mt_client_security_note(&f.client, &value) != NULL);
            CHECK_EQ_INT(exteria_mt_client_heard(&f.client), 0);
        } else {
            CHECK_EQ_INT(s, EXTERIA_OK);
            CHECK_EQ_INT(exteria_mt_client_heard(&f.client), 1);
        }
        exteria_writer_free(&w);
        exteria_writer_free(&item);
        exteria_arena_free(&a);
        fixture_free(&f);
    }
}

/* a link counts as heard once a frame was accepted, and the count starts again with the next connection */
static void test_heard(void) {
    client_fixture f;
    uint8_t body[4];
    fixture_init(&f, 0);
    exteria_put_u32le(body, EXTERIA_TL_ID_updatesTooLong);
    CHECK_EQ_INT(exteria_mt_client_heard(&f.client), 0);
    CHECK_EQ_INT(receive(&f, body, sizeof(body), f.server_id, 1, 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_client_heard(&f.client), 1);
    CHECK_EQ_INT(exteria_mt_client_heard(NULL), 0);
    CHECK(exteria_mt_client_security_note(NULL, NULL) == NULL);
    exteria_mt_client_disconnected(&f.client);
    exteria_mt_transport_free(&f.server);
    exteria_mt_transport_init(&f.server);
    CHECK_EQ_INT(exteria_mt_transport_start_server(&f.server, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_client_connect(&f.client), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_client_heard(&f.client), 0);
    fixture_free(&f);
}

/* the server's clock differs from the one the client has, as when the phone's clock moved after the offset was
   stored */
static void test_clock_correction(void) {
    client_fixture f;
    exteria_arena a;
    exteria_writer w;
    exteria_tl_value *v;
    uint64_t first, container, session_id;
    int64_t offset;
    fixture_init(&f, 1u << 20);
    exteria_arena_init(&a, 1u << 20);
    exteria_writer_init(&w, 1u << 20);
    first = submit(&f, 95, 0, 0);
    (void)submit(&f, 96, 0, 0);

    /* an hour of difference, named for a message that waits for its answer */
    v = exteria_tl_new_obj(&a, "bad_msg_notification");
    CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "bad_msg_id", (int64_t)first), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "bad_msg_seqno", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "error_code", 16), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + (3600ull << 32), 0, 0), EXTERIA_OK);
    offset = f.client.time_offset_ms;
    CHECK(offset > 3599000 && offset < 3601000);

    /* both requests go out again in one container, and that is the id the server then complains about */
    container = outgoing_id(&f, &session_id);
    CHECK(container != first);
    w.len = 0;
    v = exteria_tl_new_obj(&a, "bad_msg_notification");
    CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "bad_msg_id", (int64_t)container), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "bad_msg_seqno", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "error_code", 16), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + (7200ull << 32), 0, 0), EXTERIA_OK);
    CHECK(f.client.time_offset_ms > 7199000 && f.client.time_offset_ms < 7201000);

    /* the same complaint about an id that was never sent is refused */
    w.len = 0;
    v = exteria_tl_new_obj(&a, "bad_msg_notification");
    CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "bad_msg_id", (int64_t)(first + 8)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "bad_msg_seqno", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "error_code", 16), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    CHECK_EQ_INT(receive(&f, w.data, w.len, f.server_id + (14400ull << 32), 0, 0), EXTERIA_E_SECURITY);
    CHECK(exteria_mt_client_security_note(&f.client, NULL) != NULL);
    exteria_writer_free(&w);
    exteria_arena_free(&a);
    fixture_free(&f);
}

static exteria_status failed_send(void *ctx, const uint8_t *data, size_t len) {
    (void)ctx; (void)data; (void)len;
    return EXTERIA_E_IO;
}

static void test_teardown_and_send_error(void) {
    client_fixture f;
    exteria_arena a;
    exteria_tl_value *request;
    uint8_t rpc[16];
    uint64_t id;
    fixture_init(&f, 1u << 20);
    id = submit(&f, 90, 0, 10000);
    f.free_on_result = 1;
    exteria_put_u32le(rpc, EXTERIA_TL_ID_rpc_result);
    exteria_put_u64le(rpc + 4, id);
    exteria_put_u32le(rpc + 12, EXTERIA_TL_ID_boolTrue);
    CHECK_EQ_INT(receive(&f, rpc, sizeof(rpc), f.server_id, 1, 0), EXTERIA_E_STATE);
    CHECK_EQ_INT(f.results, 1);
    CHECK_EQ_INT(f.client.pending_count, 0);
    fixture_free(&f);
    fixture_init(&f, 1u << 20);
    f.client.events.send_checked = failed_send;
    exteria_arena_init(&a, 65536);
    request = exteria_tl_new_obj(&a, "account.updateStatus");
    CHECK_EQ_INT(exteria_tl_set(request, "offline", exteria_tl_new_obj(&a, "boolFalse")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_client_submit(&f.client, 92, request, 1000), EXTERIA_E_IO);
    CHECK_EQ_INT(f.client.state, EXTERIA_MT_CLIENT_DEAD);
    CHECK_EQ_INT(f.state_reason, EXTERIA_E_IO);
    CHECK_EQ_INT(exteria_mt_client_submit(&f.client, 93, request, 1000), EXTERIA_E_STATE);
    exteria_arena_free(&a);
    fixture_free(&f);
    fixture_init(&f, 1u << 20);
    { uint8_t body[4]; exteria_put_u32le(body, EXTERIA_TL_ID_updatesTooLong);
      CHECK_EQ_INT(receive(&f, body, 4, f.server_id - (301ull << 32), 0, 0), EXTERIA_E_SECURITY); }
    fixture_free(&f);
}

int main(void) {
    test_reconnect_services();
    test_teardown_and_send_error();
    test_rpc_gzip();
    test_rpc_error();
    test_container();
    test_bad_container();
    test_refusals();
    test_container_with_new_salt();
    test_heard();
    test_clock_correction();
    test_gzip_limits();
    test_gzip_content_message();
    test_replay_window();
    test_timeout_cancel();
    test_ping_interval();
    test_state_request();
    test_receive_errors();
    test_unpack_limits();
    return test_finish("test_mt_client");
}
