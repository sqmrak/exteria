#ifndef EXTERIA_SHIRO_STORE_H
#define EXTERIA_SHIRO_STORE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_warp.h"

/* the bytes of the file the phone keeps its WARP account in: the private key, the server key and the addresses the
   registration returned */

#define EXTERIA_SHIRO_STORE_LEN 113u

/* EXTERIA_E_ARG for an identity the tunnel could not use (no endpoint, no address, no port, more ports than the identity holds), EXTERIA_E_LIMIT when cap is
   smaller than EXTERIA_SHIRO_STORE_LEN */
exteria_status exteria_shiro_store_pack(const exteria_warp_identity *identity, uint8_t *out, size_t cap, size_t *len);

/* EXTERIA_E_MALFORMED for a wrong size, magic or flag, or for the same identity that pack would refuse. out is zeroed on every failure */
exteria_status exteria_shiro_store_unpack(const uint8_t *data, size_t len, exteria_warp_identity *out);

#endif
