#ifndef ZIP_FIXTURE_H
#define ZIP_FIXTURE_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <zlib.h>

/* writes real zip bytes for the tests: the same layout `zip -qrX` makes, with switches that break one thing at a time */

typedef struct fx_entry {
    const char *name;
    const uint8_t *data;
    size_t len;
    int deflate;            /* 1 for deflate, 2 for deflate with stored blocks only */
    uint32_t mode;          /* 0 for 0644 */
    int symlink;
    int bad_crc;
    int encrypted;
    size_t lie_size;        /* when set, the size the headers claim for the data */
    int cut_deflate;        /* drops the last bytes of the deflate stream and keeps the lengths consistent */
} fx_entry;

typedef struct fx_buf { uint8_t *p; size_t len, cap; } fx_buf;

static void fx_put(fx_buf *b, const void *data, size_t n) {
    if (b->len + n > b->cap) {
        b->cap = (b->len + n) * 2 + 64;
        b->p = (uint8_t *)realloc(b->p, b->cap);
    }
    memcpy(b->p + b->len, data, n);
    b->len += n;
}

static void fx_u16(fx_buf *b, uint32_t v) { uint8_t t[2] = {(uint8_t)v, (uint8_t)(v >> 8)}; fx_put(b, t, 2); }
static void fx_u32(fx_buf *b, uint32_t v) { uint8_t t[4] = {(uint8_t)v, (uint8_t)(v >> 8), (uint8_t)(v >> 16), (uint8_t)(v >> 24)}; fx_put(b, t, 4); }

/* the archive as a malloc'd buffer */
static uint8_t *fx_build(const fx_entry *entries, size_t count, size_t *out_len) {
    fx_buf zip = {0}, central = {0};
    size_t i;
    for (i = 0; i < count; ++i) {
        const fx_entry *e = &entries[i];
        size_t name_len = strlen(e->name), packed_len = e->len;
        uint8_t *packed = NULL;
        uint32_t crc = (uint32_t)crc32(0L, e->data ? e->data : (const uint8_t *)"", (uInt)e->len), offset = (uint32_t)zip.len;
        uint32_t claimed = (uint32_t)(e->lie_size ? e->lie_size : e->len);
        uint32_t mode = e->symlink ? 0120777u : (e->mode ? e->mode : 0644u);
        int dir = name_len && e->name[name_len - 1] == '/';
        if (dir) mode = 040755u;
        if (e->deflate && e->len) {
            z_stream z;
            memset(&z, 0, sizeof(z));
            deflateInit2(&z, e->deflate == 2 ? 0 : 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY);
            packed = (uint8_t *)malloc(deflateBound(&z, (uLong)e->len) + 16);
            z.next_in = (Bytef *)e->data;
            z.avail_in = (uInt)e->len;
            z.next_out = packed;
            z.avail_out = (uInt)deflateBound(&z, (uLong)e->len) + 16;
            deflate(&z, Z_FINISH);
            packed_len = z.total_out;
            deflateEnd(&z);
            if (e->cut_deflate && packed_len > 4) packed_len -= 3;
        } else if (e->deflate) {
            static const uint8_t empty_deflate[2] = {0x03, 0x00};
            packed = (uint8_t *)malloc(2);
            memcpy(packed, empty_deflate, 2);
            packed_len = 2;
        } else {
            packed = (uint8_t *)malloc(e->len ? e->len : 1);
            if (e->len) memcpy(packed, e->data, e->len);
        }
        if (e->bad_crc) crc ^= 0x5A5A5A5Au;
        fx_u32(&zip, 0x04034b50u);
        fx_u16(&zip, 20);
        fx_u16(&zip, e->encrypted ? 1u : 0u);
        fx_u16(&zip, e->deflate ? 8u : 0u);
        fx_u32(&zip, 0);
        fx_u32(&zip, crc);
        fx_u32(&zip, (uint32_t)packed_len);
        fx_u32(&zip, claimed);
        fx_u16(&zip, (uint32_t)name_len);
        fx_u16(&zip, 0);
        fx_put(&zip, e->name, name_len);
        fx_put(&zip, packed, packed_len);
        fx_u32(&central, 0x02014b50u);
        fx_u16(&central, 0x0314);
        fx_u16(&central, 20);
        fx_u16(&central, e->encrypted ? 1u : 0u);
        fx_u16(&central, e->deflate ? 8u : 0u);
        fx_u32(&central, 0);
        fx_u32(&central, crc);
        fx_u32(&central, (uint32_t)packed_len);
        fx_u32(&central, claimed);
        fx_u16(&central, (uint32_t)name_len);
        fx_u16(&central, 0);
        fx_u16(&central, 0);
        fx_u16(&central, 0);
        fx_u16(&central, 0);
        fx_u32(&central, mode << 16);
        fx_u32(&central, offset);
        fx_put(&central, e->name, name_len);
        free(packed);
    }
    {
        uint32_t central_offset = (uint32_t)zip.len;
        fx_put(&zip, central.p, central.len);
        fx_u32(&zip, 0x06054b50u);
        fx_u16(&zip, 0);
        fx_u16(&zip, 0);
        fx_u16(&zip, (uint32_t)count);
        fx_u16(&zip, (uint32_t)count);
        fx_u32(&zip, (uint32_t)central.len);
        fx_u32(&zip, central_offset);
        fx_u16(&zip, 0);
    }
    free(central.p);
    *out_len = zip.len;
    return zip.p;
}

static int fx_write(const char *path, const uint8_t *data, size_t len) {
    FILE *f = fopen(path, "wb");
    int ok;
    if (!f) return 0;
    ok = fwrite(data, 1, len, f) == len;
    return fclose(f) == 0 && ok;
}

static int fx_write_zip(const char *path, const fx_entry *entries, size_t count) {
    size_t len = 0;
    uint8_t *zip = fx_build(entries, count, &len);
    int ok = fx_write(path, zip, len);
    free(zip);
    return ok;
}

#endif
