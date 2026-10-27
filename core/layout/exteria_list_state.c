#include "exteria_list_state.h"
#include <string.h>
#include <limits.h>

exteria_list_presentation exteria_list_present(size_t item_count, int loading, int failed, int has_header) {
    exteria_list_presentation presentation;
    if (item_count) presentation.state = EXTERIA_LIST_CONTENT;
    else if (loading) presentation.state = EXTERIA_LIST_LOADING;
    else if (failed) presentation.state = EXTERIA_LIST_FAILED;
    else presentation.state = EXTERIA_LIST_EMPTY;
    presentation.table_visible = item_count != 0 || has_header;
    return presentation;
}

int exteria_list_flood_wait(const char *error, uint32_t *seconds) {
    const char *p;
    uint32_t value = 0;
    if (seconds) *seconds = 0;
    if (!error || !seconds) return 0;
    if (strncmp(error, "FLOOD_WAIT_", 11) == 0) p = error + 11;
    else if (strncmp(error, "FLOOD_PREMIUM_WAIT_", 19) == 0) p = error + 19;
    else return 0;
    if (!*p) return 0;
    while (*p) {
        unsigned digit;
        if (*p < '0' || *p > '9') return 0;
        digit = (unsigned)(*p++ - '0');
        if (value > ((uint32_t)INT32_MAX - digit) / 10u) return 0;
        value = value * 10u + digit;
    }
    if (!value) return 0;
    *seconds = value;
    return 1;
}

uint64_t exteria_list_flood_deadline(uint64_t current, uint64_t now, uint32_t seconds) {
    uint64_t delay = (uint64_t)seconds * 1000u;
    uint64_t until = delay > UINT64_MAX - now ? UINT64_MAX : now + delay;
    return until > current ? until : current;
}

uint32_t exteria_list_flood_remaining(uint64_t deadline, uint64_t now) {
    if (deadline <= now) return 0;
    uint64_t ms = deadline - now;
    uint64_t seconds = ms / 1000u + (ms % 1000u != 0);
    return seconds > UINT32_MAX ? UINT32_MAX : (uint32_t)seconds;
}
