#include "exteria_clock.h"
#include "exteria_shiro_engine.h"
#include "exteria_udp.h"
#include "shiro_responder.h"
#include "test_util.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <sys/socket.h>
#include <unistd.h>

#define CLIENT_ADDRESS 0xac100002u
#define PEER_ADDRESS 0x08080808u
#define PEER_PORT 3478

/* a WireGuard server that lives in the test */
typedef struct server {
    int fd;
    uint16_t port;
    responder r;
    exteria_wg_session session;
    struct sockaddr_in client;
    socklen_t client_len;
    int have_session;
    int initiations;
} server;

typedef struct watch {
    pthread_mutex_t lock;
    exteria_shiro_state state;
    exteria_status reason;
} watch;

static void on_state(void *context, exteria_shiro_state state, exteria_status reason) {
    watch *w = (watch *)context;
    pthread_mutex_lock(&w->lock);
    w->state = state;
    w->reason = reason;
    pthread_mutex_unlock(&w->lock);
}

static exteria_shiro_state watched(watch *w) {
    exteria_shiro_state s;
    pthread_mutex_lock(&w->lock);
    s = w->state;
    pthread_mutex_unlock(&w->lock);
    return s;
}

static void nonblocking(int fd) {
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
}

static void server_start(server *s, const uint8_t priv[32], const uint8_t client_pub[32]) {
    struct sockaddr_in a;
    socklen_t len = sizeof(a);
    memset(s, 0, sizeof(*s));
    s->fd = socket(AF_INET, SOCK_DGRAM, 0);
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(s->fd, (struct sockaddr *)&a, sizeof(a)) == 0);
    getsockname(s->fd, (struct sockaddr *)&a, &len);
    s->port = ntohs(a.sin_port);
    nonblocking(s->fd);
    responder_init(&s->r, priv, client_pub);
}

/* one datagram of the client's, or the plain bytes of a data message once the session exists; returns the plain length, 0 for nothing, -1 for a handshake */
static long server_step(server *s, int wait_ms, uint8_t *plain, size_t cap) {
    uint8_t raw[2048], response[EXTERIA_WG_RESPONSE_LEN];
    struct pollfd p;
    ssize_t n;
    p.fd = s->fd;
    p.events = POLLIN;
    p.revents = 0;
    if (poll(&p, 1, wait_ms) <= 0) return 0;
    s->client_len = sizeof(s->client);
    n = recvfrom(s->fd, raw, sizeof(raw), 0, (struct sockaddr *)&s->client, &s->client_len);
    if (n <= 0) return 0;
    if (n == 148 && (exteria_get_u32le(raw) & 0xffu) == 1u) {
        if (responder_answer(&s->r, raw, response, 1, 2) != 0) return 0;
        sendto(s->fd, response, sizeof(response), 0, (struct sockaddr *)&s->client, s->client_len);
        memset(&s->session, 0, sizeof(s->session));
        memcpy(s->session.send_key, s->r.send_key, 32);
        memcpy(s->session.recv_key, s->r.recv_key, 32);
        s->session.local_index = s->r.index;
        s->session.remote_index = s->r.peer_index;
        s->session.data_type = 4;
        s->session.active = 1;
        s->have_session = 1;
        ++s->initiations;
        return -1;
    }
    if (!s->have_session) return 0;
    {
        size_t plain_len = 0;
        if (exteria_wg_open(&s->session, raw, (size_t)n, plain, cap, &plain_len) != EXTERIA_OK) return 0;
        return (long)plain_len;
    }
}

