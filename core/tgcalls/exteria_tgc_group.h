#ifndef EXTERIA_TGC_GROUP_H
#define EXTERIA_TGC_GROUP_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_dtls.h"
#include "exteria_status.h"
#include "exteria_tgc_group_join.h"
#include "exteria_tgc_ice.h"
#include "exteria_tgc_srtp.h"

/* the media connection of one group call (a voice chat): the phone joins with phone.joinGroupCall and its transport description, the server answers with
   its candidates, fingerprint and the ids of the audio description, and from there one ICE path, one DTLS session and one SRTP context carry the audio of
   everybody. the server is ICE lite and starts the DTLS handshake itself, so this side is the controlling ICE agent and, with the setup the server names,
   the DTLS server. no socket lives here: the owner opens one connected UDP socket for each endpoint and feeds what arrives */

/* a connection that has no media path this long after the answer of the server is given up */
#define EXTERIA_TGC_GROUP_CONNECT_TIMEOUT_MS 30000
#define EXTERIA_TGC_GROUP_PAYLOAD_MAX 1100

typedef enum exteria_tgc_group_state {
    EXTERIA_TGC_GROUP_NEW,          /* made, the server has not answered yet */
    EXTERIA_TGC_GROUP_CONNECTING,   /* the answer is in; no media path yet */
    EXTERIA_TGC_GROUP_CONNECTED,    /* ICE and DTLS are up, audio flows */
    EXTERIA_TGC_GROUP_RECONNECTING, /* the path went silent */
    EXTERIA_TGC_GROUP_FAILED        /* the handshake or the path failed for good; the owner leaves the call */
} exteria_tgc_group_state;

typedef struct exteria_tgc_group_events {
    void *context;
    /* a datagram for the socket of endpoint number index (see exteria_tgc_group_endpoint) */
    void (*send_datagram)(void *context, unsigned index, const uint8_t *data, size_t len);
    void (*state)(void *context, exteria_tgc_group_state state);
    /* an Opus packet of the source ssrc, with its sequence number and 48 kHz timestamp. level is the audio level the sender wrote into the packet, 0 (loud)
       to 127 (silent) in -dBov, and -1 when the packet has none; voice is its voice activity bit */
    void (*audio)(void *context, uint32_t ssrc, const uint8_t *opus, size_t len, uint16_t sequence, uint32_t timestamp, int level, int voice);
    /* optional: one line of what happens; never a key, a password or media */
    void (*trace)(void *context, const char *line);
} exteria_tgc_group_events;

typedef struct exteria_tgc_group exteria_tgc_group;

/* makes the connection with a random ssrc, ICE credentials and a DTLS certificate; EXTERIA_E_CRYPTO when the certificate cannot be made */
exteria_status exteria_tgc_group_new(exteria_tgc_group **out, const exteria_tgc_group_events *events);
void exteria_tgc_group_free(exteria_tgc_group *group);

/* the ssrc of this phone's audio, as joined with */
uint32_t exteria_tgc_group_ssrc(const exteria_tgc_group *group);

/* the JSON for the params of phone.joinGroupCall */
exteria_status exteria_tgc_group_join_payload(const exteria_tgc_group *group, char *out, size_t capacity, size_t *len);

/* the answer of the server (updateGroupCallConnection): sets the remote credentials, the fingerprint and the DTLS role, and makes an endpoint of each IPv4 UDP
   candidate. EXTERIA_E_STATE when it was applied before, EXTERIA_E_UNSUPPORTED when no candidate can be used, EXTERIA_E_SECURITY for a fingerprint the
   DTLS layer refuses */
exteria_status exteria_tgc_group_apply(exteria_tgc_group *group, const exteria_tgc_group_transport *transport, uint64_t now_ms);

/* the address of endpoint number index (IPv4, host order); EXTERIA_E_NOTFOUND past the last one. valid after exteria_tgc_group_apply */
exteria_status exteria_tgc_group_endpoint(const exteria_tgc_group *group, unsigned index, uint32_t *ip, uint16_t *port);

/* a datagram that arrived at the socket of endpoint number index */
exteria_status exteria_tgc_group_datagram(exteria_tgc_group *group, unsigned index, const uint8_t *data, size_t len, uint64_t now_ms);

/* the timers: ICE checks, the DTLS flight, the connection timeout; every 20 to 50 ms */
void exteria_tgc_group_tick(exteria_tgc_group *group, uint64_t now_ms);

/* the microphone: one Opus packet of `samples` samples at 48 kHz, with the level of the frame (0 to 127, -dBov) and whether it holds speech;
   EXTERIA_E_STATE until the media path is up */
exteria_status exteria_tgc_group_send_audio(exteria_tgc_group *group, const uint8_t *opus, size_t len, uint32_t samples, int level, int voice);

/* a source that left the call gives its place in the SRTP table back */
void exteria_tgc_group_forget(exteria_tgc_group *group, uint32_t ssrc);

exteria_tgc_group_state exteria_tgc_group_get_state(const exteria_tgc_group *group);
/* the stage of the path for the diagnostics: ice state, dtls state, packets of audio in and out */
void exteria_tgc_group_diagnostics(const exteria_tgc_group *group, int *ice, int *dtls, unsigned *audio_in, unsigned *audio_out);

#endif
