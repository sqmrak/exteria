#include "exteria_mt_traffic.h"

#include <pthread.h>
#include <string.h>

/* a mutex and not atomics: a 64 bit counter on the armv7 slice needs the exclusive double word pair, and a read or write is far slower than the lock */
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static exteria_traffic counted;
static int cellular_now;

void exteria_traffic_set_cellular(int cellular) {
    pthread_mutex_lock(&lock);
    cellular_now = cellular ? 1 : 0;
    pthread_mutex_unlock(&lock);
}

void exteria_traffic_add(uint64_t sent, uint64_t received) {
    pthread_mutex_lock(&lock);
    counted.sent[cellular_now] += sent;
    counted.received[cellular_now] += received;
    pthread_mutex_unlock(&lock);
}

void exteria_traffic_take(exteria_traffic *out) {
    pthread_mutex_lock(&lock);
    if (out) *out = counted;
    memset(&counted, 0, sizeof(counted));
    pthread_mutex_unlock(&lock);
}
