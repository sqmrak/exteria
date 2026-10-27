#include "exteria_tcpip.h"

#include <stdlib.h>
#include <string.h>

#include "exteria_bytes.h"
#include "exteria_random.h"

#define IP_HEADER 20u
#define TCP_HEADER 20u
#define MSS_OPTION_LEN 4u
#define PROTO_TCP 6u

#define F_FIN 0x01u
#define F_SYN 0x02u
#define F_RST 0x04u
#define F_PSH 0x08u
#define F_ACK 0x10u

#define MAX_OOO 8
#define RTO_INITIAL_MS 1000
#define RTO_MIN_MS 200
#define RTO_MAX_MS 30000
#define SYN_RETRIES 6
#define DATA_RETRIES 10
#define DELAYED_ACK_MS 40
#define INITIAL_CWND_SEGMENTS 10u
#define DEFAULT_PEER_MSS 536u
#define PORT_LOW 49152u
#define PORT_COUNT 16384u

typedef struct range {
    uint32_t start, end;
} range;

typedef struct conn {
    int used;
    uint32_t id;
    uint32_t remote_ip;
    uint16_t remote_port, local_port;
    exteria_tcpip_state state;
    exteria_status error;

    uint8_t *snd;
    size_t snd_head, snd_len;
    uint32_t iss, snd_una, snd_nxt, snd_wnd;
    uint32_t mss, cwnd, ssthresh;
    int dupacks, in_recovery;
    uint32_t recover;
    int want_close, fin_sent, fin_acked;

    uint8_t *rcv;
    size_t rcv_head, rcv_len;
    uint32_t rcv_nxt;
    range ooo[MAX_OOO];
    int ooo_count;
    int fin_pending, peer_fin;
    uint32_t fin_seq;
    uint32_t adv_wnd;

    int32_t srtt_x8, rttvar_x4;
    uint32_t rto_ms;
    uint64_t rto_deadline;
    int rtt_timing;
    uint32_t rtt_seq;
    uint64_t rtt_sent;
    int retries;
    int ack_pending;
    uint64_t ack_deadline;
} conn;

struct exteria_tcpip {
    uint32_t local_ip;
    uint16_t mtu, ip_id;
    exteria_tcpip_emit emit;
    void *context;
    uint32_t next_id;
    conn conns[EXTERIA_TCPIP_MAX_CONNECTIONS];
    exteria_tcpip_stats stats;
};

/* sequence numbers wrap, so order is decided by the signed distance */
static int seq_lt(uint32_t a, uint32_t b) { return (int32_t)(a - b) < 0; }
static int seq_le(uint32_t a, uint32_t b) { return (int32_t)(a - b) <= 0; }
static int seq_gt(uint32_t a, uint32_t b) { return (int32_t)(a - b) > 0; }

static uint32_t min_u32(uint32_t a, uint32_t b) { return a < b ? a : b; }
static uint32_t max_u32(uint32_t a, uint32_t b) { return a > b ? a : b; }

/* the internet checksum over the parts given, as a sum that the caller folds */
static uint32_t sum_bytes(uint32_t sum, const uint8_t *p, size_t n) {
    size_t i;
    for (i = 0; i + 1 < n; i += 2) sum += (uint32_t)p[i] << 8 | p[i + 1];
    if (n & 1u) sum += (uint32_t)p[n - 1] << 8;
    return sum;
}

static uint16_t fold(uint32_t sum) {
    while (sum >> 16) sum = (sum & 0xFFFFu) + (sum >> 16);
    return (uint16_t)~sum;
}

static uint16_t tcp_checksum(uint32_t src, uint32_t dst, const uint8_t *segment, size_t len) {
    uint8_t pseudo[12];
    exteria_put_u32be(pseudo, src);
    exteria_put_u32be(pseudo + 4, dst);
    pseudo[8] = 0;
    pseudo[9] = PROTO_TCP;
    pseudo[10] = (uint8_t)(len >> 8);
    pseudo[11] = (uint8_t)len;
    return fold(sum_bytes(sum_bytes(0, pseudo, sizeof(pseudo)), segment, len));
}

static void put_u16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)v;
}

static uint16_t get_u16(const uint8_t *p) {
    return (uint16_t)((unsigned)p[0] << 8 | p[1]);
}

exteria_status exteria_tcpip_new(exteria_tcpip **out, uint32_t local_ip, uint16_t mtu, exteria_tcpip_emit emit, void *context) {
    exteria_tcpip *s;
    if (out) *out = NULL;
    if (!out || !emit || local_ip == 0 || mtu < EXTERIA_TCPIP_MIN_MTU || mtu > EXTERIA_TCPIP_MAX_MTU) return EXTERIA_E_ARG;
    s = (exteria_tcpip *)calloc(1, sizeof(*s));
    if (!s) return EXTERIA_E_NOMEM;
    s->local_ip = local_ip;
    s->mtu = mtu;
    s->emit = emit;
    s->context = context;
    s->next_id = 1;
    if (exteria_random(&s->ip_id, sizeof(s->ip_id)) != EXTERIA_OK) {
        free(s);
        return EXTERIA_E_CRYPTO;
    }
    *out = s;
    return EXTERIA_OK;
}

