#include "exteria_tgc_ice.h"
#include "test_util.h"

/* two agents and the reflector servers between them, simulated in memory with a clock the test moves */

#define MAX_QUEUE 256
#define AGENTS 2

typedef struct packet {
    int to_server;          /* 1: to the reflector server of that side, 0: from a server to an agent */
    int agent;              /* the agent the packet comes from or goes to */
    unsigned reflector;     /* the reflector index of the agent */
    uint64_t due;
    size_t len;
    uint8_t data[EXTERIA_TGC_REFLECTOR_MAX_DATAGRAM];
} packet;

typedef struct client {
    uint32_t tag;
    int agent;
    unsigned reflector;
    int known;
} client;

typedef struct server {
    uint8_t id;
    uint8_t prefix[12];
    client clients[4];
    int dead;       /* swallows everything */
} server;

typedef struct world {
    exteria_tgc_ice ice[AGENTS];
    server servers[EXTERIA_TGC_ICE_MAX_REFLECTORS];
    unsigned server_count;
    packet queue[MAX_QUEUE];
    size_t queued;
    uint64_t now;
    unsigned loss_percent;
    unsigned rng;
    uint64_t latency;
    int cut;                        /* the network drops all agent traffic */
    int deliver_candidates;         /* candidates reach the other agent at once */
    int agent_state[AGENTS];
    int connected_events[AGENTS];
    uint8_t got[AGENTS][8][64];
    size_t got_len[AGENTS][8];
    unsigned got_count[AGENTS];
    char candidates[AGENTS][8][400];
    unsigned candidate_count[AGENTS];
    unsigned delivered_candidates[AGENTS];
} world;

static world *W;

static unsigned next_random(world *w) {
    w->rng = w->rng * 1103515245u + 12345u;
    return (w->rng >> 16) & 0x7FFF;
}

static void enqueue(world *w, int to_server, int agent, unsigned reflector, const uint8_t *data, size_t len) {
    packet *p;
    if (w->queued >= MAX_QUEUE) return;
    if (w->cut || (w->loss_percent && next_random(w) % 100 < w->loss_percent)) return;
    p = &w->queue[w->queued++];
    p->to_server = to_server;
    p->agent = agent;
    p->reflector = reflector;
    p->due = w->now + w->latency;
    p->len = len;
    memcpy(p->data, data, len);
}

/* what an agent sends goes to the server of that reflector */
typedef struct context {
    world *w;
    int agent;
} context;

static context contexts[AGENTS];

static void on_send(void *ctx, unsigned index, const uint8_t *data, size_t len) {
    context *c = (context *)ctx;
    enqueue(c->w, 1, c->agent, index, data, len);
}

static void on_candidate(void *ctx, const char *sdp) {
    context *c = (context *)ctx;
    world *w = c->w;
    snprintf(w->candidates[c->agent][w->candidate_count[c->agent]++], sizeof(w->candidates[0][0]), "%s", sdp);
}

