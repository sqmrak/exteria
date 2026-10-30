#ifndef EXTERIA_MT_FILES_H
#define EXTERIA_MT_FILES_H

#include "exteria_crypto.h"
#include "exteria_mt_client.h"

#define EXTERIA_FILE_HASH_MAX 32u
#define EXTERIA_FILE_PART_MAX (512u * 1024u)
#define EXTERIA_FILE_RANGE_MAX (1024u * 1024u)
#define EXTERIA_FILE_RETRIES_MAX 5u

/* unique within the process, including across media cache instances */
uint64_t exteria_file_temporary_token(void);

typedef enum exteria_file_state {
    EXTERIA_FILE_ACTIVE = 0,
    EXTERIA_FILE_REFRESH,
    EXTERIA_FILE_WAIT,
    EXTERIA_FILE_DONE,
    EXTERIA_FILE_FAILED,
    EXTERIA_FILE_CANCELLED
} exteria_file_state;

typedef struct exteria_file_hash {
    uint64_t offset;
    uint32_t limit;
    uint8_t hash[32];
} exteria_file_hash;

typedef struct exteria_file_transfer {
    int fd;
    int upload;
    int big;
    int32_t dc;
    int32_t cdn_dc;
    int cdn;
    int cdn_disabled;
    exteria_file_state state;
    uint64_t size;
    uint64_t offset;
    uint64_t id;
    uint64_t generation;
    uint64_t pending;
    uint64_t wait_until;
    uint32_t method;
    uint32_t part_size;
    uint32_t parts;
    uint32_t attempts;
    uint32_t references;
    uint32_t redirects;
    uint32_t requested;
    char name[256];
    char temporary[1024];
    exteria_writer location;
    exteria_writer chunk;
    uint8_t token[4096];
    size_t token_len;
    uint8_t request_token[4096];
    size_t request_token_len;
    uint8_t cdn_key[32];
    uint8_t cdn_iv[16];
    exteria_file_hash hashes[EXTERIA_FILE_HASH_MAX];
    uint32_t hash_count;
    exteria_digest *md5;
    uint8_t md5_sum[16];
} exteria_file_transfer;

/* keeps each getFile request inside one mebibyte after a short response changes the next offset */
exteria_status exteria_file_download_part(uint64_t offset, uint32_t preferred, uint32_t *limit);

/* size zero uses a short reply as EOF; a known size accepts progress until its last byte */
exteria_status exteria_file_download_advance(uint64_t offset, uint64_t size, size_t received,
                                           uint32_t requested, uint64_t capacity,
                                           uint64_t *next, int *complete);

/* bounded repeats of a failed part; flood errors keep the server's requested wait */
int exteria_file_retry_delay(const char *error_name, uint32_t retries, uint32_t *delay_ms);

/* a transfer must survive its caller closing the source descriptor */
exteria_status exteria_file_upload(exteria_file_transfer *t, int fd, const char *name, int32_t dc,
                                  uint32_t part_size, uint32_t max_parts);
exteria_status exteria_file_download(exteria_file_transfer *t, const char *temporary,
                                    const exteria_tl_value *location, int32_t dc,
                                    uint64_t size, uint64_t verified_offset);
exteria_status exteria_file_next(exteria_file_transfer *t, uint64_t time_ms, exteria_arena *arena,
                                exteria_tl_value **request, uint64_t *id, int32_t *dc, int *cdn);
exteria_status exteria_file_result(exteria_file_transfer *t, uint64_t id, int32_t dc, int cdn,
                                  uint64_t time_ms, const exteria_mt_rpc_result *result);
exteria_status exteria_file_refresh(exteria_file_transfer *t, const exteria_tl_value *location);
exteria_status exteria_file_uploaded(exteria_file_transfer *t, exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_file_publish(exteria_file_transfer *t, const char *destination);
exteria_status exteria_file_cancel(exteria_file_transfer *t);
exteria_status exteria_file_close(exteria_file_transfer *t);

#endif