static void conn_free(conn *c) {
    if (c->snd) {
        exteria_wipe(c->snd, EXTERIA_TCPIP_BUFFER);
        free(c->snd);
    }
    if (c->rcv) {
        exteria_wipe(c->rcv, EXTERIA_TCPIP_BUFFER);
        free(c->rcv);
    }
    memset(c, 0, sizeof(*c));
}

void exteria_tcpip_free(exteria_tcpip *s) {
    int i;
    if (!s) return;
    for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) conn_free(&s->conns[i]);
    free(s);
}

void exteria_tcpip_stats_get(const exteria_tcpip *s, exteria_tcpip_stats *stats) {
    if (stats) memset(stats, 0, sizeof(*stats));
    if (s && stats) *stats = s->stats;
}

static conn *find_by_id(const exteria_tcpip *s, uint32_t id) {
    int i;
    if (id == 0) return NULL;
    for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) {
        if (s->conns[i].used && s->conns[i].id == id) return (conn *)&s->conns[i];
    }
    return NULL;
}

static conn *find_by_tuple(exteria_tcpip *s, uint32_t ip, uint16_t remote_port, uint16_t local_port) {
    int i;
    for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) {
        conn *c = &s->conns[i];
        if (c->used && c->remote_ip == ip && c->remote_port == remote_port && c->local_port == local_port) return c;
    }
    return NULL;
}

/* a segment out. payload may be NULL; the data of a connection's send buffer is copied by the caller into it first */
static void emit_segment(exteria_tcpip *s, uint32_t remote_ip, uint16_t remote_port, uint16_t local_port, uint32_t seq, uint32_t ack, uint8_t flags,
                         uint16_t window, int mss_option, const uint8_t *payload, size_t payload_len) {
    uint8_t packet[EXTERIA_TCPIP_MAX_MTU];
    size_t tcp_len = TCP_HEADER + (mss_option ? MSS_OPTION_LEN : 0u), total = IP_HEADER + tcp_len + payload_len;
    uint8_t *tcp = packet + IP_HEADER;
    if (total > sizeof(packet)) return;
    memset(packet, 0, IP_HEADER + tcp_len);
    packet[0] = 0x45;
    put_u16(packet + 2, (uint16_t)total);
    ++s->ip_id;
    put_u16(packet + 4, s->ip_id);
    /* the tunnel has a fixed size, so nothing is fragmented */
    put_u16(packet + 6, 0x4000);
    packet[8] = 64;
    packet[9] = PROTO_TCP;
    exteria_put_u32be(packet + 12, s->local_ip);
    exteria_put_u32be(packet + 16, remote_ip);
    put_u16(packet + 10, fold(sum_bytes(0, packet, IP_HEADER)));
    put_u16(tcp, local_port);
    put_u16(tcp + 2, remote_port);
    exteria_put_u32be(tcp + 4, seq);
    exteria_put_u32be(tcp + 8, ack);
    tcp[12] = (uint8_t)((tcp_len / 4u) << 4);
    tcp[13] = flags;
    put_u16(tcp + 14, window);
    if (mss_option) {
        uint16_t mss = (uint16_t)(s->mtu - IP_HEADER - TCP_HEADER);
        tcp[20] = 2;
        tcp[21] = 4;
        put_u16(tcp + 22, mss);
    }
    if (payload_len) memcpy(tcp + tcp_len, payload, payload_len);
    put_u16(tcp + 16, tcp_checksum(s->local_ip, remote_ip, tcp, tcp_len + payload_len));
    ++s->stats.segments_out;
    s->emit(s->context, packet, total);
}

static uint16_t advertised_window(const conn *c) {
    size_t free_space = EXTERIA_TCPIP_BUFFER - c->rcv_len;
    return free_space > 0xFFFFu ? 0xFFFFu : (uint16_t)free_space;
}

static void send_ack(exteria_tcpip *s, conn *c) {
    emit_segment(s, c->remote_ip, c->remote_port, c->local_port, c->snd_nxt, c->rcv_nxt, F_ACK, advertised_window(c), 0, NULL, 0);
    c->adv_wnd = advertised_window(c);
    c->ack_pending = 0;
}

static void send_reset_for(exteria_tcpip *s, uint32_t remote_ip, uint16_t remote_port, uint16_t local_port, uint32_t seg_seq, uint32_t seg_ack, int had_ack,
                           uint32_t seg_len) {
    ++s->stats.resets_sent;
    if (had_ack) emit_segment(s, remote_ip, remote_port, local_port, seg_ack, 0, F_RST, 0, 0, NULL, 0);
    else emit_segment(s, remote_ip, remote_port, local_port, 0, seg_seq + seg_len, (uint8_t)(F_RST | F_ACK), 0, 0, NULL, 0);
}

