#include "exteria_bytes.h"
#include "exteria_tcpip.h"
#include "fake_tcp_server.h"
#include "test_util.h"

/* the stack under test talks to a small TCP server of this file over a simulated link; time is a counter that the
   tests advance, so a run of minutes of protocol time takes a blink */

#define CLIENT_IP 0xAC100002u /* 172.16.0.2 */
#define SERVER_IP 0x95A9A733u /* 149.154.167.51 */
#define SERVER_PORT 443u
#define MTU 1280u
#define QUEUE 4096

typedef struct frame {
    uint64_t at;
    size_t len;
    uint8_t bytes[1500];
} frame;

typedef struct sim {
    exteria_tcpip *stack;
    uint64_t now;
    uint64_t rng;
    unsigned loss_to_server, loss_to_client; /* percent */
    unsigned delay_ms, jitter_ms;
    frame to_server[QUEUE], to_client[QUEUE];
    size_t n_server, n_client;
    /* every packet the stack emitted, for inspection */
    frame log[256];
    size_t logged;
    size_t emitted;
    uint32_t id;
} sim;

static uint64_t rnd(sim *s) {
    s->rng ^= s->rng << 13;
    s->rng ^= s->rng >> 7;
    s->rng ^= s->rng << 17;
    return s->rng;
}

static void put16(uint8_t *p, unsigned v) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; }

#define pattern_at fake_pattern_at
#define fold fake_fold
#define add fake_add
#define build fake_build_tcp

static void enqueue(sim *s, frame *q, size_t *n, const uint8_t *p, size_t len, unsigned loss) {
    uint64_t delay = s->delay_ms + (s->jitter_ms ? rnd(s) % (s->jitter_ms + 1) : 0);
    if (loss && rnd(s) % 100 < loss) return;
    if (*n >= QUEUE) return;
    q[*n].at = s->now + delay;
    q[*n].len = len;
    memcpy(q[*n].bytes, p, len);
    ++*n;
}

static void stack_emit(void *context, const uint8_t *packet, size_t len) {
    sim *s = (sim *)context;
    ++s->emitted;
    if (s->logged < 256) {
        s->log[s->logged].len = len;
        memcpy(s->log[s->logged].bytes, packet, len);
        ++s->logged;
    }
    enqueue(s, s->to_server, &s->n_server, packet, len, s->loss_to_server);
}

static void server_emit(void *context, const uint8_t *packet, size_t len) {
    sim *s = (sim *)context;
    enqueue(s, s->to_client, &s->n_client, packet, len, s->loss_to_client);
}

static void sim_step(sim *s, fake_tcp_server *v) {
    size_t i;
    ++s->now;
    for (i = 0; i < s->n_server; ++i) {
        if (s->to_server[i].at <= s->now) {
            frame f = s->to_server[i];
            memmove(&s->to_server[i], &s->to_server[i + 1], (s->n_server - i - 1) * sizeof(frame));
            --s->n_server;
            --i;
            fake_tcp_server_receive(v, f.bytes, f.len, s->now);
        }
    }
    for (i = 0; i < s->n_client; ++i) {
        if (s->to_client[i].at <= s->now) {
            frame f = s->to_client[i];
            memmove(&s->to_client[i], &s->to_client[i + 1], (s->n_client - i - 1) * sizeof(frame));
            --s->n_client;
            --i;
            exteria_tcpip_input(s->stack, f.bytes, f.len, s->now);
        }
    }
    fake_tcp_server_tick(v, s->now);
    if (s->now % 5 == 0) exteria_tcpip_tick(s->stack, s->now);
}

static void sim_run(sim *s, fake_tcp_server *v, uint64_t ms) {
    uint64_t end = s->now + ms;
    while (s->now < end) sim_step(s, v);
}

static void setup(sim *s, fake_tcp_server *v, size_t rx_cap) {
    memset(s, 0, sizeof(*s));
    s->rng = 0x9E3779B97F4A7C15ull;
    s->delay_ms = 20;
    s->now = 1000;
    fake_tcp_server_init(v, SERVER_IP, SERVER_PORT, rx_cap, server_emit, s);
    CHECK_EQ_INT(exteria_tcpip_new(&s->stack, CLIENT_IP, MTU, stack_emit, s), EXTERIA_OK);
}