static void on_state(void *ctx, exteria_tgc_ice_state state) {
    context *c = (context *)ctx;
    c->w->agent_state[c->agent] = (int)state;
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

static void server_receive(world *w, server *s, const packet *p) {
    unsigned i;
    uint32_t target, sender;
    client *c = NULL;
    if (s->dead || p->len < 16 || memcmp(p->data, s->prefix, 12) != 0) return;
    if (p->len >= 40 && p->data[16] == 0xFF && p->data[28] == 0xFE) {
        /* hello: learn the sender, answer with the ping body */
        uint8_t reply[40];
        sender = (uint32_t)p->data[12] | (uint32_t)p->data[13] << 8 | (uint32_t)p->data[14] << 16 | (uint32_t)p->data[15] << 24;
        for (i = 0; i < 4 && s->clients[i].known; ++i) if (s->clients[i].tag == sender && s->clients[i].agent == p->agent) c = &s->clients[i];
        if (!c) {
            for (i = 0; i < 4 && s->clients[i].known; ++i) {}
            if (i == 4) return;
            c = &s->clients[i];
            c->known = 1;
            c->tag = sender;
            c->agent = p->agent;
            c->reflector = p->reflector;
        }
        memcpy(reply, p->data, 40);
        enqueue(w, 0, p->agent, p->reflector, reply, 40);
        return;
    }
    if (p->len < 24) return;
    target = (uint32_t)p->data[12] | (uint32_t)p->data[13] << 8 | (uint32_t)p->data[14] << 16 | (uint32_t)p->data[15] << 24;
    sender = (uint32_t)p->data[16] | (uint32_t)p->data[17] << 8 | (uint32_t)p->data[18] << 16 | (uint32_t)p->data[19] << 24;
    (void)sender;
    for (i = 0; i < 4 && s->clients[i].known; ++i) {
        if (s->clients[i].tag == target) {
            enqueue(w, 0, s->clients[i].agent, s->clients[i].reflector, p->data, p->len);
            return;
        }
    }
}

static void step(world *w, uint64_t ms) {
    uint64_t end = w->now + ms;
    while (w->now < end) {
        size_t i = 0;
        int a;
        w->now += 5;
        /* deliver what is due; delivery may queue more */
        while (i < w->queued) {
            packet p = w->queue[i];
            if (p.due > w->now) {
                ++i;
                continue;
            }
            memmove(&w->queue[i], &w->queue[i + 1], (w->queued - i - 1) * sizeof(packet));
            --w->queued;
            if (p.to_server) {
                /* find the server by the id of the sender's reflector */
                unsigned id = w->ice[p.agent].reflectors[p.reflector].config.server_id, s;
                for (s = 0; s < w->server_count; ++s) if (w->servers[s].id == id) server_receive(w, &w->servers[s], &p);
            } else {
                exteria_tgc_ice_input(&w->ice[p.agent], p.reflector, p.data, p.len, w->now);
            }
            i = 0;
        }
        for (a = 0; a < AGENTS; ++a) exteria_tgc_ice_tick(&w->ice[a], w->now);
        if (w->deliver_candidates) {
            for (a = 0; a < AGENTS; ++a) {
                int other = 1 - a;
                while (w->delivered_candidates[a] < w->candidate_count[a]) {
                    exteria_tgc_ice_add_remote_candidate(&w->ice[other], w->candidates[a][w->delivered_candidates[a]], w->now);
                    ++w->delivered_candidates[a];
                }
            }
        }
    }
}

static const char *ufrag_a = "aaaa", *ufrag_b = "bbbb";
static const char *pwd_a = "aaaaaaaaaaaaaaaaaaaaaa", *pwd_b = "bbbbbbbbbbbbbbbbbbbbbb";

static exteria_tgc_ice_reflector_config reflector(uint8_t id, uint32_t tag, uint8_t salt) {
    exteria_tgc_ice_reflector_config c;
    int i;
    memset(&c, 0, sizeof(c));
    c.server_id = id;
    for (i = 0; i < 12; ++i) c.peer_tag[i] = (uint8_t)(salt + i);
    c.local_tag = tag;
    c.port = 599;
    c.address[0] = 149;
    c.address[1] = 154;
    c.address[2] = 167;
    c.address[3] = id;
    return c;
}

static world *make_world(unsigned servers, uint64_t latency, unsigned dead_mask) {
    world *w = (world *)calloc(1, sizeof(*w));
    exteria_tgc_ice_reflector_config cfg[2][EXTERIA_TGC_ICE_MAX_REFLECTORS];
    exteria_tgc_ice_events ev;
    unsigned s;
    int a;
    w->rng = 12345;
    w->latency = latency;
    w->server_count = servers;
    w->deliver_candidates = 1;
    for (s = 0; s < servers; ++s) {
        int i;
        w->servers[s].id = (uint8_t)(s + 1);
        for (i = 0; i < 12; ++i) w->servers[s].prefix[i] = (uint8_t)(0x40 + s * 16 + i);
        w->servers[s].dead = (dead_mask >> s) & 1;
        cfg[0][s] = reflector((uint8_t)(s + 1), 0x1000u + s, (uint8_t)(0x40 + s * 16));
        cfg[1][s] = reflector((uint8_t)(s + 1), 0x2000u + s, (uint8_t)(0x40 + s * 16));
    }
    for (a = 0; a < AGENTS; ++a) {
        contexts[a].w = w;
        contexts[a].agent = a;
        memset(&ev, 0, sizeof(ev));
        ev.context = &contexts[a];
        ev.send = on_send;
        ev.local_candidate = on_candidate;
        ev.state = on_state;
        ev.payload = on_payload;
        CHECK_EQ_INT(exteria_tgc_ice_init(&w->ice[a], a == 0, a == 0 ? 0x1111222233334444ull : 0x0102030405060708ull, a == 0 ? ufrag_a : ufrag_b,
                                          a == 0 ? pwd_a : pwd_b, cfg[a], servers, &ev), EXTERIA_OK);
    }
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&w->ice[0], ufrag_b, pwd_b), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&w->ice[1], ufrag_a, pwd_a), EXTERIA_OK);
    W = w;
    return w;
}

