#ifndef EXTERIA_TIME_ZONE_H
#define EXTERIA_TIME_ZONE_H

#include <stdint.h>

#define EXTERIA_TIME_ZONE_AUTO INT32_MIN
#define EXTERIA_TIME_ZONE_MIN (-12 * 60)
#define EXTERIA_TIME_ZONE_MAX (14 * 60)
#define EXTERIA_TIME_ZONE_STEP 15

/* a fixed UTC offset in minutes, or the device's time zone */
int exteria_time_zone_valid(int32_t minutes);

#endif