static void fail(conn *c, exteria_status error) {
    c->state = EXTERIA_TCPIP_FAILED;
    c->error = error;
    c->rto_deadline = 0;
    c->ack_pending = 0;
}

static void arm_timer(conn *c, uint64_t now_ms) {
    if (c->rto_deadline == 0) c->rto_deadline = now_ms + c->rto_ms;
}

static uint32_t flight_data(const conn *c) {
    uint32_t flight = c->snd_nxt - c->snd_una;
    if (c->fin_sent && flight) --flight;
    return flight;
}

static void snd_copy(const conn *c, size_t offset, uint8_t *out, size_t len) {
    size_t at = (c->snd_head + offset) % EXTERIA_TCPIP_BUFFER;
    size_t first = EXTERIA_TCPIP_BUFFER - at;
    if (first > len) first = len;
    memcpy(out, c->snd + at, first);
    if (first < len) memcpy(out + first, c->snd, len - first);
}

static void send_data_segment(exteria_tcpip *s, conn *c, uint32_t seq, size_t len, int push, int fin, uint64_t now_ms) {
    uint8_t payload[EXTERIA_TCPIP_MAX_MTU];
    uint8_t flags = F_ACK;
    if (len) snd_copy(c, (size_t)(seq - c->snd_una), payload, len);
    if (push) flags |= F_PSH;
    if (fin) flags |= F_FIN;
    emit_segment(s, c->remote_ip, c->remote_port, c->local_port, seq, c->rcv_nxt, flags, advertised_window(c), 0, payload, len);
    c->adv_wnd = advertised_window(c);
    c->ack_pending = 0;
    if (!c->rtt_timing && (len || fin) && seq_lt(seq, c->snd_nxt) == 0) {
        c->rtt_timing = 1;
        c->rtt_seq = seq + (uint32_t)len + (fin ? 1u : 0u);
        c->rtt_sent = now_ms;
    }
    arm_timer(c, now_ms);
}

/* everything the windows allow: new data, then the FIN once the queue is empty */
static void output(exteria_tcpip *s, conn *c, uint64_t now_ms) {
    if (c->state != EXTERIA_TCPIP_OPEN) return;
    for (;;) {
        uint32_t window = min_u32(c->cwnd, c->snd_wnd), flight = flight_data(c);
        size_t sent = flight, unsent = c->snd_len - sent, chunk;
        if (c->fin_sent) break;
        if (unsent > 0) {
            if (flight >= window) {
                /* a peer that closed its window gets probed by the timer */
                if (c->snd_wnd == 0 && flight == 0) arm_timer(c, now_ms);
                break;
            }
            chunk = unsent;
            if (chunk > c->mss) chunk = c->mss;
            if (chunk > window - flight) chunk = window - flight;
            send_data_segment(s, c, c->snd_nxt, chunk, chunk == unsent, 0, now_ms);
            c->snd_nxt += (uint32_t)chunk;
        } else {
            if (c->want_close) {
                send_data_segment(s, c, c->snd_nxt, 0, 0, 1, now_ms);
                c->snd_nxt += 1;
                c->fin_sent = 1;
            }
            break;
        }
    }
}

static void update_rtt(conn *c, uint64_t now_ms) {
    int32_t m = (int32_t)(now_ms - c->rtt_sent), err;
    if (m < 1) m = 1;
    if (c->srtt_x8 == 0) {
        c->srtt_x8 = m << 3;
        c->rttvar_x4 = m << 1;
    } else {
        err = m - (c->srtt_x8 >> 3);
        c->srtt_x8 += err;
        if (err < 0) err = -err;
        err -= c->rttvar_x4 >> 2;
        c->rttvar_x4 += err;
        if (c->rttvar_x4 < 0) c->rttvar_x4 = 0;
    }
    {
        int32_t rto = (c->srtt_x8 >> 3) + (c->rttvar_x4 > 10 ? c->rttvar_x4 : 10);
        if (rto < RTO_MIN_MS) rto = RTO_MIN_MS;
        if (rto > RTO_MAX_MS) rto = RTO_MAX_MS;
        c->rto_ms = (uint32_t)rto;
    }
    c->rtt_timing = 0;
}