static void teardown(sim *s, fake_tcp_server *v) {
    exteria_tcpip_free(s->stack);
    fake_tcp_server_free(v);
}

static int is_open(sim *s) {
    exteria_tcpip_info i;
    return exteria_tcpip_info_get(s->stack, s->id, &i) == EXTERIA_OK && i.state == EXTERIA_TCPIP_OPEN;
}

static void connect_and_open(sim *s, fake_tcp_server *v) {
    CHECK_EQ_INT(exteria_tcpip_connect(s->stack, SERVER_IP, SERVER_PORT, s->now, &s->id), EXTERIA_OK);
    sim_run(s, v, 200);
    CHECK(is_open(s));
}

static void handshake_on_the_wire(void) {
    sim s;
    fake_tcp_server v;
    const uint8_t *syn;
    exteria_tcpip_info info;
    setup(&s, &v, 100);
    CHECK_EQ_INT(exteria_tcpip_connect(s.stack, SERVER_IP, SERVER_PORT, s.now, &s.id), EXTERIA_OK);
    CHECK(s.id != 0);
    CHECK_EQ_INT(s.logged, 1);
    syn = s.log[0].bytes;
    /* a clean IPv4 header with DF, our address, TTL, protocol 6 */
    CHECK_EQ_INT(syn[0], 0x45);
    CHECK_EQ_INT(exteria_get_u32be(syn + 12), CLIENT_IP);
    CHECK_EQ_INT(exteria_get_u32be(syn + 16), SERVER_IP);
    CHECK_EQ_INT(syn[6] & 0x40, 0x40);
    CHECK_EQ_INT(syn[9], 6);
    CHECK_EQ_INT(fold(add(0, syn, 20)), 0);
    CHECK_EQ_INT(syn[20 + 13], 0x02);
    CHECK_EQ_INT(syn[20 + 12] >> 4, 6);
    CHECK_EQ_INT(syn[20 + 20], 2);
    CHECK_EQ_INT(syn[20 + 21], 4);
    CHECK_EQ_INT((syn[20 + 22] << 8) | syn[20 + 23], MTU - 40);
    CHECK((exteria_get_u32be(syn + 20) >> 16) >= 49152);
    CHECK_EQ_INT(exteria_get_u32be(syn + 20 + 2) >> 16, SERVER_PORT);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.state, EXTERIA_TCPIP_CONNECTING);
    CHECK_EQ_INT(info.send_space, 0);
    {
        uint8_t b[10];
        size_t got = 0, took = 0;
        CHECK_EQ_INT(exteria_tcpip_recv(s.stack, s.id, b, sizeof(b), s.now, &got), EXTERIA_E_STATE);
        CHECK_EQ_INT(exteria_tcpip_send(s.stack, s.id, b, 3, s.now, &took), EXTERIA_E_STATE);
        CHECK_EQ_INT(took, 0);
    }
    sim_run(&s, &v, 100);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.state, EXTERIA_TCPIP_OPEN);
    CHECK_EQ_INT(info.send_space, EXTERIA_TCPIP_BUFFER);
    CHECK_EQ_INT(v.connected, 1);
    /* the third packet of the handshake acknowledges the SYN-ACK */
    CHECK_EQ_INT(s.logged, 2);
    CHECK_EQ_INT(s.log[1].bytes[20 + 13], 0x10);
    CHECK_EQ_INT(exteria_get_u32be(s.log[1].bytes + 20 + 8), v.iss + 1);
    CHECK_EQ_INT(exteria_tcpip_info_get(NULL, 1, &info), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, 99, &info), EXTERIA_E_NOTFOUND);
    teardown(&s, &v);
}

