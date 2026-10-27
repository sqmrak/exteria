#include "exteria_time_zone.h"
#include "test_util.h"

int main(void) {
    CHECK(exteria_time_zone_valid(EXTERIA_TIME_ZONE_AUTO));
    for (int32_t minutes = EXTERIA_TIME_ZONE_MIN; minutes <= EXTERIA_TIME_ZONE_MAX; ++minutes)
        CHECK_EQ_INT(exteria_time_zone_valid(minutes), minutes % EXTERIA_TIME_ZONE_STEP == 0);
    CHECK(exteria_time_zone_valid(0));
    CHECK(exteria_time_zone_valid(180));
    CHECK(exteria_time_zone_valid(345));
    CHECK(exteria_time_zone_valid(-210));
    CHECK(!exteria_time_zone_valid(EXTERIA_TIME_ZONE_MIN - EXTERIA_TIME_ZONE_STEP));
    CHECK(!exteria_time_zone_valid(EXTERIA_TIME_ZONE_MAX + EXTERIA_TIME_ZONE_STEP));
    CHECK(!exteria_time_zone_valid(INT32_MIN + 1));
    CHECK(!exteria_time_zone_valid(INT32_MAX));
    return test_finish("test_time_zone");
}
