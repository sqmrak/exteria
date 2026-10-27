#ifndef FAKE_TCP_SERVER_H
#define FAKE_TCP_SERVER_H

#include <stddef.h>
#include <stdint.h>

/* a small TCP server for tests: it answers a SYN, takes bytes in order into a buffer, sends a pattern of bytes
   with a fixed window and its own retransmission */

typedef void (*fake_tcp_emit)(void *context, const uint8_t *packet, size_t len);

typedef struct fake_tcp_server {
    uint32_t ip;
    uint16_t port;
    fake_tcp_emit emit;
    void *emit_context;
    int connected;
    uint32_t client_ip;
    uint16_t client_port;
    uint32_t iss, snd_una, snd_nxt, irs, rcv_nxt, mss, client_window;
    uint16_t window;                /* advertised to the client */
    int syn_mss_option;
    int answer_syn;
    uint8_t *rx;
    size_t rx_len, rx_cap;
    int got_fin;
    size_t tx_total;                /* bytes to send, which are pattern_at(0..) */
    int fin_after_tx, fin_sent, fin_acked;
    uint32_t cwnd_segments;
    uint64_t rto_at;
    int saw_rst;
    uint32_t rst_seq;
    unsigned drop_nth_data;         /* drops the nth data segment the server sends for the first time (1 based), 0 never */
    unsigned data_segments_sent;
    unsigned dropped;
    size_t max_segment_seen;
    unsigned dup_acks_seen;
    uint32_t last_ack_seen;
    unsigned syns_seen;
} fake_tcp_server;

uint8_t fake_pattern_at(size_t i);

void fake_tcp_server_init(fake_tcp_server *v, uint32_t ip, uint16_t port, size_t rx_cap, fake_tcp_emit emit, void *context);
void fake_tcp_server_free(fake_tcp_server *v);
void fake_tcp_server_receive(fake_tcp_server *v, const uint8_t *packet, size_t len, uint64_t now);
void fake_tcp_server_pump(fake_tcp_server *v, uint64_t now);
/* the retransmission timer */
void fake_tcp_server_tick(fake_tcp_server *v, uint64_t now);

/* checksums and packets, shared with tests that craft their own segments */
uint16_t fake_fold(uint32_t sum);
uint32_t fake_add(uint32_t sum, const uint8_t *p, size_t n);
size_t fake_build_tcp(uint8_t *out, uint32_t src, uint32_t dst, uint16_t sport, uint16_t dport, uint32_t seq, uint32_t ack, uint8_t flags, uint16_t window,
                      int mss_option, const uint8_t *payload, size_t plen);

#endif
