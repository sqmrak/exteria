#ifndef EXTERIA_LIST_MOVES_H
#define EXTERIA_LIST_MOVES_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the most rows a list change is worked out for; a bigger list is reloaded whole by the caller */
#define EXTERIA_LIST_MOVES_MAX 512
/* the highest new row index a target may name */
#define EXTERIA_LIST_TARGET_MAX 4096

/* which rows of a list can stay where the rest of the change puts them. target[i] is the new index of the row that
   was at index i, or -1 when the row is gone; two rows never share a target */
exteria_status exteria_list_keep(const int32_t *target, size_t count, uint8_t *keep, size_t keep_cap);

#endif
