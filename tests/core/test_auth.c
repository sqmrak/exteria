#include "test_util.h"
#include "exteria_auth.h"
#include "exteria_tl_ids.h"

typedef struct fixture {
    exteria_auth auth;
    exteria_clock clock;
    uint64_t time;
    uint64_t wall_time;
    uint64_t id;
    uint32_t method;
    unsigned submits;
    unsigned cancels;
    unsigned changes;
    exteria_status send_status;
} fixture;

static uint64_t clock_now(void *ctx) { return ((fixture *)ctx)->time; }
static uint64_t clock_wall(void *ctx) {
    fixture *f = ctx;
    return f->wall_time ? f->wall_time : f->time;
}
static exteria_status submit(void *ctx, uint64_t id, const exteria_tl_value *v) {
    fixture *f = ctx;
    exteria_writer w;
    f->id = id;
    f->method = exteria_tl_id(v);
    ++f->submits;
    exteria_writer_init(&w, 256u * 1024u);
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    exteria_writer_free(&w);
    return f->send_status;
}
static void cancel(void *ctx, uint64_t id) {
    fixture *f = ctx;
    CHECK(id > 0);
    ++f->cancels;
}
static void change(void *ctx, exteria_auth_state s, exteria_status status, const exteria_tl_value *v, const char *e) {
    fixture *f = ctx;
    (void)status; (void)v; (void)e;
    CHECK_EQ_INT(f->auth.state, s);
    ++f->changes;
}
static void init(fixture *f) {
    exteria_auth_events events;
    memset(f, 0, sizeof(*f));
    f->time = 100000;
    f->clock.realtime_ms = clock_wall;
    f->clock.monotonic_ms = clock_now;
    f->clock.ctx = f;
    events.ctx = f; events.submit = submit; events.cancel = cancel; events.changed = change;
    CHECK_EQ_INT(exteria_auth_init(&f->auth, 12345, "0123456789abcdef0123456789abcdef", &f->clock, &events), EXTERIA_OK);
}
static exteria_status result(fixture *f, const exteria_tl_value *v, const char *error) {
    exteria_mt_rpc_result r;
    memset(&r, 0, sizeof(r));
    r.value = v;
    r.status = error ? EXTERIA_E_RPC : EXTERIA_OK;
    r.error_code = error ? 400 : 0;
    r.error_text = error;
    return exteria_auth_result(&f->auth, f->id, &r);
}
static exteria_tl_value *sent(exteria_arena *a, const char *delivery) {
    exteria_tl_value *v = exteria_tl_new_obj(a, "auth.sentCode");
    exteria_tl_value *type = exteria_tl_new_obj(a, delivery);
    CHECK_EQ_INT(exteria_tl_set_i32(a, type, "length", 5), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(v, "type", type), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(a, v, "phone_code_hash", "opaque-hash"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(v, "next_type", exteria_tl_new_obj(a, "auth.codeTypeSms")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "timeout", 30), EXTERIA_OK);
    return v;
}

static void test_phone(void) {
    fixture f;
    exteria_arena a;
    exteria_tl_value *v;
    exteria_mt_rpc_result stale;
    uint64_t old;
    init(&f);
    exteria_arena_init(&a, 1024u * 1024u);
    CHECK_EQ_INT(exteria_auth_phone(&f.auth, "+79991234567", NULL), EXTERIA_OK);
    CHECK_EQ_INT(f.method, EXTERIA_TL_ID_auth_sendCode);
    CHECK_EQ_INT(result(&f, NULL, "PHONE_MIGRATE_4"), EXTERIA_OK);
    CHECK_EQ_INT(f.auth.state, EXTERIA_AUTH_MIGRATE);
    CHECK_EQ_INT(f.auth.migrate_dc, 4);
    CHECK_EQ_INT(exteria_auth_resume(&f.auth), EXTERIA_OK);
    CHECK_EQ_INT(result(&f, sent(&a, "auth.sentCodeTypeSms"), NULL), EXTERIA_OK);
    CHECK_EQ_INT(f.auth.state, EXTERIA_AUTH_CODE);
    CHECK_EQ_INT(exteria_auth_resend(&f.auth, NULL), EXTERIA_E_STATE);
    f.time += 30000;
    CHECK_EQ_INT(exteria_auth_resend(&f.auth, "SMS"), EXTERIA_OK);
    CHECK_EQ_INT(result(&f, sent(&a, "auth.sentCodeTypeApp"), NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_auth_code(&f.auth, "12345", NULL), EXTERIA_OK);
    CHECK_EQ_INT(result(&f, NULL, "PHONE_CODE_INVALID"), EXTERIA_E_RPC);
    CHECK_EQ_INT(f.auth.state, EXTERIA_AUTH_CODE);
    CHECK_EQ_INT(exteria_auth_code(&f.auth, "54321", NULL), EXTERIA_OK);
    CHECK_EQ_INT(result(&f, NULL, "FLOOD_WAIT_17"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_auth_resume(&f.auth), EXTERIA_E_RETRY);
    f.time += 17000;
    CHECK_EQ_INT(exteria_auth_resume(&f.auth), EXTERIA_OK);
    v = exteria_tl_new_obj(&a, "auth.authorizationSignUpRequired");
    CHECK_EQ_INT(result(&f, v, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_auth_signup(&f.auth, "Name", "Last"), EXTERIA_OK);
    CHECK_EQ_INT(f.method, EXTERIA_TL_ID_auth_signUp);
    old = f.id;
    exteria_auth_cancel(&f.auth);
    memset(&stale, 0, sizeof(stale));
    stale.value = exteria_tl_new_obj(&a, "auth.authorization");
    CHECK_EQ_INT(exteria_auth_result(&f.auth, old, &stale), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(f.auth.state, EXTERIA_AUTH_IDLE);
    CHECK_EQ_INT(exteria_auth_phone(&f.auth, "+79991234568", NULL), EXTERIA_OK);
    f.time += 60000;
    CHECK_EQ_INT(exteria_auth_tick(&f.auth), EXTERIA_E_TIMEOUT);
    CHECK_EQ_INT(f.auth.state, EXTERIA_AUTH_IDLE);
    CHECK_EQ_INT(exteria_auth_phone(&f.auth, "+7999;1234", NULL), EXTERIA_E_ARG);
    f.send_status = EXTERIA_E_IO;
    CHECK_EQ_INT(exteria_auth_phone(&f.auth, "+79991234568", NULL), EXTERIA_E_IO);
    CHECK_EQ_INT(f.auth.pending, 0);
    exteria_auth_free(&f.auth);
    exteria_arena_free(&a);
}

static void test_qr(void) {
    fixture f;
    exteria_arena a;
    exteria_tl_value *v;
    char url[128];
    const uint8_t token[] = {0xff, 0xef, 0x11, 0xaa, 0x55};
    init(&f);
    exteria_arena_init(&a, 1024u * 1024u);
    CHECK_EQ_INT(exteria_auth_next_ms(&f.auth), UINT32_MAX);
    CHECK_EQ_INT(exteria_auth_qr(&f.auth, NULL, 0), EXTERIA_OK);
    /* the request waits sixty seconds for its answer */
    CHECK_EQ_INT(exteria_auth_next_ms(&f.auth), 60000);
    v = exteria_tl_new_obj(&a, "auth.loginToken");
    CHECK_EQ_INT(exteria_tl_set_bytes(&a, v, "token", token, sizeof(token)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "expires", 130), EXTERIA_OK);
    CHECK_EQ_INT(result(&f, v, NULL), EXTERIA_OK);
    /* the token ends at 130 s of a clock that stands at 100 s */
    CHECK_EQ_INT(exteria_auth_next_ms(&f.auth), 30000);
    CHECK_EQ_INT(exteria_auth_qr_url(v, url, sizeof(url)), EXTERIA_OK);
    CHECK(!strcmp(url, "tg://login?token=_-8RqlU"));
    CHECK_EQ_INT(exteria_auth_qr_url(v, url, 20), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(url[0], 0);
    f.time = 130000;
    CHECK_EQ_INT(exteria_auth_next_ms(&f.auth), 0);
    CHECK_EQ_INT(exteria_auth_tick(&f.auth), EXTERIA_OK);
    CHECK_EQ_INT(f.method, EXTERIA_TL_ID_auth_exportLoginToken);
    v = exteria_tl_new_obj(&a, "auth.loginTokenMigrateTo");
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "dc_id", 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&a, v, "token", token, sizeof(token)), EXTERIA_OK);
    CHECK_EQ_INT(result(&f, v, NULL), EXTERIA_OK);
    CHECK_EQ_INT(f.auth.state, EXTERIA_AUTH_MIGRATE);
    CHECK_EQ_INT(exteria_auth_resume(&f.auth), EXTERIA_OK);
    CHECK_EQ_INT(f.method, EXTERIA_TL_ID_auth_importLoginToken);
    CHECK_EQ_INT(result(&f, NULL, "SESSION_PASSWORD_NEEDED"), EXTERIA_OK);
    CHECK_EQ_INT(f.method, EXTERIA_TL_ID_account_getPassword);
    CHECK_EQ_INT(result(&f, NULL, "FLOOD_WAIT_1"), EXTERIA_OK);
    f.time += 1000;
    CHECK_EQ_INT(exteria_auth_resume(&f.auth), EXTERIA_OK);
    exteria_auth_free(&f.auth);
    exteria_arena_free(&a);
}

static void test_qr_clock_and_pending(void) {
    fixture f;
    exteria_arena a;
    init(&f);
    f.wall_time = 3700000;
    f.auth.server_time_offset_ms = -3600000;
    exteria_arena_init(&a, 1024u * 1024u);
    exteria_tl_value *v = exteria_tl_new_obj(&a, "auth.loginToken");
    const uint8_t token[] = {1, 2, 3};
    CHECK_EQ_INT(exteria_tl_set_bytes(&a, v, "token", token, sizeof(token)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "expires", 130), EXTERIA_OK);
    CHECK_EQ_INT(exteria_auth_qr(&f.auth, NULL, 0), EXTERIA_OK);
    CHECK_EQ_INT(result(&f, v, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_auth_next_ms(&f.auth), 30000);
    f.wall_time += 7200000;
    CHECK_EQ_INT(exteria_auth_next_ms(&f.auth), 30000);
    f.time += 30000;
    CHECK_EQ_INT(exteria_auth_tick(&f.auth), EXTERIA_OK);
    unsigned submitted = f.submits;
    CHECK_EQ_INT(exteria_auth_next_ms(&f.auth), 60000);
    for (int i = 0; i < 20; ++i) CHECK_EQ_INT(exteria_auth_tick(&f.auth), EXTERIA_OK);
    CHECK_EQ_INT(f.submits, submitted);
    CHECK_EQ_INT(f.auth.qr_refresh, 0);
    CHECK_EQ_INT(result(&f, v, NULL), EXTERIA_OK);
    CHECK_EQ_INT(f.submits, submitted);
    CHECK_EQ_INT(exteria_auth_next_ms(&f.auth), 1000);
    exteria_arena_free(&a);
    exteria_auth_free(&f.auth);
}

int main(void) {
    test_phone();
    test_qr();
    test_qr_clock_and_pending();
    return test_finish("test_auth");
}
