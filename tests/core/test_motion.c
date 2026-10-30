#include "exteria_motion.h"
#include "test_util.h"

#include <math.h>

static int near(double a, double b) {
    return fabs(a - b) < 1e-7;
}

static void reference_curves(void) {
    /* bezier parameter 0.5 gives these exact x and y coordinates */
    CHECK(near(exteria_motion_progress(EXTERIA_MOTION_ENTER, 0.33125), 0.875));
    CHECK(near(exteria_motion_progress(EXTERIA_MOTION_EXIT, 0.6575), 0.5));
    for (int curve = EXTERIA_MOTION_ENTER; curve <= EXTERIA_MOTION_DISMISS; ++curve) {
        exteria_motion_curve kind = (exteria_motion_curve)curve;
        CHECK(near(exteria_motion_progress(kind, -1), 0));
        CHECK(near(exteria_motion_progress(kind, 0), 0));
        CHECK(near(exteria_motion_progress(kind, 1), 1));
        CHECK(near(exteria_motion_progress(kind, 2), 1));
        CHECK(near(exteria_motion_progress(kind, NAN), 0));
        CHECK(near(exteria_motion_progress(kind, INFINITY), 0));
        CHECK(near(exteria_motion_progress(kind, -INFINITY), 0));
        double previous = 0;
        for (int sample = 1; sample <= 1000; ++sample) {
            double progress = exteria_motion_progress(kind, sample / 1000.0);
            CHECK(isfinite(progress));
            CHECK(progress >= 0 && progress < 1.1);
            if (kind != EXTERIA_MOTION_SPRING) {
                CHECK(progress >= previous);
                CHECK(progress <= 1);
            }
            previous = progress;
        }
    }
}

static void navigation_decelerates(void) {
    CHECK(near(exteria_motion_duration(EXTERIA_MOTION_NAVIGATION), 0.32));
    CHECK(near(exteria_motion_progress(EXTERIA_MOTION_NAVIGATION, 0.25), 0.578125));
    CHECK(near(exteria_motion_progress(EXTERIA_MOTION_NAVIGATION, 0.5), 0.875));
    CHECK(near(exteria_motion_progress(EXTERIA_MOTION_NAVIGATION, 0.75), 0.984375));
    double previous_step = 1;
    for (int sample = 1; sample <= 100; ++sample) {
        double previous = exteria_motion_progress(EXTERIA_MOTION_NAVIGATION, (sample - 1) / 100.0);
        double current = exteria_motion_progress(EXTERIA_MOTION_NAVIGATION, sample / 100.0);
        double step = current - previous;
        CHECK(step > 0 && step <= previous_step);
        previous_step = step;
    }
    CHECK(1 - exteria_motion_progress(EXTERIA_MOTION_NAVIGATION, 0.99) < 0.000002);
}

/* the move and add curve of ChatListItemAnimator: 250 ms, fast at the start, no overshoot */
static void list_move_curve(void) {
    CHECK(near(exteria_motion_duration(EXTERIA_MOTION_LIST_MOVE), 0.25));
    CHECK(exteria_motion_progress(EXTERIA_MOTION_LIST_MOVE, 0.5) > 0.7);
    CHECK(exteria_motion_progress(EXTERIA_MOTION_LIST_MOVE, 0.5) < 1);
    for (int sample = 1; sample <= 100; ++sample) {
        CHECK(exteria_motion_progress(EXTERIA_MOTION_LIST_MOVE, sample / 100.0) <= 1);
    }
}

