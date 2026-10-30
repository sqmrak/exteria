#include "exteria_mt_files.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "exteria_random.h"
#include "exteria_tl_ids.h"

#define FILE_SIZE_MAX UINT64_C(34359738368)
#define DOWNLOAD_PART (128u * 1024u)
#define FILE_RETRY_WAIT_MAX_SECONDS 300

uint64_t exteria_file_temporary_token(void) {
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static uint64_t counter;
    uint64_t result;
    pthread_mutex_lock(&lock);
    if (++counter == 0) ++counter;
    result = counter;
    pthread_mutex_unlock(&lock);
    return result;
}

exteria_status exteria_file_download_part(uint64_t offset, uint32_t preferred, uint32_t *limit) {
    if (limit) *limit = 0;
    if (!limit || offset > INT64_MAX || offset % 4096 || !preferred || preferred > EXTERIA_FILE_RANGE_MAX ||
        preferred % 4096 || EXTERIA_FILE_RANGE_MAX % preferred) return EXTERIA_E_ARG;
    while ((offset % EXTERIA_FILE_RANGE_MAX) + preferred > EXTERIA_FILE_RANGE_MAX) preferred /= 2;
    *limit = preferred;
    return EXTERIA_OK;
}

int exteria_file_retry_delay(const char *error_name, uint32_t retries, uint32_t *delay_ms) {
    char name[128];
    int32_t seconds;
    if (delay_ms) *delay_ms = 0;
    if (!error_name || !delay_ms || retries >= EXTERIA_FILE_RETRIES_MAX) return 0;
    if (!strcmp(error_name, "TIMEOUT") || !strcmp(error_name, "OFFLINE")) {
        *delay_ms = 1000u << retries;
        return 1;
    }
    exteria_mt_rpc_error_split(error_name, name, sizeof(name), &seconds);
    if ((strcmp(name, "FLOOD_WAIT") && strcmp(name, "FLOOD_PREMIUM_WAIT")) || seconds <= 0 || seconds > FILE_RETRY_WAIT_MAX_SECONDS) return 0;
    *delay_ms = (uint32_t)seconds * 1000u;
    return 1;
}

exteria_status exteria_file_download_advance(uint64_t offset, uint64_t size, size_t received,
                                           uint32_t requested, uint64_t capacity,
                                           uint64_t *next, int *complete) {
    uint64_t end;
    if (next) *next = 0;
    if (complete) *complete = 0;
    if (!next || !complete || !requested || !capacity) return EXTERIA_E_ARG;
    if (size > capacity || offset > capacity || received > capacity - offset) return EXTERIA_E_LIMIT;
    if (received > requested || (size && (offset > size || received > size - offset))) return EXTERIA_E_MALFORMED;
    end = offset + received;
    if (size && end < size && !received) return EXTERIA_E_TRUNCATED;
    *next = end;
    *complete = size ? end == size : received < requested;
    return EXTERIA_OK;
}

static void initialize(exteria_file_transfer *t) {
    memset(t, 0, sizeof(*t));
    t->fd = -1;
    exteria_writer_init(&t->location, 65536);
    exteria_writer_init(&t->chunk, EXTERIA_FILE_RANGE_MAX);
}

static exteria_status file_read(int fd, uint8_t *out, size_t n, uint64_t offset) {
    while (n) {
        ssize_t got = pread(fd, out, n, (off_t)offset);
        if (got < 0) { if (errno == EINTR) continue; return EXTERIA_E_IO; }
        if (!got) return EXTERIA_E_TRUNCATED;
        out += got;
        offset += (uint64_t)got;
        n -= (size_t)got;
    }
    return EXTERIA_OK;
}

static exteria_status file_write(int fd, const uint8_t *in, size_t n, uint64_t offset) {
    while (n) {
        ssize_t wrote = pwrite(fd, in, n, (off_t)offset);
        if (wrote < 0) { if (errno == EINTR) continue; return EXTERIA_E_IO; }
        if (!wrote) return EXTERIA_E_IO;
        in += wrote;
        offset += (uint64_t)wrote;
        n -= (size_t)wrote;
    }
    return EXTERIA_OK;
}

