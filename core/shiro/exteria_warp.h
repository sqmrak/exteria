#ifndef EXTERIA_WARP_H
#define EXTERIA_WARP_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_wg.h"

/* what Cloudflare WARP needs from a client that is not Cloudflare's */

#define EXTERIA_WARP_MAX_PORTS 16
#define EXTERIA_WARP_MTU 1280
#define EXTERIA_WARP_INSTALL_ID_LEN 22
#define EXTERIA_WARP_SIGNATURE_MAX 2048

typedef struct exteria_warp_identity {
    uint8_t private_key[EXTERIA_WG_KEY_LEN];
    uint8_t peer_public[EXTERIA_WG_KEY_LEN];
    uint8_t reserved[3];
    int has_reserved;
    uint32_t address;                       /* the IPv4 address of this phone inside the tunnel */
    uint32_t endpoint_ip;                   /* of the WireGuard server, host order */
    uint16_t ports[EXTERIA_WARP_MAX_PORTS];
    size_t port_count;
} exteria_warp_identity;

/* RFC 4648 base64 with padding. decode is strict: no white space, no missing padding, no stray bits in the last character */
exteria_status exteria_base64_encode(const uint8_t *data, size_t len, char *out, size_t cap, size_t *out_len);
exteria_status exteria_base64_decode(const char *text, size_t text_len, uint8_t *out, size_t cap, size_t *out_len);

/* "a.b.c.d" and nothing else (no leading zeros, no spaces) into host order */
exteria_status exteria_warp_parse_ipv4(const char *text, size_t len, uint32_t *out);

/* a new private key (clamped, from the system's entropy) and its public key */
exteria_status exteria_warp_generate_key(uint8_t private_key[EXTERIA_WG_KEY_LEN], uint8_t public_key[EXTERIA_WG_KEY_LEN]);

/* the JSON the registration call posts. install_id is EXTERIA_WARP_INSTALL_ID_LEN letters and digits drawn by the
   caller, tos the time as "2026-10-21T12:34:56.789Z"; EXTERIA_E_LIMIT when cap is too small */
exteria_status exteria_warp_registration_body(const uint8_t public_key[EXTERIA_WG_KEY_LEN], const char *install_id, const char *tos, char *out, size_t cap,
                                              size_t *len);

/* the answer of the registration call; every field that is used is checked for its type and its size, and the
   private key is only copied in */
exteria_status exteria_warp_parse_registration(const char *json, size_t len, const uint8_t private_key[EXTERIA_WG_KEY_LEN], exteria_warp_identity *out);

typedef struct exteria_warp_profile {
    char signature[2][EXTERIA_WARP_SIGNATURE_MAX];
} exteria_warp_profile;

/* the WireGuard configuration for the identity with the framing WARP is reached with; four junk datagrams of 40 to
   70 bytes, then two that look like SIP (an INVITE and a 100 Trying) before the initiation */
exteria_status exteria_warp_wg_config(const exteria_warp_identity *identity, exteria_warp_profile *profile, exteria_wg_config *out);

/* the server for an attempt: the first ones are the endpoint the account came with on each of its ports */
exteria_status exteria_warp_endpoint(const exteria_warp_identity *identity, unsigned attempt, uint32_t *ip, uint16_t *port);

#endif