exteria_status exteria_tcpip_connect(exteria_tcpip *s, uint32_t remote_ip, uint16_t remote_port, uint64_t now_ms, uint32_t *id) {
    conn *c = NULL;
    int i, attempt;
    uint32_t r;
    if (id) *id = 0;
    if (!s || !id || remote_ip == 0 || remote_port == 0) return EXTERIA_E_ARG;
    for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) {
        if (!s->conns[i].used) {
            c = &s->conns[i];
            break;
        }
    }
    if (!c) return EXTERIA_E_LIMIT;
    memset(c, 0, sizeof(*c));
    c->snd = (uint8_t *)malloc(EXTERIA_TCPIP_BUFFER);
    c->rcv = (uint8_t *)malloc(EXTERIA_TCPIP_BUFFER);
    if (!c->snd || !c->rcv) {
        conn_free(c);
        return EXTERIA_E_NOMEM;
    }
    /* a port nobody else of this stack holds, drawn at random so that a restarted tunnel does not reuse the ports of the last one at once */
    for (attempt = 0;; ++attempt) {
        uint16_t port;
        if (attempt > 64 || exteria_random(&r, sizeof(r)) != EXTERIA_OK) {
            conn_free(c);
            return EXTERIA_E_LIMIT;
        }
        port = (uint16_t)(PORT_LOW + r % PORT_COUNT);
        if (!find_by_tuple(s, remote_ip, remote_port, port)) {
            c->local_port = port;
            break;
        }
    }
    if (exteria_random(&c->iss, sizeof(c->iss)) != EXTERIA_OK) {
        conn_free(c);
        return EXTERIA_E_CRYPTO;
    }
    c->used = 1;
    c->id = s->next_id++;
    if (s->next_id == 0) s->next_id = 1;
    c->remote_ip = remote_ip;
    c->remote_port = remote_port;
    c->state = EXTERIA_TCPIP_CONNECTING;
    c->snd_una = c->iss;
    c->snd_nxt = c->iss + 1;
    c->mss = (uint32_t)(s->mtu - IP_HEADER - TCP_HEADER);
    c->cwnd = INITIAL_CWND_SEGMENTS * c->mss;
    c->ssthresh = 0xFFFFu;
    c->rto_ms = RTO_INITIAL_MS;
    c->snd_wnd = 0xFFFFu;
    emit_segment(s, remote_ip, remote_port, c->local_port, c->iss, 0, F_SYN, advertised_window(c), 1, NULL, 0);
    c->adv_wnd = advertised_window(c);
    c->rto_deadline = now_ms + c->rto_ms;
    /* the answer to the SYN is the first round trip measured, unless the SYN has to be sent again */
    c->rtt_timing = 1;
    c->rtt_seq = c->iss + 1;
    c->rtt_sent = now_ms;
    *id = c->id;
    return EXTERIA_OK;
}

exteria_status exteria_tcpip_info_get(const exteria_tcpip *s, uint32_t id, exteria_tcpip_info *info) {
    const conn *c;
    if (info) memset(info, 0, sizeof(*info));
    if (!s || !info) return EXTERIA_E_ARG;
    c = find_by_id(s, id);
    if (!c) return EXTERIA_E_NOTFOUND;
    info->state = c->state;
    info->readable = c->rcv_len;
    info->send_space = c->state == EXTERIA_TCPIP_OPEN && !c->want_close ? EXTERIA_TCPIP_BUFFER - c->snd_len : 0;
    info->peer_closed = c->peer_fin;
    info->closed_by_us = c->want_close;
    info->error = c->error;
    return EXTERIA_OK;
}

exteria_status exteria_tcpip_send(exteria_tcpip *s, uint32_t id, const uint8_t *data, size_t len, uint64_t now_ms, size_t *accepted) {
    conn *c;
    size_t room, at, first;
    if (accepted) *accepted = 0;
    if (!s || !accepted || (len && !data)) return EXTERIA_E_ARG;
    c = find_by_id(s, id);
    if (!c) return EXTERIA_E_NOTFOUND;
    if (c->state == EXTERIA_TCPIP_FAILED) return c->error;
    if (c->state != EXTERIA_TCPIP_OPEN || c->want_close) return EXTERIA_E_STATE;
    room = EXTERIA_TCPIP_BUFFER - c->snd_len;
    if (len > room) len = room;
    if (len == 0) return EXTERIA_OK;
    at = (c->snd_head + c->snd_len) % EXTERIA_TCPIP_BUFFER;
    first = EXTERIA_TCPIP_BUFFER - at;
    if (first > len) first = len;
    memcpy(c->snd + at, data, first);
    if (first < len) memcpy(c->snd, data + first, len - first);
    c->snd_len += len;
    *accepted = len;
    output(s, c, now_ms);
    return EXTERIA_OK;
}