exteria_status exteria_file_upload(exteria_file_transfer *t, int fd, const char *name, int32_t dc,
                                  uint32_t part_size, uint32_t max_parts) {
    struct stat st;
    exteria_status status;
    uint64_t parts;
    if (!t) return EXTERIA_E_ARG;
    initialize(t);
    if (fd < 0 || !name || !*name || strlen(name) >= sizeof(t->name) || strchr(name, '/') ||
        dc <= 0 || !part_size || part_size % 1024 || part_size > EXTERIA_FILE_PART_MAX ||
        EXTERIA_FILE_PART_MAX % part_size || !max_parts || max_parts > 65536) return EXTERIA_E_ARG;
    if (fstat(fd, &st) < 0 || !S_ISREG(st.st_mode) || st.st_size <= 0 || (uint64_t)st.st_size > FILE_SIZE_MAX) return EXTERIA_E_IO;
    t->size = (uint64_t)st.st_size;
    parts = (t->size + part_size - 1u) / part_size;
    if (parts > max_parts) return EXTERIA_E_LIMIT;
    t->fd = dup(fd);
    if (t->fd < 0) return EXTERIA_E_IO;
    if (fcntl(t->fd, F_SETFD, FD_CLOEXEC) < 0) { close(t->fd); t->fd = -1; return EXTERIA_E_IO; }
    t->upload = 1;
    t->big = t->size > 10u * 1024u * 1024u;
    t->dc = dc;
    t->part_size = part_size;
    t->parts = (uint32_t)parts;
    memcpy(t->name, name, strlen(name) + 1);
    status = exteria_random_u64(&t->id);
    if (status != EXTERIA_OK || !t->id) { exteria_file_close(t); return status == EXTERIA_OK ? EXTERIA_E_CRYPTO : status; }
    if (!t->big) {
        t->md5 = exteria_digest_new(0);
        if (!t->md5) { exteria_file_close(t); return EXTERIA_E_CRYPTO; }
    }
    return EXTERIA_OK;
}

exteria_status exteria_file_download(exteria_file_transfer *t, const char *temporary,
                                    const exteria_tl_value *location, int32_t dc,
                                    uint64_t size, uint64_t verified_offset) {
    struct stat st;
    exteria_status status;
    int flags;
    if (!t) return EXTERIA_E_ARG;
    initialize(t);
    if (!temporary || !*temporary || strlen(temporary) >= sizeof(t->temporary) || !location || dc <= 0 ||
        !size || size > FILE_SIZE_MAX || verified_offset > size || (verified_offset != size && verified_offset % 4096)) return EXTERIA_E_ARG;
    status = exteria_tl_encode(location, &t->location, NULL);
    if (status != EXTERIA_OK) return status;
    flags = O_RDWR | O_NOFOLLOW;
    if (!verified_offset) flags |= O_CREAT | O_EXCL;
    t->fd = open(temporary, flags, 0600);
    if (t->fd < 0) { exteria_file_close(t); return EXTERIA_E_IO; }
    if (fcntl(t->fd, F_SETFD, FD_CLOEXEC) < 0 || fstat(t->fd, &st) < 0 || !S_ISREG(st.st_mode) ||
        st.st_nlink != 1 || st.st_size < 0 || (uint64_t)st.st_size < verified_offset ||
        ftruncate(t->fd, (off_t)verified_offset) < 0) {
        exteria_file_close(t);
        return EXTERIA_E_IO;
    }
    memcpy(t->temporary, temporary, strlen(temporary) + 1);
    t->size = size;
    t->offset = verified_offset;
    t->dc = dc;
    t->part_size = DOWNLOAD_PART;
    if (verified_offset == size) t->state = EXTERIA_FILE_DONE;
    return EXTERIA_OK;
}

