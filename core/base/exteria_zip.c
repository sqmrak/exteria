#include "exteria_zip.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <zlib.h>

#define EOCD_SIGNATURE 0x06054b50u
#define CENTRAL_SIGNATURE 0x02014b50u
#define LOCAL_SIGNATURE 0x04034b50u
#define EOCD_SIZE 22u
#define CENTRAL_SIZE 46u
#define LOCAL_SIZE 30u
#define MAX_COMMENT 65535u
#define MAX_CENTRAL_BYTES (4u * 1024u * 1024u)
#define IO_STEP 16384u

struct exteria_zip {
    int fd;
    uint64_t file_size;
    uint32_t central_offset;
    exteria_zip_entry *entries;
    size_t count;
};

static uint16_t get16(const uint8_t *p) {
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static exteria_status read_at(int fd, uint64_t offset, void *buf, size_t len) {
    uint8_t *out = (uint8_t *)buf;
    while (len > 0) {
        ssize_t got = pread(fd, out, len, (off_t)offset);
        if (got < 0 && errno == EINTR) continue;
        if (got < 0) return EXTERIA_E_IO;
        if (got == 0) return EXTERIA_E_MALFORMED;
        out += got;
        offset += (uint64_t)got;
        len -= (size_t)got;
    }
    return EXTERIA_OK;
}

/* a name that stays inside the folder it is extracted to: no root, no parent step, no empty part, no control byte or backslash */
static int name_is_safe(const char *name, size_t len) {
    size_t i, part = 0;
    if (len == 0 || len >= EXTERIA_ZIP_NAME_MAX || name[0] == '/') return 0;
    for (i = 0; i < len; ++i) {
        unsigned char c = (unsigned char)name[i];
        if (c < 0x20 || c == 0x7F || c == '\\') return 0;
        if (c == '/') {
            if (part == 0) return 0;
            part = 0;
            continue;
        }
        ++part;
    }
    for (i = 0; i < len;) {
        size_t end = i;
        while (end < len && name[end] != '/') ++end;
        if ((end - i == 1 && name[i] == '.') || (end - i == 2 && name[i] == '.' && name[i + 1] == '.')) return 0;
        i = end + 1;
    }
    return 1;
}

static int compare_names(const void *a, const void *b) {
    return strcmp((*(const exteria_zip_entry *const *)a)->name, (*(const exteria_zip_entry *const *)b)->name);
}

static exteria_status find_eocd(int fd, uint64_t file_size, uint8_t eocd[EOCD_SIZE]) {
    uint8_t *tail;
    size_t want = file_size < EOCD_SIZE + MAX_COMMENT ? (size_t)file_size : EOCD_SIZE + MAX_COMMENT, i;
    exteria_status status;
    if (file_size < EOCD_SIZE) return EXTERIA_E_MALFORMED;
    tail = (uint8_t *)malloc(want);
    if (!tail) return EXTERIA_E_NOMEM;
    status = read_at(fd, file_size - want, tail, want);
    if (status != EXTERIA_OK) {
        free(tail);
        return status;
    }
    status = EXTERIA_E_MALFORMED;
    for (i = want - EOCD_SIZE + 1; i-- > 0;) {
        if (get32(tail + i) == EOCD_SIGNATURE && i + EOCD_SIZE + get16(tail + i + 20) == want) {
            memcpy(eocd, tail + i, EOCD_SIZE);
            status = EXTERIA_OK;
            break;
        }
    }
    free(tail);
    return status;
}

exteria_status exteria_zip_open(const char *path, exteria_zip **out) {
    exteria_zip *zip;
    uint8_t eocd[EOCD_SIZE], *central = NULL;
    const exteria_zip_entry **order = NULL;
    uint32_t central_size, central_offset, total = 0;
    size_t entries, pos = 0, i;
    struct stat st;
    exteria_status status;
    if (out) *out = NULL;
    if (!path || !out) return EXTERIA_E_ARG;
    zip = (exteria_zip *)calloc(1, sizeof(*zip));
    if (!zip) return EXTERIA_E_NOMEM;
    zip->fd = open(path, O_RDONLY);
    if (zip->fd < 0) {
        free(zip);
        return errno == ENOENT ? EXTERIA_E_NOTFOUND : EXTERIA_E_IO;
    }
    if (fstat(zip->fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0 || (uint64_t)st.st_size > 0xFFFFFFFFu) {
        status = EXTERIA_E_MALFORMED;
        goto fail;
    }
    zip->file_size = (uint64_t)st.st_size;
    status = find_eocd(zip->fd, zip->file_size, eocd);
    if (status != EXTERIA_OK) goto fail;
    entries = get16(eocd + 10);
    central_size = get32(eocd + 12);
    central_offset = get32(eocd + 16);
    /* a split archive, or the 0xFFFF and 0xFFFFFFFF markers of zip64, is a valid file this reader does not take */
    if (get16(eocd + 4) != 0 || get16(eocd + 6) != 0 || get16(eocd + 8) != entries || entries == 0xFFFFu || central_size == 0xFFFFFFFFu ||
        central_offset == 0xFFFFFFFFu) {
        status = EXTERIA_E_UNSUPPORTED;
        goto fail;
    }
    if (entries == 0 || entries > EXTERIA_ZIP_MAX_ENTRIES || central_size > MAX_CENTRAL_BYTES || (uint64_t)central_offset + central_size > zip->file_size - EOCD_SIZE) {
        status = EXTERIA_E_MALFORMED;
        goto fail;
    }
    central = (uint8_t *)malloc(central_size ? central_size : 1);
    zip->entries = (exteria_zip_entry *)calloc(entries, sizeof(*zip->entries));
    order = (const exteria_zip_entry **)malloc(entries * sizeof(*order));
    if (!central || !zip->entries || !order) {
        status = EXTERIA_E_NOMEM;
        goto fail;
    }
    status = read_at(zip->fd, central_offset, central, central_size);
    if (status != EXTERIA_OK) goto fail;
    zip->central_offset = central_offset;
    for (i = 0; i < entries; ++i) {
        const uint8_t *h = central + pos;
        exteria_zip_entry *e = &zip->entries[i];
        size_t name_len, extra_len, comment_len;
        uint16_t flags, method;
        uint32_t attrs;
        if (central_size - pos < CENTRAL_SIZE || get32(h) != CENTRAL_SIGNATURE) {
            status = EXTERIA_E_MALFORMED;
            goto fail;
        }
        flags = get16(h + 8);
        method = get16(h + 10);
        name_len = get16(h + 28);
        extra_len = get16(h + 30);
        comment_len = get16(h + 32);
        attrs = get32(h + 38);
        if (central_size - pos - CENTRAL_SIZE < name_len + extra_len + comment_len || !name_is_safe((const char *)h + CENTRAL_SIZE, name_len)) {
            status = EXTERIA_E_MALFORMED;
            goto fail;
        }
        memcpy(e->name, h + CENTRAL_SIZE, name_len);
        e->crc32 = get32(h + 16);
        e->packed = get32(h + 20);
        e->size = get32(h + 24);
        e->offset = get32(h + 42);
        e->is_dir = e->name[name_len - 1] == '/';
        e->mode = 0644;
        if ((flags & 1u) || (flags & 0x40u)) {
            status = EXTERIA_E_UNSUPPORTED;
            goto fail;
        }
        if (e->packed == 0xFFFFFFFFu || e->size == 0xFFFFFFFFu || e->offset == 0xFFFFFFFFu) {
            status = EXTERIA_E_UNSUPPORTED;
            goto fail;
        }
        /* made by unix: the upper half of the external attributes is st_mode, and a link would be written as its target text */
        if ((get16(h + 4) >> 8) == 3) {
            uint32_t unix_mode = attrs >> 16;
            if ((unix_mode & 0170000u) == 0120000u) {
                status = EXTERIA_E_UNSUPPORTED;
                goto fail;
            }
            if (unix_mode & 0777u) e->mode = unix_mode & 0777u;
        }
        if (method == 8) e->deflated = 1;
        else if (method != 0) {
            status = EXTERIA_E_UNSUPPORTED;
            goto fail;
        }
        if (e->is_dir ? (e->size != 0 || e->packed > 2) : (e->size > EXTERIA_ZIP_MAX_ENTRY_SIZE || (!e->deflated && e->packed != e->size) ||
                                                           (uint64_t)e->offset + LOCAL_SIZE > zip->central_offset)) {
            status = e->is_dir ? EXTERIA_E_MALFORMED : EXTERIA_E_LIMIT;
            goto fail;
        }
        if (!e->is_dir) {
            if (total + e->size < total || total + e->size > EXTERIA_ZIP_MAX_TOTAL_SIZE) {
                status = EXTERIA_E_LIMIT;
                goto fail;
            }
            total += e->size;
        }
        order[i] = e;
        pos += CENTRAL_SIZE + name_len + extra_len + comment_len;
    }
    zip->count = entries;
    /* the same name twice would let a later entry replace a checked one */
    qsort((void *)order, entries, sizeof(*order), compare_names);
    for (i = 1; i < entries; ++i) {
        if (!strcmp(order[i - 1]->name, order[i]->name)) {
            status = EXTERIA_E_MALFORMED;
            goto fail;
        }
    }
    free(order);
    free(central);
    *out = zip;
    return EXTERIA_OK;
fail:
    free(order);
    free(central);
    exteria_zip_close(zip);
    return status;
}

void exteria_zip_close(exteria_zip *zip) {
    if (!zip) return;
    if (zip->fd >= 0) close(zip->fd);
    free(zip->entries);
    free(zip);
}

size_t exteria_zip_count(const exteria_zip *zip) {
    return zip ? zip->count : 0;
}

const exteria_zip_entry *exteria_zip_entry_at(const exteria_zip *zip, size_t index) {
    return zip && index < zip->count ? &zip->entries[index] : NULL;
}

static exteria_status write_all(int fd, const uint8_t *data, size_t len) {
    while (len > 0) {
        ssize_t put = write(fd, data, len);
        if (put < 0 && errno == EINTR) continue;
        if (put <= 0) return errno == ENOSPC || errno == EDQUOT ? EXTERIA_E_STORAGE : EXTERIA_E_IO;
        data += put;
        len -= (size_t)put;
    }
    return EXTERIA_OK;
}

/* the byte offset of the entry's data, after its local header, which has its own name and extra lengths */
static exteria_status data_offset(const exteria_zip *zip, const exteria_zip_entry *e, uint64_t *offset) {
    uint8_t h[LOCAL_SIZE];
    exteria_status status = read_at(zip->fd, e->offset, h, sizeof(h));
    uint64_t start;
    if (status != EXTERIA_OK) return status;
    if (get32(h) != LOCAL_SIGNATURE || (get16(h + 6) & 1u)) return EXTERIA_E_MALFORMED;
    start = (uint64_t)e->offset + LOCAL_SIZE + get16(h + 26) + get16(h + 28);
    if (start + e->packed > zip->central_offset) return EXTERIA_E_MALFORMED;
    *offset = start;
    return EXTERIA_OK;
}

exteria_status exteria_zip_extract(const exteria_zip *zip, const exteria_zip_entry *entry, const char *dest, exteria_zip_progress progress, void *ctx) {
    uint8_t in[IO_STEP], out[IO_STEP];
    uint64_t offset = 0;
    uint32_t packed_left, written = 0, crc = (uint32_t)crc32(0L, Z_NULL, 0);
    z_stream z;
    int fd, inflating = 0;
    exteria_status status;
    if (!zip || !entry || !dest || entry->is_dir) return EXTERIA_E_ARG;
    status = data_offset(zip, entry, &offset);
    if (status != EXTERIA_OK) return status;
    fd = open(dest, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) return errno == EEXIST ? EXTERIA_E_STATE : EXTERIA_E_IO;
    memset(&z, 0, sizeof(z));
    if (entry->deflated) {
        if (inflateInit2(&z, -MAX_WBITS) != Z_OK) {
            status = EXTERIA_E_CRYPTO;
            goto fail;
        }
        inflating = 1;
    }
    packed_left = entry->packed;
    do {
        size_t take = packed_left < sizeof(in) ? packed_left : sizeof(in);
        int ended = 0;
        if (take > 0) {
            status = read_at(zip->fd, offset, in, take);
            if (status != EXTERIA_OK) goto fail;
            offset += take;
            packed_left -= (uint32_t)take;
        }
        if (!entry->deflated) {
            crc = (uint32_t)crc32(crc, in, (uInt)take);
            written += (uint32_t)take;
            status = write_all(fd, in, take);
            if (status != EXTERIA_OK) goto fail;
            if (progress && (status = progress(ctx, written)) != EXTERIA_OK) goto fail;
            continue;
        }
        z.next_in = in;
        z.avail_in = (uInt)take;
        do {
            size_t produced;
            int rc;
            z.next_out = out;
            z.avail_out = sizeof(out);
            rc = inflate(&z, Z_NO_FLUSH);
            /* the previous call may have spent the input and filled the output together; with nothing left to read, zlib's Z_BUF_ERROR only
               says the stream wants the next chunk. A stream that really is cut short is caught after the loop */
            if (rc == Z_BUF_ERROR && z.avail_in == 0) break;
            if (rc != Z_OK && rc != Z_STREAM_END) {
                status = EXTERIA_E_MALFORMED;
                goto fail;
            }
            produced = sizeof(out) - z.avail_out;
            /* the stated size is a hard bound: an entry that inflates past it is a bomb or a lie */
            if (produced > entry->size - written) {
                status = EXTERIA_E_MALFORMED;
                goto fail;
            }
            crc = (uint32_t)crc32(crc, out, (uInt)produced);
            written += (uint32_t)produced;
            status = write_all(fd, out, produced);
            if (status != EXTERIA_OK) goto fail;
            if (progress && (status = progress(ctx, written)) != EXTERIA_OK) goto fail;
            if (rc == Z_STREAM_END) {
                ended = 1;
                break;
            }
            if (produced == 0 && z.avail_in == 0) break;
        } while (z.avail_in > 0 || z.avail_out == 0);
        if (ended) {
            if (z.avail_in != 0 || packed_left != 0) {
                status = EXTERIA_E_MALFORMED;
                goto fail;
            }
            break;
        }
    } while (packed_left > 0);
    if (entry->deflated && packed_left == 0) {
        /* input spent without the end marker of the stream is a cut entry */
        int rc;
        z.next_in = in;
        z.avail_in = 0;
        z.next_out = out;
        z.avail_out = sizeof(out);
        rc = inflate(&z, Z_FINISH);
        if (rc != Z_STREAM_END || z.avail_out != sizeof(out)) {
            status = EXTERIA_E_MALFORMED;
            goto fail;
        }
    }
    if (written != entry->size || crc != entry->crc32) {
        status = EXTERIA_E_MALFORMED;
        goto fail;
    }
    if (inflating) inflateEnd(&z);
    if (fsync(fd) != 0 || close(fd) != 0) {
        unlink(dest);
        return EXTERIA_E_IO;
    }
    return EXTERIA_OK;
fail:
    if (inflating) inflateEnd(&z);
    close(fd);
    unlink(dest);
    return status;
}

exteria_status exteria_zip_entry_matches(const exteria_zip_entry *entry, const char *path, int *same) {
    uint8_t buf[IO_STEP];
    struct stat st;
    uint32_t crc = (uint32_t)crc32(0L, Z_NULL, 0);
    int fd;
    if (same) *same = 0;
    if (!entry || !path || !same || entry->is_dir) return EXTERIA_E_ARG;
    if (stat(path, &st) != 0) return errno == ENOENT || errno == ENOTDIR ? EXTERIA_OK : EXTERIA_E_IO;
    if (!S_ISREG(st.st_mode) || st.st_size < 0 || (uint64_t)st.st_size != entry->size) return EXTERIA_OK;
    fd = open(path, O_RDONLY);
    if (fd < 0) return EXTERIA_E_IO;
    for (;;) {
        ssize_t got = read(fd, buf, sizeof(buf));
        if (got < 0 && errno == EINTR) continue;
        if (got < 0) {
            close(fd);
            return EXTERIA_E_IO;
        }
        if (got == 0) break;
        crc = (uint32_t)crc32(crc, buf, (uInt)got);
    }
    close(fd);
    *same = crc == entry->crc32;
    return EXTERIA_OK;
}
