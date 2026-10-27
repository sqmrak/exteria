#include "exteria_blake2s.h"

#include <string.h>

#include "exteria_bytes.h"

static const uint32_t iv[8] = {0x6A09E667u, 0xBB67AE85u, 0x3C6EF372u, 0xA54FF53Au, 0x510E527Fu, 0x9B05688Cu, 0x1F83D9ABu, 0x5BE0CD19u};

static const uint8_t sigma[10][16] = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}, {14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
    {11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4}, {7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8},
    {9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13}, {2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9},
    {12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11}, {13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10},
    {6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5}, {10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0}};

static uint32_t rotr(uint32_t x, unsigned n) {
    return (x >> n) | (x << (32u - n));
}

static uint32_t load32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

#define G(a, b, c, d, x, y)  \
    do {                     \
        v[a] += v[b] + (x);  \
        v[d] = rotr(v[d] ^ v[a], 16); \
        v[c] += v[d];        \
        v[b] = rotr(v[b] ^ v[c], 12); \
        v[a] += v[b] + (y);  \
        v[d] = rotr(v[d] ^ v[a], 8);  \
        v[c] += v[d];        \
        v[b] = rotr(v[b] ^ v[c], 7);  \
    } while (0)

static void compress(exteria_blake2s_ctx *ctx, const uint8_t block[EXTERIA_BLAKE2S_BLOCK], int last) {
    uint32_t m[16], v[16];
    unsigned i, r;
    for (i = 0; i < 16; ++i) m[i] = load32(block + 4 * i);
    for (i = 0; i < 8; ++i) {
        v[i] = ctx->h[i];
        v[i + 8] = iv[i];
    }
    v[12] ^= ctx->t[0];
    v[13] ^= ctx->t[1];
    if (last) v[14] = ~v[14];
    for (r = 0; r < 10; ++r) {
        const uint8_t *s = sigma[r];
        G(0, 4, 8, 12, m[s[0]], m[s[1]]);
        G(1, 5, 9, 13, m[s[2]], m[s[3]]);
        G(2, 6, 10, 14, m[s[4]], m[s[5]]);
        G(3, 7, 11, 15, m[s[6]], m[s[7]]);
        G(0, 5, 10, 15, m[s[8]], m[s[9]]);
        G(1, 6, 11, 12, m[s[10]], m[s[11]]);
        G(2, 7, 8, 13, m[s[12]], m[s[13]]);
        G(3, 4, 9, 14, m[s[14]], m[s[15]]);
    }
    for (i = 0; i < 8; ++i) ctx->h[i] ^= v[i] ^ v[i + 8];
    exteria_wipe(m, sizeof(m));
    exteria_wipe(v, sizeof(v));
}

static void count(exteria_blake2s_ctx *ctx, size_t n) {
    ctx->t[0] += (uint32_t)n;
    if (ctx->t[0] < (uint32_t)n) ++ctx->t[1];
}

exteria_status exteria_blake2s_init(exteria_blake2s_ctx *ctx, size_t out_len, const uint8_t *key, size_t key_len) {
    unsigned i;
    if (!ctx) return EXTERIA_E_ARG;
    memset(ctx, 0, sizeof(*ctx));
    if (out_len < 1 || out_len > EXTERIA_BLAKE2S_MAX_OUT || key_len > EXTERIA_BLAKE2S_MAX_KEY || (key_len && !key)) return EXTERIA_E_ARG;
    for (i = 0; i < 8; ++i) ctx->h[i] = iv[i];
    /* the parameter block: digest length, key length, fanout 1 and depth 1 */
    ctx->h[0] ^= 0x01010000u ^ (uint32_t)(key_len << 8) ^ (uint32_t)out_len;
    ctx->out_len = out_len;
    if (key_len) {
        /* the key fills a whole block of its own, ahead of the data */
        memcpy(ctx->buf, key, key_len);
        ctx->used = EXTERIA_BLAKE2S_BLOCK;
    }
    return EXTERIA_OK;
}

void exteria_blake2s_update(exteria_blake2s_ctx *ctx, const void *data, size_t len) {
    const uint8_t *in = (const uint8_t *)data;
    while (len > 0) {
        size_t room;
        /* a full buffer is only compressed once more data follows, since the last block carries the final flag */
        if (ctx->used == EXTERIA_BLAKE2S_BLOCK) {
            count(ctx, EXTERIA_BLAKE2S_BLOCK);
            compress(ctx, ctx->buf, 0);
            ctx->used = 0;
        }
        room = EXTERIA_BLAKE2S_BLOCK - ctx->used;
        if (room > len) room = len;
        memcpy(ctx->buf + ctx->used, in, room);
        ctx->used += room;
        in += room;
        len -= room;
    }
}

void exteria_blake2s_final(exteria_blake2s_ctx *ctx, uint8_t *out) {
    uint8_t full[EXTERIA_BLAKE2S_MAX_OUT];
    unsigned i;
    count(ctx, ctx->used);
    memset(ctx->buf + ctx->used, 0, EXTERIA_BLAKE2S_BLOCK - ctx->used);
    compress(ctx, ctx->buf, 1);
    for (i = 0; i < 8; ++i) {
        full[4 * i] = (uint8_t)ctx->h[i];
        full[4 * i + 1] = (uint8_t)(ctx->h[i] >> 8);
        full[4 * i + 2] = (uint8_t)(ctx->h[i] >> 16);
        full[4 * i + 3] = (uint8_t)(ctx->h[i] >> 24);
    }
    memcpy(out, full, ctx->out_len);
    exteria_wipe(full, sizeof(full));
    exteria_wipe(ctx, sizeof(*ctx));
}

exteria_status exteria_blake2s(uint8_t *out, size_t out_len, const uint8_t *key, size_t key_len, const void *data, size_t len) {
    exteria_blake2s_ctx ctx;
    exteria_status status;
    if (!out || (len && !data)) return EXTERIA_E_ARG;
    status = exteria_blake2s_init(&ctx, out_len, key, key_len);
    if (status != EXTERIA_OK) return status;
    exteria_blake2s_update(&ctx, data, len);
    exteria_blake2s_final(&ctx, out);
    return EXTERIA_OK;
}

exteria_status exteria_blake2s_hmac(uint8_t out[32], const uint8_t *key, size_t key_len, const void *data, size_t len) {
    uint8_t pad[EXTERIA_BLAKE2S_BLOCK], inner[32];
    exteria_blake2s_ctx ctx;
    size_t i;
    if (!out || (key_len && !key) || key_len > EXTERIA_BLAKE2S_BLOCK || (len && !data)) return EXTERIA_E_ARG;
    memset(pad, 0, sizeof(pad));
    if (key_len) memcpy(pad, key, key_len);
    for (i = 0; i < sizeof(pad); ++i) pad[i] ^= 0x36;
    (void)exteria_blake2s_init(&ctx, 32, NULL, 0);
    exteria_blake2s_update(&ctx, pad, sizeof(pad));
    exteria_blake2s_update(&ctx, data, len);
    exteria_blake2s_final(&ctx, inner);
    for (i = 0; i < sizeof(pad); ++i) pad[i] ^= 0x36 ^ 0x5c;
    (void)exteria_blake2s_init(&ctx, 32, NULL, 0);
    exteria_blake2s_update(&ctx, pad, sizeof(pad));
    exteria_blake2s_update(&ctx, inner, sizeof(inner));
    exteria_blake2s_final(&ctx, out);
    exteria_wipe(pad, sizeof(pad));
    exteria_wipe(inner, sizeof(inner));
    return EXTERIA_OK;
}
