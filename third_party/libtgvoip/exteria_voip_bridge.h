#ifndef EXTERIA_VOIP_BRIDGE_H
#define EXTERIA_VOIP_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* the glue between the app and libtgvoip: a C face on the call engine, so the Objective-C side never meets the C++ classes. The engine
   runs its own threads, and every callback below arrives on one of them, not on the main thread */

#define EXTERIA_VOIP_KEY_LEN 256
#define EXTERIA_VOIP_TAG_LEN 16

/* the states libtgvoip reports, as its own numbers */
enum {
    EXTERIA_VOIP_WAIT_INIT = 1,
    EXTERIA_VOIP_WAIT_INIT_ACK,
    EXTERIA_VOIP_ESTABLISHED,
    EXTERIA_VOIP_FAILED,
    EXTERIA_VOIP_RECONNECTING
};

typedef struct exteria_voip exteria_voip;

typedef struct exteria_voip_endpoint {
    int64_t id;
    uint16_t port;
    uint8_t tcp;
    char ip[48];
    char ipv6[48];
    uint8_t peer_tag[EXTERIA_VOIP_TAG_LEN];
} exteria_voip_endpoint;

typedef void (*exteria_voip_state_callback)(void *context, int state);
typedef void (*exteria_voip_bars_callback)(void *context, int bars);

/* the library version the engine speaks, to name in the call protocol */
const char *exteria_voip_version(void);

/* makes an engine for one call over the endpoints with the shared key; nothing runs until exteria_voip_start. allow_p2p is the call's flag,
   max_layer the layer its protocol settled on. NULL when the arguments are unusable */
exteria_voip *exteria_voip_create(const exteria_voip_endpoint *endpoints, size_t count, const uint8_t key[EXTERIA_VOIP_KEY_LEN], int outgoing,
                                  int allow_p2p, int32_t max_layer, exteria_voip_state_callback state, exteria_voip_bars_callback bars,
                                  void *context);
/* opens the audio and starts connecting */
void exteria_voip_start(exteria_voip *voip);
void exteria_voip_set_muted(exteria_voip *voip, int muted);
/* the signal bars from 1 to 4 */
int exteria_voip_bars(exteria_voip *voip);
/* the last error: 0 none, 1 incompatible, 2 timeout, 3 audio io, 4 proxy */
int exteria_voip_last_error(exteria_voip *voip);
/* the endpoint id the call settled on, zero before it did */
int64_t exteria_voip_relay_id(exteria_voip *voip);
/* stops the threads and frees the engine; it joins them, so it is not for the main thread */
void exteria_voip_destroy(exteria_voip *voip);

#ifdef __cplusplus
}
#endif

#endif
