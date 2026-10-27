#include "exteria_shiro_engine.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "exteria_bytes.h"
#include "exteria_clock.h"
#include "exteria_random.h"
#include "exteria_tcpip.h"
#include "exteria_udp.h"
#include "exteria_wg.h"

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

#define MAX_PENDING 16
#define MAX_UDP 16
#define UDP_BURST 16
/* a datagram socket nobody wrote to or read from for this long is let go: a peer that closed its end of a datagram pair is not always reported */
#define UDP_IDLE_MS 300000u
/* a local datagram pair does not report that the other end closed (a read just waits for ever), but a write to it
   fails */
#define UDP_PROBE_MS 2000u
#define UDP_PORT_FIRST 49152u
#define UDP_PORT_COUNT 16384u
#define LOOP_TICK_MS 20
#define HANDSHAKE_WAIT_MS 4000u
#define HANDSHAKE_ATTEMPTS 4u
#define LIVENESS_MS 20000u
#define PREVIOUS_SESSION_MS 15000u
#define REKEY_RETRY_MS 10000u
#define RELAY_BUFFER 16384
#define STREAM_BUFFER 65536
#define UDP_BUFFER 262144
#define THREAD_STACK (512u * 1024u)

typedef struct pending {
    int fd;
    uint32_t ip;
    uint16_t port;
    uint64_t deadline;
} pending;

typedef struct relay {
    int used;
    int fd;
    uint32_t conn;
    int open;
    uint64_t deadline;
    uint8_t out[RELAY_BUFFER];
    size_t out_len, out_off;
    int fd_eof, shut_wr;
} relay;

typedef struct udp_socket {
    int used;
    int fd;
    uint16_t port;
    uint64_t last_ms, probed_ms;
} udp_socket;

struct exteria_shiro_engine {
    exteria_warp_identity identity;
    exteria_warp_profile profile;
    exteria_wg_config wg;
    uint32_t endpoint_ip;
    uint16_t endpoint_port;
    exteria_shiro_events events;
    pthread_t thread;
    int thread_started;
    pthread_mutex_t lock;
    int wake[2];
    int stop;
    exteria_shiro_state state;
    pending queue[MAX_PENDING];
    size_t queue_count;
    exteria_shiro_stats stats;
    int udp_queue[MAX_UDP];
    size_t udp_queue_count;
    /* sockets queued or adopted, so the limit holds before the thread has taken them */
    size_t udp_held;

    /* everything below belongs to the thread */
    int udp;
    exteria_wg_handshake hs;
    int hs_pending;
    uint64_t hs_sent_ms;
    unsigned hs_attempts;
    uint64_t next_rekey_ms;
    exteria_wg_session session, previous;
    uint64_t previous_until;
    exteria_tcpip *stack;
    uint64_t last_rx_ms, last_tx_ms, unanswered_since;
    uint64_t bytes_in, bytes_out;
    uint32_t handshakes;
    relay relays[EXTERIA_TCPIP_MAX_CONNECTIONS];
    udp_socket udps[MAX_UDP];
    uint16_t udp_ident;
    uint16_t udp_next_port;
};

static uint64_t now_ms(void) {
    return exteria_system_clock.monotonic_ms(NULL);
}

/* milliseconds from a stamp to now, never negative */
static uint64_t elapsed_ms(uint64_t now, uint64_t since) {
    return now > since ? now - since : 0;
}

static void trace(exteria_shiro_engine *e, const char *format, ...) {
    char line[160];
    va_list args;
    if (!e->events.trace) return;
    va_start(args, format);
    vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    e->events.trace(e->events.context, line);
}

static void set_state(exteria_shiro_engine *e, exteria_shiro_state state, exteria_status reason) {
    pthread_mutex_lock(&e->lock);
    e->state = state;
    pthread_mutex_unlock(&e->lock);
    if (e->events.state) e->events.state(e->events.context, state, reason);
}

static void udp_out(exteria_shiro_engine *e, const uint8_t *data, size_t len) {
    ssize_t n = send(e->udp, data, len, MSG_NOSIGNAL);
    /* a full socket buffer or a route that is gone for a moment drops the datagram, as the network would, and the layers above resend */
    if (n > 0) e->bytes_out += (uint64_t)n;
}

static void handshake_emit(void *context, const uint8_t *data, size_t len) {
    udp_out((exteria_shiro_engine *)context, data, len);
}

/* counts says whether the datagram is something that an answer is expected to: a TCP segment is acknowledged, but a UDP datagram to a silent peer is not
   a sign of a dead path */
