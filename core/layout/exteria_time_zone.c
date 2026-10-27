#include "exteria_time_zone.h"

int exteria_time_zone_valid(int32_t minutes) {
    return minutes == EXTERIA_TIME_ZONE_AUTO ||
           (minutes >= EXTERIA_TIME_ZONE_MIN && minutes <= EXTERIA_TIME_ZONE_MAX && minutes % EXTERIA_TIME_ZONE_STEP == 0);
}
