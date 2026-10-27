#include "exteria_pcm_ring.h"

#include <string.h>

#define MASK (EXTERIA_PCM_RING_SIZE - 1u)

void exteria_pcm_ring_reset(exteria_pcm_ring *r) {
    if (!r) return;
    r->head = 0;
    r->tail = 0;
}

size_t exteria_pcm_ring_fill(const exteria_pcm_ring *r) {
    if (!r) return 0;
    return (size_t)(__atomic_load_n(&r->head, __ATOMIC_ACQUIRE) - __atomic_load_n(&r->tail, __ATOMIC_ACQUIRE));
}

size_t exteria_pcm_ring_write(exteria_pcm_ring *r, const int16_t *samples, size_t count) {
    uint32_t head, tail, room, i, n;
    if (!r || !samples) return 0;
    head = r->head;
    tail = __atomic_load_n(&r->tail, __ATOMIC_ACQUIRE);
    room = EXTERIA_PCM_RING_SIZE - (head - tail);
    n = count < room ? (uint32_t)count : room;
    for (i = 0; i < n; ++i) r->samples[(head + i) & MASK] = samples[i];
    __atomic_store_n(&r->head, head + n, __ATOMIC_RELEASE);
    return n;
}

size_t exteria_pcm_ring_read(exteria_pcm_ring *r, int16_t *samples, size_t count) {
    uint32_t head, tail, have, i, n;
    if (!r || !samples) return 0;
    tail = r->tail;
    head = __atomic_load_n(&r->head, __ATOMIC_ACQUIRE);
    have = head - tail;
    n = count < have ? (uint32_t)count : have;
    for (i = 0; i < n; ++i) samples[i] = r->samples[(tail + i) & MASK];
    __atomic_store_n(&r->tail, tail + n, __ATOMIC_RELEASE);
    return n;
}