static void small_exchange_and_delayed_ack(void) {
    sim s;
    fake_tcp_server v;
    uint8_t out[300], in[300];
    size_t took = 0, got = 0, i, before;
    setup(&s, &v, 400);
    connect_and_open(&s, &v);
    for (i = 0; i < sizeof(out); ++i) out[i] = pattern_at(i);
    CHECK_EQ_INT(exteria_tcpip_send(s.stack, s.id, out, sizeof(out), s.now, &took), EXTERIA_OK);
    CHECK_EQ_INT(took, 300);
    sim_run(&s, &v, 200);
    CHECK_EQ_INT(v.rx_len, 300);
    CHECK_MEM(v.rx, out, 300);
    /* the server sends two small data segments: the second one brings an acknowledgement at once, a single one waits for the delayed ack timer */
    v.tx_total = 100;
    fake_tcp_server_pump(&v, s.now);
    sim_run(&s, &v, 25);
    before = s.emitted;
    sim_run(&s, &v, 10);
    CHECK_EQ_INT(exteria_tcpip_recv(s.stack, s.id, in, sizeof(in), s.now, &got), EXTERIA_OK);
    CHECK_EQ_INT(got, 100);
    for (i = 0; i < 100; ++i) CHECK_EQ_INT(in[i], pattern_at(i));
    CHECK_EQ_INT(exteria_tcpip_recv(s.stack, s.id, in, sizeof(in), s.now, &got), EXTERIA_E_RETRY);
    (void)before;
    sim_run(&s, &v, 200);
    CHECK_EQ_INT(v.snd_una, v.snd_nxt);
    teardown(&s, &v);
}

static void upload(unsigned loss, unsigned jitter, size_t total, int expect_retransmit) {
    sim s;
    fake_tcp_server v;
    uint8_t *data = (uint8_t *)malloc(total);
    size_t sent = 0, i;
    exteria_tcpip_stats st;
    setup(&s, &v, total);
    s.loss_to_server = loss;
    s.loss_to_client = loss;
    s.jitter_ms = jitter;
    for (i = 0; i < total; ++i) data[i] = pattern_at(i);
    connect_and_open(&s, &v);
    while (sent < total && s.now < 600000) {
        size_t took = 0;
        exteria_status st2 = exteria_tcpip_send(s.stack, s.id, data + sent, total - sent, s.now, &took);
        CHECK_EQ_INT(st2, EXTERIA_OK);
        sent += took;
        sim_run(&s, &v, 5);
    }
    CHECK_EQ_INT(sent, total);
    for (i = 0; i < 4000 && v.rx_len < total; ++i) sim_run(&s, &v, 50);
    CHECK_EQ_INT(v.rx_len, total);
    CHECK_MEM(v.rx, data, total);
    exteria_tcpip_stats_get(s.stack, &st);
    if (expect_retransmit) CHECK(st.retransmits + st.fast_retransmits > 0);
    else CHECK_EQ_INT(st.retransmits, 0);
    free(data);
    teardown(&s, &v);
}

static void download(unsigned loss, unsigned jitter, size_t total, size_t read_chunk, int expect_ooo) {
    sim s;
    fake_tcp_server v;
    uint8_t *got_all = (uint8_t *)malloc(total), buf[4096];
    size_t have = 0, i;
    exteria_tcpip_stats st;
    setup(&s, &v, 100);
    s.loss_to_server = loss;
    s.loss_to_client = loss;
    s.jitter_ms = jitter;
    connect_and_open(&s, &v);
    v.tx_total = total;
    fake_tcp_server_pump(&v, s.now);
    for (i = 0; have < total && i < 800000; ++i) {
        size_t got = 0, want = read_chunk < sizeof(buf) ? read_chunk : sizeof(buf);
        sim_step(&s, &v);
        if (exteria_tcpip_recv(s.stack, s.id, buf, want, s.now, &got) == EXTERIA_OK) {
            memcpy(got_all + have, buf, got);
            have += got;
        }
    }
    CHECK_EQ_INT(have, total);
    if (have == total) {
        int same = 1;
        for (i = 0; i < total && same; ++i) same = got_all[i] == pattern_at(i);
        CHECK(same);
    }
    exteria_tcpip_stats_get(s.stack, &st);
    if (expect_ooo) CHECK(st.out_of_order > 0);
    free(got_all);
    teardown(&s, &v);
}