static void connects_and_carries_data(void) {
    world *w = make_world(1, 20, 0);
    static const uint8_t ping[] = "dtls hello", pong[] = "dtls reply";
    step(w, 3000);
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->connected_events[0], 1);
    CHECK_EQ_INT(w->connected_events[1], 1);
    CHECK_EQ_INT(w->candidate_count[0], 1);
    CHECK(strstr(w->candidates[0][0], "reflector-1-4096.reflector 599 typ relay") != NULL);
    CHECK(strstr(w->candidates[0][0], "ufrag aaaa") != NULL);
    {
        unsigned reflector_index = 9;
        uint32_t tag = 0;
        CHECK_EQ_INT(exteria_tgc_ice_selected(&w->ice[0], &reflector_index, &tag), 1);
        CHECK_EQ_INT(reflector_index, 0);
        CHECK(tag == 0x2000u);
        CHECK_EQ_INT(exteria_tgc_ice_selected(&w->ice[1], &reflector_index, &tag), 1);
        CHECK(tag == 0x1000u);
    }
    CHECK_EQ_INT(exteria_tgc_ice_send(&w->ice[0], ping, sizeof(ping) - 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_send(&w->ice[1], pong, sizeof(pong) - 1), EXTERIA_OK);
    step(w, 200);
    CHECK_EQ_INT(w->got_count[1], 1);
    CHECK(w->got_len[1][0] == sizeof(ping) - 1 && memcmp(w->got[1][0], ping, sizeof(ping) - 1) == 0);
    CHECK_EQ_INT(w->got_count[0], 1);
    CHECK(w->got_len[0][0] == sizeof(pong) - 1 && memcmp(w->got[0][0], pong, sizeof(pong) - 1) == 0);
    /* a long quiet stretch keeps the pair alive on keepalives alone, with no new connection event */
    step(w, 60000);
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->connected_events[0], 1);
    CHECK_EQ_INT(w->connected_events[1], 1);
    /* the roles stayed as the call set them */
    CHECK_EQ_INT(w->ice[0].controlling, 1);
    CHECK_EQ_INT(w->ice[1].controlling, 0);
    free(w);
}

static void dead_server_is_skipped(void) {
    /* two servers; the first one answers nothing, so the call goes through the second */
    world *w = make_world(2, 20, 1);
    step(w, 6000);
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_CONNECTED);
    {
        unsigned reflector_index = 9;
        uint32_t tag = 0;
        CHECK_EQ_INT(exteria_tgc_ice_selected(&w->ice[0], &reflector_index, &tag), 1);
        CHECK_EQ_INT(reflector_index, 1);
    }
    /* only the live server announced a candidate */
    CHECK_EQ_INT(w->candidate_count[0], 1);
    CHECK(strstr(w->candidates[0][0], "reflector-2-") != NULL);
    free(w);
}

static void survives_loss(void) {
    unsigned loss;
    for (loss = 10; loss <= 40; loss += 15) {
        world *w = make_world(1, 30, 0);
        w->loss_percent = loss;
        step(w, 30000);
        CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
        CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_CONNECTED);
        free(w);
    }
}

static void late_candidates(void) {
    /* the candidates are exchanged only after a second; checks that arrive first make the pair themselves */
    world *w = make_world(1, 20, 0);
    w->deliver_candidates = 0;
    step(w, 1000);
    CHECK(w->agent_state[0] != EXTERIA_TGC_ICE_CONNECTED);
    w->deliver_candidates = 1;
    step(w, 3000);
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_CONNECTED);
    free(w);
}