exteria_status exteria_tcpip_recv(exteria_tcpip *s, uint32_t id, uint8_t *buf, size_t cap, uint64_t now_ms, size_t *got) {
    conn *c;
    size_t n, first;
    uint16_t before;
    (void)now_ms;
    if (got) *got = 0;
    if (!s || !got || !buf || cap == 0) return EXTERIA_E_ARG;
    c = find_by_id(s, id);
    if (!c) return EXTERIA_E_NOTFOUND;
    if (c->state == EXTERIA_TCPIP_FAILED) return c->error;
    if (c->rcv_len == 0) {
        if (c->peer_fin) return EXTERIA_E_EOF;
        return c->state == EXTERIA_TCPIP_CONNECTING ? EXTERIA_E_STATE : EXTERIA_E_RETRY;
    }
    n = c->rcv_len < cap ? c->rcv_len : cap;
    first = EXTERIA_TCPIP_BUFFER - c->rcv_head;
    if (first > n) first = n;
    memcpy(buf, c->rcv + c->rcv_head, first);
    if (first < n) memcpy(buf + first, c->rcv, n - first);
    c->rcv_head = (c->rcv_head + n) % EXTERIA_TCPIP_BUFFER;
    c->rcv_len -= n;
    *got = n;
    /* the peer is told about room it could not use only when that room is worth a segment, which keeps tiny window updates from flooding the link */
    before = (uint16_t)c->adv_wnd;
    if (c->state == EXTERIA_TCPIP_OPEN) {
        uint16_t now_window = advertised_window(c);
        if (before < c->mss && now_window >= c->mss) send_ack(s, c);
        else if ((uint32_t)now_window >= (uint32_t)before + 2u * c->mss) send_ack(s, c);
    }
    return EXTERIA_OK;
}

exteria_status exteria_tcpip_close(exteria_tcpip *s, uint32_t id, uint64_t now_ms) {
    conn *c;
    if (!s) return EXTERIA_E_ARG;
    c = find_by_id(s, id);
    if (!c) return EXTERIA_E_NOTFOUND;
    if (c->state == EXTERIA_TCPIP_FAILED) return c->error;
    c->want_close = 1;
    output(s, c, now_ms);
    return EXTERIA_OK;
}

void exteria_tcpip_release(exteria_tcpip *s, uint32_t id, uint64_t now_ms) {
    conn *c;
    (void)now_ms;
    if (!s) return;
    c = find_by_id(s, id);
    if (!c) return;
    /* a connection that is still alive is reset, so the peer does not wait on a phone that forgot it */
    if (c->state == EXTERIA_TCPIP_OPEN) {
        ++s->stats.resets_sent;
        emit_segment(s, c->remote_ip, c->remote_port, c->local_port, c->snd_nxt, c->rcv_nxt, (uint8_t)(F_RST | F_ACK), 0, 0, NULL, 0);
    } else if (c->state == EXTERIA_TCPIP_CONNECTING) {
        ++s->stats.resets_sent;
        emit_segment(s, c->remote_ip, c->remote_port, c->local_port, c->snd_nxt, 0, F_RST, 0, 0, NULL, 0);
    }
    conn_free(c);
}

/* retransmission of the oldest thing the peer has not acknowledged: the SYN, a segment of data or the FIN */
static void retransmit_oldest(exteria_tcpip *s, conn *c, uint64_t now_ms) {
    ++s->stats.retransmits;
    c->rtt_timing = 0;
    if (c->state == EXTERIA_TCPIP_CONNECTING) {
        emit_segment(s, c->remote_ip, c->remote_port, c->local_port, c->iss, 0, F_SYN, advertised_window(c), 1, NULL, 0);
        return;
    }
    {
        uint32_t data_in_buffer = (uint32_t)c->snd_len;
        if (data_in_buffer > 0) {
            uint32_t len = min_u32(data_in_buffer, c->mss);
            send_data_segment(s, c, c->snd_una, len, 0, 0, now_ms);
        } else if (c->fin_sent && !c->fin_acked) {
            send_data_segment(s, c, c->snd_una, 0, 0, 1, now_ms);
        }
    }
}

static void on_timeout(exteria_tcpip *s, conn *c, uint64_t now_ms) {
    c->retries++;
    if (c->state == EXTERIA_TCPIP_CONNECTING) {
        if (c->retries > SYN_RETRIES) {
            fail(c, EXTERIA_E_TIMEOUT);
            return;
        }
    } else if (flight_data(c) > 0 || (c->fin_sent && !c->fin_acked)) {
        if (c->retries > DATA_RETRIES) {
            fail(c, EXTERIA_E_TIMEOUT);
            return;
        }
        {
            uint32_t flight = max_u32(flight_data(c), c->mss);
            c->ssthresh = max_u32(flight / 2u, 2u * c->mss);
            c->cwnd = c->mss;
            c->dupacks = 0;
            c->in_recovery = 0;
        }
    } else if (c->snd_len > 0 && c->snd_wnd == 0) {
        /* the persist timer: one byte of new data finds out whether the window has opened */
        send_data_segment(s, c, c->snd_nxt, 1, 0, 0, now_ms);
        c->snd_nxt += 1;
        c->retries = 0;
        c->rto_ms = c->rto_ms * 2u > RTO_MAX_MS ? RTO_MAX_MS : c->rto_ms * 2u;
        c->rto_deadline = now_ms + c->rto_ms;
        return;
    } else {
        c->rto_deadline = 0;
        return;
    }
    c->rto_ms = c->rto_ms * 2u > RTO_MAX_MS ? RTO_MAX_MS : c->rto_ms * 2u;
    c->rto_deadline = now_ms + c->rto_ms;
    retransmit_oldest(s, c, now_ms);
    if (c->state == EXTERIA_TCPIP_OPEN) {
        /* everything after the lost segment goes out again as the window allows, the peer drops what it already has */
        c->snd_nxt = c->snd_una + (uint32_t)(c->snd_len < c->mss ? c->snd_len : c->mss);
        if (c->snd_len == 0 && c->fin_sent) c->snd_nxt = c->snd_una + 1;
        else c->fin_sent = 0;
    }
}

