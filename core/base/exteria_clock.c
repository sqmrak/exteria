#include "exteria_clock.h"

#include <stddef.h>
#include <sys/time.h>
#include <time.h>

#if defined(__APPLE__)
#include <mach/mach_time.h>
#endif

static uint64_t system_realtime_ms(void *ctx) {
    struct timeval tv;
    (void)ctx;
    if (gettimeofday(&tv, NULL) != 0) return 0;
    return (uint64_t)tv.tv_sec * 1000u + (uint64_t)tv.tv_usec / 1000u;
}

/* clock_gettime is absent before ios 10, mach_absolute_time exists on every ios */
static uint64_t system_monotonic_ms(void *ctx) {
    (void)ctx;
#if defined(__APPLE__)
    mach_timebase_info_data_t base;
    uint64_t ticks = mach_absolute_time();
    uint64_t divisor;
    if (mach_timebase_info(&base) != KERN_SUCCESS || base.denom == 0) return 0;
    divisor = (uint64_t)base.denom * 1000000u;
    /* multiplying the full tick count overflows after long device uptime */
    return (ticks / divisor) * base.numer + ((ticks % divisor) * base.numer) / divisor;
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
#endif
}

const exteria_clock exteria_system_clock = { system_realtime_ms, system_monotonic_ms, NULL };