static void send_datagram_as(exteria_shiro_engine *e, const uint8_t *plain, size_t len, uint64_t now, int counts) {
    uint8_t out[EXTERIA_WG_MAX_DATAGRAM];
    size_t n = 0;
    if (!e->session.active) return;
    if (exteria_wg_seal(&e->session, plain, len, out, sizeof(out), &n) != EXTERIA_OK) return;
    udp_out(e, out, n);
    e->last_tx_ms = now;
    /* what is sent and not answered is how a dead path shows itself; a keepalive does not count, it is the answer that is wanted from data */
    if (counts && len > 0 && e->unanswered_since == 0) e->unanswered_since = now;
}

static void send_datagram(exteria_shiro_engine *e, const uint8_t *plain, size_t len, uint64_t now) {
    send_datagram_as(e, plain, len, now, 1);
}

static void stack_emit(void *context, const uint8_t *packet, size_t len) {
    exteria_shiro_engine *e = (exteria_shiro_engine *)context;
    send_datagram(e, packet, len, now_ms());
}

static void begin_handshake(exteria_shiro_engine *e, uint64_t now) {
    struct timeval tv;
    exteria_status status;
    gettimeofday(&tv, NULL);
    status = exteria_wg_handshake_begin(&e->hs, &e->wg, (uint64_t)tv.tv_sec, (uint32_t)tv.tv_usec * 1000u, handshake_emit, e);
    if (status != EXTERIA_OK) {
        trace(e, "handshake could not be built (%s)", exteria_status_name(status));
        e->hs_pending = 0;
        return;
    }
    e->hs_pending = 1;
    e->hs_sent_ms = now;
    ++e->hs_attempts;
    trace(e, "handshake sent, attempt %u", e->hs_attempts);
}

static void on_handshake_done(exteria_shiro_engine *e, const exteria_wg_session *fresh, uint64_t now) {
    int first = !e->session.active;
    if (!first) {
        e->previous = e->session;
        e->previous_until = now + PREVIOUS_SESSION_MS;
    }
    e->session = *fresh;
    e->hs_pending = 0;
    e->hs_attempts = 0;
    e->next_rekey_ms = 0;
    ++e->handshakes;
    e->unanswered_since = 0;
    e->last_rx_ms = now;
    /* the keepalive is what tells the server that the new keys work, since a responder only starts using them once the initiator has sent with them */
    send_datagram(e, NULL, 0, now);
    if (first) {
        exteria_tcpip_new(&e->stack, e->identity.address, EXTERIA_WARP_MTU, stack_emit, e);
        trace(e, "tunnel up after %llu ms", (unsigned long long)(now - e->hs_sent_ms));
        if (!e->stack) {
            set_state(e, EXTERIA_SHIRO_DOWN, EXTERIA_E_NOMEM);
            return;
        }
        set_state(e, EXTERIA_SHIRO_UP, EXTERIA_OK);
    } else {
        trace(e, "keys renewed");
    }
}

static void deliver_udp(exteria_shiro_engine *e, const uint8_t *packet, size_t len, uint64_t now);

static void on_datagram(exteria_shiro_engine *e, const uint8_t *data, size_t len, uint64_t now) {
    uint8_t plain[EXTERIA_WG_MAX_DATAGRAM];
    size_t plain_len = 0;
    exteria_status status;
    e->bytes_in += len;
    if (e->hs_pending) {
        exteria_wg_session fresh;
        status = exteria_wg_handshake_finish(&e->hs, data, len, now, &fresh);
        if (status == EXTERIA_OK) {
            on_handshake_done(e, &fresh, now);
            exteria_wg_session_clear(&fresh);
            return;
        }
        if (status == EXTERIA_E_SECURITY) {
            /* the peer answered and the answer does not check out: a wrong key on either side, not a network problem */
            trace(e, "handshake answer rejected");
            e->hs_pending = 0;
            if (!e->session.active) {
                set_state(e, EXTERIA_SHIRO_DOWN, EXTERIA_E_SECURITY);
                return;
            }
            e->hs_attempts = 0;
            e->next_rekey_ms = now + REKEY_RETRY_MS;
            return;
        }
        /* anything else may be traffic of the current session that crossed the handshake */
    }
    if (!e->session.active) return;
    status = exteria_wg_open(&e->session, data, len, plain, sizeof(plain), &plain_len);
    if (status == EXTERIA_E_MALFORMED && e->previous.active) status = exteria_wg_open(&e->previous, data, len, plain, sizeof(plain), &plain_len);
    if (status != EXTERIA_OK) return;
    e->last_rx_ms = now;
    e->unanswered_since = 0;
    if (plain_len == 0) return;
    if (exteria_udp_is_udp(plain, plain_len)) deliver_udp(e, plain, plain_len, now);
    else if (e->stack) exteria_tcpip_input(e->stack, plain, plain_len, now);
}

