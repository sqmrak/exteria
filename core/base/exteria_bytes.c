#include "exteria_bytes.h"

#include <stdlib.h>
#include <string.h>

void exteria_put_u32le(uint8_t *out, uint32_t v) {
    out[0] = (uint8_t)v;
    out[1] = (uint8_t)(v >> 8);
    out[2] = (uint8_t)(v >> 16);
    out[3] = (uint8_t)(v >> 24);
}

void exteria_put_u64le(uint8_t *out, uint64_t v) {
    exteria_put_u32le(out, (uint32_t)v);
    exteria_put_u32le(out + 4, (uint32_t)(v >> 32));
}

void exteria_put_u32be(uint8_t *out, uint32_t v) {
    out[0] = (uint8_t)(v >> 24);
    out[1] = (uint8_t)(v >> 16);
    out[2] = (uint8_t)(v >> 8);
    out[3] = (uint8_t)v;
}

void exteria_put_u64be(uint8_t *out, uint64_t v) {
    exteria_put_u32be(out, (uint32_t)(v >> 32));
    exteria_put_u32be(out + 4, (uint32_t)v);
}

uint32_t exteria_get_u32le(const uint8_t *in) {
    return (uint32_t)in[0] | ((uint32_t)in[1] << 8) | ((uint32_t)in[2] << 16) | ((uint32_t)in[3] << 24);
}

uint64_t exteria_get_u64le(const uint8_t *in) {
    return (uint64_t)exteria_get_u32le(in) | ((uint64_t)exteria_get_u32le(in + 4) << 32);
}

uint32_t exteria_get_u32be(const uint8_t *in) {
    return ((uint32_t)in[0] << 24) | ((uint32_t)in[1] << 16) | ((uint32_t)in[2] << 8) | (uint32_t)in[3];
}

uint64_t exteria_get_u64be(const uint8_t *in) {
    return ((uint64_t)exteria_get_u32be(in) << 32) | (uint64_t)exteria_get_u32be(in + 4);
}

void exteria_reader_init(exteria_reader *r, const uint8_t *data, size_t len) {
    r->data = data;
    r->len = data ? len : 0;
    r->pos = 0;
    r->status = EXTERIA_OK;
}

size_t exteria_reader_left(const exteria_reader *r) {
    return r->len - r->pos;
}

const uint8_t *exteria_rd_bytes(exteria_reader *r, size_t n) {
    const uint8_t *p;
    if (r->status != EXTERIA_OK) return NULL;
    if (n > r->len - r->pos) {
        r->status = EXTERIA_E_TRUNCATED;
        return NULL;
    }
    p = r->data + r->pos;
    r->pos += n;
    return p;
}

uint8_t exteria_rd_u8(exteria_reader *r) {
    const uint8_t *p = exteria_rd_bytes(r, 1);
    return p ? p[0] : 0;
}

uint32_t exteria_rd_u32le(exteria_reader *r) {
    const uint8_t *p = exteria_rd_bytes(r, 4);
    return p ? exteria_get_u32le(p) : 0;
}

uint64_t exteria_rd_u64le(exteria_reader *r) {
    const uint8_t *p = exteria_rd_bytes(r, 8);
    return p ? exteria_get_u64le(p) : 0;
}

uint32_t exteria_rd_u32be(exteria_reader *r) {
    const uint8_t *p = exteria_rd_bytes(r, 4);
    return p ? exteria_get_u32be(p) : 0;
}

void exteria_writer_init(exteria_writer *w, size_t max) {
    w->data = NULL;
    w->len = 0;
    w->cap = 0;
    w->max = max;
    w->status = EXTERIA_OK;
}

void exteria_writer_free(exteria_writer *w) {
    free(w->data);
    w->data = NULL;
    w->len = 0;
    w->cap = 0;
}

uint8_t *exteria_writer_take(exteria_writer *w, size_t *len) {
    uint8_t *p = w->data;
    if (len) *len = w->len;
    w->data = NULL;
    w->len = 0;
    w->cap = 0;
    return p;
}

exteria_status exteria_wr_reserve(exteria_writer *w, size_t extra) {
    size_t need, cap;
    uint8_t *grown;
    if (w->status != EXTERIA_OK) return w->status;
    if (extra > w->max - w->len) {
        w->status = EXTERIA_E_LIMIT;
        return w->status;
    }
    need = w->len + extra;
    if (need <= w->cap) return EXTERIA_OK;
    cap = w->cap ? w->cap : 256;
    while (cap < need) {
        if (cap > w->max / 2) {
            cap = w->max;
            break;
        }
        cap *= 2;
    }
    if (cap < need) cap = need;
    grown = (uint8_t *)realloc(w->data, cap);
    if (!grown) {
        w->status = EXTERIA_E_NOMEM;
        return w->status;
    }
    w->data = grown;
    w->cap = cap;
    return EXTERIA_OK;
}

exteria_status exteria_wr_bytes(exteria_writer *w, const void *data, size_t n) {
    exteria_status s;
    if (n == 0) return w->status;
    if (!data) return EXTERIA_E_ARG;
    s = exteria_wr_reserve(w, n);
    if (s != EXTERIA_OK) return s;
    memcpy(w->data + w->len, data, n);
    w->len += n;
    return EXTERIA_OK;
}

exteria_status exteria_wr_zero(exteria_writer *w, size_t n) {
    exteria_status s = exteria_wr_reserve(w, n);
    if (s != EXTERIA_OK) return s;
    if (n) memset(w->data + w->len, 0, n);
    w->len += n;
    return EXTERIA_OK;
}

exteria_status exteria_wr_u8(exteria_writer *w, uint8_t v) {
    return exteria_wr_bytes(w, &v, 1);
}

exteria_status exteria_wr_u32le(exteria_writer *w, uint32_t v) {
    uint8_t b[4];
    exteria_put_u32le(b, v);
    return exteria_wr_bytes(w, b, 4);
}

exteria_status exteria_wr_u64le(exteria_writer *w, uint64_t v) {
    uint8_t b[8];
    exteria_put_u64le(b, v);
    return exteria_wr_bytes(w, b, 8);
}

exteria_status exteria_wr_u32be(exteria_writer *w, uint32_t v) {
    uint8_t b[4];
    exteria_put_u32be(b, v);
    return exteria_wr_bytes(w, b, 4);
}

int exteria_ct_equal(const void *a, const void *b, size_t n) {
    const volatile uint8_t *x = (const volatile uint8_t *)a;
    const volatile uint8_t *y = (const volatile uint8_t *)b;
    uint8_t diff = 0;
    size_t i;
    for (i = 0; i < n; ++i) diff |= (uint8_t)(x[i] ^ y[i]);
    return diff == 0;
}

void exteria_wipe(void *p, size_t n) {
    volatile uint8_t *v = (volatile uint8_t *)p;
    size_t i;
    for (i = 0; i < n; ++i) v[i] = 0;
}