static void silence_and_recovery(void) {
    world *w = make_world(1, 20, 0);
    step(w, 3000);
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
    w->cut = 1;
    step(w, 15000);
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_DISCONNECTED);
    CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_DISCONNECTED);
    w->cut = 0;
    step(w, 15000);
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_CONNECTED);
    free(w);
}

static void role_conflict(void) {
    /* both sides think they are controlling: the larger tie breaker keeps it */
    world *w = make_world(1, 20, 0);
    w->ice[1].controlling = 1;
    step(w, 6000);
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->ice[0].controlling, 1);
    CHECK_EQ_INT(w->ice[1].controlling, 0);
    free(w);
    /* both controlled: the one with the larger tie breaker takes the role */
    w = make_world(1, 20, 0);
    w->ice[0].controlling = 0;
    step(w, 6000);
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_CONNECTED);
    CHECK(w->ice[0].controlling != w->ice[1].controlling);
    free(w);
}

static void wrong_password_never_connects(void) {
    world *w = make_world(1, 20, 0);
    /* each agent believes in another password for the other, so no check passes in either direction (one wrong direction alone would let the
       other agent connect, as in any ICE: its checks are accepted and answered) */
    memset(&w->ice[0].remote_pwd, 0, sizeof(w->ice[0].remote_pwd));
    memcpy(w->ice[0].remote_pwd, "dddddddddddddddddddddd", 23);
    memset(&w->ice[1].remote_pwd, 0, sizeof(w->ice[1].remote_pwd));
    memcpy(w->ice[1].remote_pwd, "cccccccccccccccccccccc", 23);
    step(w, 20000);
    CHECK(w->agent_state[0] != EXTERIA_TGC_ICE_CONNECTED);
    CHECK(w->agent_state[1] != EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->got_count[0], 0);
    CHECK_EQ_INT(w->got_count[1], 0);
    CHECK_EQ_INT(exteria_tgc_ice_send(&w->ice[1], (const uint8_t *)"x", 1), EXTERIA_E_STATE);
    free(w);
}

static void payload_before_authentication_is_dropped(void) {
    world *w = make_world(1, 20, 0);
    uint8_t out[EXTERIA_TGC_REFLECTOR_MAX_DATAGRAM];
    size_t n = 0;
    exteria_tgc_reflector injector;
    step(w, 100);
    /* a datagram of someone who never passed a check, addressed to agent 1 */
    exteria_tgc_reflector_init(&injector, 1, w->ice[1].reflectors[0].config.peer_tag, 0x99999u, 0);
    CHECK_EQ_INT(exteria_tgc_reflector_wrap(&injector, w->ice[1].reflectors[0].config.local_tag, (const uint8_t *)"\x16\xFE\xFD sneaky", 11, out, sizeof(out), &n), EXTERIA_OK);
    exteria_tgc_ice_input(&w->ice[1], 0, out, n, w->now);
    CHECK_EQ_INT(w->got_count[1], 0);
    free(w);
}

static void candidate_handling(void) {
    world *w = make_world(1, 20, 0);
    exteria_tgc_ice *ice = &w->ice[0];
    int count = 0, i;
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, "candidate:1 1 udp 2122260223 192.168.0.5 53333 typ host generation 0", 0), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, "candidate:2 1 udp 1686052607 5.6.7.8 61000 typ srflx raddr 192.168.0.5 rport 53333", 0), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, "candidate:3 1 udp 41885439 turn.example.com 3478 typ relay", 0), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, "garbage", 0), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, "", 0), EXTERIA_E_MALFORMED);
    /* a reflector no server of ours serves, and a server on another port, are dropped without an error and make no pair */
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, "candidate:9 1 udp 41885439 reflector-5-77.reflector 599 typ relay", 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, "candidate:1 1 udp 41885439 reflector-1-77.reflector 600 typ relay", 0), EXTERIA_OK);
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) count += ice->pairs[i].used;
    CHECK_EQ_INT(count, 0);
    /* a good one makes one pair, and the same again makes no second */
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, "candidate:1 1 udp 41885439 reflector-1-77.reflector 599 typ relay", 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, "candidate:1 1 udp 41885439 reflector-1-77.reflector 599 typ relay", 0), EXTERIA_OK);
    count = 0;
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) count += ice->pairs[i].used;
    CHECK_EQ_INT(count, 1);
    /* the pairs are bounded: more candidates than the table are dropped, never overrun */
    for (i = 0; i < 100; ++i) {
        char sdp[160];
        snprintf(sdp, sizeof(sdp), "candidate:1 1 udp 41885439 reflector-1-%d.reflector 599 typ relay", 1000 + i);
        CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(ice, sdp, 0), EXTERIA_OK);
    }
    count = 0;
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) count += ice->pairs[i].used;
    CHECK_EQ_INT(count, EXTERIA_TGC_ICE_MAX_PAIRS);
    free(w);
}