static void drop_udp(exteria_shiro_engine *e, udp_socket *u) {
    if (u->fd >= 0) close(u->fd);
    memset(u, 0, sizeof(*u));
    u->fd = -1;
    pthread_mutex_lock(&e->lock);
    if (e->udp_held > 0) --e->udp_held;
    pthread_mutex_unlock(&e->lock);
}

/* a datagram from the far side, handed to the socket that owns the local port it was sent to; a port nobody holds is dropped, as a host without a listener
   would, and a packet that is not valid UDP is dropped without an answer */
static void deliver_udp(exteria_shiro_engine *e, const uint8_t *packet, size_t len, uint64_t now) {
    exteria_udp_datagram d;
    uint8_t frame[EXTERIA_UDP_FRAME_HEADER + EXTERIA_UDP_MAX_PAYLOAD];
    size_t frame_len = 0, i;
    if (exteria_udp_parse(packet, len, &d) != EXTERIA_OK) return;
    if (d.dst_ip != e->identity.address || d.src_ip == 0 || d.src_port == 0) return;
    for (i = 0; i < MAX_UDP; ++i) {
        udp_socket *u = &e->udps[i];
        ssize_t n;
        if (!u->used || u->port != d.dst_port) continue;
        if (exteria_udp_frame_encode(d.src_ip, d.src_port, d.payload, d.payload_len, frame, sizeof(frame), &frame_len) != EXTERIA_OK) return;
        n = send(u->fd, frame, frame_len, MSG_NOSIGNAL);
        if (n >= 0) {
            u->last_ms = now;
        } else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != ENOBUFS && errno != EINTR) {
            /* the other end is gone */
            drop_udp(e, u);
        }
        return;
    }
}

/* takes the datagram sockets that callers have made since the last pass and gives each a local port of its own */
static void adopt_udp(exteria_shiro_engine *e, uint64_t now) {
    int taken[MAX_UDP];
    size_t count, i;
    pthread_mutex_lock(&e->lock);
    count = e->udp_queue_count;
    memcpy(taken, e->udp_queue, count * sizeof(int));
    e->udp_queue_count = 0;
    pthread_mutex_unlock(&e->lock);
    for (i = 0; i < count; ++i) {
        udp_socket *u = NULL;
        size_t k, tries;
        for (k = 0; k < MAX_UDP && !u; ++k) {
            if (!e->udps[k].used) u = &e->udps[k];
        }
        if (u) {
            uint16_t port = 0;
            /* the ports run in order from a random start, so two sockets never share one */
            for (tries = 0; tries < UDP_PORT_COUNT && port == 0; ++tries) {
                uint16_t candidate = (uint16_t)(UDP_PORT_FIRST + (e->udp_next_port + tries) % UDP_PORT_COUNT);
                int free_port = 1;
                for (k = 0; k < MAX_UDP; ++k) {
                    if (e->udps[k].used && e->udps[k].port == candidate) free_port = 0;
                }
                if (free_port) port = candidate;
            }
            if (port) {
                e->udp_next_port = (uint16_t)((port - UDP_PORT_FIRST + 1u) % UDP_PORT_COUNT);
                u->used = 1;
                u->fd = taken[i];
                u->port = port;
                u->last_ms = now;
                continue;
            }
        }
        close(taken[i]);
        pthread_mutex_lock(&e->lock);
        if (e->udp_held > 0) --e->udp_held;
        pthread_mutex_unlock(&e->lock);
    }
}