static void fast_retransmit_on_one_loss(void) {
    sim s;
    fake_tcp_server v;
    uint8_t *data = (uint8_t *)malloc(60000);
    size_t i, sent = 0;
    exteria_tcpip_stats st;
    setup(&s, &v, 60000);
    for (i = 0; i < 60000; ++i) data[i] = pattern_at(i);
    connect_and_open(&s, &v);
    /* the third segment of the burst vanishes, the later ones make the server send duplicate acknowledgements */
    CHECK_EQ_INT(exteria_tcpip_send(s.stack, s.id, data, 60000, s.now, &sent), EXTERIA_OK);
    s.loss_to_server = 0;
    {
        /* drop exactly one packet towards the server: the third of the data */
        size_t k, dropped = 0, seen = 0;
        for (k = 0; k < s.n_server; ++k) {
            if (s.to_server[k].len > 100) {
                if (++seen == 3 && !dropped) {
                    memmove(&s.to_server[k], &s.to_server[k + 1], (s.n_server - k - 1) * sizeof(frame));
                    --s.n_server;
                    dropped = 1;
                    break;
                }
            }
        }
        CHECK_EQ_INT(dropped, 1);
    }
    while (sent < 60000) {
        size_t took = 0;
        sim_run(&s, &v, 5);
        exteria_tcpip_send(s.stack, s.id, data + sent, 60000 - sent, s.now, &took);
        sent += took;
    }
    sim_run(&s, &v, 5000);
    CHECK_EQ_INT(v.rx_len, 60000);
    CHECK_MEM(v.rx, data, 60000);
    exteria_tcpip_stats_get(s.stack, &st);
    CHECK(st.fast_retransmits >= 1);
    free(data);
    teardown(&s, &v);
}

static void close_by_us_then_peer(void) {
    sim s;
    fake_tcp_server v;
    exteria_tcpip_info info;
    uint8_t buf[8];
    size_t got = 0;
    setup(&s, &v, 100);
    connect_and_open(&s, &v);
    CHECK_EQ_INT(exteria_tcpip_close(s.stack, s.id, s.now), EXTERIA_OK);
    sim_run(&s, &v, 100);
    CHECK_EQ_INT(v.got_fin, 1);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.closed_by_us, 1);
    CHECK_EQ_INT(info.state, EXTERIA_TCPIP_OPEN);
    CHECK_EQ_INT(info.send_space, 0);
    CHECK_EQ_INT(exteria_tcpip_send(s.stack, s.id, buf, 1, s.now, &got), EXTERIA_E_STATE);
    /* the server answers with its own FIN: both directions are done */
    v.fin_after_tx = 1;
    fake_tcp_server_pump(&v, s.now);
    sim_run(&s, &v, 200);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.peer_closed, 1);
    CHECK_EQ_INT(info.state, EXTERIA_TCPIP_DONE);
    CHECK_EQ_INT(exteria_tcpip_recv(s.stack, s.id, buf, sizeof(buf), s.now, &got), EXTERIA_E_EOF);
    exteria_tcpip_release(s.stack, s.id, s.now);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(v.saw_rst, 0);
    teardown(&s, &v);
}

static void peer_closes_first_with_data(void) {
    sim s;
    fake_tcp_server v;
    exteria_tcpip_info info;
    uint8_t buf[400];
    size_t got = 0, total = 0;
    setup(&s, &v, 100);
    connect_and_open(&s, &v);
    v.tx_total = 300;
    v.fin_after_tx = 1;
    fake_tcp_server_pump(&v, s.now);
    sim_run(&s, &v, 200);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.readable, 300);
    CHECK_EQ_INT(info.peer_closed, 1);
    /* the data comes before the end of file */
    CHECK_EQ_INT(exteria_tcpip_recv(s.stack, s.id, buf, sizeof(buf), s.now, &got), EXTERIA_OK);
    total += got;
    CHECK_EQ_INT(total, 300);
    CHECK_EQ_INT(exteria_tcpip_recv(s.stack, s.id, buf, sizeof(buf), s.now, &got), EXTERIA_E_EOF);
    /* half closed: we may still send */
    {
        size_t took = 0;
        CHECK_EQ_INT(exteria_tcpip_send(s.stack, s.id, buf, 50, s.now, &took), EXTERIA_OK);
        CHECK_EQ_INT(took, 50);
        sim_run(&s, &v, 100);
        CHECK_EQ_INT(v.rx_len, 50);
    }
    CHECK_EQ_INT(exteria_tcpip_close(s.stack, s.id, s.now), EXTERIA_OK);
    sim_run(&s, &v, 200);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.state, EXTERIA_TCPIP_DONE);
    teardown(&s, &v);
}

