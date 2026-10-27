#include "fake_tcp_server.h"

#include <stdlib.h>
#include <string.h>

#include "exteria_bytes.h"

uint8_t fake_pattern_at(size_t i) {
    return (uint8_t)((i * 31 + 7) & 0xFF);
}

uint16_t fake_fold(uint32_t sum) {
    while (sum >> 16) sum = (sum & 0xFFFF) + (sum >> 16);
    return (uint16_t)~sum;
}

uint32_t fake_add(uint32_t sum, const uint8_t *p, size_t n) {
    size_t i;
    for (i = 0; i + 1 < n; i += 2) sum += (uint32_t)p[i] << 8 | p[i + 1];
    if (n & 1) sum += (uint32_t)p[n - 1] << 8;
    return sum;
}

static void put16(uint8_t *p, unsigned v) {
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)v;
}

size_t fake_build_tcp(uint8_t *out, uint32_t src, uint32_t dst, uint16_t sport, uint16_t dport, uint32_t seq, uint32_t ack, uint8_t flags, uint16_t window,
                      int mss_option, const uint8_t *payload, size_t plen) {
    size_t tcp_len = 20 + (mss_option ? 4 : 0), total = 20 + tcp_len + plen;
    uint8_t pseudo[12];
    uint8_t *tcp = out + 20;
    memset(out, 0, 20 + tcp_len);
    out[0] = 0x45;
    put16(out + 2, (unsigned)total);
    put16(out + 6, 0x4000);
    out[8] = 64;
    out[9] = 6;
    exteria_put_u32be(out + 12, src);
    exteria_put_u32be(out + 16, dst);
    put16(out + 10, fake_fold(fake_add(0, out, 20)));
    put16(tcp, sport);
    put16(tcp + 2, dport);
    exteria_put_u32be(tcp + 4, seq);
    exteria_put_u32be(tcp + 8, ack);
    tcp[12] = (uint8_t)((tcp_len / 4) << 4);
    tcp[13] = flags;
    put16(tcp + 14, window);
    if (mss_option) {
        tcp[20] = 2;
        tcp[21] = 4;
        put16(tcp + 22, 1240);
    }
    if (plen) memcpy(tcp + tcp_len, payload, plen);
    exteria_put_u32be(pseudo, src);
    exteria_put_u32be(pseudo + 4, dst);
    pseudo[8] = 0;
    pseudo[9] = 6;
    put16(pseudo + 10, (unsigned)(tcp_len + plen));
    put16(tcp + 16, fake_fold(fake_add(fake_add(0, pseudo, 12), tcp, tcp_len + plen)));
    return total;
}

void fake_tcp_server_init(fake_tcp_server *v, uint32_t ip, uint16_t port, size_t rx_cap, fake_tcp_emit emit, void *context) {
    memset(v, 0, sizeof(*v));
    v->ip = ip;
    v->port = port;
    v->emit = emit;
    v->emit_context = context;
    v->iss = 0xFFFFFF00u; /* the sequence numbers wrap during the transfers */
    v->mss = 1240;
    v->window = 65535;
    v->cwnd_segments = 8;
    v->syn_mss_option = 1;
    v->answer_syn = 1;
    v->rx_cap = rx_cap;
    v->rx = (uint8_t *)malloc(rx_cap ? rx_cap : 1);
}

void fake_tcp_server_free(fake_tcp_server *v) {
    free(v->rx);
    v->rx = NULL;
}

static void server_send(fake_tcp_server *v, uint32_t seq, uint8_t flags, const uint8_t *payload, size_t plen, int mss_option) {
    uint8_t packet[1500];
    size_t n = fake_build_tcp(packet, v->ip, v->client_ip, v->port, v->client_port, seq, v->rcv_nxt, flags, v->window, mss_option, payload, plen);
    v->emit(v->emit_context, packet, n);
}

