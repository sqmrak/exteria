#include "test_util.h"

#include "exteria_crypto.h"
#include "exteria_mt_handshake.h"
#include "fake_mt_server.h"

typedef struct fixed_clock {
    uint64_t now_ms;
} fixed_clock;

static uint64_t fixed_realtime(void *ctx) {
    return ((fixed_clock *)ctx)->now_ms;
}

static uint64_t fixed_monotonic(void *ctx) {
    return ((fixed_clock *)ctx)->now_ms;
}

static exteria_status run_exchange(fake_mt_server *srv, exteria_mt_handshake *hs, exteria_writer *c2s, exteria_writer *s2c,
                                   int *server_status) {
    exteria_status s = exteria_mt_hs_start(hs, c2s);
    int guard;
    *server_status = EXTERIA_OK;
    for (guard = 0; guard < 16 && s == EXTERIA_OK; ++guard) {
        if (hs->state == EXTERIA_MT_HS_DONE) return EXTERIA_OK;
        s2c->len = 0;
        *server_status = fake_mt_server_handshake(srv, c2s->data, c2s->len, s2c);
        if (*server_status != EXTERIA_OK) return EXTERIA_E_STATE;
        c2s->len = 0;
        s = exteria_mt_hs_receive(hs, s2c->data, s2c->len, 0, c2s);
    }
    return s;
}

static fake_mt_server g_srv;

static void setup(exteria_mt_handshake *hs, fixed_clock *clk, exteria_clock *ck, fake_hs_mode mode) {
    exteria_mt_hs_config cfg;
    memset(&g_srv.mode, 0, sizeof(g_srv.mode));
    g_srv.mode = mode;
    g_srv.retries_left = 1;
    clk->now_ms = (uint64_t)g_srv.server_time * 1000u - 4200u;
    ck->realtime_ms = fixed_realtime;
    ck->monotonic_ms = fixed_monotonic;
    ck->ctx = clk;
    memset(&cfg, 0, sizeof(cfg));
    cfg.dc_id = 2;
    cfg.is_test = 1;
    cfg.keys = &g_srv.key;
    cfg.key_count = 1;
    cfg.clock = ck;
    g_srv.dc_expected = 10002;
    exteria_mt_hs_init(hs, &cfg);
}

static void test_success(void) {
    exteria_mt_handshake hs;
    fixed_clock clk;
    exteria_clock ck;
    exteria_writer c2s, s2c;
    int ss;
    const exteria_mt_hs_result *r;
    exteria_writer_init(&c2s, 1 << 16);
    exteria_writer_init(&s2c, 1 << 16);
    setup(&hs, &clk, &ck, FAKE_HS_NORMAL);
    CHECK_EQ_INT(run_exchange(&g_srv, &hs, &c2s, &s2c, &ss), EXTERIA_OK);
    r = exteria_mt_hs_result_get(&hs);
    CHECK(r != NULL);
    if (r) {
        CHECK_MEM(r->key.key, g_srv.auth_key.key, 256);
        CHECK(r->key.id == g_srv.auth_key.id);
        CHECK(r->server_salt == g_srv.salt);
        CHECK(r->time_offset_ms == 4200);
    }
    /* completing dh must erase the private exponent and handshake nonces */
    {
        uint8_t zero[256] = { 0 };
        CHECK_MEM(hs.auth_key, zero, 256);
        CHECK_MEM(hs.new_nonce, zero, 32);
    }
    CHECK_EQ_INT(exteria_mt_hs_start(&hs, &c2s), EXTERIA_E_STATE);
    exteria_writer_free(&c2s);
    exteria_writer_free(&s2c);
}