void exteria_tcpip_tick(exteria_tcpip *s, uint64_t now_ms) {
    int i;
    if (!s) return;
    for (i = 0; i < EXTERIA_TCPIP_MAX_CONNECTIONS; ++i) {
        conn *c = &s->conns[i];
        if (!c->used || c->state == EXTERIA_TCPIP_FAILED || c->state == EXTERIA_TCPIP_DONE) continue;
        if (c->ack_pending && now_ms >= c->ack_deadline) send_ack(s, c);
        if (c->rto_deadline && now_ms >= c->rto_deadline) on_timeout(s, c, now_ms);
        if (c->state == EXTERIA_TCPIP_OPEN) output(s, c, now_ms);
    }
}

/* data at its place in the receive buffer, which is the tail of the in order bytes plus the distance of the segment from the next expected number */
static void rcv_store(conn *c, uint32_t offset, const uint8_t *data, size_t len) {
    size_t at = (c->rcv_head + c->rcv_len + offset) % EXTERIA_TCPIP_BUFFER;
    size_t first = EXTERIA_TCPIP_BUFFER - at;
    if (first > len) first = len;
    memcpy(c->rcv + at, data, first);
    if (first < len) memcpy(c->rcv, data + first, len - first);
}

static void ooo_add(conn *c, uint32_t start, uint32_t end) {
    int i, j;
    range merged = {start, end};
    range keep[MAX_OOO], out[MAX_OOO + 1];
    int kept = 0, placed = 0;
    for (i = 0; i < c->ooo_count; ++i) {
        range r = c->ooo[i];
        if (seq_lt(merged.end, r.start) || seq_lt(r.end, merged.start)) {
            keep[kept++] = r;
        } else {
            if (seq_lt(r.start, merged.start)) merged.start = r.start;
            if (seq_gt(r.end, merged.end)) merged.end = r.end;
        }
    }
    /* the ranges stay sorted from the nearest to the farthest; when there are too many the farthest is forgotten and its data will be sent again */
    for (i = 0, j = 0; i < kept || !placed; ++j) {
        if (!placed && (i >= kept || seq_lt(merged.start, keep[i].start))) {
            out[j] = merged;
            placed = 1;
        } else {
            out[j] = keep[i++];
        }
    }
    c->ooo_count = j > MAX_OOO ? MAX_OOO : j;
    memcpy(c->ooo, out, (size_t)c->ooo_count * sizeof(range));
}

/* in order bytes may have closed the gap in front of stored ranges, and a FIN that waited for the data in front of it may be due */
static void absorb(conn *c) {
    for (;;) {
        int progressed = 0;
        if (c->ooo_count > 0 && seq_le(c->ooo[0].start, c->rcv_nxt)) {
            if (seq_gt(c->ooo[0].end, c->rcv_nxt)) {
                uint32_t n = c->ooo[0].end - c->rcv_nxt;
                c->rcv_len += n;
                c->rcv_nxt += n;
            }
            memmove(&c->ooo[0], &c->ooo[1], (size_t)(c->ooo_count - 1) * sizeof(range));
            --c->ooo_count;
            progressed = 1;
        }
        if (c->fin_pending && c->fin_seq == c->rcv_nxt) {
            c->rcv_nxt += 1;
            c->peer_fin = 1;
            c->fin_pending = 0;
            progressed = 1;
        }
        if (!progressed) break;
    }
}

