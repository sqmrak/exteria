#ifndef EXTERIA_TCPIP_H
#define EXTERIA_TCPIP_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the TCP of one phone inside a tunnel: IPv4 only, client side only, no options but the segment size */

#define EXTERIA_TCPIP_MAX_CONNECTIONS 32
/* each direction of a connection keeps this many bytes, which is also the largest window without the scaling option */
#define EXTERIA_TCPIP_BUFFER 65536
#define EXTERIA_TCPIP_MIN_MTU 576
#define EXTERIA_TCPIP_MAX_MTU 1500

typedef void (*exteria_tcpip_emit)(void *context, const uint8_t *packet, size_t len);

typedef struct exteria_tcpip exteria_tcpip;

/* local_ip is the address the tunnel gave this phone; mtu from EXTERIA_TCPIP_MIN_MTU to EXTERIA_TCPIP_MAX_MTU is the size of the largest packet sent */
exteria_status exteria_tcpip_new(exteria_tcpip **out, uint32_t local_ip, uint16_t mtu, exteria_tcpip_emit emit, void *context);
void exteria_tcpip_free(exteria_tcpip *stack);

/* a packet that came out of the tunnel */
void exteria_tcpip_input(exteria_tcpip *stack, const uint8_t *packet, size_t len, uint64_t now_ms);

/* timers: retransmission, delayed acknowledgements, giving up */
void exteria_tcpip_tick(exteria_tcpip *stack, uint64_t now_ms);

/* the connection id stays valid until released; EXTERIA_E_LIMIT when all slots are taken, EXTERIA_E_NOMEM,
   EXTERIA_E_ARG for port 0 or address 0 */
exteria_status exteria_tcpip_connect(exteria_tcpip *stack, uint32_t remote_ip, uint16_t remote_port, uint64_t now_ms, uint32_t *id);

typedef enum exteria_tcpip_state {
    EXTERIA_TCPIP_CONNECTING = 0,   /* the SYN is out */
    EXTERIA_TCPIP_OPEN,             /* data may flow both ways (maybe one of them already ended) */
    EXTERIA_TCPIP_DONE,             /* both directions ended and acknowledged */
    EXTERIA_TCPIP_FAILED            /* reset by the peer, or no answer in time */
} exteria_tcpip_state;

typedef struct exteria_tcpip_info {
    exteria_tcpip_state state;
    size_t readable;            /* bytes waiting for exteria_tcpip_recv */
    size_t send_space;          /* bytes exteria_tcpip_send will take now */
    int peer_closed;            /* the peer's FIN arrived and everything before it was received */
    int closed_by_us;           /* exteria_tcpip_close was called */
    exteria_status error;       /* EXTERIA_E_TIMEOUT, EXTERIA_E_IO (reset) or EXTERIA_OK */
} exteria_tcpip_info;

/* EXTERIA_E_NOTFOUND for an id that is not a connection of this stack */
exteria_status exteria_tcpip_info_get(const exteria_tcpip *stack, uint32_t id, exteria_tcpip_info *info);

/* queues up to len bytes and sends what the windows allow; *accepted says how many were taken (0 when the buffer
   is full: retry after the peer acknowledges) */
exteria_status exteria_tcpip_send(exteria_tcpip *stack, uint32_t id, const uint8_t *data, size_t len, uint64_t now_ms, size_t *accepted);

/* takes what has arrived, in order; EXTERIA_E_RETRY when nothing is there yet, EXTERIA_E_EOF when the peer closed
   and everything was read, EXTERIA_E_IO or EXTERIA_E_TIMEOUT for a failed connection */
exteria_status exteria_tcpip_recv(exteria_tcpip *stack, uint32_t id, uint8_t *buf, size_t cap, uint64_t now_ms, size_t *got);

/* no more data from us: the FIN follows the queued bytes */
exteria_status exteria_tcpip_close(exteria_tcpip *stack, uint32_t id, uint64_t now_ms);

/* frees the slot */
void exteria_tcpip_release(exteria_tcpip *stack, uint32_t id, uint64_t now_ms);

typedef struct exteria_tcpip_stats {
    uint32_t segments_in, segments_out, bad_packets, retransmits, fast_retransmits, out_of_order, resets_sent;
} exteria_tcpip_stats;

void exteria_tcpip_stats_get(const exteria_tcpip *stack, exteria_tcpip_stats *stats);

#endif
