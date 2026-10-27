#include "exteria_tgc_ice.h"
#include "fake_turn.h"
#include "test_util.h"

/* two agents whose reflectors are both blocked and whose TURN servers relay between their allocations, as a
   network that lets standard TURN through and not the reflector protocol does */

#define MAX_QUEUE 256
#define AGENTS 2

typedef struct packet {
    int to_server;
    int agent;
    unsigned index;
    uint64_t due;
    size_t len;
    uint8_t data[1500];
} packet;

typedef struct world {
    exteria_tgc_ice ice[AGENTS];
    server turn[AGENTS];
    packet queue[MAX_QUEUE];
    size_t queued;
    uint64_t now, latency;
    int cut;
    int state[AGENTS];
    int connected_events[AGENTS];
    uint8_t got[AGENTS][8][64];
    size_t got_len[AGENTS][8];
    unsigned got_count[AGENTS];
    char candidates[AGENTS][8][400];
    unsigned candidate_count[AGENTS], delivered[AGENTS];
    unsigned reflector_packets;
} world;

typedef struct context {
    world *w;
    int agent;
} context;

static context contexts[AGENTS];

static void enqueue(world *w, int to_server, int agent, unsigned index, const uint8_t *data, size_t len) {
    packet *p;
    if (w->queued >= MAX_QUEUE || w->cut || len > sizeof(p->data)) return;
    p = &w->queue[w->queued++];
    p->to_server = to_server;
    p->agent = agent;
    p->index = index;
    p->due = w->now + w->latency;
    p->len = len;
    memcpy(p->data, data, len);
}

static void on_ice_send(void *ctx, unsigned index, const uint8_t *data, size_t len) {
    context *c = (context *)ctx;
    /* index 0 is the reflector, which never answers; index 1 is the TURN server */
    if (index == 0) {
        ++c->w->reflector_packets;
        return;
    }
    enqueue(c->w, 1, c->agent, index, data, len);
}

static void on_candidate(void *ctx, const char *sdp) {
    context *c = (context *)ctx;
    world *w = c->w;
    if (w->candidate_count[c->agent] < 8) snprintf(w->candidates[c->agent][w->candidate_count[c->agent]++], 400, "%s", sdp);
}

static void on_state(void *ctx, exteria_tgc_ice_state state) {
    context *c = (context *)ctx;
    c->w->state[c->agent] = (int)state;
    if (state == EXTERIA_TGC_ICE_CONNECTED) ++c->w->connected_events[c->agent];
}

static void on_payload(void *ctx, const uint8_t *data, size_t len) {
    context *c = (context *)ctx;
    world *w = c->w;
    unsigned k = w->got_count[c->agent];
    if (k < 8 && len <= 64) {
        memcpy(w->got[c->agent][k], data, len);
        w->got_len[c->agent][k] = len;
        ++w->got_count[c->agent];
    }
}

static int has_grant(const server *s, uint32_t ip) {
    size_t i;
    for (i = 0; i < s->granted_count; ++i) if (s->granted[i] == ip) return 1;
    return 0;
}

/* a Send indication of one allocation reaches the other one when both sides have a permission for the address it comes from */
static void forward(void *hub, server *from, uint32_t ip, uint16_t port, const uint8_t *data, size_t len) {
    world *w = (world *)hub;
    int a;
    for (a = 0; a < AGENTS; ++a) {
        server *to = &w->turn[a];
        wbuf m;
        uint8_t txid[12] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
        if (to == from || to->relay_ip != ip || to->relay_port != port) continue;
        if (!has_grant(from, to->relay_ip) || !has_grant(to, from->relay_ip)) return;
        wbegin(&m, 0x0017, txid);
        wxor(&m, 0x0012, from->relay_ip, from->relay_port);
        wattr(&m, 0x0013, data, len);
        wfinish(&m, NULL);
        enqueue(w, 0, a, 1, m.b, m.len);
        return;
    }
}

