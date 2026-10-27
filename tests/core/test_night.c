#include <stdlib.h>

#include "test_util.h"
#include "exteria_night.h"

static exteria_night_config config(int32_t mode, int32_t from, int32_t to, int32_t threshold) {
    exteria_night_config c;
    exteria_night_config_default(&c);
    c.mode = mode;
    c.from_minute = from;
    c.to_minute = to;
    c.threshold_percent = threshold;
    return c;
}

static void test_defaults(void) {
    exteria_night_config c;
    exteria_night_config_default(&c);
    CHECK_EQ_INT(c.mode, EXTERIA_NIGHT_OFF);
    CHECK_EQ_INT(c.from_minute, 22 * 60);
    CHECK_EQ_INT(c.to_minute, 8 * 60);
    CHECK_EQ_INT(c.threshold_percent, 25);
    CHECK_EQ_INT(exteria_night_config_valid(&c), 1);
    exteria_night_config_default(NULL);
}

static void test_valid(void) {
    exteria_night_config good = config(EXTERIA_NIGHT_SCHEDULED, 0, 1439, 100);
    CHECK_EQ_INT(exteria_night_config_valid(&good), 1);
    exteria_night_config bad[] = {
        config(-1, 0, 0, 0), config(1, -1, 0, 0), config(1, 1440, 0, 0), config(1, 0, -1, 0), config(1, 0, 1440, 0),
        config(2, 0, 0, -1), config(2, 0, 0, 101), config(4, 0, 0, 25),
    };
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) CHECK_EQ_INT(exteria_night_config_valid(&bad[i]), 0);
    CHECK_EQ_INT(exteria_night_config_valid(NULL), 0);
}

static void test_schedule(void) {
    /* 22:00 to 08:00 runs over midnight; both ends are night */
    exteria_night_config over = config(EXTERIA_NIGHT_SCHEDULED, 22 * 60, 8 * 60, 25);
    static const struct { int32_t minute; int expect; } over_cases[] = {
        {0, 1}, {7 * 60, 1}, {8 * 60, 1}, {8 * 60 + 1, 0}, {12 * 60, 0}, {21 * 60 + 59, 0}, {22 * 60, 1}, {23 * 60 + 59, 1},
    };
    for (size_t i = 0; i < sizeof(over_cases) / sizeof(over_cases[0]); ++i) CHECK_EQ_INT(exteria_night_decide(&over, over_cases[i].minute, 0, -1), over_cases[i].expect);
    /* a schedule inside one day */
    exteria_night_config same_day = config(EXTERIA_NIGHT_SCHEDULED, 13 * 60, 15 * 60, 25);
    CHECK_EQ_INT(exteria_night_decide(&same_day, 12 * 60 + 59, 0, -1), 0);
    CHECK_EQ_INT(exteria_night_decide(&same_day, 13 * 60, 0, -1), 1);
    CHECK_EQ_INT(exteria_night_decide(&same_day, 15 * 60, 0, -1), 1);
    CHECK_EQ_INT(exteria_night_decide(&same_day, 15 * 60 + 1, 0, -1), 0);
    /* a schedule that ends where it starts is night all day */
    exteria_night_config equal = config(EXTERIA_NIGHT_SCHEDULED, 600, 600, 25);
    CHECK_EQ_INT(exteria_night_decide(&equal, 0, 0, -1), 1);
    CHECK_EQ_INT(exteria_night_decide(&equal, 1439, 0, -1), 1);
    /* a time of day that does not exist is no opinion, and the brightness is not read in this mode */
    CHECK_EQ_INT(exteria_night_decide(&over, -1, 50, -1), -1);
    CHECK_EQ_INT(exteria_night_decide(&over, 1440, 50, -1), -1);
    CHECK_EQ_INT(exteria_night_decide(&over, 12 * 60, 999, -1), 0);
}

