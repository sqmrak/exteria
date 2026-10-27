#ifndef EXTERIA_SHIRO_ENGINE_H
#define EXTERIA_SHIRO_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_warp.h"

/* a WireGuard tunnel that lives in the process: one UDP socket to the server, a TCP stack behind it, and streams
   that other parts of the program open to addresses on the far side */

typedef enum exteria_shiro_state {
    EXTERIA_SHIRO_HANDSHAKING = 0,
    EXTERIA_SHIRO_UP,
    EXTERIA_SHIRO_DOWN
} exteria_shiro_state;

typedef struct exteria_shiro_events {
    void *context;
    /* on the engine's thread; keep it short; DOWN comes with the reason: EXTERIA_E_TIMEOUT for a server that does
       not answer, EXTERIA_E_SECURITY for a reply that does not authenticate */
    void (*state)(void *context, exteria_shiro_state state, exteria_status reason);
    /* one line of what the tunnel does, never with a key or with payload */
    void (*trace)(void *context, const char *line);
} exteria_shiro_events;

typedef struct exteria_shiro_stats {
    uint64_t bytes_in, bytes_out;           /* UDP payload bytes to and from the server */
    uint32_t handshakes;
    uint64_t session_age_ms;
    unsigned streams;
} exteria_shiro_stats;

typedef struct exteria_shiro_engine exteria_shiro_engine;

/* starts the thread and the first handshake with the server at endpoint_ip:endpoint_port */
exteria_status exteria_shiro_engine_start(exteria_shiro_engine **out, const exteria_warp_identity *identity, uint32_t endpoint_ip, uint16_t endpoint_port,
                                          const exteria_shiro_events *events);

/* ends everything: the streams are closed, the keys wiped, the thread joined */
void exteria_shiro_engine_stop(exteria_shiro_engine *engine);

/* a stream to ip:port (host order) on the far side, as a connected non blocking socket for the caller to use like
   any TCP socket; waits until the far side has answered or timeout_ms has passed */
exteria_status exteria_shiro_engine_open(exteria_shiro_engine *engine, uint32_t ip, uint16_t port, int timeout_ms, int *fd);

/* a datagram socket for UDP through the tunnel, as a non blocking local socket for the caller to use with send and
   recv */
exteria_status exteria_shiro_engine_open_udp(exteria_shiro_engine *engine, int *fd);

exteria_shiro_state exteria_shiro_engine_state(exteria_shiro_engine *engine);
void exteria_shiro_engine_stats(exteria_shiro_engine *engine, exteria_shiro_stats *stats);

#endif