static exteria_file_hash *current_hash(exteria_file_transfer *t) {
    uint32_t i;
    for (i = 0; i < t->hash_count; ++i) if (t->hashes[i].offset == t->offset) return &t->hashes[i];
    return NULL;
}

static exteria_status read_location(exteria_file_transfer *t, exteria_arena *arena, exteria_tl_value **out) {
    return exteria_tl_decode_all(arena, NULL, EXTERIA_TL_REF_ANY, t->location.data, t->location.len, out);
}

exteria_status exteria_file_next(exteria_file_transfer *t, uint64_t time_ms, exteria_arena *arena,
                                exteria_tl_value **request, uint64_t *id, int32_t *dc, int *cdn) {
    exteria_tl_value *v = NULL, *location;
    exteria_status status = EXTERIA_OK;
    exteria_file_hash *hash;
    uint64_t offset;
    uint32_t limit;
    if (!request || !id || !dc || !cdn) return EXTERIA_E_ARG;
    *request = NULL; *id = 0; *dc = 0; *cdn = 0;
    if (!t || !arena || t->fd < 0 || t->pending) return EXTERIA_E_STATE;
    if (t->state == EXTERIA_FILE_WAIT && time_ms >= t->wait_until) t->state = EXTERIA_FILE_ACTIVE;
    if (t->state == EXTERIA_FILE_WAIT) return EXTERIA_E_RETRY;
    if (t->state != EXTERIA_FILE_ACTIVE) return EXTERIA_E_STATE;
    *dc = t->dc;
    if (t->upload) {
        uint64_t left = t->size - t->offset;
        limit = left < t->part_size ? (uint32_t)left : t->part_size;
        t->chunk.len = 0;
        status = exteria_wr_zero(&t->chunk, limit);
        if (status == EXTERIA_OK) status = file_read(t->fd, t->chunk.data, limit, t->offset);
        v = exteria_tl_new_obj(arena, t->big ? "upload.saveBigFilePart" : "upload.saveFilePart");
        if (status == EXTERIA_OK) status = v ? exteria_tl_set_i64(arena, v, "file_id", (int64_t)t->id) : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, v, "file_part", (int32_t)(t->offset / t->part_size));
        if (status == EXTERIA_OK && t->big) status = exteria_tl_set_i32(arena, v, "file_total_parts", (int32_t)t->parts);
        if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, v, "bytes", t->chunk.data, limit);
        t->requested = limit;
    } else if (t->request_token_len) {
        v = exteria_tl_new_obj(arena, "upload.reuploadCdnFile");
        status = v ? exteria_tl_set_bytes(arena, v, "file_token", t->token, t->token_len) : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, v, "request_token", t->request_token, t->request_token_len);
    } else if (!(hash = current_hash(t))) {
        v = exteria_tl_new_obj(arena, t->cdn ? "upload.getCdnFileHashes" : "upload.getFileHashes");
        status = v ? EXTERIA_OK : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK && t->cdn) status = exteria_tl_set_bytes(arena, v, "file_token", t->token, t->token_len);
        if (status == EXTERIA_OK && !t->cdn) {
            status = read_location(t, arena, &location);
            if (status == EXTERIA_OK) status = exteria_tl_set(v, "location", location);
        }
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, v, "offset", (int64_t)t->offset);
    } else {
        offset = t->offset + t->chunk.len;
        status = exteria_file_download_part(offset, t->part_size, &limit);
        if (status != EXTERIA_OK) return status;
        if (hash->limit - t->chunk.len < limit) {
            uint64_t range_left = hash->limit - t->chunk.len;
            if (offset + range_left != t->size) while (limit > range_left && limit > 4096) limit /= 2;
        }
        if (t->cdn) { *dc = t->cdn_dc; *cdn = 1; }
        v = exteria_tl_new_obj(arena, t->cdn ? "upload.getCdnFile" : "upload.getFile");
        status = v ? EXTERIA_OK : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK && t->cdn) status = exteria_tl_set_bytes(arena, v, "file_token", t->token, t->token_len);
        if (status == EXTERIA_OK && !t->cdn) {
            status = read_location(t, arena, &location);
            if (status == EXTERIA_OK) status = exteria_tl_set(v, "location", location);
            if (status == EXTERIA_OK && !t->cdn_disabled) status = exteria_tl_set_flag(v, "cdn_supported");
        }
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, v, "offset", (int64_t)offset);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, v, "limit", (int32_t)limit);
        t->requested = limit;
    }
    if (status != EXTERIA_OK) return status;
    *request = v;
    t->pending = ++t->generation;
    if (!t->pending) t->pending = ++t->generation;
    *id = t->pending;
    t->method = exteria_tl_id(v);
    return EXTERIA_OK;
}