/* the datagrams a caller wrote to its socket, framed with the peer they go to, become UDP packets in the tunnel */
static void pump_udp(exteria_shiro_engine *e, udp_socket *u, uint64_t now) {
    uint8_t frame[EXTERIA_UDP_FRAME_HEADER + EXTERIA_UDP_MAX_PAYLOAD + 1];
    int burst;
    if (elapsed_ms(now, u->last_ms) >= UDP_IDLE_MS) {
        drop_udp(e, u);
        return;
    }
    if (elapsed_ms(now, u->last_ms) >= UDP_PROBE_MS && elapsed_ms(now, u->probed_ms) >= UDP_PROBE_MS) {
        u->probed_ms = now;
        if (send(u->fd, frame, 0, MSG_NOSIGNAL) < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != ENOBUFS && errno != EINTR) {
            drop_udp(e, u);
            return;
        }
    }
    for (burst = 0; burst < UDP_BURST; ++burst) {
        uint8_t packet[EXTERIA_UDP_PACKET_MAX];
        const uint8_t *payload = NULL;
        size_t payload_len = 0, packet_len = 0;
        uint32_t ip = 0;
        uint16_t port = 0;
        ssize_t n = recv(u->fd, frame, sizeof(frame), 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK) drop_udp(e, u);
            return;
        }
        u->last_ms = now;
        /* a frame with no destination, or with a payload over the limit, is dropped like any other bad datagram */
        if (exteria_udp_frame_decode(frame, (size_t)n, &ip, &port, &payload, &payload_len) != EXTERIA_OK) continue;
        if (exteria_udp_build(e->identity.address, u->port, ip, port, ++e->udp_ident, payload, payload_len, packet, sizeof(packet), &packet_len) != EXTERIA_OK) continue;
        send_datagram_as(e, packet, packet_len, now, 0);
    }
}

static void drop_relay(exteria_shiro_engine *e, relay *r, uint64_t now) {
    if (e->stack && r->conn) exteria_tcpip_release(e->stack, r->conn, now);
    if (r->fd >= 0) close(r->fd);
    memset(r, 0, sizeof(*r));
    r->fd = -1;
}

static void adopt_pending(exteria_shiro_engine *e, uint64_t now) {
    pending taken[MAX_PENDING];
    size_t count, i;
    pthread_mutex_lock(&e->lock);
    count = e->queue_count;
    memcpy(taken, e->queue, count * sizeof(pending));
    e->queue_count = 0;
    pthread_mutex_unlock(&e->lock);
    for (i = 0; i < count; ++i) {
        relay *r = NULL;
        uint32_t id = 0;
        size_t k;
        for (k = 0; k < EXTERIA_TCPIP_MAX_CONNECTIONS; ++k) {
            if (!e->relays[k].used) {
                r = &e->relays[k];
                break;
            }
        }
        if (!r || !e->stack || exteria_tcpip_connect(e->stack, taken[i].ip, taken[i].port, now, &id) != EXTERIA_OK) {
            /* the caller waits for a first byte and sees the end of the stream instead */
            close(taken[i].fd);
            continue;
        }
        memset(r, 0, sizeof(*r));
        r->used = 1;
        r->fd = taken[i].fd;
        r->conn = id;
        r->deadline = taken[i].deadline;
    }
}

/* moves bytes between a stream and its connection, as far as both will go now */
static void pump_relay(exteria_shiro_engine *e, relay *r, uint64_t now) {
    exteria_tcpip_info info;
    uint8_t chunk[RELAY_BUFFER];
    if (exteria_tcpip_info_get(e->stack, r->conn, &info) != EXTERIA_OK) {
        drop_relay(e, r, now);
        return;
    }
    if (info.state == EXTERIA_TCPIP_FAILED) {
        drop_relay(e, r, now);
        return;
    }
    if (info.state == EXTERIA_TCPIP_CONNECTING) {
        if (now >= r->deadline) drop_relay(e, r, now);
        return;
    }
    if (!r->open) {
        uint8_t ready = 0;
        /* the first byte tells the caller that the far side answered; it is not data */
        if (send(r->fd, &ready, 1, MSG_NOSIGNAL) != 1) {
            drop_relay(e, r, now);
            return;
        }
        r->open = 1;
    }
    /* connection to stream */
    if (r->out_off < r->out_len) {
        ssize_t n = send(r->fd, r->out + r->out_off, r->out_len - r->out_off, MSG_NOSIGNAL);
        if (n > 0) {
            r->out_off += (size_t)n;
        } else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
            drop_relay(e, r, now);
            return;
        }
    }
    if (r->out_off >= r->out_len) {
        r->out_off = r->out_len = 0;
        if (info.readable > 0) {
            size_t got = 0;
            if (exteria_tcpip_recv(e->stack, r->conn, r->out, sizeof(r->out), now, &got) == EXTERIA_OK && got > 0) {
                ssize_t n;
                r->out_len = got;
                n = send(r->fd, r->out, r->out_len, MSG_NOSIGNAL);
                if (n > 0) r->out_off = (size_t)n;
                else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
                    drop_relay(e, r, now);
                    return;
                }
                if (r->out_off >= r->out_len) r->out_off = r->out_len = 0;
            }
        } else if (info.peer_closed && !r->shut_wr) {
            shutdown(r->fd, SHUT_WR);
            r->shut_wr = 1;
        }
    }
    /* stream to connection */
    if (!r->fd_eof && info.state == EXTERIA_TCPIP_OPEN && !info.closed_by_us && info.send_space > 0) {
        size_t want = info.send_space < sizeof(chunk) ? info.send_space : sizeof(chunk);
        ssize_t n = recv(r->fd, chunk, want, 0);
        if (n > 0) {
            size_t taken = 0;
            exteria_tcpip_send(e->stack, r->conn, chunk, (size_t)n, now, &taken);
        } else if (n == 0) {
            r->fd_eof = 1;
            exteria_tcpip_close(e->stack, r->conn, now);
        } else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
            drop_relay(e, r, now);
            return;
        }
    }
    if (exteria_tcpip_info_get(e->stack, r->conn, &info) == EXTERIA_OK && info.state == EXTERIA_TCPIP_DONE && r->out_len == 0) drop_relay(e, r, now);
}

