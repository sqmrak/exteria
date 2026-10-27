#include "exteria_motion.h"

#include <math.h>

static double cubic(double t, double first, double second) {
    double inverse = 1.0 - t;
    return 3.0 * inverse * inverse * t * first + 3.0 * inverse * t * t * second + t * t * t;
}

static double bezier(double time, double x1, double y1, double x2, double y2) {
    double lower = 0.0, upper = 1.0;
    /* bisection stays bounded where a bezier endpoint has zero derivative */
    for (int i = 0; i < 32; ++i) {
        double middle = (lower + upper) * 0.5;
        if (cubic(middle, x1, x2) < time) lower = middle;
        else upper = middle;
    }
    return cubic((lower + upper) * 0.5, y1, y2);
}

double exteria_motion_duration(exteria_motion_curve curve) {
    switch (curve) {
    case EXTERIA_MOTION_ENTER: return 0.32;
    case EXTERIA_MOTION_EXIT: return 0.18;
    case EXTERIA_MOTION_SPRING: return 0.48;
    case EXTERIA_MOTION_NAVIGATION: return 0.32;
    case EXTERIA_MOTION_LIST_MOVE: return 0.25;
    }
    return 0.0;
}

static double spring(double seconds) {
    /* ActionBarLayout preview: stiffness 650, damping ratio 0.6, unit mass */
    double frequency = sqrt(650.0), damping = 0.6;
    double decay = frequency * damping;
    double oscillation = frequency * sqrt(1.0 - damping * damping);
    return 1.0 - exp(-decay * seconds) *
        (cos(oscillation * seconds) + decay / oscillation * sin(oscillation * seconds));
}

double exteria_motion_progress(exteria_motion_curve curve, double time) {
    if (exteria_motion_duration(curve) == 0.0) return 0.0;
    if (!isfinite(time) || time <= 0.0) return 0.0;
    if (time >= 1.0) return 1.0;
    switch (curve) {
    /* CubicBezierInterpolator.EASE_OUT_QUINT and EASE_IN */
    case EXTERIA_MOTION_ENTER: return bezier(time, 0.23, 1.0, 0.32, 1.0);
    case EXTERIA_MOTION_EXIT: return bezier(time, 0.42, 0.0, 1.0, 1.0);
    case EXTERIA_MOTION_SPRING:
        return spring(time * exteria_motion_duration(curve)) / spring(exteria_motion_duration(curve));
    case EXTERIA_MOTION_NAVIGATION: {
        /* uses DecelerateInterpolator(1.5) for opening and closing screens */
        double remaining = 1.0 - time;
        return 1.0 - remaining * remaining * remaining;
    }
    /* ChatListItemAnimator: DEFAULT_DURATION 250 ms with its DEFAULT_INTERPOLATOR, for rows that move and rows
       that are added */
    case EXTERIA_MOTION_LIST_MOVE: return bezier(time, 0.19919472913616398, 0.010644531250000006, 0.27920937042459737, 0.91025390625);
    }
    return 0.0;
}

double exteria_motion_elapsed(double elapsed, double previous, double now, int paused) {
    if (!isfinite(elapsed) || elapsed < 0) elapsed = 0;
    if (paused || !isfinite(previous) || !isfinite(now) || now < previous) return elapsed;
    double next = elapsed + (now - previous);
    return isfinite(next) ? next : elapsed;
}

double exteria_motion_snapshot_scale(double width, double height, double display_scale) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(display_scale) ||
        width <= 0 || height <= 0 || width > 8192 || height > 8192 || display_scale <= 0) return 0;
    /* UIGraphics rounds each pixel dimension up */
    double area = width * height, edges = width + height;
    double bounded = 2 * 1048575.0 / (sqrt(edges * edges + 4 * area * 1048575.0) + edges);
    return display_scale < bounded ? display_scale : bounded;
}

int exteria_motion_reply_swipe_begins(double velocity_x, double velocity_y) {
    return isfinite(velocity_x) && isfinite(velocity_y) && velocity_x < 0 && -velocity_x > fabs(velocity_y) * 1.5;
}

double exteria_motion_reply_swipe_pull(double translation_x) {
    return isfinite(translation_x) && translation_x < 0 ? -translation_x : 0;
}

exteria_motion_swipe exteria_motion_back_swipe(double width, double translation, double velocity, int ended) {
    exteria_motion_swipe result = {0, 0, 0};
    if (!isfinite(width) || width <= 0 || !isfinite(translation)) return result;
    if (!isfinite(velocity)) velocity = 0;
    result.progress = fmax(0, fmin(1, translation / width));
    result.completes = ended && velocity > -600 && (result.progress > 0.33 || velocity > 600);
    double distance = result.completes ? 1 - result.progress : result.progress;
    if (distance == 0) return result;
    double toward = result.completes ? velocity : -velocity;
    double speed = fmax(width / 0.25, toward);
    result.duration = fmax(0.08, fmin(0.25, distance * (width / speed)));
    return result;
}

double exteria_motion_alternating(double time, double seconds) {
    if (!isfinite(time) || time < 0 || !isfinite(seconds) || seconds <= 0 || seconds > 3600) return 0;
    double phase = fmod(time, seconds * 2) / seconds;
    if (phase > 1) phase = 2 - phase;
    return bezier(phase, 0.42, 0.0, 0.58, 1.0);
}
