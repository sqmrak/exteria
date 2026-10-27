#include "exteria_pcm_ring.h"
#include "test_util.h"

#include <pthread.h>

static exteria_pcm_ring ring;

static void basics(void) {
    int16_t in[100], out[100];
    size_t i;
    exteria_pcm_ring_reset(&ring);
    for (i = 0; i < 100; ++i) in[i] = (int16_t)(i * 3 - 100);
    CHECK_EQ_INT(exteria_pcm_ring_fill(&ring), 0);
    CHECK_EQ_INT(exteria_pcm_ring_read(&ring, out, 10), 0);
    CHECK_EQ_INT(exteria_pcm_ring_write(&ring, in, 100), 100);
    CHECK_EQ_INT(exteria_pcm_ring_fill(&ring), 100);
    CHECK_EQ_INT(exteria_pcm_ring_read(&ring, out, 40), 40);
    CHECK(memcmp(out, in, 40 * sizeof(int16_t)) == 0);
    CHECK_EQ_INT(exteria_pcm_ring_read(&ring, out, 100), 60);
    CHECK(memcmp(out, in + 40, 60 * sizeof(int16_t)) == 0);
    CHECK_EQ_INT(exteria_pcm_ring_fill(&ring), 0);
    CHECK_EQ_INT(exteria_pcm_ring_write(NULL, in, 4), 0);
    CHECK_EQ_INT(exteria_pcm_ring_write(&ring, NULL, 4), 0);
    CHECK_EQ_INT(exteria_pcm_ring_read(NULL, out, 4), 0);
    CHECK_EQ_INT(exteria_pcm_ring_fill(NULL), 0);
    exteria_pcm_ring_reset(NULL);
}

static void full_and_wrap(void) {
    static int16_t big[EXTERIA_PCM_RING_SIZE + 50], got[EXTERIA_PCM_RING_SIZE + 50];
    size_t i, round;
    exteria_pcm_ring_reset(&ring);
    for (i = 0; i < sizeof(big) / sizeof(big[0]); ++i) big[i] = (int16_t)i;
    /* only what fits is taken */
    CHECK_EQ_INT(exteria_pcm_ring_write(&ring, big, EXTERIA_PCM_RING_SIZE + 50), EXTERIA_PCM_RING_SIZE);
    CHECK_EQ_INT(exteria_pcm_ring_write(&ring, big, 1), 0);
    CHECK_EQ_INT(exteria_pcm_ring_read(&ring, got, 1000), 1000);
    CHECK_EQ_INT(exteria_pcm_ring_write(&ring, big, 5000), 1000);
    CHECK_EQ_INT(exteria_pcm_ring_read(&ring, got, EXTERIA_PCM_RING_SIZE), EXTERIA_PCM_RING_SIZE);
    CHECK_EQ_INT(got[0], (int16_t)1000);
    CHECK_EQ_INT(got[EXTERIA_PCM_RING_SIZE - 1000], 0);
    /* the indexes run past 32 bits' worth of wrap without losing track: many rounds of an uneven size */
    exteria_pcm_ring_reset(&ring);
    ring.head = ring.tail = 0xFFFFF000u;
    for (round = 0; round < 40; ++round) {
        size_t n = 1000 + round * 7, w, r;
        for (i = 0; i < n; ++i) big[i] = (int16_t)(round * 31 + i);
        w = exteria_pcm_ring_write(&ring, big, n);
        CHECK_EQ_INT(w, n);
        r = exteria_pcm_ring_read(&ring, got, n);
        CHECK_EQ_INT(r, n);
        CHECK(memcmp(got, big, n * sizeof(int16_t)) == 0);
    }
}

static void *writer(void *arg) {
    int16_t block[160];
    uint32_t next = 0, total = *(uint32_t *)arg, k;
    while (next < total) {
        uint32_t n = total - next < 160 ? total - next : 160, written;
        for (k = 0; k < n; ++k) block[k] = (int16_t)((next + k) * 7u);
        written = (uint32_t)exteria_pcm_ring_write(&ring, block, n);
        next += written;
        /* a short write leaves the rest of the block to be offered again, from where it stopped, as the loop does */
        if (written == 0) sched_yield();
    }
    return NULL;
}

static void two_threads_keep_every_sample_in_order(void) {
    pthread_t t;
    uint32_t total = 3000000, seen = 0, k;
    int16_t block[500];
    int ok = 1;
    exteria_pcm_ring_reset(&ring);
    pthread_create(&t, NULL, writer, &total);
    while (seen < total) {
        size_t n = exteria_pcm_ring_read(&ring, block, 500);
        if (n == 0) {
            sched_yield();
            continue;
        }
        for (k = 0; k < n; ++k) {
            if (block[k] != (int16_t)((seen + k) * 7u)) ok = 0;
        }
        seen += (uint32_t)n;
    }
    pthread_join(t, NULL);
    CHECK_EQ_INT(ok, 1);
    CHECK_EQ_INT(seen, total);
}

int main(void) {
    basics();
    full_and_wrap();
    two_threads_keep_every_sample_in_order();
    return test_finish("test_pcm_ring");
}