static void arguments(void) {
    exteria_tgc_ice ice;
    exteria_tgc_ice_reflector_config cfg[EXTERIA_TGC_ICE_MAX_REFLECTORS + 1];
    exteria_tgc_ice_events ev;
    size_t i;
    memset(&ev, 0, sizeof(ev));
    ev.send = on_send;
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_REFLECTORS + 1; ++i) cfg[i] = reflector((uint8_t)(i + 1), (uint32_t)(i + 1), 1);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", pwd_a, cfg, 1, &ev), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_init(NULL, 1, 1, "abcd", pwd_a, cfg, 1, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", pwd_a, cfg, 0, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", pwd_a, cfg, EXTERIA_TGC_ICE_MAX_REFLECTORS + 1, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abc", pwd_a, cfg, 1, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "ab:d", pwd_a, cfg, 1, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", "short", cfg, 1, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", pwd_a, cfg, 1, NULL), EXTERIA_E_ARG);
    ev.send = NULL;
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", pwd_a, cfg, 1, &ev), EXTERIA_E_ARG);
    ev.send = on_send;
    cfg[0].server_id = 0;
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", pwd_a, cfg, 1, &ev), EXTERIA_E_ARG);
    cfg[0] = reflector(1, 0, 1);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", pwd_a, cfg, 1, &ev), EXTERIA_E_ARG);
    cfg[0] = reflector(1, 5, 1);
    cfg[0].port = 0;
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", pwd_a, cfg, 1, &ev), EXTERIA_E_ARG);
    cfg[0] = reflector(1, 5, 1);
    CHECK_EQ_INT(exteria_tgc_ice_init(&ice, 1, 1, "abcd", pwd_a, cfg, 1, &ev), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&ice, "abc", pwd_b), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&ice, ufrag_b, "short"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&ice, ufrag_b, pwd_b), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&ice, ufrag_b, pwd_b), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&ice, "zzzz", pwd_b), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_tgc_ice_input(&ice, 5, (const uint8_t *)"x", 1, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_input(NULL, 0, (const uint8_t *)"x", 1, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_ice_send(&ice, (const uint8_t *)"x", 1), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_tgc_ice_selected(&ice, NULL, NULL), 0);
    exteria_tgc_ice_tick(NULL, 0);
}