static exteria_status accept_hashes(exteria_file_transfer *t, const exteria_tl_value *vec) {
    exteria_file_hash hashes[EXTERIA_FILE_HASH_MAX];
    uint32_t i, count = 0;
    if (!vec || vec->kind != EXTERIA_TL_V_VEC || !vec->u.vec.count || vec->u.vec.count > EXTERIA_FILE_HASH_MAX) return EXTERIA_E_MALFORMED;
    for (i = 0; i < vec->u.vec.count; ++i) {
        const exteria_tl_value *v = vec->u.vec.items[i];
        const uint8_t *hash;
        size_t len;
        int64_t offset;
        int32_t limit;
        uint64_t effective;
        if (exteria_tl_get_i64(v, "offset", &offset) != EXTERIA_OK || offset < 0 || (uint64_t)offset >= t->size ||
            exteria_tl_get_i32(v, "limit", &limit) != EXTERIA_OK || limit <= 0 || (uint32_t)limit > EXTERIA_FILE_RANGE_MAX ||
            exteria_tl_get_bytes(v, "hash", &hash, &len) != EXTERIA_OK || len != 32) return EXTERIA_E_MALFORMED;
        effective = (uint32_t)limit;
        if (effective > t->size - (uint64_t)offset) effective = t->size - (uint64_t)offset;
        if (((uint64_t)offset % 4096) || ((uint64_t)offset + effective < t->size && effective % 4096)) return EXTERIA_E_MALFORMED;
        hashes[count].offset = (uint64_t)offset;
        hashes[count].limit = (uint32_t)effective;
        memcpy(hashes[count].hash, hash, 32);
        ++count;
    }
    for (i = 0; i < count; ++i) {
        uint32_t j;
        for (j = 0; j < i; ++j) if (hashes[i].offset < hashes[j].offset + hashes[j].limit &&
            hashes[j].offset < hashes[i].offset + hashes[i].limit) return EXTERIA_E_SECURITY;
    }
    memcpy(t->hashes, hashes, count * sizeof(hashes[0]));
    t->hash_count = count;
    return current_hash(t) ? EXTERIA_OK : EXTERIA_E_MALFORMED;
}

static exteria_status redirect(exteria_file_transfer *t, const exteria_tl_value *v) {
    const uint8_t *key, *iv, *token;
    size_t key_len, iv_len, token_len;
    int32_t dc;
    exteria_status status;
    if (++t->redirects > 3 || t->cdn_disabled) return EXTERIA_E_LIMIT;
    if (exteria_tl_get_i32(v, "dc_id", &dc) != EXTERIA_OK || dc <= 0 ||
        exteria_tl_get_bytes(v, "encryption_key", &key, &key_len) != EXTERIA_OK || key_len != 32 ||
        exteria_tl_get_bytes(v, "encryption_iv", &iv, &iv_len) != EXTERIA_OK || iv_len != 16 ||
        exteria_tl_get_bytes(v, "file_token", &token, &token_len) != EXTERIA_OK || !token_len || token_len > sizeof(t->token)) return EXTERIA_E_MALFORMED;
    status = accept_hashes(t, exteria_tl_get(v, "file_hashes"));
    if (status != EXTERIA_OK) return status;
    memcpy(t->cdn_key, key, 32); memcpy(t->cdn_iv, iv, 16); memcpy(t->token, token, token_len);
    t->token_len = token_len;
    t->cdn_dc = dc;
    t->cdn = 1;
    t->chunk.len = 0;
    return EXTERIA_OK;
}

