#ifndef EXTERIA_RANDOM_H
#define EXTERIA_RANDOM_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* mtproto nonces and dh exponents require kernel entropy */
exteria_status exteria_random(void *buf, size_t n);
exteria_status exteria_random_u64(uint64_t *out);

#endif