static void timers(exteria_shiro_engine *e, uint64_t now) {
    if (e->previous.active && now >= e->previous_until) exteria_wg_session_clear(&e->previous);
    if (e->hs_pending && elapsed_ms(now, e->hs_sent_ms) >= HANDSHAKE_WAIT_MS) {
        if (e->hs_attempts < HANDSHAKE_ATTEMPTS) {
            begin_handshake(e, now);
        } else {
            e->hs_pending = 0;
            if (!e->session.active) {
                trace(e, "no answer from the server");
                set_state(e, EXTERIA_SHIRO_DOWN, EXTERIA_E_TIMEOUT);
                return;
            }
            /* a renewal that fails leaves the working keys in place until they expire or the path proves dead */
            e->next_rekey_ms = now + REKEY_RETRY_MS;
            e->hs_attempts = 0;
        }
    }
    if (e->session.active) {
        uint64_t age = exteria_wg_session_age_ms(&e->session, now);
        if (age >= EXTERIA_WG_REJECT_AFTER_MS) {
            trace(e, "keys expired");
            set_state(e, EXTERIA_SHIRO_DOWN, EXTERIA_E_TIMEOUT);
            return;
        }
        if (e->unanswered_since && elapsed_ms(now, e->unanswered_since) >= LIVENESS_MS) {
            if (!e->hs_pending && e->hs_attempts == 0 && now >= e->next_rekey_ms) {
                trace(e, "no answer for %u s, new handshake", LIVENESS_MS / 1000u);
                begin_handshake(e, now);
            } else if (!e->hs_pending && e->next_rekey_ms) {
                trace(e, "the path is dead");
                set_state(e, EXTERIA_SHIRO_DOWN, EXTERIA_E_TIMEOUT);
                return;
            }
        } else if (age >= EXTERIA_WG_REKEY_AFTER_MS && !e->hs_pending && now >= e->next_rekey_ms) {
            begin_handshake(e, now);
        }
        if (elapsed_ms(now, e->last_tx_ms) >= EXTERIA_WG_KEEPALIVE_MS) send_datagram(e, NULL, 0, now);
    }
    if (e->stack) exteria_tcpip_tick(e->stack, now);
}

static void snapshot(exteria_shiro_engine *e, uint64_t now) {
    unsigned streams = 0, i;
    for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) streams += e->relays[i].used ? 1u : 0u;
    pthread_mutex_lock(&e->lock);
    e->stats.bytes_in = e->bytes_in;
    e->stats.bytes_out = e->bytes_out;
    e->stats.handshakes = e->handshakes;
    e->stats.session_age_ms = e->session.active ? exteria_wg_session_age_ms(&e->session, now) : 0;
    e->stats.streams = streams;
    pthread_mutex_unlock(&e->lock);
}

static int should_stop(exteria_shiro_engine *e) {
    int stop;
    pthread_mutex_lock(&e->lock);
    stop = e->stop || e->state == EXTERIA_SHIRO_DOWN;
    pthread_mutex_unlock(&e->lock);
    return stop;
}

