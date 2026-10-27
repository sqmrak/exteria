#ifndef EXTERIA_PHONE_H
#define EXTERIA_PHONE_H

#include <stddef.h>

#include "exteria_status.h"

#define EXTERIA_PHONE_MAX_DIGITS 15
#define EXTERIA_COUNTRY_CODE_MAX 4
#define EXTERIA_COUNTRY_MAX 320

typedef struct exteria_country {
    char code[EXTERIA_COUNTRY_CODE_MAX + 1];
    char iso[3];
    char name[48];
    char pattern[24];
} exteria_country;

/* keeps the ascii digits of in, at most cap - 1 of them; returns how many it kept */
size_t exteria_phone_digits(const char *in, char *out, size_t cap);

/* pattern letters X take digits, other characters only appear when a digit follows them */
exteria_status exteria_phone_format(const char *pattern, const char *digits, char *out, size_t cap);

int exteria_phone_valid(size_t code_digits, size_t national_digits);

/* lines of code;ISO;name or code;ISO;name;pattern */
exteria_status exteria_country_parse(const char *text, size_t len, exteria_country *out, size_t cap,
                                     size_t *count);

/* longest dial code that starts digits; among equal codes the later entry wins, which is the main country */
const exteria_country *exteria_country_match(const exteria_country *list, size_t count,
                                             const char *digits, size_t *code_len);

#endif
