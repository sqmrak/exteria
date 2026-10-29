#ifndef EXTERIA_LIST_STATE_H
#define EXTERIA_LIST_STATE_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    EXTERIA_LIST_CONTENT,
    EXTERIA_LIST_LOADING,
    EXTERIA_LIST_EMPTY,
    EXTERIA_LIST_FAILED
} exteria_list_state;

typedef struct exteria_list_presentation {
    exteria_list_state state;
    int table_visible;
} exteria_list_presentation;

/* the selected list can be empty even when another folder loaded before it; its header must remain reachable */
exteria_list_presentation exteria_list_present(size_t item_count, int loading, int failed, int has_header);
int exteria_list_flood_wait(const char *error, uint32_t *seconds);
uint64_t exteria_list_flood_deadline(uint64_t current, uint64_t now, uint32_t seconds);
uint32_t exteria_list_flood_remaining(uint64_t deadline, uint64_t now);
/* coalesce updates and leave at least interval_ms between list requests */
uint64_t exteria_list_refresh_delay(uint64_t now, uint64_t last, uint32_t interval_ms, uint32_t debounce_ms);

#endif
