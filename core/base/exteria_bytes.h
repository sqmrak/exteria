#ifndef EXTERIA_BYTES_H
#define EXTERIA_BYTES_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

typedef struct exteria_slice {
    const uint8_t *data;
    size_t len;
} exteria_slice;

typedef struct exteria_reader {
    const uint8_t *data;
    size_t len;
    size_t pos;
    exteria_status status;
} exteria_reader;

void exteria_reader_init(exteria_reader *r, const uint8_t *data, size_t len);
size_t exteria_reader_left(const exteria_reader *r);
uint8_t exteria_rd_u8(exteria_reader *r);
uint32_t exteria_rd_u32le(exteria_reader *r);
uint64_t exteria_rd_u64le(exteria_reader *r);
uint32_t exteria_rd_u32be(exteria_reader *r);
const uint8_t *exteria_rd_bytes(exteria_reader *r, size_t n);

typedef struct exteria_writer {
    uint8_t *data;
    size_t len;
    size_t cap;
    size_t max;
    exteria_status status;
} exteria_writer;

void exteria_writer_init(exteria_writer *w, size_t max);
void exteria_writer_free(exteria_writer *w);
uint8_t *exteria_writer_take(exteria_writer *w, size_t *len);
exteria_status exteria_wr_reserve(exteria_writer *w, size_t extra);
exteria_status exteria_wr_bytes(exteria_writer *w, const void *data, size_t n);
exteria_status exteria_wr_zero(exteria_writer *w, size_t n);
exteria_status exteria_wr_u8(exteria_writer *w, uint8_t v);
exteria_status exteria_wr_u32le(exteria_writer *w, uint32_t v);
exteria_status exteria_wr_u64le(exteria_writer *w, uint64_t v);
exteria_status exteria_wr_u32be(exteria_writer *w, uint32_t v);

void exteria_put_u32le(uint8_t *out, uint32_t v);
void exteria_put_u64le(uint8_t *out, uint64_t v);
void exteria_put_u32be(uint8_t *out, uint32_t v);
void exteria_put_u64be(uint8_t *out, uint64_t v);
uint32_t exteria_get_u32le(const uint8_t *in);
uint64_t exteria_get_u64le(const uint8_t *in);
uint32_t exteria_get_u32be(const uint8_t *in);
uint64_t exteria_get_u64be(const uint8_t *in);

int exteria_ct_equal(const void *a, const void *b, size_t n);
/* a plain memset on a dead buffer is removed by the optimizer, key material would stay in memory */
void exteria_wipe(void *p, size_t n);

#endif
