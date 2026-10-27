#include "exteria_scroll.h"

#include <math.h>

/* below this speed a list counts as resting in no direction */
#define SPEED_FLOOR 60.0
/* the share of a new reading that enters the speed, the rest is the old speed */
#define SPEED_NEW 0.6
#define SAMPLE_GAP_MIN 0.003
#define SAMPLE_GAP_MAX 0.25
#define PROJECT_SECONDS 0.18
#define PROJECT_SCREENS 3.0
#define ASK_SCREENS 2.0
#define ASK_FLOOR 640.0
#define LEAD_SCREENS 4.0
#define LEAD_SECONDS 0.35
#define AHEAD_SCREENS 2.5
#define BEHIND_SCREENS 0.8
#define BOTTOM_DISTANCE 80.0

static int is_number(double value) {
    return isfinite(value);
}

int exteria_scroll_tracks_bottom(int following, int user_scrolling, double previous_offset, double offset, double end) {
    if (!user_scrolling || !is_number(previous_offset) || !is_number(offset) || !is_number(end)) return !!following;
    /* the return from a bottom bounce still lands at the end */
    if (offset >= end) return 1;
    if (offset < previous_offset) return 0;
    if (offset > previous_offset && end - offset <= BOTTOM_DISTANCE) return 1;
    return !!following;
}

exteria_status exteria_scroll_resize(double offset, double old_height, double new_height,
                                     double min_offset, double max_offset, double *next) {
    double value;
    if (next) *next = 0;
    if (!next || !is_number(offset) || !is_number(old_height) || !is_number(new_height) ||
        !is_number(min_offset) || !is_number(max_offset) || old_height < 0 || new_height < 0) return EXTERIA_E_ARG;
    value = offset + (old_height - new_height);
    if (!is_number(value)) return EXTERIA_E_ARG;
    if (max_offset < min_offset) max_offset = min_offset;
    *next = fmax(min_offset, fmin(value, max_offset));
    return EXTERIA_OK;
}

exteria_status exteria_scroll_follow(double offset, double target, double elapsed, double *next) {
    double distance;
    if (next) *next = 0;
    if (!next || !is_number(offset) || !is_number(target) || !is_number(elapsed) || elapsed <= 0) return EXTERIA_E_ARG;
    if (elapsed > 0.1) elapsed = 0.1;
    distance = target - offset;
    if (!is_number(distance)) return EXTERIA_E_ARG;
    *next = fabs(distance) <= 0.5 ? target : offset + distance * (1 - exp(-elapsed / 0.075));
    return EXTERIA_OK;
}

exteria_status exteria_scroll_begin(exteria_scroll_state *state, double offset, double now) {
    if (!state) return EXTERIA_E_ARG;
    state->velocity = 0;
    state->last_offset = 0;
    state->last_time = 0;
    state->sampled = 0;
    if (!is_number(offset) || !is_number(now)) return EXTERIA_E_ARG;
    state->last_offset = offset;
    state->last_time = now;
    state->sampled = 1;
    return EXTERIA_OK;
}

exteria_status exteria_scroll_sample(exteria_scroll_state *state, double offset, double now, double viewport) {
    double elapsed, displacement;
    if (!state) return EXTERIA_E_ARG;
    if (!is_number(offset) || !is_number(now) || !is_number(viewport) || viewport <= 0) return EXTERIA_E_ARG;
    if (!state->sampled) {
        state->last_offset = offset;
        state->last_time = now;
        state->sampled = 1;
        return EXTERIA_OK;
    }
    elapsed = now - state->last_time;
    displacement = offset - state->last_offset;
    if (elapsed > SAMPLE_GAP_MIN && elapsed < SAMPLE_GAP_MAX && fabs(displacement) < viewport * 2) {
        state->velocity = state->velocity * (1 - SPEED_NEW) + displacement / elapsed * SPEED_NEW;
    } else if (elapsed >= SAMPLE_GAP_MAX || elapsed < 0 || fabs(displacement) >= viewport * 2) {
        /* a clock set back counts as a gap, or every later event would be measured against a time in the future */
        state->velocity = 0;
    } else {
        /* too close to the last event to tell a speed, so the base stays at that event */
        return EXTERIA_OK;
    }
    state->last_offset = offset;
    state->last_time = now;
    return EXTERIA_OK;
}

exteria_status exteria_scroll_predict(const exteria_scroll_state *state, double offset, double viewport, int has_target,
                                      double target, double min_offset, double max_offset, double *predicted) {
    double value, reach;
    if (predicted) *predicted = 0;
    if (!state || !predicted || !is_number(offset) || !is_number(viewport) || viewport <= 0 || !is_number(min_offset) ||
        !is_number(max_offset) || (has_target && !is_number(target))) return EXTERIA_E_ARG;
    reach = state->velocity * PROJECT_SECONDS;
    if (reach > viewport * PROJECT_SCREENS) reach = viewport * PROJECT_SCREENS;
    if (reach < -viewport * PROJECT_SCREENS) reach = -viewport * PROJECT_SCREENS;
    value = has_target ? target : offset + reach;
    /* a list shorter than its view has no room to move, the first offset wins */
    if (max_offset < min_offset) max_offset = min_offset;
    if (value > max_offset) value = max_offset;
    if (value < min_offset) value = min_offset;
    *predicted = value;
    return EXTERIA_OK;
}

int exteria_scroll_wants_older(double distance, double velocity, double viewport) {
    double base, asks;
    if (!is_number(distance) || !is_number(velocity) || !is_number(viewport) || viewport <= 0) return 0;
    base = viewport * ASK_SCREENS;
    if (base < ASK_FLOOR) base = ASK_FLOOR;
    asks = base;
    if (velocity < -SPEED_FLOOR) {
        double lead = fabs(velocity) * LEAD_SECONDS;
        if (lead > viewport * LEAD_SCREENS) lead = viewport * LEAD_SCREENS;
        asks = base + lead;
    } else if (velocity > SPEED_FLOOR) {
        asks = base / 2;
    }
    return distance < asks;
}

exteria_status exteria_scroll_prepare_window(double offset, double predicted, double velocity, double viewport,
                                             exteria_scroll_window *window) {
    double low, high, behind, ahead;
    int direction;
    if (window) window->min_y = window->max_y = 0;
    if (!window || !is_number(offset) || !is_number(predicted) || !is_number(velocity) || !is_number(viewport) || viewport <= 0)
        return EXTERIA_E_ARG;
    low = offset < predicted ? offset : predicted;
    high = offset > predicted ? offset : predicted;
    direction = velocity > SPEED_FLOOR ? 1 : (velocity < -SPEED_FLOOR ? -1 : 0);
    if (direction == 0) {
        behind = viewport;
        ahead = viewport;
    } else {
        behind = viewport * BEHIND_SCREENS;
        ahead = viewport * AHEAD_SCREENS;
    }
    window->min_y = low - (direction < 0 ? ahead : behind);
    window->max_y = high + viewport + (direction > 0 ? ahead : behind);
    return EXTERIA_OK;
}