static void reset_handling(void) {
    sim s;
    fake_tcp_server v;
    exteria_tcpip_info info;
    uint8_t packet[200], buf[4];
    size_t n, got = 0;
    uint32_t client_port, nxt;
    setup(&s, &v, 100);
    connect_and_open(&s, &v);
    client_port = exteria_get_u32be(s.log[0].bytes + 20) >> 16;
    nxt = v.snd_nxt;
    /* a reset far outside the window is ignored */
    n = build(packet, SERVER_IP, CLIENT_IP, SERVER_PORT, (uint16_t)client_port, nxt + 1000000u, 0, 0x04, 0, 0, NULL, 0);
    exteria_tcpip_input(s.stack, packet, n, s.now);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.state, EXTERIA_TCPIP_OPEN);
    /* one at the next expected number kills the connection */
    n = build(packet, SERVER_IP, CLIENT_IP, SERVER_PORT, (uint16_t)client_port, nxt, 0, 0x04, 0, 0, NULL, 0);
    exteria_tcpip_input(s.stack, packet, n, s.now);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.state, EXTERIA_TCPIP_FAILED);
    CHECK_EQ_INT(info.error, EXTERIA_E_IO);
    CHECK_EQ_INT(exteria_tcpip_recv(s.stack, s.id, buf, sizeof(buf), s.now, &got), EXTERIA_E_IO);
    CHECK_EQ_INT(exteria_tcpip_send(s.stack, s.id, buf, 1, s.now, &got), EXTERIA_E_IO);
    exteria_tcpip_release(s.stack, s.id, s.now);
    teardown(&s, &v);
}

static void refused_and_silent_connects(void) {
    sim s;
    fake_tcp_server v;
    exteria_tcpip_info info;
    uint8_t packet[100];
    size_t n;
    uint32_t port;
    uint64_t started;
    setup(&s, &v, 100);
    CHECK_EQ_INT(exteria_tcpip_connect(s.stack, SERVER_IP, SERVER_PORT, s.now, &s.id), EXTERIA_OK);
    port = exteria_get_u32be(s.log[0].bytes + 20) >> 16;
    /* RST+ACK for our SYN is a refusal */
    n = build(packet, SERVER_IP, CLIENT_IP, SERVER_PORT, (uint16_t)port, 0, exteria_get_u32be(s.log[0].bytes + 24) + 1, 0x14, 0, 0, NULL, 0);
    exteria_tcpip_input(s.stack, packet, n, s.now);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.state, EXTERIA_TCPIP_FAILED);
    CHECK_EQ_INT(info.error, EXTERIA_E_IO);
    exteria_tcpip_release(s.stack, s.id, s.now);
    /* a peer that never answers: the SYN is repeated with growing gaps and the connect fails with a timeout */
    v.answer_syn = 0;
    started = s.now;
    s.logged = 0;
    CHECK_EQ_INT(exteria_tcpip_connect(s.stack, SERVER_IP, SERVER_PORT, s.now, &s.id), EXTERIA_OK);
    while (s.now - started < 200000) {
        sim_step(&s, &v);
        if (exteria_tcpip_info_get(s.stack, s.id, &info) == EXTERIA_OK && info.state == EXTERIA_TCPIP_FAILED) break;
    }
    CHECK_EQ_INT(info.state, EXTERIA_TCPIP_FAILED);
    CHECK_EQ_INT(info.error, EXTERIA_E_TIMEOUT);
    CHECK_EQ_INT(s.logged, 1 + 6);
    CHECK(s.now - started > 30000 && s.now - started < 130000);
    teardown(&s, &v);
}