static void test_adaptive(void) {
    exteria_night_config c = config(EXTERIA_NIGHT_ADAPTIVE, 0, 0, 25);
    CHECK_EQ_INT(exteria_night_decide(&c, 0, 0, -1), 1);
    CHECK_EQ_INT(exteria_night_decide(&c, 0, 25, -1), 1);
    CHECK_EQ_INT(exteria_night_decide(&c, 0, 26, -1), 0);
    CHECK_EQ_INT(exteria_night_decide(&c, 0, 100, -1), 0);
    CHECK_EQ_INT(exteria_night_decide(&c, 9999, 100, -1), 0);
    CHECK_EQ_INT(exteria_night_decide(&c, 0, -1, -1), -1);
    CHECK_EQ_INT(exteria_night_decide(&c, 0, 101, -1), -1);
    exteria_night_config zero = config(EXTERIA_NIGHT_ADAPTIVE, 0, 0, 0);
    CHECK_EQ_INT(exteria_night_decide(&zero, 0, 0, -1), 1);
    CHECK_EQ_INT(exteria_night_decide(&zero, 0, 1, -1), 0);
}

static void test_off_and_invalid(void) {
    exteria_night_config off = config(EXTERIA_NIGHT_OFF, 0, 0, 25);
    CHECK_EQ_INT(exteria_night_decide(&off, 100, 10, -1), -1);
    exteria_night_config bad = config(1, 5000, 0, 25);
    CHECK_EQ_INT(exteria_night_decide(&bad, 100, 10, -1), -1);
    CHECK_EQ_INT(exteria_night_decide(NULL, 100, 10, -1), -1);
}

static void test_system(void) {
    exteria_night_config c = config(EXTERIA_NIGHT_SYSTEM, 0, 0, 25);
    CHECK_EQ_INT(exteria_night_decide(&c, 600, 50, 1), 1);
    CHECK_EQ_INT(exteria_night_decide(&c, 600, 50, 0), 0);
    /* a system without an appearance has no opinion, and so has a value that is not one */
    CHECK_EQ_INT(exteria_night_decide(&c, 600, 50, -1), -1);
    CHECK_EQ_INT(exteria_night_decide(&c, 600, 50, 2), -1);
}

static void test_sun_schedule(void) {
    exteria_night_config c = config(EXTERIA_NIGHT_SCHEDULED, 100, 200, 25);
    c.by_sun = 1;
    c.sunset_minute = 20 * 60;
    c.sunrise_minute = 6 * 60;
    c.sun_state = EXTERIA_SUN_NORMAL;
    CHECK_EQ_INT(exteria_night_decide(&c, 12 * 60, 0, -1), 0);
    CHECK_EQ_INT(exteria_night_decide(&c, 20 * 60, 0, -1), 1);
    CHECK_EQ_INT(exteria_night_decide(&c, 3 * 60, 0, -1), 1);
    CHECK_EQ_INT(exteria_night_decide(&c, 6 * 60, 0, -1), 1);
    CHECK_EQ_INT(exteria_night_decide(&c, 6 * 60 + 1, 0, -1), 0);
    /* the polar day and night decide by themselves, and the fixed times are not read */
    c.sun_state = EXTERIA_SUN_NEVER_RISES;
    CHECK_EQ_INT(exteria_night_decide(&c, 12 * 60, 0, -1), 1);
    c.sun_state = EXTERIA_SUN_NEVER_SETS;
    CHECK_EQ_INT(exteria_night_decide(&c, 0, 0, -1), 0);
    /* without the sun the fixed times work as before */
    c.by_sun = 0;
    c.sun_state = EXTERIA_SUN_NORMAL;
    CHECK_EQ_INT(exteria_night_decide(&c, 150, 0, -1), 1);
    exteria_night_config bad = c;
    bad.sun_state = 3;
    CHECK_EQ_INT(exteria_night_config_valid(&bad), 0);
    bad = c;
    bad.sunset_minute = 1440;
    CHECK_EQ_INT(exteria_night_config_valid(&bad), 0);
    bad = c;
    bad.by_sun = 2;
    CHECK_EQ_INT(exteria_night_config_valid(&bad), 0);
}

/* the minute a time of the day has, within a few minutes of a published sunrise and sunset table */
static void check_sun(double lat, double lon, int y, int m, int d, int offset, int rise_expect, int set_expect, int tolerance) {
    int32_t rise = -1, set = -1, state = -1;
    CHECK_EQ_INT(exteria_sun_times(lat, lon, y, m, d, offset, &rise, &set, &state), 0);
    CHECK_EQ_INT(state, EXTERIA_SUN_NORMAL);
    CHECK(abs((int)rise - rise_expect) <= tolerance);
    CHECK(abs((int)set - set_expect) <= tolerance);
}

