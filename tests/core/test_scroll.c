#include "exteria_scroll.h"
#include "test_util.h"

#include <math.h>
#include <float.h>

#define VIEW 480.0

static int near(double a, double b) {
    return fabs(a - b) < 1e-6;
}

static void bottom_follows_user_intent(void) {
    const struct {
        int following, user_scrolling;
        double previous, offset, end;
        int expected;
    } cases[] = {
        /* cached and fresh history change the end without a gesture */
        {1, 0, 0, 0, 3000, 1},
        {1, 0, 3000, 3000, 9000, 1},
        /* even a short upward drag opts out of following */
        {1, 1, 3000, 2999, 3000, 0},
        {1, 1, 3000, 2940, 3000, 0},
        /* a stationary event near the end cannot undo that choice */
        {0, 1, 2940, 2940, 3000, 0},
        /* moving down near the end resumes following */
        {0, 1, 2800, 2900, 3000, 0},
        {0, 1, 2900, 2920, 3000, 1},
        {0, 1, 2990, 3000, 3000, 1},
        {1, 1, 3000, 3020, 3000, 1},
        {0, 1, 3020, 3000, 3000, 1},
        {0, 1, 3000, 3000, 3000, 1},
        /* keyboard layout and jumps to a message do not opt back in */
        {0, 0, 2940, 3000, 3000, 0},
        {0, 0, 2940, 2724, 2784, 0},
        {1, 0, 3000, 3000, 3216, 1},
        {1, 1, NAN, 3000, 3000, 1},
        {0, 1, 0, INFINITY, 3000, 0},
        {0, 1, 0, 100, NAN, 0}
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        CHECK_EQ_INT(exteria_scroll_tracks_bottom(cases[i].following, cases[i].user_scrolling,
                                                  cases[i].previous, cases[i].offset, cases[i].end), cases[i].expected);
    }
}