static void *run(void *arg) {
    exteria_shiro_engine *e = (exteria_shiro_engine *)arg;
    struct pollfd fds[2 + EXTERIA_TCPIP_MAX_CONNECTIONS + MAX_UDP];
    /* what each descriptor after the first two belongs to: a relay is its index, a datagram socket is minus two less its index */
    int relay_of[2 + EXTERIA_TCPIP_MAX_CONNECTIONS + MAX_UDP];
    uint8_t datagram[EXTERIA_WG_MAX_DATAGRAM + 64];
    uint64_t now = now_ms();
    begin_handshake(e, now);
    if (!e->hs_pending) set_state(e, EXTERIA_SHIRO_DOWN, EXTERIA_E_CRYPTO);
    while (!should_stop(e)) {
        size_t nfds = 0, i;
        int rc, burst;
        fds[nfds].fd = e->wake[0];
        fds[nfds].events = POLLIN;
        relay_of[nfds++] = -1;
        fds[nfds].fd = e->udp;
        fds[nfds].events = POLLIN;
        relay_of[nfds++] = -1;
        for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) {
            relay *r = &e->relays[i];
            exteria_tcpip_info info;
            if (!r->used) continue;
            fds[nfds].fd = r->fd;
            fds[nfds].events = 0;
            if (r->open && !r->fd_eof && exteria_tcpip_info_get(e->stack, r->conn, &info) == EXTERIA_OK && info.send_space > 0) fds[nfds].events |= POLLIN;
            if (r->out_off < r->out_len) fds[nfds].events |= POLLOUT;
            relay_of[nfds++] = (int)i;
        }
        for (i = 0; i < MAX_UDP; ++i) {
            if (!e->udps[i].used) continue;
            fds[nfds].fd = e->udps[i].fd;
            fds[nfds].events = POLLIN;
            relay_of[nfds++] = -2 - (int)i;
        }
        rc = poll(fds, (nfds_t)nfds, LOOP_TICK_MS);
        now = now_ms();
        /* a stream whose other end is closed or broken is let go at once; left alone, poll would return for it again and again */
        for (i = 2; rc > 0 && i < nfds; ++i) {
            if (!(fds[i].revents & (POLLHUP | POLLERR | POLLNVAL))) continue;
            if (relay_of[i] >= 0) drop_relay(e, &e->relays[relay_of[i]], now);
            else drop_udp(e, &e->udps[-2 - relay_of[i]]);
            fds[i].revents = 0;
        }
        if (rc > 0 && (fds[0].revents & POLLIN)) {
            uint8_t drain[64];
            while (read(e->wake[0], drain, sizeof(drain)) > 0) {
            }
        }
        adopt_pending(e, now);
        adopt_udp(e, now);
        if (rc > 0 && (fds[1].revents & POLLIN)) {
            for (burst = 0; burst < 64; ++burst) {
                ssize_t n = recv(e->udp, datagram, sizeof(datagram), 0);
                if (n < 0) {
                    if (errno == ECONNREFUSED) {
                        /* an ICMP port unreachable for an earlier datagram; the server may simply be starting, the handshake timer decides */
                        continue;
                    }
                    break;
                }
                if (n > 0) on_datagram(e, datagram, (size_t)n, now);
            }
        }
        timers(e, now);
        for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) {
            if (e->relays[i].used && e->stack) pump_relay(e, &e->relays[i], now);
        }
        /* a socket with nothing to read is still visited, for its idle limit */
        for (i = 0; i < MAX_UDP; ++i) {
            if (e->udps[i].used && e->session.active) pump_udp(e, &e->udps[i], now);
        }
        snapshot(e, now);
    }
    /* the end: every stream is closed (its far side sees a reset), then the state of the engine is wiped */
    {
        size_t i;
        now = now_ms();
        for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) {
            if (e->relays[i].used) drop_relay(e, &e->relays[i], now);
        }
        for (i = 0; i < MAX_UDP; ++i) {
            if (e->udps[i].used) drop_udp(e, &e->udps[i]);
        }
        pthread_mutex_lock(&e->lock);
        for (i = 0; i < e->queue_count; ++i) close(e->queue[i].fd);
        e->queue_count = 0;
        for (i = 0; i < e->udp_queue_count; ++i) close(e->udp_queue[i]);
        e->udp_queue_count = 0;
        e->udp_held = 0;
        pthread_mutex_unlock(&e->lock);
    }
    exteria_tcpip_free(e->stack);
    e->stack = NULL;
    exteria_wg_session_clear(&e->session);
    exteria_wg_session_clear(&e->previous);
    exteria_wg_handshake_clear(&e->hs);
    return NULL;
}

static void make_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    fcntl(fd, F_SETFD, FD_CLOEXEC);
}

static void no_sigpipe(int fd) {
#ifdef SO_NOSIGPIPE
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#else
    (void)fd;
#endif
}

