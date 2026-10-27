#include "exteria_crypto.h"
#include "exteria_tgc_turn.h"
#include "fake_turn.h"
#include "test_util.h"


/* delivers what the client sent to the server and what the server answers back, until nothing moves */
static void run(exteria_tgc_turn *t, client_side *c, server *s, uint64_t now) {
    size_t done = 0;
    int rounds;
    for (rounds = 0; rounds < 12; ++rounds) {
        size_t i, end = c->count;
        for (i = done; i < end; ++i) {
            wbuf w;
            if (server_answer(s, c->out[i].data, c->out[i].len, &w)) {
                exteria_tgc_turn_output o;
                CHECK(exteria_tgc_turn_input(t, w.b, w.len, now, &o) == EXTERIA_OK);
            }
        }
        done = end;
        if (c->count == done) break;
    }
}

static void init_pair(exteria_tgc_turn *t, client_side *c, server *s) {
    exteria_tgc_turn_events ev;
    memset(c, 0, sizeof(*c));
    ev.context = c;
    ev.send = on_send;
    ev.trace = on_trace;
    server_init(s);
    CHECK_EQ_INT(exteria_tgc_turn_init(t, SERVER_IP, SERVER_PORT, "reflector", "s3cret-pass", &ev), EXTERIA_OK);
}

static void allocation_with_challenge(void) {
    exteria_tgc_turn t;
    client_side c;
    server s;
    uint32_t relay, mapped;
    uint16_t relay_port, mapped_port;
    init_pair(&t, &c, &s);
    CHECK_EQ_INT(exteria_tgc_turn_ready(&t), 0);
    exteria_tgc_turn_tick(&t, 1000);
    CHECK_EQ_INT(c.count, 1);
    /* the first request carries no credentials: only the transport, UDP */
    CHECK(find_attr(c.out[0].data, c.out[0].len, 0x0006, NULL) == NULL);
    {
        size_t l = 0;
        const uint8_t *transport = find_attr(c.out[0].data, c.out[0].len, 0x0019, &l);
        CHECK(transport != NULL && l == 4 && transport[0] == 17);
    }
    run(&t, &c, &s, 1000);
    CHECK_EQ_INT(s.challenges, 1);
    CHECK_EQ_INT(s.allocations, 1);
    CHECK_EQ_INT(s.bad_integrity, 0);
    CHECK_EQ_INT(exteria_tgc_turn_ready(&t), 1);
    CHECK_EQ_INT(exteria_tgc_turn_relayed(&t, &relay, &relay_port, &mapped, &mapped_port), 1);
    CHECK_EQ_INT(relay, RELAY_IP);
    CHECK_EQ_INT(relay_port, RELAY_PORT);
    CHECK_EQ_INT(mapped, MAPPED_IP);
    CHECK_EQ_INT(mapped_port, MAPPED_PORT);
    /* the second request names the realm and the nonce the server gave */
    {
        size_t l = 0;
        const uint8_t *realm = find_attr(s.last_request, s.last_request_len, 0x0014, &l);
        CHECK(realm != NULL && l == strlen(s.realm) && memcmp(realm, s.realm, l) == 0);
        {
            const uint8_t *nonce = find_attr(s.last_request, s.last_request_len, 0x0015, &l);
            CHECK(nonce != NULL && l == strlen(s.nonce) && memcmp(nonce, s.nonce, l) == 0);
        }
    }
}

static void wrong_password_fails(void) {
    exteria_tgc_turn t;
    client_side c;
    server s;
    exteria_tgc_turn_events ev;
    memset(&c, 0, sizeof(c));
    ev.context = &c;
    ev.send = on_send;
    ev.trace = on_trace;
    server_init(&s);
    CHECK_EQ_INT(exteria_tgc_turn_init(&t, SERVER_IP, SERVER_PORT, "reflector", "not-the-password", &ev), EXTERIA_OK);
    exteria_tgc_turn_tick(&t, 1000);
    run(&t, &c, &s, 1000);
    CHECK_EQ_INT(t.state, EXTERIA_TGC_TURN_FAILED);
    CHECK(s.bad_integrity >= 1);
    CHECK_EQ_INT(exteria_tgc_turn_ready(&t), 0);
}