static void step(world *w, uint64_t ms) {
    uint64_t end = w->now + ms;
    while (w->now < end) {
        size_t i = 0;
        int a;
        w->now += 5;
        while (i < w->queued) {
            packet p = w->queue[i];
            if (p.due > w->now) {
                ++i;
                continue;
            }
            memmove(&w->queue[i], &w->queue[i + 1], (w->queued - i - 1) * sizeof(packet));
            --w->queued;
            if (p.to_server) {
                wbuf answer;
                if (server_answer(&w->turn[p.agent], p.data, p.len, &answer)) enqueue(w, 0, p.agent, p.index, answer.b, answer.len);
            } else {
                exteria_tgc_ice_input(&w->ice[p.agent], p.index, p.data, p.len, w->now);
            }
            i = 0;
        }
        for (a = 0; a < AGENTS; ++a) exteria_tgc_ice_tick(&w->ice[a], w->now);
        for (a = 0; a < AGENTS; ++a) {
            while (w->delivered[a] < w->candidate_count[a]) {
                exteria_tgc_ice_add_remote_candidate(&w->ice[1 - a], w->candidates[a][w->delivered[a]], w->now);
                ++w->delivered[a];
            }
        }
    }
}

static exteria_tgc_ice_reflector_config blocked_reflector(void) {
    exteria_tgc_ice_reflector_config c;
    int i;
    memset(&c, 0, sizeof(c));
    c.server_id = 1;
    for (i = 0; i < 12; ++i) c.peer_tag[i] = (uint8_t)(0x40 + i);
    c.local_tag = 0x1234;
    c.port = 599;
    c.address[0] = 149;
    c.address[1] = 154;
    c.address[2] = 167;
    c.address[3] = 1;
    return c;
}

static world *make_world(uint64_t latency) {
    world *w = (world *)calloc(1, sizeof(*w));
    exteria_tgc_ice_events ev;
    exteria_tgc_ice_reflector_config reflector = blocked_reflector();
    int a;
    w->latency = latency;
    for (a = 0; a < AGENTS; ++a) {
        server_init(&w->turn[a]);
        w->turn[a].relay_ip = a == 0 ? 0x5b6c0d17u : 0x5b6c0e09u;
        w->turn[a].relay_port = (uint16_t)(a == 0 ? 49512 : 50001);
        w->turn[a].mapped_ip = a == 0 ? 0x6edf0a14u : 0x2e5a0b0cu;
        w->turn[a].mapped_port = (uint16_t)(a == 0 ? 40071 : 41112);
        w->turn[a].forward = forward;
        w->turn[a].hub = w;
        contexts[a].w = w;
        contexts[a].agent = a;
        memset(&ev, 0, sizeof(ev));
        ev.context = &contexts[a];
        ev.send = on_ice_send;
        ev.local_candidate = on_candidate;
        ev.state = on_state;
        ev.payload = on_payload;
        CHECK_EQ_INT(exteria_tgc_ice_init(&w->ice[a], a == 0, a == 0 ? 0x1111222233334444ull : 0x0102030405060708ull, a == 0 ? "aaaa" : "bbbb",
                                          a == 0 ? "aaaaaaaaaaaaaaaaaaaaaa" : "bbbbbbbbbbbbbbbbbbbbbb", &reflector, 1, &ev), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tgc_ice_add_turn(&w->ice[a], SERVER_IP, SERVER_PORT, "reflector", "s3cret-pass"), EXTERIA_OK);
    }
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&w->ice[0], "bbbb", "bbbbbbbbbbbbbbbbbbbbbb"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&w->ice[1], "aaaa", "aaaaaaaaaaaaaaaaaaaaaa"), EXTERIA_OK);
    return w;
}