static exteria_status receive_chunk(exteria_file_transfer *t, const uint8_t *bytes, size_t len) {
    exteria_file_hash *hash = current_hash(t);
    uint8_t digest[32], iv[16];
    size_t mark = t->chunk.len;
    uint64_t next;
    int complete;
    exteria_status status;
    if (!hash || !len || mark > hash->limit || len > hash->limit - mark)
        return EXTERIA_E_MALFORMED;
    status = exteria_file_download_advance(t->offset + mark, t->size, len, t->requested, FILE_SIZE_MAX, &next, &complete);
    if (status != EXTERIA_OK) return status;
    status = exteria_wr_bytes(&t->chunk, bytes, len);
    if (status != EXTERIA_OK) return status;
    if (t->cdn) {
        exteria_aes_ctr *ctr;
        uint64_t counter = (t->offset + mark) / 16u;
        if (counter > UINT32_MAX) return EXTERIA_E_LIMIT;
        memcpy(iv, t->cdn_iv, 16);
        exteria_put_u32be(iv + 12, (uint32_t)counter);
        ctr = exteria_aes_ctr_new(t->cdn_key, iv);
        if (!ctr) return EXTERIA_E_CRYPTO;
        status = exteria_aes_ctr_apply(ctr, t->chunk.data + mark, t->chunk.data + mark, len);
        exteria_aes_ctr_free(ctr);
        if (status != EXTERIA_OK) return status;
    }
    if (t->chunk.len < hash->limit) return EXTERIA_OK;
    status = exteria_sha256_one(t->chunk.data, t->chunk.len, digest);
    if (status == EXTERIA_OK && !exteria_ct_equal(digest, hash->hash, 32)) status = EXTERIA_E_SECURITY;
    if (status == EXTERIA_OK) status = file_write(t->fd, t->chunk.data, t->chunk.len, t->offset);
    if (status == EXTERIA_OK && fsync(t->fd) != 0) status = EXTERIA_E_IO;
    if (status == EXTERIA_OK) {
        t->offset = next;
        t->chunk.len = 0;
        if (complete) t->state = EXTERIA_FILE_DONE;
    }
    return status;
}

