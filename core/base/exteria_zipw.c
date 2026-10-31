#include "exteria_zipw.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_zip.h"

#define ZIPW_ENTRIES_MAX 65534u
#define ZIPW_SIZE_MAX 0xFFFFFFF0u
/* 1980-01-01 00:00, the date every reproducible archive uses when it has no clock of its own */
#define ZIPW_DOS_DATE 0x0021u

struct exteria_zipw {
    FILE *file;
    char *path;
    uint32_t offset;
    uint8_t *dir;
    size_t dir_len;
    size_t dir_cap;
    uint16_t count;
};

static uint32_t crc_table[256];
static int crc_ready;

static uint32_t crc32_of(const uint8_t *data, size_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    size_t i;
    if (!crc_ready) {
        uint32_t n, k;
        for (n = 0; n < 256; ++n) {
            uint32_t c = n;
            for (k = 0; k < 8; ++k) c = (c & 1u) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            crc_table[n] = c;
        }
        crc_ready = 1;
    }
    for (i = 0; i < len; ++i) crc = crc_table[(crc ^ data[i]) & 0xFFu] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

static void put16(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static void put32(uint8_t *p, uint32_t v) {
    put16(p, v);
    put16(p + 2, v >> 16);
}

static int name_valid(const char *name, size_t *len) {
    size_t i;
    if (!name || !name[0]) return 0;
    *len = strlen(name);
    if (*len >= EXTERIA_ZIP_NAME_MAX || name[0] == '/') return 0;
    for (i = 0; i < *len; ++i) {
        if (name[i] == '\\' || (unsigned char)name[i] < 0x20) return 0;
        if (name[i] == '.' && name[i + 1] == '.' && (i == 0 || name[i - 1] == '/') && (name[i + 2] == '/' || name[i + 2] == 0)) return 0;
    }
    return 1;
}

exteria_status exteria_zipw_begin(const char *path, exteria_zipw **out) {
    exteria_zipw *zip;
    FILE *existing;
    if (out) *out = NULL;
    if (!path || !out) return EXTERIA_E_ARG;
    existing = fopen(path, "rb");
    if (existing) {
        fclose(existing);
        return EXTERIA_E_STATE;
    }
    zip = (exteria_zipw *)calloc(1, sizeof(*zip));
    if (!zip) return EXTERIA_E_NOMEM;
    zip->path = (char *)malloc(strlen(path) + 1);
    if (!zip->path) {
        free(zip);
        return EXTERIA_E_NOMEM;
    }
    strcpy(zip->path, path);
    zip->file = fopen(path, "wb");
    if (!zip->file) {
        free(zip->path);
        free(zip);
        return EXTERIA_E_IO;
    }
    *out = zip;
    return EXTERIA_OK;
}

static void release(exteria_zipw *zip, int remove_file) {
    if (zip->file) fclose(zip->file);
    if (remove_file) remove(zip->path);
    free(zip->dir);
    free(zip->path);
    free(zip);
}

void exteria_zipw_abort(exteria_zipw *zip) {
    if (zip) release(zip, 1);
}

static exteria_status dir_append(exteria_zipw *zip, const uint8_t *bytes, size_t len) {
    if (len > SIZE_MAX - zip->dir_len) return EXTERIA_E_LIMIT;
    if (zip->dir_len + len > zip->dir_cap) {
        size_t cap = zip->dir_cap ? zip->dir_cap : 1024;
        uint8_t *grown;
        while (cap < zip->dir_len + len) cap *= 2;
        grown = (uint8_t *)realloc(zip->dir, cap);
        if (!grown) return EXTERIA_E_NOMEM;
        zip->dir = grown;
        zip->dir_cap = cap;
    }
    memcpy(zip->dir + zip->dir_len, bytes, len);
    zip->dir_len += len;
    return EXTERIA_OK;
}

exteria_status exteria_zipw_add(exteria_zipw *zip, const char *name, const uint8_t *data, size_t len, uint32_t mode) {
    uint8_t local[30], central[46];
    size_t name_len;
    uint32_t crc;
    exteria_status status;
    if (!zip || !zip->file || (len && !data) || !name_valid(name, &name_len)) return EXTERIA_E_ARG;
    if (zip->count >= ZIPW_ENTRIES_MAX || len > ZIPW_SIZE_MAX || zip->offset > ZIPW_SIZE_MAX - len - 2 * (name_len + 46u)) return EXTERIA_E_LIMIT;
    crc = crc32_of(data, len);
    memset(local, 0, sizeof(local));
    put32(local, 0x04034B50u);
    put16(local + 4, 20);
    put16(local + 6, 0x0800);   /* names are UTF-8 */
    put16(local + 10, 0);
    put16(local + 12, ZIPW_DOS_DATE);
    put32(local + 14, crc);
    put32(local + 18, (uint32_t)len);
    put32(local + 22, (uint32_t)len);
    put16(local + 26, (uint32_t)name_len);
    memset(central, 0, sizeof(central));
    put32(central, 0x02014B50u);
    put16(central + 4, 0x031E);     /* made by unix, so the permission bits below are read */
    put16(central + 6, 20);
    put16(central + 8, 0x0800);
    put16(central + 14, ZIPW_DOS_DATE);
    put32(central + 16, crc);
    put32(central + 20, (uint32_t)len);
    put32(central + 24, (uint32_t)len);
    put16(central + 28, (uint32_t)name_len);
    put32(central + 38, (0100000u | (mode & 07777u)) << 16);
    put32(central + 42, zip->offset);
    if (fwrite(local, 1, sizeof(local), zip->file) != sizeof(local) || fwrite(name, 1, name_len, zip->file) != name_len ||
        (len && fwrite(data, 1, len, zip->file) != len)) return EXTERIA_E_IO;
    status = dir_append(zip, central, sizeof(central));
    if (status == EXTERIA_OK) status = dir_append(zip, (const uint8_t *)name, name_len);
    if (status != EXTERIA_OK) return status;
    zip->offset += (uint32_t)(sizeof(local) + name_len + len);
    ++zip->count;
    return EXTERIA_OK;
}

exteria_status exteria_zipw_finish(exteria_zipw *zip) {
    uint8_t end[22];
    exteria_status status = EXTERIA_OK;
    if (!zip) return EXTERIA_E_ARG;
    if (zip->dir_len > ZIPW_SIZE_MAX - zip->offset - sizeof(end)) status = EXTERIA_E_LIMIT;
    if (status == EXTERIA_OK) {
        memset(end, 0, sizeof(end));
        put32(end, 0x06054B50u);
        put16(end + 8, zip->count);
        put16(end + 10, zip->count);
        put32(end + 12, (uint32_t)zip->dir_len);
        put32(end + 16, zip->offset);
        if ((zip->dir_len && fwrite(zip->dir, 1, zip->dir_len, zip->file) != zip->dir_len) || fwrite(end, 1, sizeof(end), zip->file) != sizeof(end)) status = EXTERIA_E_IO;
    }
    if (status == EXTERIA_OK && fclose(zip->file) != 0) status = EXTERIA_E_IO;
    zip->file = NULL;
    release(zip, status != EXTERIA_OK);
    return status;
}
