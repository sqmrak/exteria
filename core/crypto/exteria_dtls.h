#ifndef EXTERIA_DTLS_H
#define EXTERIA_DTLS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* DTLS 1.2 with SRTP keying (RFC 5764) for the media path of a call; input takes what arrived from the network and
   poll gives what has to be sent, so no socket lives here and the whole handshake can run in memory */

#define EXTERIA_DTLS_FINGERPRINT_LEN 95
#define EXTERIA_DTLS_MAX_DATAGRAM 1500
/* the most one write may carry: a record has to fit the 1200 byte MTU the session is set to, with its header, tag and explicit nonce */
#define EXTERIA_DTLS_MAX_APP_DATA 1100
#define EXTERIA_DTLS_SRTP_KEY_LEN 16
#define EXTERIA_DTLS_SRTP_SALT_LEN 14

typedef struct exteria_dtls exteria_dtls;

typedef enum exteria_dtls_state {
    EXTERIA_DTLS_IDLE,          /* made, not started */
    EXTERIA_DTLS_HANDSHAKING,
    EXTERIA_DTLS_CONNECTED,
    EXTERIA_DTLS_FAILED
} exteria_dtls_state;

/* makes the session and its certificate; EXTERIA_E_CRYPTO when the library cannot make one */
exteria_status exteria_dtls_new(exteria_dtls **out);
void exteria_dtls_free(exteria_dtls *d);

/* "AA:BB:...:FF", 95 characters, the SHA-256 of the certificate as RFC 4572 writes it; valid as long as d */
const char *exteria_dtls_local_fingerprint(const exteria_dtls *d);

/* the fingerprint the other side announced; only "sha-256" (any case) is understood; the value is 32 hex pairs
   with colons, either case */
exteria_status exteria_dtls_set_peer_fingerprint(exteria_dtls *d, const char *hash, const char *fingerprint);

/* starts the handshake as the client (sends the first flight) or the server (waits for it); EXTERIA_E_STATE when
   it was started before */
exteria_status exteria_dtls_start(exteria_dtls *d, int is_client);

/* one datagram from the network; EXTERIA_E_LIMIT above EXTERIA_DTLS_MAX_DATAGRAM, EXTERIA_E_LIMIT also when too
   many wait for a start */
exteria_status exteria_dtls_input(exteria_dtls *d, const uint8_t *datagram, size_t len);

/* the next datagram to send, in out; EXTERIA_E_RETRY when there is none */
exteria_status exteria_dtls_poll(exteria_dtls *d, uint8_t *out, size_t capacity, size_t *len);

/* milliseconds until the handshake wants on_timeout called to resend its flight; EXTERIA_E_STATE when no timer runs */
exteria_status exteria_dtls_timeout(exteria_dtls *d, uint32_t *ms);
/* the time given by timeout has passed: resends the flight */
exteria_status exteria_dtls_on_timeout(exteria_dtls *d);

exteria_dtls_state exteria_dtls_get_state(const exteria_dtls *d);

/* once CONNECTED: the SRTP keys of the two directions as a 16 byte key and a 14 byte salt each; send is for what
   this side sends; EXTERIA_E_STATE before that */
exteria_status exteria_dtls_srtp_keys(exteria_dtls *d, uint8_t send_key[EXTERIA_DTLS_SRTP_KEY_LEN], uint8_t send_salt[EXTERIA_DTLS_SRTP_SALT_LEN],
                                      uint8_t recv_key[EXTERIA_DTLS_SRTP_KEY_LEN], uint8_t recv_salt[EXTERIA_DTLS_SRTP_SALT_LEN]);

/* application data: write one message of up to EXTERIA_DTLS_MAX_APP_DATA bytes (EXTERIA_E_LIMIT above that,
   EXTERIA_E_STATE before CONNECTED); read gives the next decrypted message */
exteria_status exteria_dtls_write(exteria_dtls *d, const uint8_t *data, size_t len);
exteria_status exteria_dtls_read(exteria_dtls *d, uint8_t *out, size_t capacity, size_t *len);

#endif