exteria_status exteria_shiro_engine_start(exteria_shiro_engine **out, const exteria_warp_identity *identity, uint32_t endpoint_ip, uint16_t endpoint_port,
                                          const exteria_shiro_events *events) {
    exteria_shiro_engine *e;
    struct sockaddr_in server;
    pthread_attr_t attr;
    exteria_status status;
    int size = UDP_BUFFER;
    size_t i;
    if (out) *out = NULL;
    if (!out || !identity || endpoint_ip == 0 || endpoint_port == 0 || identity->address == 0) return EXTERIA_E_ARG;
    e = (exteria_shiro_engine *)calloc(1, sizeof(*e));
    if (!e) return EXTERIA_E_NOMEM;
    e->identity = *identity;
    e->endpoint_ip = endpoint_ip;
    e->endpoint_port = endpoint_port;
    if (events) e->events = *events;
    e->wake[0] = e->wake[1] = e->udp = -1;
    for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) e->relays[i].fd = -1;
    for (i = 0; i < MAX_UDP; ++i) e->udps[i].fd = -1;
    {
        uint16_t seed = 0;
        /* a start that cannot draw is still unique per run through the clock; the ports only have to differ between sockets */
        if (exteria_random(&seed, sizeof(seed)) != EXTERIA_OK) seed = (uint16_t)now_ms();
        e->udp_next_port = (uint16_t)(seed % UDP_PORT_COUNT);
    }
    status = exteria_warp_wg_config(&e->identity, &e->profile, &e->wg);
    if (status != EXTERIA_OK) goto fail;
    status = EXTERIA_E_IO;
    if (pthread_mutex_init(&e->lock, NULL) != 0) goto fail_free;
    if (pipe(e->wake) != 0) goto fail_mutex;
    make_nonblocking(e->wake[0]);
    make_nonblocking(e->wake[1]);
    e->udp = socket(AF_INET, SOCK_DGRAM, 0);
    if (e->udp < 0) goto fail_pipe;
    make_nonblocking(e->udp);
    no_sigpipe(e->udp);
    setsockopt(e->udp, SOL_SOCKET, SO_RCVBUF, &size, sizeof(size));
    setsockopt(e->udp, SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));
    memset(&server, 0, sizeof(server));
    server.sin_family = AF_INET;
    server.sin_port = htons(endpoint_port);
    server.sin_addr.s_addr = htonl(endpoint_ip);
#ifdef __APPLE__
    server.sin_len = sizeof(server);
#endif
    if (connect(e->udp, (struct sockaddr *)&server, sizeof(server)) != 0) goto fail_udp;
    e->state = EXTERIA_SHIRO_HANDSHAKING;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, THREAD_STACK);
    if (pthread_create(&e->thread, &attr, run, e) != 0) {
        pthread_attr_destroy(&attr);
        goto fail_udp;
    }
    pthread_attr_destroy(&attr);
    e->thread_started = 1;
    *out = e;
    return EXTERIA_OK;
fail_udp:
    close(e->udp);
fail_pipe:
    close(e->wake[0]);
    close(e->wake[1]);
fail_mutex:
    pthread_mutex_destroy(&e->lock);
fail_free:
fail:
    exteria_wipe(e, sizeof(*e));
    free(e);
    return status;
}

static void wake(exteria_shiro_engine *e) {
    uint8_t one = 1;
    (void)write(e->wake[1], &one, 1);
}

void exteria_shiro_engine_stop(exteria_shiro_engine *e) {
    if (!e) return;
    pthread_mutex_lock(&e->lock);
    e->stop = 1;
    pthread_mutex_unlock(&e->lock);
    wake(e);
    if (e->thread_started) pthread_join(e->thread, NULL);
    close(e->udp);
    close(e->wake[0]);
    close(e->wake[1]);
    pthread_mutex_destroy(&e->lock);
    exteria_wipe(e, sizeof(*e));
    free(e);
}

exteria_shiro_state exteria_shiro_engine_state(exteria_shiro_engine *e) {
    exteria_shiro_state state;
    if (!e) return EXTERIA_SHIRO_DOWN;
    pthread_mutex_lock(&e->lock);
    state = e->state;
    pthread_mutex_unlock(&e->lock);
    return state;
}

void exteria_shiro_engine_stats(exteria_shiro_engine *e, exteria_shiro_stats *stats) {
    if (stats) memset(stats, 0, sizeof(*stats));
    if (!e || !stats) return;
    pthread_mutex_lock(&e->lock);
    *stats = e->stats;
    pthread_mutex_unlock(&e->lock);
}