static void test_retry(void) {
    exteria_mt_handshake hs;
    fixed_clock clk;
    exteria_clock ck;
    exteria_writer c2s, s2c;
    int ss;
    exteria_writer_init(&c2s, 1 << 16);
    exteria_writer_init(&s2c, 1 << 16);
    setup(&hs, &clk, &ck, FAKE_HS_RETRY_ONCE);
    CHECK_EQ_INT(run_exchange(&g_srv, &hs, &c2s, &s2c, &ss), EXTERIA_OK);
    CHECK_EQ_INT(hs.attempts, 1);
    CHECK(exteria_mt_hs_result_get(&hs) != NULL);
    setup(&hs, &clk, &ck, FAKE_HS_ALWAYS_RETRY);
    CHECK_EQ_INT(run_exchange(&g_srv, &hs, &c2s, &s2c, &ss), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(hs.state, EXTERIA_MT_HS_FAILED);
    CHECK(exteria_mt_hs_result_get(&hs) == NULL);
    setup(&hs, &clk, &ck, FAKE_HS_FAIL);
    CHECK_EQ_INT(run_exchange(&g_srv, &hs, &c2s, &s2c, &ss), EXTERIA_E_LIMIT);
    exteria_writer_free(&c2s);
    exteria_writer_free(&s2c);
}

static void test_attacks(void) {
    static const struct { fake_hs_mode mode; exteria_status want; } cases[] = {
        { FAKE_HS_BAD_SERVER_NONCE, EXTERIA_E_SECURITY },
        { FAKE_HS_BAD_NEW_NONCE_HASH, EXTERIA_E_SECURITY },
        { FAKE_HS_COMPOSITE_PRIME, EXTERIA_E_SECURITY },
        { FAKE_HS_SMALL_GA, EXTERIA_E_SECURITY },
        { FAKE_HS_PARAMS_FAIL, EXTERIA_E_SECURITY },
        { FAKE_HS_PRIME_PQ, EXTERIA_E_MALFORMED },
        { FAKE_HS_UNKNOWN_KEY, EXTERIA_E_UNSUPPORTED },
    };
    unsigned i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        exteria_mt_handshake hs;
        fixed_clock clk;
        exteria_clock ck;
        exteria_writer c2s, s2c;
        int ss;
        exteria_status s;
        exteria_writer_init(&c2s, 1 << 16);
        exteria_writer_init(&s2c, 1 << 16);
        setup(&hs, &clk, &ck, cases[i].mode);
        s = run_exchange(&g_srv, &hs, &c2s, &s2c, &ss);
        if (s != cases[i].want) fprintf(stderr, "case %u: got %d, wanted %d\n", i, (int)s, (int)cases[i].want);
        CHECK_EQ_INT(s, cases[i].want);
        CHECK_EQ_INT(hs.state, EXTERIA_MT_HS_FAILED);
        CHECK(exteria_mt_hs_result_get(&hs) == NULL);
        exteria_writer_free(&c2s);
        exteria_writer_free(&s2c);
    }
}

static void test_garbage_replies(void) {
    exteria_mt_handshake hs;
    fixed_clock clk;
    exteria_clock ck;
    exteria_writer c2s, junk;
    uint8_t body[8] = { 0x78, 0x56, 0x34, 0x12, 0, 0, 0, 0 };
    exteria_writer_init(&c2s, 1 << 16);
    exteria_writer_init(&junk, 1 << 12);
    setup(&hs, &clk, &ck, FAKE_HS_NORMAL);
    CHECK_EQ_INT(exteria_mt_hs_receive(&hs, junk.data, 0, 0, &c2s), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_mt_hs_start(&hs, &c2s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_plain_wrap(1, body, 8, &junk), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_hs_receive(&hs, junk.data, junk.len, 0, &c2s), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(hs.state, EXTERIA_MT_HS_FAILED);
    CHECK_EQ_INT(exteria_mt_hs_receive(&hs, junk.data, junk.len, 0, &c2s), EXTERIA_E_STATE);
    /* accepting an even id would admit a client message as a server reply */
    junk.len = 0;
    setup(&hs, &clk, &ck, FAKE_HS_NORMAL);
    CHECK_EQ_INT(exteria_mt_hs_start(&hs, &c2s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_plain_wrap(2, body, 8, &junk), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_hs_receive(&hs, junk.data, junk.len, 0, &c2s), EXTERIA_E_MALFORMED);
    exteria_writer_free(&c2s);
    exteria_writer_free(&junk);
}

static void test_rsa_pad_roundtrip(void) {
    uint8_t out[256], data[100];
    size_t i;
    exteria_mt_rsa_key key = g_srv.key;
    for (i = 0; i < sizeof(data); ++i) data[i] = (uint8_t)i;
    CHECK_EQ_INT(exteria_mt_rsa_pad_encrypt(&key, data, sizeof(data), out), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_rsa_pad_encrypt(&key, data, 145, out), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_mt_rsa_pad_encrypt(&key, data, 0, out), EXTERIA_E_ARG);
}

int main(void) {
    if (fake_mt_server_init(&g_srv) != 0) {
        fprintf(stderr, "fake server init failed\n");
        return 1;
    }
    test_success();
    test_retry();
    test_attacks();
    test_garbage_replies();
    test_rsa_pad_roundtrip();
    fake_mt_server_free(&g_srv);
    return test_finish("test_mt_handshake");
}
