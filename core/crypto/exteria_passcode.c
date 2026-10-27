#include "exteria_passcode.h"

#include <string.h>

#include "exteria_bytes.h"
#include "exteria_crypto.h"

#define WAIT_FREE_TRIES 4u
#define WAIT_FIRST_SECONDS 5u
#define WAIT_MAX_SECONDS 300u

int exteria_passcode_valid(exteria_passcode_type type, const char *code, size_t len) {
    size_t i;
    if (!code) return 0;
    if (type == EXTERIA_PASSCODE_PIN) {
        if (len != EXTERIA_PASSCODE_PIN_LEN) return 0;
        for (i = 0; i < len; ++i) {
            if (code[i] < '0' || code[i] > '9') return 0;
        }
        return 1;
    }
    if (type != EXTERIA_PASSCODE_PASSWORD || len == 0 || len > EXTERIA_PASSCODE_MAX_LEN) return 0;
    for (i = 0; i < len; ++i) {
        unsigned char c = (unsigned char)code[i];
        if (c < 0x20 || c == 0x7f) return 0;
    }
    return 1;
}

exteria_status exteria_passcode_hash(const uint8_t salt[EXTERIA_PASSCODE_SALT_LEN], const char *code, size_t len, char out[EXTERIA_PASSCODE_HEX_LEN + 1]) {
    static const char digits[] = "0123456789abcdef";
    exteria_slice parts[3];
    uint8_t digest[EXTERIA_SHA256_LEN];
    exteria_status status;
    size_t i;
    out[0] = '\0';
    if (!salt || !code || len == 0 || len > EXTERIA_PASSCODE_MAX_LEN) return EXTERIA_E_ARG;
    parts[0].data = salt;
    parts[0].len = EXTERIA_PASSCODE_SALT_LEN;
    parts[1].data = (const uint8_t *)code;
    parts[1].len = len;
    parts[2] = parts[0];
    status = exteria_sha256(parts, 3, digest);
    if (status != EXTERIA_OK) return status;
    for (i = 0; i < EXTERIA_SHA256_LEN; ++i) {
        out[i * 2] = digits[digest[i] >> 4];
        out[i * 2 + 1] = digits[digest[i] & 15];
    }
    out[EXTERIA_PASSCODE_HEX_LEN] = '\0';
    return EXTERIA_OK;
}

int exteria_passcode_matches(const uint8_t salt[EXTERIA_PASSCODE_SALT_LEN], const char *code, size_t len, const char *hex) {
    char made[EXTERIA_PASSCODE_HEX_LEN + 1];
    if (!hex || strlen(hex) != EXTERIA_PASSCODE_HEX_LEN) return 0;
    if (exteria_passcode_hash(salt, code, len, made) != EXTERIA_OK) return 0;
    return exteria_ct_equal(made, hex, EXTERIA_PASSCODE_HEX_LEN);
}

uint32_t exteria_passcode_wait_seconds(uint32_t failures) {
    uint32_t wait = WAIT_FIRST_SECONDS;
    if (failures <= WAIT_FREE_TRIES) return 0;
    for (failures -= WAIT_FREE_TRIES + 1; failures > 0 && wait < WAIT_MAX_SECONDS; --failures) wait *= 2;
    return wait < WAIT_MAX_SECONDS ? wait : WAIT_MAX_SECONDS;
}

int exteria_passcode_should_lock(uint32_t auto_lock, int64_t left_at, int64_t now) {
    if (auto_lock == 0) return 0;
    if (auto_lock == EXTERIA_PASSCODE_AT_ONCE) return 1;
    if (left_at <= 0 || now < left_at) return 1;
    return now - left_at >= (int64_t)auto_lock;
}