static void keyboard_preserves_reading_position(void) {
    double next = 0;
    CHECK_EQ_INT(exteria_scroll_resize(1000, 480, 264, -6, 3000, &next), EXTERIA_OK);
    CHECK(near(next, 1216));
    CHECK_EQ_INT(exteria_scroll_resize(next, 264, 480, -6, 2784, &next), EXTERIA_OK);
    CHECK(near(next, 1000));
    /* UIKit would clamp 2940 to 2784 on expansion; the captured 2940 gives 2724, not 2568 */
    CHECK_EQ_INT(exteria_scroll_resize(2940, 264, 480, -6, 2784, &next), EXTERIA_OK);
    CHECK(near(next, 2724));
    CHECK_EQ_INT(exteria_scroll_resize(-6, 480, 480, -6, 2784, &next), EXTERIA_OK);
    CHECK(near(next, -6));
    CHECK_EQ_INT(exteria_scroll_resize(0, 264, 480, -6, 2784, &next), EXTERIA_OK);
    CHECK(near(next, -6));
    CHECK_EQ_INT(exteria_scroll_resize(3000, 480, 264, -6, 3100, &next), EXTERIA_OK);
    CHECK(near(next, 3100));
    CHECK_EQ_INT(exteria_scroll_resize(0, 264, 480, -6, -100, &next), EXTERIA_OK);
    CHECK(near(next, -6));
    CHECK_EQ_INT(exteria_scroll_resize(0, 0, 480, -6, -100, &next), EXTERIA_OK);
    CHECK(near(next, -6));
    CHECK_EQ_INT(exteria_scroll_resize(NAN, 480, 264, -6, 3000, &next), EXTERIA_E_ARG);
    CHECK(near(next, 0));
    CHECK_EQ_INT(exteria_scroll_resize(0, -1, 264, -6, 3000, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_resize(0, 480, -1, -6, 3000, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_resize(0, INFINITY, 264, -6, 3000, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_resize(0, 480, 264, NAN, 3000, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_resize(0, 480, 264, -6, INFINITY, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_resize(DBL_MAX, DBL_MAX, 0, -6, 3000, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_resize(0, 480, 264, -6, 3000, NULL), EXTERIA_E_ARG);
}

static void speed_follows_the_finger(void) {
    exteria_scroll_state s;
    CHECK_EQ_INT(exteria_scroll_begin(&s, 1000, 10.0), EXTERIA_OK);
    CHECK(near(s.velocity, 0));
    /* 10 points in 10 ms is 1000 points per second, 60 percent of it enters at once */
    CHECK_EQ_INT(exteria_scroll_sample(&s, 1010, 10.01, VIEW), EXTERIA_OK);
    CHECK(near(s.velocity, 600));
    CHECK_EQ_INT(exteria_scroll_sample(&s, 1020, 10.02, VIEW), EXTERIA_OK);
    CHECK(near(s.velocity, 600 * 0.4 + 1000 * 0.6));
    /* moving the other way turns the sign */
    for (int i = 0; i < 40; ++i) exteria_scroll_sample(&s, 1020 - 10 * (i + 1), 10.02 + 0.01 * (i + 1), VIEW);
    CHECK(s.velocity < -900);
}

static void gaps_and_jumps_reset(void) {
    exteria_scroll_state s;
    exteria_scroll_begin(&s, 0, 1.0);
    exteria_scroll_sample(&s, 10, 1.01, VIEW);
    CHECK(s.velocity > 0);
    /* a quarter second of silence is no movement */
    exteria_scroll_sample(&s, 20, 1.30, VIEW);
    CHECK(near(s.velocity, 0));
    CHECK(near(s.last_offset, 20));
    exteria_scroll_sample(&s, 30, 1.31, VIEW);
    CHECK(s.velocity > 0);
    /* a jump of two screens is a scroll to a row, not a swipe */
    exteria_scroll_sample(&s, 30 + VIEW * 2, 1.32, VIEW);
    CHECK(near(s.velocity, 0));
    CHECK(near(s.last_offset, 30 + VIEW * 2));
    /* a clock that went back must not freeze the sampling */
    exteria_scroll_sample(&s, 1100, 0.5, VIEW);
    CHECK(near(s.velocity, 0));
    CHECK(near(s.last_time, 0.5));
    exteria_scroll_sample(&s, 1110, 0.51, VIEW);
    CHECK(s.velocity > 0);
}

static void close_events_keep_the_base(void) {
    exteria_scroll_state s;
    exteria_scroll_begin(&s, 0, 1.0);
    exteria_scroll_sample(&s, 5, 1.001, VIEW);
    CHECK(near(s.velocity, 0));
    CHECK(near(s.last_offset, 0));
    CHECK(near(s.last_time, 1.0));
    exteria_scroll_sample(&s, 5, 1.0, VIEW);
    CHECK(near(s.velocity, 0));
}

static void first_event_only_sets_the_base(void) {
    exteria_scroll_state s;
    s.velocity = 99;
    s.last_offset = 0;
    s.last_time = 0;
    s.sampled = 0;
    CHECK_EQ_INT(exteria_scroll_sample(&s, 40, 5.0, VIEW), EXTERIA_OK);
    CHECK(s.sampled);
    CHECK(near(s.last_offset, 40));
    CHECK(near(s.velocity, 99));
}

static void prediction(void) {
    exteria_scroll_state s;
    double p = -1;
    exteria_scroll_begin(&s, 0, 0);
    s.velocity = 1000;
    CHECK_EQ_INT(exteria_scroll_predict(&s, 500, VIEW, 0, 0, 0, 5000, &p), EXTERIA_OK);
    CHECK(near(p, 500 + 180));
    /* held to three screens either way */
    s.velocity = 100000;
    exteria_scroll_predict(&s, 500, VIEW, 0, 0, 0, 50000, &p);
    CHECK(near(p, 500 + VIEW * 3));
    s.velocity = -100000;
    exteria_scroll_predict(&s, 5000, VIEW, 0, 0, 0, 50000, &p);
    CHECK(near(p, 5000 - VIEW * 3));
    /* the end point of the system wins over the speed, and the list limits hold */
    s.velocity = 1000;
    exteria_scroll_predict(&s, 500, VIEW, 1, 1234, 0, 5000, &p);
    CHECK(near(p, 1234));
    exteria_scroll_predict(&s, 500, VIEW, 1, 9000, 0, 5000, &p);
    CHECK(near(p, 5000));
    exteria_scroll_predict(&s, 500, VIEW, 1, -80, -64, 5000, &p);
    CHECK(near(p, -64));
    /* a list shorter than its view */
    exteria_scroll_predict(&s, 0, VIEW, 0, 0, -64, -100, &p);
    CHECK(near(p, -64));
}

static void asks_for_older_rows(void) {
    /* at rest: two screens, never less than 640 points */
    CHECK(exteria_scroll_wants_older(900, 0, VIEW));
    CHECK(!exteria_scroll_wants_older(960, 0, VIEW));
    CHECK(exteria_scroll_wants_older(639, 0, 100));
    CHECK(!exteria_scroll_wants_older(640, 0, 100));
    /* toward the old rows the ask comes earlier the faster the list moves */
    CHECK(!exteria_scroll_wants_older(1000, -50, VIEW));
    CHECK(exteria_scroll_wants_older(1000, -1000, VIEW));
    CHECK(!exteria_scroll_wants_older(960 + 350 + 1, -1000, VIEW));
    /* the lead stops at four screens however fast the fling */
    CHECK(exteria_scroll_wants_older(960 + VIEW * 4 - 1, -1e9, VIEW));
    CHECK(!exteria_scroll_wants_older(960 + VIEW * 4 + 1, -1e9, VIEW));
    /* away from them it waits for half the distance */
    CHECK(exteria_scroll_wants_older(479, 1000, VIEW));
    CHECK(!exteria_scroll_wants_older(481, 1000, VIEW));
    /* nothing to compare is no reason to load */
    CHECK(!exteria_scroll_wants_older(NAN, 0, VIEW));
    CHECK(!exteria_scroll_wants_older(0, INFINITY, VIEW));
    CHECK(!exteria_scroll_wants_older(0, 0, 0));
    CHECK(!exteria_scroll_wants_older(0, 0, -5));
}

static void prepare_window(void) {
    exteria_scroll_window w;
    /* resting: a screen on each side of the view */
    CHECK_EQ_INT(exteria_scroll_prepare_window(1000, 1000, 0, VIEW, &w), EXTERIA_OK);
    CHECK(near(w.min_y, 1000 - VIEW));
    CHECK(near(w.max_y, 1000 + VIEW * 2));
    /* toward larger offsets the span reaches far below and little above */
    exteria_scroll_prepare_window(1000, 1300, 800, VIEW, &w);
    CHECK(near(w.min_y, 1000 - VIEW * 0.8));
    CHECK(near(w.max_y, 1300 + VIEW + VIEW * 2.5));
    /* and the other way round */
    exteria_scroll_prepare_window(1000, 700, -800, VIEW, &w);
    CHECK(near(w.min_y, 700 - VIEW * 2.5));
    CHECK(near(w.max_y, 1000 + VIEW + VIEW * 0.8));
    /* a prediction behind the speed's direction still covers both ends */
    exteria_scroll_prepare_window(1000, 900, 800, VIEW, &w);
    CHECK(w.min_y <= 900 && w.max_y >= 1000 + VIEW);
}

static void rejects_bad_input(void) {
    exteria_scroll_state s;
    exteria_scroll_window w;
    double p = 7;
    CHECK_EQ_INT(exteria_scroll_begin(NULL, 0, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_begin(&s, NAN, 0), EXTERIA_E_ARG);
    CHECK(!s.sampled);
    CHECK_EQ_INT(exteria_scroll_sample(NULL, 0, 0, VIEW), EXTERIA_E_ARG);
    exteria_scroll_begin(&s, 0, 1);
    CHECK_EQ_INT(exteria_scroll_sample(&s, 0, 2, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_sample(&s, INFINITY, 2, VIEW), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_sample(&s, 0, NAN, VIEW), EXTERIA_E_ARG);
    CHECK(near(s.last_time, 1));
    CHECK_EQ_INT(exteria_scroll_predict(NULL, 0, VIEW, 0, 0, 0, 1, &p), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_predict(&s, 0, VIEW, 0, 0, 0, 1, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_predict(&s, 0, 0, 0, 0, 0, 1, &p), EXTERIA_E_ARG);
    CHECK(near(p, 0));
    CHECK_EQ_INT(exteria_scroll_predict(&s, 0, VIEW, 1, NAN, 0, 1, &p), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_predict(&s, 0, VIEW, 0, NAN, 0, 1, &p), EXTERIA_OK);
    CHECK_EQ_INT(exteria_scroll_prepare_window(0, 0, 0, 0, &w), EXTERIA_E_ARG);
    CHECK(near(w.min_y, 0) && near(w.max_y, 0));
    CHECK_EQ_INT(exteria_scroll_prepare_window(0, 0, 0, VIEW, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_prepare_window(NAN, 0, 0, VIEW, &w), EXTERIA_E_ARG);
}

static void follows_a_moving_end(void) {
    double fast = 0, slow = 0, next = 0;
    for (int i = 0; i < 30; ++i) {
        CHECK_EQ_INT(exteria_scroll_follow(fast, 500, 1.0 / 60, &next), EXTERIA_OK);
        CHECK(next >= fast && next <= 500);
        fast = next;
    }
    for (int i = 0; i < 15; ++i) {
        CHECK_EQ_INT(exteria_scroll_follow(slow, 500, 1.0 / 30, &next), EXTERIA_OK);
        slow = next;
    }
    CHECK(near(fast, slow));
    double target = 500;
    for (int i = 0; i < 120; ++i) {
        target += 8;
        CHECK_EQ_INT(exteria_scroll_follow(fast, target, 1.0 / 60, &next), EXTERIA_OK);
        CHECK(next > fast && next < target);
        fast = next;
    }
    for (int i = 0; i < 60; ++i) {
        CHECK_EQ_INT(exteria_scroll_follow(fast, target, 1.0 / 60, &fast), EXTERIA_OK);
    }
    CHECK(near(fast, target));
    CHECK_EQ_INT(exteria_scroll_follow(100, 50, 1.0 / 60, &next), EXTERIA_OK);
    CHECK(next < 100 && next > 50);
    CHECK_EQ_INT(exteria_scroll_follow(50.4, 50, 1.0 / 60, &next), EXTERIA_OK);
    CHECK(near(next, 50));
    CHECK_EQ_INT(exteria_scroll_follow(50, 100, 0, &next), EXTERIA_E_ARG);
    CHECK(near(next, 0));
    CHECK_EQ_INT(exteria_scroll_follow(NAN, 100, 0.1, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_follow(50, INFINITY, 0.1, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_follow(50, 100, NAN, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_follow(50, 100, -1, &next), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_scroll_follow(DBL_MAX, -DBL_MAX, 0.1, &next), EXTERIA_E_ARG);
    CHECK(near(next, 0));
    CHECK_EQ_INT(exteria_scroll_follow(50, 100, 0.1, NULL), EXTERIA_E_ARG);
}

int main(void) {
    bottom_follows_user_intent();
    keyboard_preserves_reading_position();
    follows_a_moving_end();
    speed_follows_the_finger();
    gaps_and_jumps_reset();
    close_events_keep_the_base();
    first_event_only_sets_the_base();
    prediction();
    asks_for_older_rows();
    prepare_window();
    rejects_bad_input();
    return test_finish("test_scroll");
}