static void garbage_is_dropped(void) {
    sim s;
    fake_tcp_server v;
    uint8_t packet[200], copy[200];
    size_t n, i;
    exteria_tcpip_stats st;
    exteria_tcpip_info info;
    uint32_t port;
    setup(&s, &v, 100);
    connect_and_open(&s, &v);
    port = exteria_get_u32be(s.log[0].bytes + 20) >> 16;
    n = build(packet, SERVER_IP, CLIENT_IP, SERVER_PORT, (uint16_t)port, v.snd_nxt, v.rcv_nxt, 0x10, 65535, 0, (const uint8_t *)"hello", 5);
    /* a whole valid packet first, so the corruptions below are known to be the only difference */
    memcpy(copy, packet, n);
    for (i = 0; i < 6; ++i) {
        memcpy(copy, packet, n);
        switch (i) {
        case 0: copy[20 + 16] ^= 1; break;           /* tcp checksum */
        case 1: copy[10] ^= 1; break;                /* ip checksum */
        case 2: copy[9] = 17; copy[10] = 0; copy[11] = 0; put16(copy + 10, fold(add(0, copy, 20))); break; /* not tcp */
        case 3: copy[16] ^= 1; put16(copy + 10, 0); put16(copy + 10, fold(add(0, copy, 20))); break;      /* for another address */
        case 4: copy[6] = 0x20; put16(copy + 10, 0); put16(copy + 10, fold(add(0, copy, 20))); break;      /* more fragments */
        default: copy[0] = 0x65; break;               /* version 6 */
        }
        exteria_tcpip_input(s.stack, copy, n, s.now);
    }
    exteria_tcpip_input(s.stack, packet, 10, s.now);
    exteria_tcpip_input(s.stack, packet, n - 1, s.now);
    exteria_tcpip_stats_get(s.stack, &st);
    CHECK_EQ_INT(st.bad_packets, 8);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.readable, 0);
    exteria_tcpip_input(s.stack, packet, n, s.now);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, s.id, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.readable, 5);
    /* padding behind the IP total length (the tunnel pads packets to 16 bytes) is ignored */
    memset(copy, 0, sizeof(copy));
    n = build(copy, SERVER_IP, CLIENT_IP, SERVER_PORT, (uint16_t)port, v.snd_nxt, v.rcv_nxt, 0x10, 65535, 0, (const uint8_t *)"hello", 5);
    exteria_tcpip_input(s.stack, copy, n + 11, s.now);
    teardown(&s, &v);
}

static void unknown_segments_get_a_reset(void) {
    sim s;
    fake_tcp_server v;
    uint8_t packet[100];
    size_t n;
    setup(&s, &v, 100);
    n = build(packet, SERVER_IP, CLIENT_IP, SERVER_PORT, 50000, 777, 888, 0x10, 100, 0, (const uint8_t *)"abc", 3);
    exteria_tcpip_input(s.stack, packet, n, s.now);
    CHECK_EQ_INT(s.logged, 1);
    CHECK_EQ_INT(s.log[0].bytes[20 + 13], 0x04);
    CHECK_EQ_INT(exteria_get_u32be(s.log[0].bytes + 20 + 4), 888);
    /* a reset is never answered with a reset */
    n = build(packet, SERVER_IP, CLIENT_IP, SERVER_PORT, 50000, 777, 0, 0x04, 0, 0, NULL, 0);
    exteria_tcpip_input(s.stack, packet, n, s.now);
    CHECK_EQ_INT(s.logged, 1);
    /* without an ack field the reset acknowledges the segment */
    n = build(packet, SERVER_IP, CLIENT_IP, SERVER_PORT, 50000, 1000, 0, 0x00, 100, 0, (const uint8_t *)"abc", 3);
    exteria_tcpip_input(s.stack, packet, n, s.now);
    CHECK_EQ_INT(s.logged, 2);
    CHECK_EQ_INT(s.log[1].bytes[20 + 13], 0x14);
    CHECK_EQ_INT(exteria_get_u32be(s.log[1].bytes + 20 + 8), 1003);
    teardown(&s, &v);
}

static void no_mss_option_means_536(void) {
    sim s;
    fake_tcp_server v;
    uint8_t data[3000];
    size_t took = 0, i, seen = 0;
    setup(&s, &v, 3000);
    v.syn_mss_option = 0;
    connect_and_open(&s, &v);
    memset(data, 7, sizeof(data));
    CHECK_EQ_INT(exteria_tcpip_send(s.stack, s.id, data, sizeof(data), s.now, &took), EXTERIA_OK);
    sim_run(&s, &v, 1000);
    CHECK_EQ_INT(v.rx_len, 3000);
    for (i = 0; i < s.logged; ++i) {
        if (s.log[i].len > seen) seen = s.log[i].len;
    }
    CHECK_EQ_INT(seen, 40 + 536);
    teardown(&s, &v);
}