exteria_status exteria_file_result(exteria_file_transfer *t, uint64_t id, int32_t dc, int cdn,
                                  uint64_t time_ms, const exteria_mt_rpc_result *r) {
    exteria_status status;
    int expected_cdn;
    int32_t expected_dc;
    if (!t || !r) return EXTERIA_E_ARG;
    if (!id || id != t->pending || t->state != EXTERIA_FILE_ACTIVE) return EXTERIA_E_NOTFOUND;
    expected_cdn = t->method == EXTERIA_TL_ID_upload_getCdnFile;
    expected_dc = expected_cdn ? t->cdn_dc : t->dc;
    if (cdn != expected_cdn || dc != expected_dc) return EXTERIA_E_SECURITY;
    t->pending = 0;
    if (r->status != EXTERIA_OK) {
        char name[128];
        int32_t number;
        exteria_mt_rpc_error_split(r->error_text, name, sizeof(name), &number);
        if (++t->attempts > EXTERIA_FILE_RETRIES_MAX) { t->state = EXTERIA_FILE_FAILED; return EXTERIA_E_LIMIT; }
        if (r->status == EXTERIA_E_RPC && (!strcmp(name, "FLOOD_WAIT") || !strcmp(name, "FLOOD_PREMIUM_WAIT")) && number > 0) {
            t->wait_until = time_ms + (uint64_t)number * 1000u;
            t->state = EXTERIA_FILE_WAIT;
            return EXTERIA_E_RETRY;
        }
        if (r->status == EXTERIA_E_RPC && !strcmp(name, "FILE_MIGRATE") && number > 0 && !cdn) {
            t->dc = number;
            return EXTERIA_E_RETRY;
        }
        if (r->status == EXTERIA_E_RPC && (!strcmp(name, "FILE_REFERENCE_EXPIRED") || !strcmp(name, "FILE_REFERENCE_EMPTY"))) {
            t->state = EXTERIA_FILE_REFRESH;
            return EXTERIA_E_RETRY;
        }
        if (r->status == EXTERIA_E_RPC && t->cdn && (!strcmp(name, "FILE_TOKEN_INVALID") || !strcmp(name, "REQUEST_TOKEN_INVALID"))) {
            t->cdn = 0;
            t->cdn_disabled = 1;
            t->chunk.len = 0;
            t->hash_count = 0;
            t->request_token_len = 0;
            exteria_wipe(t->cdn_key, 32);
            return EXTERIA_E_RETRY;
        }
        if (r->status == EXTERIA_E_TIMEOUT || r->status == EXTERIA_E_IO || r->status == EXTERIA_E_RETRY) return EXTERIA_E_RETRY;
        t->state = EXTERIA_FILE_FAILED;
        return r->status;
    }
    if (t->upload) {
        if (!exteria_tl_is(r->value, EXTERIA_TL_ID_boolTrue)) status = EXTERIA_E_RPC;
        else {
            status = t->big ? EXTERIA_OK : exteria_digest_update(t->md5, t->chunk.data, t->chunk.len);
            if (status == EXTERIA_OK) {
                t->offset += t->chunk.len;
                t->chunk.len = 0;
                if (t->offset == t->size) {
                    status = t->big ? EXTERIA_OK : exteria_digest_finish(t->md5, t->md5_sum, sizeof(t->md5_sum));
                    if (status == EXTERIA_OK) t->state = EXTERIA_FILE_DONE;
                }
            }
        }
    } else if (t->method == EXTERIA_TL_ID_upload_getFileHashes || t->method == EXTERIA_TL_ID_upload_getCdnFileHashes ||
               t->method == EXTERIA_TL_ID_upload_reuploadCdnFile) {
        status = accept_hashes(t, r->value);
        if (status == EXTERIA_OK) t->request_token_len = 0;
    } else if (!cdn && exteria_tl_is(r->value, EXTERIA_TL_ID_upload_fileCdnRedirect)) status = redirect(t, r->value);
    else if (cdn && exteria_tl_is(r->value, EXTERIA_TL_ID_upload_cdnFileReuploadNeeded)) {
        const uint8_t *token;
        size_t len;
        status = exteria_tl_get_bytes(r->value, "request_token", &token, &len);
        if (status == EXTERIA_OK && (!len || len > sizeof(t->request_token) || ++t->redirects > 3)) status = EXTERIA_E_LIMIT;
        if (status == EXTERIA_OK) { memcpy(t->request_token, token, len); t->request_token_len = len; }
    } else if (exteria_tl_is(r->value, cdn ? EXTERIA_TL_ID_upload_cdnFile : EXTERIA_TL_ID_upload_file)) {
        const uint8_t *bytes;
        size_t len;
        status = exteria_tl_get_bytes(r->value, "bytes", &bytes, &len);
        if (status == EXTERIA_OK) status = receive_chunk(t, bytes, len);
    } else status = EXTERIA_E_MALFORMED;
    if (status == EXTERIA_OK) t->attempts = 0;
    else t->state = EXTERIA_FILE_FAILED;
    return status;
}

