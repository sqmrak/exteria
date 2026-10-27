#ifndef EXTERIA_PASSCODE_H
#define EXTERIA_PASSCODE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the passcode lock: a code of four digits or a free password, kept as sha256(salt, code, salt) in hex with a
   random 16 byte salt */

#define EXTERIA_PASSCODE_SALT_LEN 16
#define EXTERIA_PASSCODE_HEX_LEN 64
#define EXTERIA_PASSCODE_PIN_LEN 4
#define EXTERIA_PASSCODE_MAX_LEN 64
/* the auto lock value that locks on every return, however short the leave was */
#define EXTERIA_PASSCODE_AT_ONCE 1u

typedef enum exteria_passcode_type {
    EXTERIA_PASSCODE_PIN = 0,
    EXTERIA_PASSCODE_PASSWORD = 1
} exteria_passcode_type;

/* a pin is exactly four ascii digits, a password is one to EXTERIA_PASSCODE_MAX_LEN bytes without a control character */
int exteria_passcode_valid(exteria_passcode_type type, const char *code, size_t len);

/* out holds the hex and a terminating zero; EXTERIA_E_ARG for a code that is not valid as a password (the type is not part of the hash) */
exteria_status exteria_passcode_hash(const uint8_t salt[EXTERIA_PASSCODE_SALT_LEN], const char *code, size_t len, char out[EXTERIA_PASSCODE_HEX_LEN + 1]);

/* 1 when the code made with this salt has the stored hash; 0 for anything else, a malformed stored hash included */
int exteria_passcode_matches(const uint8_t salt[EXTERIA_PASSCODE_SALT_LEN], const char *code, size_t len, const char *hex);

/* seconds the lock refuses a try after this many wrong ones in a row: none for the first four, then 5 s doubling to 5 min */
uint32_t exteria_passcode_wait_seconds(uint32_t failures);

/* whether the app locks on return. auto_lock is the seconds the person allows away (0 never, 1 at once) */
int exteria_passcode_should_lock(uint32_t auto_lock, int64_t left_at, int64_t now);

#endif