exteria_status exteria_shiro_engine_open(exteria_shiro_engine *e, uint32_t ip, uint16_t port, int timeout_ms, int *fd) {
    int pair[2], size = STREAM_BUFFER;
    uint64_t deadline;
    uint8_t ready = 1;
    exteria_status status = EXTERIA_E_IO;
    if (fd) *fd = -1;
    if (!e || !fd || ip == 0 || port == 0 || timeout_ms <= 0) return EXTERIA_E_ARG;
    if (exteria_shiro_engine_state(e) != EXTERIA_SHIRO_UP) return EXTERIA_E_STATE;
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair) != 0) return EXTERIA_E_IO;
    fcntl(pair[1], F_SETFD, FD_CLOEXEC);
    no_sigpipe(pair[0]);
    no_sigpipe(pair[1]);
    make_nonblocking(pair[0]);
    setsockopt(pair[0], SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));
    setsockopt(pair[0], SOL_SOCKET, SO_RCVBUF, &size, sizeof(size));
    setsockopt(pair[1], SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));
    setsockopt(pair[1], SOL_SOCKET, SO_RCVBUF, &size, sizeof(size));
    deadline = now_ms() + (uint64_t)timeout_ms;
    pthread_mutex_lock(&e->lock);
    if (e->queue_count >= MAX_PENDING || e->state != EXTERIA_SHIRO_UP) {
        pthread_mutex_unlock(&e->lock);
        close(pair[0]);
        close(pair[1]);
        return e->queue_count >= MAX_PENDING ? EXTERIA_E_LIMIT : EXTERIA_E_STATE;
    }
    e->queue[e->queue_count].fd = pair[0];
    e->queue[e->queue_count].ip = ip;
    e->queue[e->queue_count].port = port;
    e->queue[e->queue_count].deadline = deadline;
    ++e->queue_count;
    pthread_mutex_unlock(&e->lock);
    wake(e);
    for (;;) {
        struct pollfd p;
        uint64_t now = now_ms();
        int left, rc;
        if (now >= deadline) {
            status = EXTERIA_E_TIMEOUT;
            break;
        }
        left = (int)(deadline - now);
        p.fd = pair[1];
        p.events = POLLIN;
        p.revents = 0;
        rc = poll(&p, 1, left);
        if (rc < 0 && errno == EINTR) continue;
        if (rc <= 0) {
            status = EXTERIA_E_TIMEOUT;
            break;
        }
        {
            ssize_t n = recv(pair[1], &ready, 1, 0);
            if (n == 1 && ready == 0) status = EXTERIA_OK;
            break;
        }
    }
    if (status != EXTERIA_OK) {
        close(pair[1]);
        return status;
    }
    make_nonblocking(pair[1]);
    *fd = pair[1];
    return EXTERIA_OK;
}

exteria_status exteria_shiro_engine_open_udp(exteria_shiro_engine *e, int *fd) {
    int pair[2], size = STREAM_BUFFER;
    if (fd) *fd = -1;
    if (!e || !fd) return EXTERIA_E_ARG;
    if (exteria_shiro_engine_state(e) != EXTERIA_SHIRO_UP) return EXTERIA_E_STATE;
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, pair) != 0) return EXTERIA_E_IO;
    no_sigpipe(pair[0]);
    no_sigpipe(pair[1]);
    make_nonblocking(pair[0]);
    make_nonblocking(pair[1]);
    /* a refusal only means the system keeps its own size */
    setsockopt(pair[0], SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));
    setsockopt(pair[0], SOL_SOCKET, SO_RCVBUF, &size, sizeof(size));
    setsockopt(pair[1], SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));
    setsockopt(pair[1], SOL_SOCKET, SO_RCVBUF, &size, sizeof(size));
    pthread_mutex_lock(&e->lock);
    if (e->udp_held >= MAX_UDP || e->state != EXTERIA_SHIRO_UP) {
        int limited = e->udp_held >= MAX_UDP;
        pthread_mutex_unlock(&e->lock);
        close(pair[0]);
        close(pair[1]);
        return limited ? EXTERIA_E_LIMIT : EXTERIA_E_STATE;
    }
    e->udp_queue[e->udp_queue_count++] = pair[0];
    ++e->udp_held;
    pthread_mutex_unlock(&e->lock);
    wake(e);
    *fd = pair[1];
    return EXTERIA_OK;
}