static void connects_through_turn(void) {
    world *w = make_world(30);
    static const uint8_t ping[] = "dtls hello", pong[] = "dtls reply";
    unsigned index = 9;
    uint32_t ip = 0;
    step(w, 8000);
    CHECK_EQ_INT(w->state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->state[1], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->connected_events[0], 1);
    CHECK_EQ_INT(w->connected_events[1], 1);
    /* each announced its relay address, with the address the server saw it at as the related one */
    CHECK_EQ_INT(w->candidate_count[0], 1);
    CHECK(strstr(w->candidates[0][0], " typ relay raddr 110.223.10.20 rport 40071 generation 0 ufrag aaaa network-id 1") != NULL);
    CHECK(strstr(w->candidates[0][0], "91.108.13.23 49512 typ relay") != NULL);
    CHECK(strstr(w->candidates[1][0], "91.108.14.9 50001 typ relay") != NULL);
    /* the pair is a TURN one: server number reflector_count + 0, and the address of the other relay */
    CHECK_EQ_INT(exteria_tgc_ice_selected(&w->ice[0], &index, &ip), 1);
    CHECK_EQ_INT(index, 1);
    CHECK_EQ_INT(ip, 0x5b6c0e09u);
    CHECK_EQ_INT(exteria_tgc_ice_selected(&w->ice[1], &index, &ip), 1);
    CHECK_EQ_INT(ip, 0x5b6c0d17u);
    CHECK(has_grant(&w->turn[0], 0x5b6c0e09u));
    CHECK(has_grant(&w->turn[1], 0x5b6c0d17u));

    CHECK_EQ_INT(exteria_tgc_ice_send(&w->ice[0], ping, sizeof(ping) - 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_send(&w->ice[1], pong, sizeof(pong) - 1), EXTERIA_OK);
    step(w, 300);
    CHECK_EQ_INT(w->got_count[1], 1);
    CHECK(w->got_len[1][0] == sizeof(ping) - 1 && memcmp(w->got[1][0], ping, sizeof(ping) - 1) == 0);
    CHECK_EQ_INT(w->got_count[0], 1);
    CHECK(w->got_len[0][0] == sizeof(pong) - 1 && memcmp(w->got[0][0], pong, sizeof(pong) - 1) == 0);

    /* long enough for the permissions to be asked for again (after four minutes) and the allocation to be refreshed, with the pair alive all the time */
    step(w, 700000);
    CHECK_EQ_INT(w->state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->state[1], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->connected_events[0], 1);
    CHECK(w->turn[0].permissions >= 2);
    free(w);
}

static void other_candidates_are_handled(void) {
    world *w = make_world(30);
    /* a private address, a TCP one, an IPv6 one, a garbage line: none of them makes a pair, and none of them harms */
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(&w->ice[0], "candidate:1 1 udp 2122260223 192.168.1.5 50000 typ host generation 0", 1), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(&w->ice[0], "candidate:1 1 tcp 1518280447 91.108.9.9 9 typ host tcptype active", 1), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(&w->ice[0], "candidate:1 1 udp 2122260223 2001:db8::1 50000 typ host", 1), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(&w->ice[0], "not a candidate", 1), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(&w->ice[0], "candidate:1 1 udp 2122260223 300.1.1.1 50000 typ host", 1), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(w->ice[0].pairs[0].used, 0);
    /* a public one pairs with the TURN server, and a second line for the same address adds nothing */
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(&w->ice[0], "candidate:7 1 udp 1686052607 151.241.141.11 35594 typ srflx raddr 10.0.0.2 rport 35594 generation 0", 1), EXTERIA_OK);
    CHECK_EQ_INT(w->ice[0].pairs[0].used, 1);
    CHECK_EQ_INT(w->ice[0].pairs[0].turn, 1);
    CHECK_EQ_INT(w->ice[0].pairs[0].remote_ip, 0x97f18d0bu);
    CHECK_EQ_INT(w->ice[0].pairs[0].remote_port, 35594);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(&w->ice[0], "candidate:7 1 udp 1686052607 151.241.141.11 35594 typ srflx raddr 10.0.0.2 rport 35594 generation 0", 1), EXTERIA_OK);
    CHECK_EQ_INT(w->ice[0].pairs[1].used, 0);
    free(w);
}

static void add_turn_refusals(void) {
    exteria_tgc_ice ice;
    exteria_tgc_ice_events ev;
    exteria_tgc_ice_reflector_config reflector = blocked_reflector();
    unsigned i;
    memset(&ev, 0, sizeof(ev));
    ev.send = on_ice_send;
    CHECK_EQ_INT(exteria_tgc_ice_add_turn(&ice, 1, 1, "a", "b"), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 5, "aaaa", "aaaaaaaaaaaaaaaaaaaaaa", &reflector, 1, &ev), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_add_turn(&ice, 0, 1, "a", "b"), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_add_turn(&ice, 1, 0, "a", "b"), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_add_turn(&ice, 1, 1, "", "b"), EXTERIA_E_ARG);
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_TURNS; ++i) CHECK_EQ_INT(exteria_tgc_ice_add_turn(&ice, 0x5b6c0d17u + i, 598, "u", "p"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_add_turn(&ice, 0x5b6c0d17u, 598, "u", "p"), EXTERIA_E_LIMIT);
}

int main(void) {
    connects_through_turn();
    other_candidates_are_handled();
    add_turn_refusals();
    return test_finish("test_tgc_ice_turn");
}
