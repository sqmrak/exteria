#ifndef EXTERIA_NIGHT_H
#define EXTERIA_NIGHT_H

#include <stdint.h>

/* the rules of the automatic night theme (Theme.java); the app reads the clock and the screen brightness and asks
   here which theme the person set up for that moment; nothing else lives here */

#define EXTERIA_NIGHT_DEFAULT_FROM (22 * 60)
#define EXTERIA_NIGHT_DEFAULT_TO (8 * 60)
#define EXTERIA_NIGHT_DEFAULT_THRESHOLD 25

typedef enum exteria_night_mode {
    EXTERIA_NIGHT_OFF = 0,
    /* night between two times of the day */
    EXTERIA_NIGHT_SCHEDULED,
    /* night while the screen is at or below a brightness */
    EXTERIA_NIGHT_ADAPTIVE,
    /* night while the system is in its dark appearance */
    EXTERIA_NIGHT_SYSTEM
} exteria_night_mode;

/* what the sun does on a day at a place, for a schedule by the sun */
typedef enum exteria_sun_state {
    EXTERIA_SUN_NORMAL = 0,     /* it rises and sets */
    EXTERIA_SUN_NEVER_RISES,    /* a polar night: night all day */
    EXTERIA_SUN_NEVER_SETS      /* a polar day: day all day */
} exteria_sun_state;

typedef struct exteria_night_config {
    int32_t mode;                   /* exteria_night_mode */
    int32_t from_minute;            /* minutes after midnight, 0 to 1439: the night starts */
    int32_t to_minute;              /* and ends */
    int32_t threshold_percent;      /* 0 to 100: the brightness at or below which it is night */
    int32_t by_sun;                 /* the schedule runs from sunset to sunrise instead of from_minute to to_minute */
    int32_t sunset_minute;          /* minutes after midnight of the place of the phone, for today */
    int32_t sunrise_minute;
    int32_t sun_state;              /* exteria_sun_state of today */
} exteria_night_config;

/* what a person who never opened the screen has: off, from 22:00 to 08:00, at 25 percent, and no sun times yet */
void exteria_night_config_default(exteria_night_config *config);
/* 1 when every field is in its range */
int exteria_night_config_valid(const exteria_night_config *config);

/* 1 for night, 0 for day, -1 for no opinion: the mode is off, the config is not valid, or the reading the mode
   needs is outside its range */
int exteria_night_decide(const exteria_night_config *config, int32_t minute_of_day, int32_t brightness_percent, int system_dark);

/* sunrise and sunset of a day at a place, in minutes after midnight of the local day, with the calculation of
   SunDate (the sun at -35 arcminutes with the upper limb) */
int exteria_sun_times(double latitude, double longitude, int year, int month, int day, int utc_offset_minutes, int32_t *sunrise_minute, int32_t *sunset_minute,
                      int32_t *state);

/* whether the theme has to change now; looking only at changes lets a person who flipped the theme by hand keep it
   until the schedule next turns. last_decision is -1 before the first look; the caller keeps the last decision
   that was not -1 */
int exteria_night_should_switch(int decision, int last_decision, int currently_dark);

#endif
