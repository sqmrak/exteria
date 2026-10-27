#ifndef EXTERIA_CLOCK_H
#define EXTERIA_CLOCK_H

#include <stdint.h>

/* injected so protocol state machines run in tests without sleeping */
typedef struct exteria_clock {
    uint64_t (*realtime_ms)(void *ctx);
    uint64_t (*monotonic_ms)(void *ctx);
    void *ctx;
} exteria_clock;

extern const exteria_clock exteria_system_clock;

#endif