static void spring_settles(void) {
    double duration = exteria_motion_duration(EXTERIA_MOTION_SPRING);
    double peak = 3.14159265358979323846 / (sqrt(650.0) * 0.8);
    double progress = exteria_motion_progress(EXTERIA_MOTION_SPRING, peak / duration);
    CHECK(progress > 1.09 && progress < 1.1);
    /* the normalized spring must reach its model value without a visible final snap */
    CHECK(fabs(exteria_motion_progress(EXTERIA_MOTION_SPRING, 0.999999) - 1) < 1e-6);
    CHECK(exteria_motion_progress(EXTERIA_MOTION_ENTER, 0.25) > 0.7);
    CHECK(exteria_motion_progress(EXTERIA_MOTION_EXIT, 0.25) < 0.1);
    CHECK(near(exteria_motion_duration(EXTERIA_MOTION_ENTER), 0.32));
    CHECK(near(exteria_motion_duration(EXTERIA_MOTION_EXIT), 0.18));
    /* a dismissal is well on its way after a tenth of its time, where the slow start of EXIT has hardly moved */
    CHECK(near(exteria_motion_duration(EXTERIA_MOTION_DISMISS), 0.2));
    CHECK(exteria_motion_progress(EXTERIA_MOTION_DISMISS, 0.1) > 0.15);
    CHECK(near(exteria_motion_progress(EXTERIA_MOTION_DISMISS, 1.0), 1.0));
    CHECK(near(duration, 0.48));
    CHECK(near(exteria_motion_duration((exteria_motion_curve)-1), 0));
    CHECK(near(exteria_motion_progress((exteria_motion_curve)-1, 1), 0));
}

static void playback_uses_elapsed_time(void) {
    const int rates[] = {25, 30, 60};
    for (unsigned int i = 0; i < sizeof(rates) / sizeof(rates[0]); ++i) {
        double elapsed = 0, previous = 10;
        for (int frame = 1; frame <= rates[i]; ++frame) {
            double now = 10 + (double)frame / rates[i];
            elapsed = exteria_motion_elapsed(elapsed, previous, now, 0);
            previous = now;
        }
        CHECK(near(elapsed, 1));
    }
    CHECK(near(exteria_motion_elapsed(1, 10, 10.3, 0), 1.3));
    CHECK(near(exteria_motion_elapsed(1, 10, 50, 1), 1));
    CHECK(near(exteria_motion_elapsed(1, 10, 9, 0), 1));
    CHECK(near(exteria_motion_elapsed(1, NAN, 11, 0), 1));
    CHECK(near(exteria_motion_elapsed(1, 10, INFINITY, 0), 1));
    CHECK(near(exteria_motion_elapsed(NAN, 10, 10, 0), 0));
    CHECK(near(exteria_motion_elapsed(-1, 10, 10, 0), 0));
}

static void outgoing_screen_memory(void) {
    const double screens[][3] = {{320, 480, 1}, {320, 480, 2}, {375, 667, 2}, {414, 736, 3}, {768, 1024, 2}, {1024, 768, 2}, {8192, 16, 3}};
    for (unsigned int i = 0; i < sizeof(screens) / sizeof(screens[0]); ++i) {
        double width = screens[i][0], height = screens[i][1], requested = screens[i][2];
        double scale = exteria_motion_snapshot_scale(width, height, requested);
        CHECK(scale > 0 && scale <= requested);
        CHECK(ceil(width * scale) * ceil(height * scale) <= 1048576);
        CHECK(near(scale, exteria_motion_snapshot_scale(height, width, requested)));
    }
    CHECK(near(exteria_motion_snapshot_scale(320, 480, 2), 2));
    CHECK(near(exteria_motion_snapshot_scale(0, 480, 2), 0));
    CHECK(near(exteria_motion_snapshot_scale(320, -1, 2), 0));
    CHECK(near(exteria_motion_snapshot_scale(NAN, 480, 2), 0));
    CHECK(near(exteria_motion_snapshot_scale(320, INFINITY, 2), 0));
    CHECK(near(exteria_motion_snapshot_scale(320, 480, NAN), 0));
    CHECK(near(exteria_motion_snapshot_scale(320, 480, 0), 0));
    CHECK(near(exteria_motion_snapshot_scale(8193, 480, 2), 0));
}