static void test_sun_times(void) {
    /* greenwich at the summer solstice, in British Summer Time (UTC+1): about 04:43 and 21:21 */
    check_sun(51.4779, 0.0, 2024, 6, 21, 60, 4 * 60 + 43, 21 * 60 + 21, 8);
    /* moscow at the winter solstice (UTC+3): about 08:57 and 15:57 */
    check_sun(55.7558, 37.6173, 2024, 12, 21, 180, 8 * 60 + 57, 15 * 60 + 57, 10);
    /* the equator at the equinox, UTC: about six and six */
    check_sun(0.0, 0.0, 2024, 3, 20, 0, 6 * 60, 18 * 60, 12);
    /* a place east of Greenwich with a negative offset still wraps into the day */
    int32_t rise = 0, set = 0, state = 0;
    CHECK_EQ_INT(exteria_sun_times(-33.8688, 151.2093, 2024, 1, 15, 11 * 60, &rise, &set, &state), 0);
    CHECK(rise >= 0 && rise < 1440 && set >= 0 && set < 1440);
    /* the polar night and the polar day of Tromso */
    CHECK_EQ_INT(exteria_sun_times(69.6492, 18.9553, 2024, 12, 21, 60, &rise, &set, &state), 0);
    CHECK_EQ_INT(state, EXTERIA_SUN_NEVER_RISES);
    CHECK(rise >= 0 && rise < 1440 && set >= 0 && set < 1440);
    CHECK_EQ_INT(exteria_sun_times(69.6492, 18.9553, 2024, 6, 21, 120, &rise, &set, &state), 0);
    CHECK_EQ_INT(state, EXTERIA_SUN_NEVER_SETS);
    /* out of range and missing arguments are refused, with the outputs cleared */
    CHECK_EQ_INT(exteria_sun_times(91.0, 0.0, 2024, 6, 21, 0, &rise, &set, &state), -1);
    CHECK_EQ_INT(rise, 0);
    CHECK_EQ_INT(exteria_sun_times(0.0, 181.0, 2024, 6, 21, 0, &rise, &set, &state), -1);
    CHECK_EQ_INT(exteria_sun_times(0.0, 0.0, 2024, 13, 21, 0, &rise, &set, &state), -1);
    CHECK_EQ_INT(exteria_sun_times(0.0, 0.0, 2024, 6, 0, 0, &rise, &set, &state), -1);
    CHECK_EQ_INT(exteria_sun_times(0.0, 0.0, 2024, 6, 21, 15 * 60, &rise, &set, &state), -1);
    CHECK_EQ_INT(exteria_sun_times(0.0, 0.0, 2024, 6, 21, 0, NULL, &set, &state), -1);
    CHECK_EQ_INT(exteria_sun_times(0.0, 0.0, 2024, 6, 21, 0, &rise, &set, NULL), -1);
}

static void test_should_switch(void) {
    /* the first look switches when the theme differs from the decision */
    CHECK_EQ_INT(exteria_night_should_switch(1, -1, 0), 1);
    CHECK_EQ_INT(exteria_night_should_switch(0, -1, 1), 1);
    CHECK_EQ_INT(exteria_night_should_switch(1, -1, 1), 0);
    CHECK_EQ_INT(exteria_night_should_switch(0, -1, 0), 0);
    /* an unchanged decision never switches, so a theme flipped by hand stays until the decision turns */
    CHECK_EQ_INT(exteria_night_should_switch(1, 1, 0), 0);
    CHECK_EQ_INT(exteria_night_should_switch(0, 0, 1), 0);
    /* a decision that turned does */
    CHECK_EQ_INT(exteria_night_should_switch(1, 0, 0), 1);
    CHECK_EQ_INT(exteria_night_should_switch(0, 1, 1), 1);
    /* no opinion and nonsense decisions do nothing */
    CHECK_EQ_INT(exteria_night_should_switch(-1, 0, 1), 0);
    CHECK_EQ_INT(exteria_night_should_switch(2, 0, 0), 0);
    CHECK_EQ_INT(exteria_night_should_switch(-1, -1, 0), 0);
}

int main(void) {
    test_defaults();
    test_valid();
    test_schedule();
    test_adaptive();
    test_off_and_invalid();
    test_system();
    test_sun_schedule();
    test_sun_times();
    test_should_switch();
    return test_finish("test_night");
}