static void server_send_udp(server *s, uint32_t src_ip, uint16_t src_port, uint16_t dst_port, const char *text) {
    uint8_t packet[EXTERIA_UDP_PACKET_MAX], sealed[EXTERIA_WG_MAX_DATAGRAM];
    size_t packet_len = 0, sealed_len = 0;
    CHECK_EQ_INT(exteria_udp_build(src_ip, src_port, CLIENT_ADDRESS, dst_port, 9, (const uint8_t *)text, strlen(text), packet, sizeof(packet), &packet_len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_wg_seal(&s->session, packet, packet_len, sealed, sizeof(sealed), &sealed_len), EXTERIA_OK);
    sendto(s->fd, sealed, sealed_len, 0, (struct sockaddr *)&s->client, s->client_len);
}

/* the next UDP packet the client sent through the tunnel, within wait_ms; keepalives and other messages are skipped */
static int server_expect_udp(server *s, int wait_ms, exteria_udp_datagram *d, uint8_t *keep, size_t keep_cap) {
    uint64_t end = exteria_system_clock.monotonic_ms(NULL) + (uint64_t)wait_ms;
    while (exteria_system_clock.monotonic_ms(NULL) < end) {
        long n = server_step(s, 50, keep, keep_cap);
        if (n > 0 && exteria_udp_parse(keep, (size_t)n, d) == EXTERIA_OK) return 1;
    }
    return 0;
}

static int wait_readable(int fd, int ms) {
    struct pollfd p;
    p.fd = fd;
    p.events = POLLIN;
    p.revents = 0;
    return poll(&p, 1, ms) > 0 && (p.revents & POLLIN);
}

int main(void) {
    uint8_t client_priv[32], client_pub[32], server_priv[32], server_pub[32];
    uint8_t plain[EXTERIA_WG_MAX_DATAGRAM], frame[EXTERIA_UDP_FRAME_HEADER + EXTERIA_UDP_MAX_PAYLOAD + 8];
    exteria_warp_identity id;
    exteria_shiro_events events;
    exteria_shiro_engine *engine = NULL;
    watch w;
    server s;
    exteria_udp_datagram d;
    size_t frame_len = 0;
    int fd = -1, fds[32], i;
    uint64_t end;

    exteria_random(client_priv, 32);
    client_priv[0] &= 248;
    client_priv[31] = (uint8_t)((client_priv[31] & 127) | 64);
    exteria_x25519_public(client_priv, client_pub);
    exteria_random(server_priv, 32);
    server_priv[0] &= 248;
    server_priv[31] = (uint8_t)((server_priv[31] & 127) | 64);
    exteria_x25519_public(server_priv, server_pub);
    server_start(&s, server_priv, client_pub);

    memset(&id, 0, sizeof(id));
    memcpy(id.private_key, client_priv, 32);
    memcpy(id.peer_public, server_pub, 32);
    id.address = CLIENT_ADDRESS;
    id.endpoint_ip = 0x7f000001u;
    id.ports[0] = s.port;
    id.port_count = 1;

    pthread_mutex_init(&w.lock, NULL);
    w.state = EXTERIA_SHIRO_HANDSHAKING;
    w.reason = EXTERIA_OK;
    events.context = &w;
    events.state = on_state;
    events.trace = NULL;
    CHECK_EQ_INT(exteria_shiro_engine_start(&engine, &id, id.endpoint_ip, id.ports[0], &events), EXTERIA_OK);
    if (!engine) return 1;

    /* no datagram socket before the tunnel is up */
    CHECK_EQ_INT(exteria_shiro_engine_open_udp(engine, &fd), EXTERIA_E_STATE);
    CHECK_EQ_INT(fd, -1);

    end = exteria_system_clock.monotonic_ms(NULL) + 5000;
    while (watched(&w) != EXTERIA_SHIRO_UP && exteria_system_clock.monotonic_ms(NULL) < end) server_step(&s, 20, plain, sizeof(plain));
    CHECK_EQ_INT(watched(&w), EXTERIA_SHIRO_UP);

    CHECK_EQ_INT(exteria_shiro_engine_open_udp(engine, &fd), EXTERIA_OK);
    CHECK(fd >= 0);

    /* out: a framed datagram becomes a UDP packet from the address of the phone and a port of the tunnel's choosing */
    CHECK_EQ_INT(exteria_udp_frame_encode(PEER_ADDRESS, PEER_PORT, (const uint8_t *)"ping", 4, frame, sizeof(frame), &frame_len), EXTERIA_OK);
    CHECK_EQ_INT(send(fd, frame, frame_len, 0), (ssize_t)frame_len);
    CHECK(server_expect_udp(&s, 3000, &d, plain, sizeof(plain)));
    CHECK_EQ_INT(d.src_ip, CLIENT_ADDRESS);
    CHECK_EQ_INT(d.dst_ip, PEER_ADDRESS);
    CHECK_EQ_INT(d.dst_port, PEER_PORT);
    CHECK(d.src_port >= 49152);
    CHECK_EQ_INT(d.payload_len, 4);
    CHECK_MEM(d.payload, "ping", 4);
    {
        uint16_t local_port = d.src_port;

        /* in: a reply to that port comes back as a frame that names its sender */
        server_send_udp(&s, PEER_ADDRESS, PEER_PORT, local_port, "pong");
        CHECK(wait_readable(fd, 3000));
        {
            ssize_t n = recv(fd, frame, sizeof(frame), 0);
            uint32_t ip = 0;
            uint16_t port = 0;
            const uint8_t *payload = NULL;
            size_t payload_len = 0;
            CHECK(n > 0);
            CHECK_EQ_INT(exteria_udp_frame_decode(frame, (size_t)(n > 0 ? n : 0), &ip, &port, &payload, &payload_len), EXTERIA_OK);
            CHECK_EQ_INT(ip, PEER_ADDRESS);
            CHECK_EQ_INT(port, PEER_PORT);
            CHECK_EQ_INT(payload_len, 4);
            CHECK_MEM(payload, "pong", 4);
        }

        /* a datagram from any other peer reaches the socket too, as for an unconnected UDP socket */
        server_send_udp(&s, 0x01020304u, 9999, local_port, "other");
        CHECK(wait_readable(fd, 3000));
        {
            ssize_t n = recv(fd, frame, sizeof(frame), 0);
            uint32_t ip = 0;
            uint16_t port = 0;
            const uint8_t *payload = NULL;
            size_t payload_len = 0;
            CHECK_EQ_INT(exteria_udp_frame_decode(frame, (size_t)(n > 0 ? n : 0), &ip, &port, &payload, &payload_len), EXTERIA_OK);
            CHECK_EQ_INT(ip, 0x01020304u);
            CHECK_EQ_INT(port, 9999);
        }

        /* a port that no socket holds is dropped */
        server_send_udp(&s, PEER_ADDRESS, PEER_PORT, (uint16_t)(local_port + 1), "nobody");
        CHECK(!wait_readable(fd, 400));
    }

    /* bad frames are dropped: too short, no destination, a payload over the limit; nothing of them reaches the server */
    {
        static uint8_t big[EXTERIA_UDP_FRAME_HEADER + EXTERIA_UDP_MAX_PAYLOAD + 1];
        uint8_t zero_dest[EXTERIA_UDP_FRAME_HEADER + 2] = {0, 0, 0, 0, 0, 0, 'h', 'i'};
        memset(big, 'x', sizeof(big));
        memcpy(big, "\x08\x08\x08\x08\x0d\x96", 6);
        CHECK(send(fd, big, 3, 0) == 3);
        CHECK(send(fd, zero_dest, sizeof(zero_dest), 0) == (ssize_t)sizeof(zero_dest));
        CHECK(send(fd, big, sizeof(big), 0) == (ssize_t)sizeof(big));
        CHECK(!server_expect_udp(&s, 400, &d, plain, sizeof(plain)));
    }

    /* the largest payload goes through whole */
    {
        static uint8_t full[EXTERIA_UDP_MAX_PAYLOAD];
        memset(full, 0x5a, sizeof(full));
        CHECK_EQ_INT(exteria_udp_frame_encode(PEER_ADDRESS, PEER_PORT, full, sizeof(full), frame, sizeof(frame), &frame_len), EXTERIA_OK);
        CHECK(send(fd, frame, frame_len, 0) == (ssize_t)frame_len);
        CHECK(server_expect_udp(&s, 3000, &d, plain, sizeof(plain)));
        CHECK_EQ_INT(d.payload_len, EXTERIA_UDP_MAX_PAYLOAD);
        CHECK_MEM(d.payload, full, sizeof(full));
    }

    /* the sockets are limited, and a refused one leaves nothing behind */
    for (i = 0; i < 32; ++i) fds[i] = -1;
    for (i = 0; i < 15; ++i) CHECK_EQ_INT(exteria_shiro_engine_open_udp(engine, &fds[i]), EXTERIA_OK);
    {
        int extra = 7;
        CHECK_EQ_INT(exteria_shiro_engine_open_udp(engine, &extra), EXTERIA_E_LIMIT);
        CHECK_EQ_INT(extra, -1);
    }
    /* a socket that is closed makes room again, once the tunnel has noticed that its other end is gone */
    close(fd);
    fd = -1;
    for (i = 0; i < 15; ++i) close(fds[i]);
    end = exteria_system_clock.monotonic_ms(NULL) + 3000;
    while (exteria_system_clock.monotonic_ms(NULL) < end) {
        if (exteria_shiro_engine_open_udp(engine, &fd) == EXTERIA_OK) break;
        usleep(20000);
    }
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);

    /* a stream whose far side never answers is not a dead path for twenty seconds yet, so the tunnel starts no
       handshake of its own meanwhile */
    {
        int stream = -1;
        uint64_t drain_end;
        CHECK_EQ_INT(s.initiations, 1);
        CHECK_EQ_INT(exteria_shiro_engine_open(engine, PEER_ADDRESS, 443, 700, &stream), EXTERIA_E_TIMEOUT);
        drain_end = exteria_system_clock.monotonic_ms(NULL) + 400;
        while (exteria_system_clock.monotonic_ms(NULL) < drain_end) server_step(&s, 20, plain, sizeof(plain));
        CHECK_EQ_INT(s.initiations, 1);
    }

    exteria_shiro_engine_stop(engine);
    close(s.fd);
    pthread_mutex_destroy(&w.lock);
    return test_finish("test_shiro_engine_udp");
}