void fake_tcp_server_pump(fake_tcp_server *v, uint64_t now) {
    uint32_t window_bytes = v->cwnd_segments * v->mss;
    if (!v->connected) return;
    if (v->client_window < window_bytes) window_bytes = v->client_window;
    for (;;) {
        uint32_t flight = v->snd_nxt - v->snd_una;
        size_t off = (size_t)(v->snd_nxt - (v->iss + 1));
        if (v->fin_sent) break;
        if (off < v->tx_total) {
            uint8_t chunk[1500];
            size_t len = v->tx_total - off, i;
            if (flight >= window_bytes) break;
            if (len > v->mss) len = v->mss;
            if (len > window_bytes - flight) len = window_bytes - flight;
            for (i = 0; i < len; ++i) chunk[i] = fake_pattern_at(off + i);
            ++v->data_segments_sent;
            if (v->drop_nth_data && v->data_segments_sent == v->drop_nth_data) ++v->dropped;
            else server_send(v, v->snd_nxt, 0x10, chunk, len, 0);
            v->snd_nxt += (uint32_t)len;
            if (!v->rto_at) v->rto_at = now + 300;
        } else {
            if (v->fin_after_tx) {
                server_send(v, v->snd_nxt, 0x11, NULL, 0, 0);
                v->snd_nxt += 1;
                v->fin_sent = 1;
                if (!v->rto_at) v->rto_at = now + 300;
            }
            break;
        }
    }
}

void fake_tcp_server_receive(fake_tcp_server *v, const uint8_t *packet, size_t len, uint64_t now) {
    const uint8_t *tcp = packet + 20;
    uint32_t seq = exteria_get_u32be(tcp + 4), ack = exteria_get_u32be(tcp + 8);
    uint8_t flags = tcp[13];
    size_t doff = (size_t)(tcp[12] >> 4) * 4, plen = len - 20 - doff;
    if (len > v->max_segment_seen) v->max_segment_seen = len;
    if (flags & 0x04) {
        v->saw_rst = 1;
        v->rst_seq = seq;
        return;
    }
    if (flags & 0x02) {
        ++v->syns_seen;
        if (!v->answer_syn) return;
        v->client_ip = exteria_get_u32be(packet + 12);
        v->client_port = (uint16_t)(tcp[0] << 8 | tcp[1]);
        v->irs = seq;
        v->rcv_nxt = seq + 1;
        v->snd_una = v->iss;
        v->snd_nxt = v->iss + 1;
        v->connected = 1;
        v->client_window = (uint32_t)(tcp[14] << 8 | tcp[15]);
        server_send(v, v->iss, 0x12, NULL, 0, v->syn_mss_option);
        return;
    }
    if (!v->connected) return;
    if (flags & 0x10) {
        v->client_window = (uint32_t)(tcp[14] << 8 | tcp[15]);
        if (ack == v->last_ack_seen && plen == 0 && !(flags & 0x01) && ack == v->snd_una) ++v->dup_acks_seen;
        v->last_ack_seen = ack;
        if ((int32_t)(ack - v->snd_una) > 0 && (int32_t)(ack - v->snd_nxt) <= 0) {
            v->snd_una = ack;
            v->rto_at = v->snd_una == v->snd_nxt ? 0 : now + 300;
            if (v->fin_sent && ack == v->snd_nxt) v->fin_acked = 1;
        }
    }
    if (plen > 0 || (flags & 0x01)) {
        if (seq == v->rcv_nxt) {
            if (plen > 0 && v->rx_len + plen <= v->rx_cap) {
                memcpy(v->rx + v->rx_len, tcp + doff, plen);
                v->rx_len += plen;
                v->rcv_nxt += (uint32_t)plen;
            }
            if (flags & 0x01) {
                v->got_fin = 1;
                v->rcv_nxt += 1;
            }
        }
        server_send(v, v->snd_nxt, 0x10, NULL, 0, 0);
    }
    fake_tcp_server_pump(v, now);
}

void fake_tcp_server_tick(fake_tcp_server *v, uint64_t now) {
    if (v->rto_at && now >= v->rto_at && v->connected) {
        /* the server's own retransmission: everything unacknowledged again */
        v->snd_nxt = v->snd_una;
        v->fin_sent = 0;
        v->rto_at = 0;
        fake_tcp_server_pump(v, now);
    }
}