static void permissions_and_sending(void) {
    exteria_tgc_turn t;
    client_side c;
    server s;
    uint8_t out[1400], payload[1200];
    size_t n = 0, i;
    init_pair(&t, &c, &s);
    exteria_tgc_turn_tick(&t, 1000);
    run(&t, &c, &s, 1000);
    CHECK_EQ_INT(exteria_tgc_turn_ready(&t), 1);

    CHECK_EQ_INT(exteria_tgc_turn_permit(&t, PEER_IP), 0);
    exteria_tgc_turn_tick(&t, 1050);
    run(&t, &c, &s, 1050);
    CHECK_EQ_INT(s.permissions, 1);
    CHECK_EQ_INT(s.last_permission_ip, PEER_IP);
    CHECK_EQ_INT(exteria_tgc_turn_permit(&t, PEER_IP), 1);

    for (i = 0; i < sizeof(payload); ++i) payload[i] = (uint8_t)(i * 5 + 1);
    CHECK_EQ_INT(exteria_tgc_turn_wrap(&t, PEER_IP, PEER_PORT, payload, sizeof(payload), out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, sizeof(payload) + EXTERIA_TGC_TURN_WRAP_OVERHEAD);
    {
        wbuf w;
        CHECK_EQ_INT(server_answer(&s, out, n, &w), 0);
    }
    CHECK_EQ_INT(s.send_indications, 1);
    CHECK_EQ_INT(s.last_peer_ip, PEER_IP);
    CHECK_EQ_INT(s.last_peer_port, PEER_PORT);
    CHECK_EQ_INT(s.last_data_len, sizeof(payload));
    CHECK_MEM(s.last_data, payload, sizeof(payload));

    CHECK_EQ_INT(exteria_tgc_turn_wrap(&t, PEER_IP, PEER_PORT, payload, sizeof(payload) + 1, out, sizeof(out), &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_turn_wrap(&t, PEER_IP, PEER_PORT, payload, 10, out, 40, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_turn_wrap(&t, PEER_IP, PEER_PORT, payload, 0, out, sizeof(out), &n), EXTERIA_E_ARG);
}

static void wrap_needs_an_allocation(void) {
    exteria_tgc_turn t;
    client_side c;
    server s;
    uint8_t out[200], data[4] = {1, 2, 3, 4};
    size_t n = 5;
    init_pair(&t, &c, &s);
    CHECK_EQ_INT(exteria_tgc_turn_wrap(&t, PEER_IP, PEER_PORT, data, sizeof(data), out, sizeof(out), &n), EXTERIA_E_STATE);
    CHECK_EQ_INT(n, 0);
}

static void data_indications(void) {
    exteria_tgc_turn t;
    client_side c;
    server s;
    wbuf w;
    uint8_t txid[12] = {9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2}, body[100];
    exteria_tgc_turn_output o;
    size_t i;
    init_pair(&t, &c, &s);
    for (i = 0; i < sizeof(body); ++i) body[i] = (uint8_t)(255 - i);
    wbegin(&w, 0x0017, txid);
    wxor(&w, 0x0012, PEER_IP, PEER_PORT);
    wattr(&w, 0x0013, body, sizeof(body));
    wfinish(&w, NULL);
    CHECK_EQ_INT(exteria_tgc_turn_input(&t, w.b, w.len, 5, &o), EXTERIA_OK);
    CHECK_EQ_INT(o.kind, EXTERIA_TGC_TURN_INPUT_DATA);
    CHECK_EQ_INT(o.peer_ip, PEER_IP);
    CHECK_EQ_INT(o.peer_port, PEER_PORT);
    CHECK_EQ_INT(o.len, sizeof(body));
    CHECK_MEM(o.data, body, sizeof(body));

    /* without a peer address or without data there is nothing to give on */
    wbegin(&w, 0x0017, txid);
    wattr(&w, 0x0013, body, 4);
    wfinish(&w, NULL);
    CHECK_EQ_INT(exteria_tgc_turn_input(&t, w.b, w.len, 5, &o), EXTERIA_OK);
    CHECK_EQ_INT(o.kind, EXTERIA_TGC_TURN_INPUT_NONE);
    wbegin(&w, 0x0017, txid);
    wxor(&w, 0x0012, PEER_IP, PEER_PORT);
    wfinish(&w, NULL);
    CHECK_EQ_INT(exteria_tgc_turn_input(&t, w.b, w.len, 5, &o), EXTERIA_OK);
    CHECK_EQ_INT(o.kind, EXTERIA_TGC_TURN_INPUT_NONE);
}

static void stale_nonce_is_retried(void) {
    exteria_tgc_turn t;
    client_side c;
    server s;
    init_pair(&t, &c, &s);
    exteria_tgc_turn_tick(&t, 1000);
    run(&t, &c, &s, 1000);
    CHECK_EQ_INT(exteria_tgc_turn_ready(&t), 1);
    s.stale_next = 1;
    CHECK_EQ_INT(exteria_tgc_turn_permit(&t, PEER_IP), 0);
    exteria_tgc_turn_tick(&t, 1100);
    run(&t, &c, &s, 1100);
    CHECK_EQ_INT(s.permissions, 1);
    CHECK_EQ_INT(exteria_tgc_turn_permit(&t, PEER_IP), 1);
    CHECK_EQ_INT(exteria_tgc_turn_ready(&t), 1);
}

static void retransmission_and_giving_up(void) {
    exteria_tgc_turn t;
    client_side c;
    server s;
    uint64_t now = 1000;
    size_t i, first_count;
    uint8_t first[600], second[600];
    size_t first_len, second_len;
    init_pair(&t, &c, &s);
    s.silent = 1;
    exteria_tgc_turn_tick(&t, now);
    CHECK_EQ_INT(c.count, 1);
    memcpy(first, c.out[0].data, c.out[0].len);
    first_len = c.out[0].len;
    first_count = c.count;
    /* before the retransmission time nothing is sent again; then the same message, same transaction id */
    exteria_tgc_turn_tick(&t, now + 100);
    CHECK_EQ_INT(c.count, first_count);
    exteria_tgc_turn_tick(&t, now + 600);
    CHECK_EQ_INT(c.count, 2);
    memcpy(second, c.out[1].data, c.out[1].len);
    second_len = c.out[1].len;
    CHECK_EQ_INT(first_len, second_len);
    CHECK_MEM(first, second, first_len);
    now += 600;
    for (i = 0; i < 40 && t.state != EXTERIA_TGC_TURN_FAILED; ++i) {
        now += 9000;
        exteria_tgc_turn_tick(&t, now);
    }
    CHECK_EQ_INT(t.state, EXTERIA_TGC_TURN_FAILED);
    CHECK(c.count <= 8);
}

static void malformed_input(void) {
    exteria_tgc_turn t;
    client_side c;
    server s;
    wbuf w;
    uint8_t txid[12] = {0}, junk[40] = {0};
    exteria_tgc_turn_output o;
    init_pair(&t, &c, &s);
    CHECK_EQ_INT(exteria_tgc_turn_input(&t, junk, 10, 1, &o), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_turn_input(&t, junk, 20, 1, &o), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(o.kind, EXTERIA_TGC_TURN_INPUT_NONE);
    wbegin(&w, 0x0017, txid);
    wattr(&w, 0x0013, "abcd", 4);
    wfinish(&w, NULL);
    w.b[3] = 99;
    CHECK_EQ_INT(exteria_tgc_turn_input(&t, w.b, w.len, 1, &o), EXTERIA_E_MALFORMED);
    /* an answer to a transaction that is not ours */
    wbegin(&w, 0x0103, txid);
    wfinish(&w, NULL);
    CHECK_EQ_INT(exteria_tgc_turn_input(&t, w.b, w.len, 1, &o), EXTERIA_OK);
    CHECK_EQ_INT(o.kind, EXTERIA_TGC_TURN_INPUT_NONE);
    CHECK_EQ_INT(exteria_tgc_turn_input(NULL, w.b, w.len, 1, &o), EXTERIA_E_ARG);
}

static void forged_success_is_refused(void) {
    exteria_tgc_turn t;
    client_side c;
    server s;
    wbuf w;
    exteria_tgc_turn_output o;
    init_pair(&t, &c, &s);
    exteria_tgc_turn_tick(&t, 1000);
    /* the challenge is genuine, the allocation that follows is answered by someone who does not know the key */
    {
        wbuf ch;
        server_answer(&s, c.out[0].data, c.out[0].len, &ch);
        CHECK_EQ_INT(exteria_tgc_turn_input(&t, ch.b, ch.len, 1000, &o), EXTERIA_OK);
    }
    CHECK_EQ_INT(c.count, 2);
    {
        uint8_t wrong_key[16];
        memset(wrong_key, 7, sizeof(wrong_key));
        wbegin(&w, 0x0103, c.out[1].data + 8);
        wxor(&w, 0x0016, 0x01020304u, 4000);
        wfinish(&w, wrong_key);
    }
    CHECK_EQ_INT(exteria_tgc_turn_input(&t, w.b, w.len, 1001, &o), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_tgc_turn_ready(&t), 0);
}

static void init_refusals(void) {
    exteria_tgc_turn t;
    client_side c;
    exteria_tgc_turn_events ev;
    ev.context = &c;
    ev.send = on_send;
    ev.trace = NULL;
    CHECK_EQ_INT(exteria_tgc_turn_init(NULL, 1, 1, "a", "b", &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_turn_init(&t, 0, 1, "a", "b", &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_turn_init(&t, 1, 0, "a", "b", &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_turn_init(&t, 1, 1, "", "b", &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_turn_init(&t, 1, 1, "a", NULL, &ev), EXTERIA_E_ARG);
    ev.send = NULL;
    CHECK_EQ_INT(exteria_tgc_turn_init(&t, 1, 1, "a", "b", &ev), EXTERIA_E_ARG);
}

int main(void) {
    allocation_with_challenge();
    wrong_password_fails();
    permissions_and_sending();
    wrap_needs_an_allocation();
    data_indications();
    stale_nonce_is_retried();
    retransmission_and_giving_up();
    malformed_input();
    forged_success_is_refused();
    init_refusals();
    return test_finish("test_tgc_turn");
}