static void handle_ack(exteria_tcpip *s, conn *c, uint32_t ack, uint32_t window, int has_data, uint64_t now_ms) {
    uint32_t acked;
    if (seq_gt(ack, c->snd_nxt)) {
        /* it acknowledges what was never sent: tell the peer where we are */
        send_ack(s, c);
        return;
    }
    if (seq_lt(ack, c->snd_una)) return;
    c->retries = 0;
    if (ack == c->snd_una) {
        int same_window = c->snd_wnd == window;
        c->snd_wnd = window;
        if (!has_data && flight_data(c) > 0 && same_window) {
            if (++c->dupacks == 3 && !c->in_recovery) {
                uint32_t flight = flight_data(c);
                ++s->stats.fast_retransmits;
                c->ssthresh = max_u32(flight / 2u, 2u * c->mss);
                c->cwnd = c->ssthresh + 3u * c->mss;
                c->in_recovery = 1;
                c->recover = c->snd_nxt;
                retransmit_oldest(s, c, now_ms);
                --s->stats.retransmits;
            } else if (c->in_recovery && c->dupacks > 3) {
                c->cwnd += c->mss;
            }
        }
        return;
    }
    acked = ack - c->snd_una;
    c->snd_wnd = window;
    c->dupacks = 0;
    c->retries = 0;
    if (c->rtt_timing && seq_le(c->rtt_seq, ack)) update_rtt(c, now_ms);
    {
        uint32_t data_acked = acked;
        if (c->fin_sent && ack == c->snd_nxt) {
            c->fin_acked = 1;
            --data_acked;
        }
        if (data_acked > c->snd_len) data_acked = (uint32_t)c->snd_len;
        c->snd_head = (c->snd_head + data_acked) % EXTERIA_TCPIP_BUFFER;
        c->snd_len -= data_acked;
    }
    c->snd_una = ack;
    if (seq_lt(c->snd_nxt, c->snd_una)) c->snd_nxt = c->snd_una;
    if (c->in_recovery) {
        if (seq_le(c->recover, ack)) {
            c->cwnd = c->ssthresh;
            c->in_recovery = 0;
        } else {
            /* a partial acknowledgement means the next segment was lost too */
            ++s->stats.fast_retransmits;
            retransmit_oldest(s, c, now_ms);
            --s->stats.retransmits;
            c->cwnd = c->cwnd > acked ? c->cwnd - acked + c->mss : c->mss;
        }
    } else if (c->cwnd < c->ssthresh) {
        c->cwnd += min_u32(acked, c->mss);
    } else {
        c->cwnd += max_u32(1u, c->mss * c->mss / c->cwnd);
    }
    if (c->cwnd > 0x7FFFFFFFu) c->cwnd = 0x7FFFFFFFu;
    c->rto_deadline = 0;
    if (flight_data(c) > 0 || (c->fin_sent && !c->fin_acked)) c->rto_deadline = now_ms + c->rto_ms;
}

/* 1 when the options carried a segment size, which then bounds ours */
static int parse_mss(conn *c, const uint8_t *opts, size_t len) {
    size_t i = 0;
    while (i < len) {
        uint8_t kind = opts[i];
        if (kind == 0) break;
        if (kind == 1) {
            ++i;
            continue;
        }
        if (i + 1 >= len || opts[i + 1] < 2 || i + opts[i + 1] > len) break;
        if (kind == 2 && opts[i + 1] == 4) {
            uint32_t peer = get_u16(opts + i + 2);
            if (peer >= 64 && peer < c->mss) c->mss = peer;
            return 1;
        }
        i += opts[i + 1];
    }
    return 0;
}