exteria_status exteria_file_refresh(exteria_file_transfer *t, const exteria_tl_value *location) {
    exteria_arena arena;
    exteria_tl_value *old;
    exteria_writer encoded;
    exteria_status status;
    int64_t old_id, new_id;
    const uint8_t *old_thumb, *new_thumb;
    size_t old_len, new_len;
    if (!t || !location || t->state != EXTERIA_FILE_REFRESH) return EXTERIA_E_STATE;
    if (++t->references > 3) return EXTERIA_E_LIMIT;
    exteria_arena_init(&arena, 256u * 1024u);
    exteria_writer_init(&encoded, 65536);
    status = read_location(t, &arena, &old);
    if (status == EXTERIA_OK && (exteria_tl_id(old) != exteria_tl_id(location) ||
        exteria_tl_get_i64(old, "id", &old_id) != EXTERIA_OK ||
        exteria_tl_get_i64(location, "id", &new_id) != EXTERIA_OK || old_id != new_id ||
        exteria_tl_get_bytes(old, "thumb_size", &old_thumb, &old_len) != EXTERIA_OK ||
        exteria_tl_get_bytes(location, "thumb_size", &new_thumb, &new_len) != EXTERIA_OK ||
        old_len != new_len || !exteria_ct_equal(old_thumb, new_thumb, old_len))) status = EXTERIA_E_SECURITY;
    if (status == EXTERIA_OK) status = exteria_tl_encode(location, &encoded, NULL);
    if (status == EXTERIA_OK) {
        exteria_writer_free(&t->location);
        t->location = encoded;
        memset(&encoded, 0, sizeof(encoded));
        t->state = EXTERIA_FILE_ACTIVE;
    }
    exteria_writer_free(&encoded);
    exteria_arena_free(&arena);
    return status;
}

exteria_status exteria_file_uploaded(exteria_file_transfer *t, exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *v;
    exteria_status status;
    char md5[33];
    size_t i;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!t || !arena || !t->upload || t->state != EXTERIA_FILE_DONE) return EXTERIA_E_STATE;
    v = exteria_tl_new_obj(arena, t->big ? "inputFileBig" : "inputFile");
    status = v ? exteria_tl_set_i64(arena, v, "id", (int64_t)t->id) : EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, v, "parts", (int32_t)t->parts);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, v, "name", t->name);
    if (!t->big) {
        for (i = 0; i < 16; ++i) snprintf(md5 + i * 2, 3, "%02x", t->md5_sum[i]);
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, v, "md5_checksum", md5);
    }
    if (status == EXTERIA_OK) *out = v;
    return status;
}

exteria_status exteria_file_publish(exteria_file_transfer *t, const char *destination) {
    if (!t || t->upload || t->state != EXTERIA_FILE_DONE || !destination || !*destination || !t->temporary[0]) return EXTERIA_E_STATE;
    if (t->fd >= 0 && fsync(t->fd) != 0) return EXTERIA_E_IO;
    if (rename(t->temporary, destination) != 0) return EXTERIA_E_IO;
    t->temporary[0] = 0;
    return EXTERIA_OK;
}

exteria_status exteria_file_cancel(exteria_file_transfer *t) {
    exteria_status status = EXTERIA_OK;
    if (!t) return EXTERIA_E_ARG;
    t->pending = 0;
    t->state = EXTERIA_FILE_CANCELLED;
    if (t->fd >= 0) { if (close(t->fd) != 0) status = EXTERIA_E_IO; t->fd = -1; }
    if (t->temporary[0] && unlink(t->temporary) != 0 && errno != ENOENT) status = EXTERIA_E_IO;
    if (status == EXTERIA_OK) t->temporary[0] = 0;
    return status;
}

exteria_status exteria_file_close(exteria_file_transfer *t) {
    exteria_status status = EXTERIA_OK;
    if (!t) return EXTERIA_E_ARG;
    if (t->fd >= 0 && close(t->fd) != 0) status = EXTERIA_E_IO;
    t->fd = -1;
    exteria_writer_free(&t->location);
    if (t->chunk.data) exteria_wipe(t->chunk.data, t->chunk.cap);
    exteria_writer_free(&t->chunk);
    exteria_digest_free(t->md5);
    t->md5 = NULL;
    exteria_wipe(t->cdn_key, sizeof(t->cdn_key));
    exteria_wipe(t->token, sizeof(t->token));
    return status;
}
