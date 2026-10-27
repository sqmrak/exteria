#ifndef EXTERIA_MT_TRAFFIC_H
#define EXTERIA_MT_TRAFFIC_H

#include <stdint.h>

/* bytes the connections of the app sent and received, counted where the sockets read and write, apart for Wi-Fi
   and for the mobile network */

typedef struct exteria_traffic {
    uint64_t sent[2];       /* index 0 Wi-Fi, 1 mobile */
    uint64_t received[2];
} exteria_traffic;

/* 0 for Wi-Fi, anything else for the mobile network */
void exteria_traffic_set_cellular(int cellular);
/* adds to the class that is set now */
void exteria_traffic_add(uint64_t sent, uint64_t received);
/* what was counted since the last take, which then starts again from zero */
void exteria_traffic_take(exteria_traffic *out);

#endif