static void conn_input(exteria_tcpip *s, conn *c, uint32_t seq, uint32_t ack, uint8_t flags, uint32_t window, const uint8_t *opts, size_t opts_len,
                       const uint8_t *data, size_t data_len, uint64_t now_ms) {
    int has_ack = (flags & F_ACK) != 0;
    if (c->state == EXTERIA_TCPIP_CONNECTING) {
        if (has_ack && (seq_le(ack, c->iss) || seq_gt(ack, c->snd_nxt))) {
            if (!(flags & F_RST)) send_reset_for(s, c->remote_ip, c->remote_port, c->local_port, seq, ack, 1, 0);
            return;
        }
        if (flags & F_RST) {
            if (has_ack) fail(c, EXTERIA_E_IO);
            return;
        }
        if ((flags & F_SYN) && has_ack) {
            c->rcv_nxt = seq + 1;
            c->snd_una = ack;
            c->snd_wnd = window;
            c->mss = (uint32_t)(s->mtu - IP_HEADER - TCP_HEADER);
            /* a peer that names no segment size is taken to accept 536, as RFC 9293 says */
            if (!parse_mss(c, opts, opts_len)) c->mss = min_u32(c->mss, DEFAULT_PEER_MSS);
            c->cwnd = INITIAL_CWND_SEGMENTS * c->mss;
            c->state = EXTERIA_TCPIP_OPEN;
            c->retries = 0;
            c->rto_deadline = 0;
            if (c->rtt_timing) update_rtt(c, now_ms);
            send_ack(s, c);
        }
        return;
    }
    if (flags & F_RST) {
        /* only a reset that lands in the window counts, or anyone could end a connection by guessing a port */
        if (seq_le(c->rcv_nxt, seq) && seq_lt(seq, c->rcv_nxt + (uint32_t)(EXTERIA_TCPIP_BUFFER - c->rcv_len) + 1u)) fail(c, EXTERIA_E_IO);
        return;
    }
    if (flags & F_SYN) {
        /* a repeated SYN-ACK: the handshake ACK was lost */
        send_ack(s, c);
        return;
    }
    if (!has_ack) return;
    handle_ack(s, c, ack, window, data_len > 0, now_ms);
    if (c->state == EXTERIA_TCPIP_FAILED) return;
    {
        uint32_t seg_seq = seq;
        size_t skip = 0, take = data_len;
        int immediate = 0;
        if (data_len > 0 || (flags & F_FIN)) {
            if (seq_lt(seg_seq, c->rcv_nxt)) {
                uint32_t behind = c->rcv_nxt - seg_seq;
                skip = behind >= data_len ? data_len : behind;
                take = data_len - skip;
                if (take == 0) immediate = 1;
            }
            if (take > 0) {
                uint32_t offset = (seg_seq + (uint32_t)skip) - c->rcv_nxt;
                size_t room = EXTERIA_TCPIP_BUFFER - c->rcv_len;
                if (offset >= room) {
                    take = 0;
                    immediate = 1;
                } else if (take > room - offset) {
                    take = room - offset;
                }
                if (take > 0) {
                    rcv_store(c, offset, data + skip, take);
                    if (offset == 0) {
                        c->rcv_len += take;
                        c->rcv_nxt += (uint32_t)take;
                    } else {
                        ++s->stats.out_of_order;
                        ooo_add(c, c->rcv_nxt + offset, c->rcv_nxt + offset + (uint32_t)take);
                        immediate = 1;
                    }
                }
            }
            if (flags & F_FIN) {
                uint32_t fin_seq = seg_seq + (uint32_t)data_len;
                if (seq_le(c->rcv_nxt, fin_seq) && seq_le(fin_seq, c->rcv_nxt + (uint32_t)(EXTERIA_TCPIP_BUFFER - c->rcv_len))) {
                    c->fin_pending = 1;
                    c->fin_seq = fin_seq;
                }
                immediate = 1;
            }
            absorb(c);
            if (c->ooo_count > 0) immediate = 1;
            if (immediate) {
                send_ack(s, c);
            } else if (take > 0) {
                if (++c->ack_pending >= 2) send_ack(s, c);
                else if (c->ack_pending == 1) c->ack_deadline = now_ms + DELAYED_ACK_MS;
            }
        }
    }
    if (c->state == EXTERIA_TCPIP_OPEN && c->fin_acked && c->peer_fin) c->state = EXTERIA_TCPIP_DONE;
    output(s, c, now_ms);
}

void exteria_tcpip_input(exteria_tcpip *s, const uint8_t *packet, size_t len, uint64_t now_ms) {
    size_t ihl, total, tcp_len, doff;
    uint32_t src, dst, seq, ack, window, seg_len;
    uint8_t flags;
    const uint8_t *tcp;
    conn *c;
    uint16_t src_port, dst_port;
    if (!s || !packet) return;
    ++s->stats.segments_in;
    if (len < IP_HEADER + TCP_HEADER || (packet[0] >> 4) != 4) goto bad;
    ihl = (size_t)(packet[0] & 0x0Fu) * 4u;
    total = get_u16(packet + 2);
    if (ihl < IP_HEADER || total < ihl + TCP_HEADER || total > len || packet[9] != PROTO_TCP) goto bad;
    if (fold(sum_bytes(0, packet, ihl)) != 0) goto bad;
    /* fragments cannot be put back together here, and a sender that set DF never makes them */
    if ((get_u16(packet + 6) & 0x3FFFu) != 0) goto bad;
    src = exteria_get_u32be(packet + 12);
    dst = exteria_get_u32be(packet + 16);
    if (dst != s->local_ip) goto bad;
    tcp = packet + ihl;
    tcp_len = total - ihl;
    doff = (size_t)(tcp[12] >> 4) * 4u;
    if (doff < TCP_HEADER || doff > tcp_len) goto bad;
    if (tcp_checksum(src, dst, tcp, tcp_len) != 0) goto bad;
    src_port = get_u16(tcp);
    dst_port = get_u16(tcp + 2);
    seq = exteria_get_u32be(tcp + 4);
    ack = exteria_get_u32be(tcp + 8);
    flags = tcp[13];
    window = get_u16(tcp + 14);
    seg_len = (uint32_t)(tcp_len - doff) + ((flags & F_SYN) ? 1u : 0u) + ((flags & F_FIN) ? 1u : 0u);
    c = find_by_tuple(s, src, src_port, dst_port);
    if (!c) {
        if (!(flags & F_RST)) send_reset_for(s, src, src_port, dst_port, seq, ack, (flags & F_ACK) != 0, seg_len);
        return;
    }
    conn_input(s, c, seq, ack, flags, window, tcp + TCP_HEADER, doff - TCP_HEADER, tcp + doff, tcp_len - doff, now_ms);
    return;
bad:
    ++s->stats.bad_packets;
}
