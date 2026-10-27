#include "exteria_night.h"

#include <math.h>
#include <stddef.h>

#define MINUTES_PER_DAY (24 * 60)

void exteria_night_config_default(exteria_night_config *config) {
    if (!config) return;
    config->mode = EXTERIA_NIGHT_OFF;
    config->from_minute = EXTERIA_NIGHT_DEFAULT_FROM;
    config->to_minute = EXTERIA_NIGHT_DEFAULT_TO;
    config->threshold_percent = EXTERIA_NIGHT_DEFAULT_THRESHOLD;
    config->by_sun = 0;
    config->sunset_minute = EXTERIA_NIGHT_DEFAULT_FROM;
    config->sunrise_minute = EXTERIA_NIGHT_DEFAULT_TO;
    config->sun_state = EXTERIA_SUN_NORMAL;
}

int exteria_night_config_valid(const exteria_night_config *config) {
    if (!config) return 0;
    return config->mode >= EXTERIA_NIGHT_OFF && config->mode <= EXTERIA_NIGHT_SYSTEM &&
           config->from_minute >= 0 && config->from_minute < MINUTES_PER_DAY &&
           config->to_minute >= 0 && config->to_minute < MINUTES_PER_DAY &&
           config->threshold_percent >= 0 && config->threshold_percent <= 100 &&
           (config->by_sun == 0 || config->by_sun == 1) &&
           config->sunset_minute >= 0 && config->sunset_minute < MINUTES_PER_DAY &&
           config->sunrise_minute >= 0 && config->sunrise_minute < MINUTES_PER_DAY &&
           config->sun_state >= EXTERIA_SUN_NORMAL && config->sun_state <= EXTERIA_SUN_NEVER_SETS;
}

/* night between two times of the day, both included; a start that is not before the end runs over midnight */
static int in_night(int32_t start, int32_t end, int32_t minute) {
    if (start < end) return start <= minute && minute <= end;
    return minute >= start || minute <= end;
}

int exteria_night_decide(const exteria_night_config *config, int32_t minute_of_day, int32_t brightness_percent, int system_dark) {
    if (!exteria_night_config_valid(config)) return -1;
    if (config->mode == EXTERIA_NIGHT_SCHEDULED) {
        if (minute_of_day < 0 || minute_of_day >= MINUTES_PER_DAY) return -1;
        if (config->by_sun) {
            if (config->sun_state == EXTERIA_SUN_NEVER_RISES) return 1;
            if (config->sun_state == EXTERIA_SUN_NEVER_SETS) return 0;
            return in_night(config->sunset_minute, config->sunrise_minute, minute_of_day);
        }
        return in_night(config->from_minute, config->to_minute, minute_of_day);
    }
    if (config->mode == EXTERIA_NIGHT_ADAPTIVE) {
        if (brightness_percent < 0 || brightness_percent > 100) return -1;
        return brightness_percent <= config->threshold_percent;
    }
    if (config->mode == EXTERIA_NIGHT_SYSTEM) return system_dark == 0 || system_dark == 1 ? system_dark : -1;
    return -1;
}

int exteria_night_should_switch(int decision, int last_decision, int currently_dark) {
    if (decision != 0 && decision != 1) return 0;
    if (decision == last_decision) return 0;
    return decision != (currently_dark ? 1 : 0);
}

/* the sun, after sunriset.c of Paul Schlyter carries it */
#define DEGRAD (M_PI / 180.0)
#define RADEG (180.0 / M_PI)

static double sind(double x) { return sin(x * DEGRAD); }
static double cosd(double x) { return cos(x * DEGRAD); }
static double revolution(double x) { return x - 360.0 * floor(x / 360.0); }
static double rev180(double x) { return x - 360.0 * floor(x / 360.0 + 0.5); }

static long days_since_2000_jan_0(int y, int m, int d) {
    return 367L * y - ((7L * (y + ((m + 9) / 12))) / 4) + ((275L * m) / 9) + d - 730530L;
}

/* the sun's ecliptic longitude and distance at day number p */
static void sun_position(double p, double *longitude, double *distance) {
    double s = revolution(356.0470 + 0.9856002585 * p);
    double l = 282.9404 + 4.70935E-5 * p;
    double a = 0.016709 - 1.151E-9 * p;
    double v = a * RADEG * sind(s) * (1.0 + a * cosd(s)) + s;
    double k = cosd(v) - a;
    double i = sqrt(1.0 - a * a) * sind(v);
    *distance = sqrt(k * k + i * i);
    *longitude = RADEG * atan2(i, k) + l;
    if (*longitude >= 360.0) *longitude -= 360.0;
}

static void sun_ra_dec(double d, double *ra, double *dec, double *distance) {
    double longitude, xs, ys, obliquity, xe, ye, ze;
    sun_position(d, &longitude, distance);
    xs = *distance * cosd(longitude);
    ys = *distance * sind(longitude);
    obliquity = 23.4393 - 3.563E-7 * d;
    xe = xs;
    ye = ys * cosd(obliquity);
    ze = ys * sind(obliquity);
    *ra = RADEG * atan2(ye, xe);
    *dec = RADEG * atan2(ze, sqrt(xe * xe + ye * ye));
}

static int32_t wrap_minutes(double hours, int utc_offset_minutes) {
    long minutes = (long)(hours * 60.0) + utc_offset_minutes;
    minutes %= MINUTES_PER_DAY;
    if (minutes < 0) minutes += MINUTES_PER_DAY;
    return (int32_t)minutes;
}

int exteria_sun_times(double latitude, double longitude, int year, int month, int day, int utc_offset_minutes, int32_t *sunrise_minute, int32_t *sunset_minute,
                      int32_t *state) {
    double d, sidereal, ra, dec, distance, south, radius, altitude, cost, t;
    int32_t kind = EXTERIA_SUN_NORMAL;
    if (!sunrise_minute || !sunset_minute || !state) return -1;
    *sunrise_minute = 0;
    *sunset_minute = 0;
    *state = EXTERIA_SUN_NORMAL;
    if (!(latitude >= -90.0 && latitude <= 90.0) || !(longitude >= -180.0 && longitude <= 180.0) || month < 1 || month > 12 || day < 1 || day > 31 || year < 1900 ||
        year > 2200 || utc_offset_minutes < -14 * 60 || utc_offset_minutes > 14 * 60) return -1;
    d = (double)days_since_2000_jan_0(year, month, day) + 0.5 - longitude / 360.0;
    sidereal = revolution(revolution((180.0 + 356.0470 + 282.9404) + (0.9856002585 + 4.70935E-5) * d) + 180.0 + longitude);
    sun_ra_dec(d, &ra, &dec, &distance);
    south = 12.0 - rev180(sidereal - ra) / 15.0;
    radius = 0.2666 / distance;
    altitude = -35.0 / 60.0 - radius;
    cost = (sind(altitude) - sind(latitude) * sind(dec)) / (cosd(latitude) * cosd(dec));
    if (cost >= 1.0) {
        kind = EXTERIA_SUN_NEVER_RISES;
        t = 0.0;
    } else if (cost <= -1.0) {
        kind = EXTERIA_SUN_NEVER_SETS;
        t = 12.0;
    } else {
        t = RADEG * acos(cost) / 15.0;
    }
    *sunrise_minute = wrap_minutes(south - t, utc_offset_minutes);
    *sunset_minute = wrap_minutes(south + t, utc_offset_minutes);
    *state = kind;
    return 0;
}
