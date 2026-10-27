#ifndef EXTERIA_BLAKE2S_H
#define EXTERIA_BLAKE2S_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* BLAKE2s as RFC 7693 defines it, with the key and the short outputs that WireGuard asks for (a 16 byte keyed mac,
   a 32 byte hash). openssl only exposes the unkeyed 32 byte form */

#define EXTERIA_BLAKE2S_BLOCK 64
#define EXTERIA_BLAKE2S_MAX_OUT 32
#define EXTERIA_BLAKE2S_MAX_KEY 32

typedef struct exteria_blake2s_ctx {
    uint32_t h[8];
    uint32_t t[2];
    uint8_t buf[EXTERIA_BLAKE2S_BLOCK];
    size_t used;
    size_t out_len;
} exteria_blake2s_ctx;

/* out_len from 1 to 32, key_len from 0 to 32 (EXTERIA_E_ARG outside that or for a null key with a length) */
exteria_status exteria_blake2s_init(exteria_blake2s_ctx *ctx, size_t out_len, const uint8_t *key, size_t key_len);
void exteria_blake2s_update(exteria_blake2s_ctx *ctx, const void *data, size_t len);
/* writes out_len bytes and wipes the state; the context is dead afterwards */
void exteria_blake2s_final(exteria_blake2s_ctx *ctx, uint8_t *out);

exteria_status exteria_blake2s(uint8_t *out, size_t out_len, const uint8_t *key, size_t key_len, const void *data, size_t len);

/* HMAC over BLAKE2s-256 (block size 64), the pseudo random function of the WireGuard key derivation. key_len up to 64 */
exteria_status exteria_blake2s_hmac(uint8_t out[32], const uint8_t *key, size_t key_len, const void *data, size_t len);

#endif
