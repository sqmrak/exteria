#ifndef EXTERIA_ARENA_H
#define EXTERIA_ARENA_H

#include <stddef.h>

typedef struct exteria_arena_chunk exteria_arena_chunk;

typedef struct exteria_arena {
    exteria_arena_chunk *head;
    size_t used;
    size_t limit;
} exteria_arena;

void exteria_arena_init(exteria_arena *a, size_t limit);
void *exteria_arena_alloc(exteria_arena *a, size_t n);
void *exteria_arena_copy(exteria_arena *a, const void *data, size_t n);
char *exteria_arena_strdup(exteria_arena *a, const char *s);
void exteria_arena_free(exteria_arena *a);

#endif
