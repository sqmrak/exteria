#ifndef EXTERIA_MT_KEYS_H
#define EXTERIA_MT_KEYS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

typedef struct exteria_mt_rsa_key {
    uint64_t fingerprint;
    const uint8_t *n;
    size_t n_len;
    uint32_t e;
} exteria_mt_rsa_key;

const exteria_mt_rsa_key *exteria_mt_default_keys(int is_test, size_t *count);
exteria_status exteria_mt_rsa_fingerprint(const uint8_t *n, size_t n_len, uint32_t e, uint64_t *out);
const exteria_mt_rsa_key *exteria_mt_find_key(const exteria_mt_rsa_key *keys, size_t count, uint64_t fingerprint);

#endif