static void direct_agents_connect(void) {
    world *w = (world *)calloc(1, sizeof(*w));
    exteria_tgc_ice_events ev;
    unsigned index, duplicate;
    int a, tick;
    CHECK(w != NULL);
    for (a = 0; a < AGENTS; ++a) {
        contexts[a].w = w;
        contexts[a].agent = a;
        memset(&ev, 0, sizeof(ev));
        ev.context = &contexts[a];
        ev.send = on_send;
        ev.state = on_state;
        ev.payload = on_payload;
        CHECK_EQ_INT(exteria_tgc_ice_init_direct(&w->ice[a], a == 0, (uint64_t)(a + 1), a == 0 ? ufrag_a : ufrag_b,
                                                  a == 0 ? pwd_a : pwd_b, &ev), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tgc_ice_set_remote(&w->ice[a], a == 0 ? ufrag_b : ufrag_a, a == 0 ? pwd_b : pwd_a), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tgc_ice_add_direct(&w->ice[a], 0x7f000001u, 1000, 1, &index), EXTERIA_OK);
        CHECK_EQ_INT(index, 0);
        CHECK_EQ_INT(exteria_tgc_ice_add_direct(&w->ice[a], 0x7f000001u, 1000, 1, &duplicate), EXTERIA_OK);
        CHECK_EQ_INT(duplicate, index);
    }
    for (tick = 1; tick < 100; ++tick) {
        w->now = (uint64_t)tick * 50;
        for (a = 0; a < AGENTS; ++a) exteria_tgc_ice_tick(&w->ice[a], w->now);
        while (w->queued) {
            packet p = w->queue[0];
            memmove(&w->queue[0], &w->queue[1], (--w->queued) * sizeof(packet));
            CHECK_EQ_INT(exteria_tgc_ice_input(&w->ice[1 - p.agent], p.reflector, p.data, p.len, w->now), EXTERIA_OK);
        }
        if (w->agent_state[0] == EXTERIA_TGC_ICE_CONNECTED && w->agent_state[1] == EXTERIA_TGC_ICE_CONNECTED) break;
    }
    CHECK_EQ_INT(w->agent_state[0], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(w->agent_state[1], EXTERIA_TGC_ICE_CONNECTED);
    CHECK_EQ_INT(exteria_tgc_ice_send(&w->ice[0], (const uint8_t *)"media", 5), EXTERIA_OK);
    CHECK_EQ_INT(w->queued, 1);
    CHECK_EQ_INT(exteria_tgc_ice_input(&w->ice[1], 0, w->queue[0].data, w->queue[0].len, w->now), EXTERIA_OK);
    CHECK_EQ_INT(w->got_count[1], 1);
    free(w);
}

static void response_must_match_path(void) {
    world *w = make_world(1, 0, 0);
    exteria_tgc_ice_pair *pair;
    exteria_stun response;
    exteria_tgc_reflector sender = w->ice[1].reflectors[0].wire;
    uint8_t stun[EXTERIA_STUN_MAX_MESSAGE], packet_data[EXTERIA_TGC_REFLECTOR_MAX_DATAGRAM];
    size_t stun_len = 0, packet_len = 0;
    CHECK_EQ_INT(exteria_tgc_ice_add_remote_candidate(&w->ice[0], "candidate:1 1 udp 1 reflector-1-8192.reflector 599 typ relay", 0), EXTERIA_OK);
    pair = &w->ice[0].pairs[0];
    CHECK(pair->used);
    pair->outstanding = 1;
    memset(pair->txid, 42, sizeof(pair->txid));
    memset(&response, 0, sizeof(response));
    response.type = EXTERIA_STUN_BINDING_SUCCESS;
    memcpy(response.txid, pair->txid, sizeof(response.txid));
    CHECK_EQ_INT(exteria_stun_write(&response, (const uint8_t *)pwd_b, strlen(pwd_b), 1, stun, sizeof(stun), &stun_len), EXTERIA_OK);
    sender.local_tag = 8193;
    CHECK_EQ_INT(exteria_tgc_reflector_wrap(&sender, 4096, stun, stun_len, packet_data, sizeof(packet_data), &packet_len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_input(&w->ice[0], 0, packet_data, packet_len, 10), EXTERIA_OK);
    CHECK_EQ_INT(pair->valid, 0);
    CHECK_EQ_INT(pair->outstanding, 1);
    sender.local_tag = 8192;
    CHECK_EQ_INT(exteria_tgc_reflector_wrap(&sender, 4096, stun, stun_len, packet_data, sizeof(packet_data), &packet_len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_input(&w->ice[0], 0, packet_data, packet_len, 20), EXTERIA_OK);
    CHECK_EQ_INT(pair->valid, 1);
    free(w);
}

int main(void) {
    connects_and_carries_data();
    dead_server_is_skipped();
    survives_loss();
    late_candidates();
    silence_and_recovery();
    role_conflict();
    wrong_password_never_connects();
    payload_before_authentication_is_dropped();
    candidate_handling();
    direct_agents_connect();
    response_must_match_path();
    arguments();
    return test_finish("test_tgc_ice");
}