static void reply_swipe_direction(void) {
    CHECK(exteria_motion_reply_swipe_begins(-90, 20));
    CHECK(!exteria_motion_reply_swipe_begins(90, 20));
    CHECK(!exteria_motion_reply_swipe_begins(-20, 30));
    CHECK(!exteria_motion_reply_swipe_begins(-60, 20));
    CHECK(exteria_motion_reply_swipe_begins(-61, 20));
    CHECK(!exteria_motion_reply_swipe_begins(0, 0));
    CHECK(!exteria_motion_reply_swipe_begins(NAN, 0));
    CHECK(near(exteria_motion_reply_swipe_pull(-75), 75));
    CHECK(near(exteria_motion_reply_swipe_pull(-80), 80));
    CHECK(near(exteria_motion_reply_swipe_pull(-1000), 80));
    CHECK(near(exteria_motion_reply_swipe_pull(75), 0));
    CHECK(near(exteria_motion_reply_swipe_pull(NAN), 0));
}

static void back_swipe_settles_from_finger(void) {
    const struct {
        double width, translation, velocity;
        int ended, completes;
        double progress, duration;
    } cases[] = {
        {320, 0, 0, 1, 0, 0, 0},
        {320, -20, 0, 1, 0, 0, 0},
        {320, 80, 0, 1, 0, 0.25, 0.08},
        {320, 160, 0, 1, 1, 0.5, 0.125},
        {320, 300, 0, 1, 1, 0.9375, 0.08},
        {320, 400, 0, 1, 1, 1, 0},
        {320, 80, 800, 1, 1, 0.25, 0.1875},
        {320, 160, 2000, 1, 1, 0.5, 0.08},
        {320, 160, -800, 1, 0, 0.5, 0.125},
        {320, 160, -600, 1, 0, 0.5, 0.125},
        {320, 160, -599, 1, 1, 0.5, 0.125},
        {320, 80, 600, 1, 0, 0.25, 0.08},
        {320, 80, 601, 1, 1, 0.25, 0.1875},
        {320, 160, 800, 0, 0, 0.5, 0.125},
        {320, 320, 800, 0, 0, 1, 0.25},
        {768, 384, 0, 1, 1, 0.5, 0.125},
        {320, 160, NAN, 1, 1, 0.5, 0.125},
        {0, 160, 800, 1, 0, 0, 0},
        {-320, 160, 800, 1, 0, 0, 0},
        {NAN, 160, 800, 1, 0, 0, 0},
        {INFINITY, 160, 800, 1, 0, 0, 0},
        {320, INFINITY, 800, 1, 0, 0, 0},
        {320, NAN, 800, 1, 0, 0, 0}
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        exteria_motion_swipe plan = exteria_motion_back_swipe(cases[i].width, cases[i].translation,
                                                            cases[i].velocity, cases[i].ended);
        CHECK_EQ_INT(plan.completes, cases[i].completes);
        CHECK(near(plan.progress, cases[i].progress));
        CHECK(near(plan.duration, cases[i].duration));
    }
}

static void ambient_phase_survives_rebuild(void) {
    const double periods[] = {7, 9, 3.2, 4};
    for (size_t i = 0; i < sizeof(periods) / sizeof(periods[0]); ++i) {
        double seconds = periods[i];
        CHECK(near(exteria_motion_alternating(0, seconds), 0));
        CHECK(near(exteria_motion_alternating(seconds, seconds), 1));
        CHECK(near(exteria_motion_alternating(seconds * 2, seconds), 0));
        CHECK(near(exteria_motion_alternating(seconds / 2, seconds), 0.5));
        for (int frame = 0; frame < 100; ++frame) {
            double time = frame / 60.0;
            CHECK(near(exteria_motion_alternating(time, seconds), exteria_motion_alternating(time + seconds * 2, seconds)));
        }
    }
    CHECK(near(exteria_motion_alternating(NAN, 7), 0));
    CHECK(near(exteria_motion_alternating(INFINITY, 7), 0));
    CHECK(near(exteria_motion_alternating(-1, 7), 0));
    CHECK(near(exteria_motion_alternating(1, 0), 0));
    CHECK(near(exteria_motion_alternating(1, NAN), 0));
    CHECK(near(exteria_motion_alternating(1, 3601), 0));
}

int main(void) {
    reference_curves();
    navigation_decelerates();
    spring_settles();
    list_move_curve();
    playback_uses_elapsed_time();
    outgoing_screen_memory();
    reply_swipe_direction();
    back_swipe_settles_from_finger();
    ambient_phase_survives_rebuild();
    return test_finish("test_motion");
}