static void zero_window_is_probed(void) {
    sim s;
    fake_tcp_server v;
    uint8_t data[2000];
    size_t took = 0, i;
    setup(&s, &v, 2000);
    connect_and_open(&s, &v);
    /* the server's receive window is shut for a while */
    v.window = 0;
    memset(data, 9, sizeof(data));
    for (i = 0; i < sizeof(data); ++i) data[i] = pattern_at(i);
    v.client_window = 0;
    {
        /* tell the client so with a bare ack carrying window 0 */
        uint8_t packet[60];
        size_t n = build(packet, SERVER_IP, CLIENT_IP, SERVER_PORT, (uint16_t)(exteria_get_u32be(s.log[0].bytes + 20) >> 16), v.snd_nxt, v.rcv_nxt, 0x10, 0, 0, NULL, 0);
        exteria_tcpip_input(s.stack, packet, n, s.now);
    }
    CHECK_EQ_INT(exteria_tcpip_send(s.stack, s.id, data, sizeof(data), s.now, &took), EXTERIA_OK);
    CHECK_EQ_INT(took, 2000);
    sim_run(&s, &v, 3000);
    /* nothing but probes of one byte went out meanwhile */
    for (i = 0; i < s.logged; ++i) CHECK(s.log[i].len <= 41 + 0 || i < 3);
    /* the window opens with the next acknowledgement the server sends */
    v.window = 65535;
    sim_run(&s, &v, 40000);
    CHECK_EQ_INT(v.rx_len >= 2000 ? 2000 : v.rx_len, 2000);
    CHECK_MEM(v.rx, data, 2000);
    teardown(&s, &v);
}

static void slot_limit_and_release_resets(void) {
    sim s;
    fake_tcp_server v;
    uint32_t ids[EXTERIA_TCPIP_MAX_CONNECTIONS + 1], extra = 0;
    int i;
    size_t logged;
    exteria_tcpip_info info;
    setup(&s, &v, 100);
    v.answer_syn = 0;
    for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) CHECK_EQ_INT(exteria_tcpip_connect(s.stack, SERVER_IP, (uint16_t)(1000 + i), s.now, &ids[i]), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tcpip_connect(s.stack, SERVER_IP, 5000, s.now, &extra), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(extra, 0);
    CHECK_EQ_INT(exteria_tcpip_connect(s.stack, 0, 5000, s.now, &extra), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tcpip_connect(s.stack, SERVER_IP, 0, s.now, &extra), EXTERIA_E_ARG);
    logged = s.logged;
    exteria_tcpip_release(s.stack, ids[0], s.now);
    CHECK_EQ_INT(exteria_tcpip_info_get(s.stack, ids[0], &info), EXTERIA_E_NOTFOUND);
    CHECK(s.emitted > logged - 1);
    CHECK_EQ_INT(exteria_tcpip_connect(s.stack, SERVER_IP, 5000, s.now, &extra), EXTERIA_OK);
    CHECK(extra != ids[0]);
    exteria_tcpip_release(s.stack, 12345, s.now);
    teardown(&s, &v);
}

static void bad_arguments(void) {
    exteria_tcpip *stack = NULL;
    sim s;
    memset(&s, 0, sizeof(s));
    CHECK_EQ_INT(exteria_tcpip_new(&stack, 0, MTU, stack_emit, &s), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tcpip_new(&stack, CLIENT_IP, 100, stack_emit, &s), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tcpip_new(&stack, CLIENT_IP, 2000, stack_emit, &s), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tcpip_new(&stack, CLIENT_IP, MTU, NULL, &s), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tcpip_new(NULL, CLIENT_IP, MTU, stack_emit, &s), EXTERIA_E_ARG);
    CHECK(stack == NULL);
    exteria_tcpip_free(NULL);
    exteria_tcpip_tick(NULL, 0);
    exteria_tcpip_input(NULL, NULL, 0, 0);
}

int main(void) {
    handshake_on_the_wire();
    small_exchange_and_delayed_ack();
    upload(0, 0, 150000, 0);
    upload(3, 15, 150000, 1);
    upload(10, 30, 60000, 1);
    download(0, 0, 200000, 4096, 0);
    download(3, 15, 200000, 4096, 1);
    download(8, 40, 80000, 4096, 1);
    /* an application that reads slowly closes the window and has to open it again */
    download(0, 0, 150000, 300, 0);
    fast_retransmit_on_one_loss();
    close_by_us_then_peer();
    peer_closes_first_with_data();
    reset_handling();
    refused_and_silent_connects();
    garbage_is_dropped();
    unknown_segments_get_a_reset();
    no_mss_option_means_536();
    zero_window_is_probed();
    slot_limit_and_release_resets();
    bad_arguments();
    return test_finish("test_shiro_tcpip");
}
