#include "exteria_welcome.h"
#include "test_util.h"

#include <math.h>

static exteria_welcome_metrics metrics(double w, double h, double top, double bottom, int wide) {
    exteria_welcome_metrics m;
    m.width = w;
    m.height = h;
    m.top_inset = top;
    m.bottom_inset = bottom;
    m.wide = wide;
    m.pages = 6;
    return m;
}

static double bottom_of(exteria_rect r) {
    return r.y + r.height;
}

static void check_stack(const exteria_welcome_metrics *m, const exteria_welcome_layout *l) {
    CHECK(l->art.y >= m->top_inset);
    CHECK(bottom_of(l->art) <= l->title.y);
    CHECK(bottom_of(l->title) <= l->message.y);
    CHECK(bottom_of(l->message) <= l->dots.y);
    CHECK(bottom_of(l->dots) <= l->button.y);
    CHECK(bottom_of(l->button) <= m->height - m->bottom_inset);
    CHECK(l->button.x >= 0 && l->button.x + l->button.width <= m->width);
    CHECK(l->title.x >= 0 && l->title.x + l->title.width <= m->width);
    CHECK(l->dots.x >= 0 && l->dots.x + l->dots.width <= m->width);
    CHECK(fabs(l->art.x * 2 + l->art.width - m->width) < 1e-9);
    CHECK(fabs(l->dots.x * 2 + l->dots.width - m->width) < 1e-9);
    CHECK(fabs(l->button.x * 2 + l->button.width - m->width) < 1e-9);
}

static void supported_screens(void) {
    static const struct {
        double w, h, top, bottom;
        int wide;
    } screens[] = {
        {320, 460, 0, 0, 0},      /* iphone 4 portrait on ios 5, status bar outside the view */
        {320, 480, 20, 0, 0},     /* same screen on ios 7 */
        {320, 568, 20, 0, 0},
        {375, 667, 20, 0, 0},
        {414, 896, 44, 34, 0},
        {430, 932, 59, 34, 0},
        {480, 300, 0, 0, 0},      /* iphone 4 landscape on ios 5 */
        {568, 320, 0, 0, 0},
        {844, 390, 0, 21, 0},
        {768, 1004, 0, 0, 1},     /* ipad portrait on ios 5 */
        {1024, 768, 20, 0, 1},
        {834, 1194, 24, 20, 1},
        {1366, 1024, 24, 20, 1},
        {320, 1024, 20, 0, 1},    /* ipad slide over */
        {507, 768, 20, 0, 1}      /* ipad split view */
    };
    size_t i;
    for (i = 0; i < sizeof(screens) / sizeof(screens[0]); ++i) {
        exteria_welcome_metrics m = metrics(screens[i].w, screens[i].h, screens[i].top,
                                            screens[i].bottom, screens[i].wide);
        exteria_welcome_layout l;
        CHECK_EQ_INT(exteria_welcome_layout_compute(&m, &l), EXTERIA_OK);
        CHECK(l.art.width >= 48 && l.art.width == l.art.height);
        CHECK(l.art.width <= 200);
        check_stack(&m, &l);
        if (screens[i].wide) CHECK(l.button.width <= 400);
        else CHECK(l.button.width == m.width - 28);
    }
}

static void reference_proportions(void) {
    exteria_welcome_metrics m = metrics(320, 460, 0, 0, 0);
    exteria_welcome_layout l;
    CHECK_EQ_INT(exteria_welcome_layout_compute(&m, &l), EXTERIA_OK);
    /* the 320 pt reference screen shows a 127 pt icon, 14 pt button margins and a 52 pt button */
    CHECK(fabs(l.art.width - 128) < 1);
    CHECK_EQ_INT(l.button.x, 14);
    CHECK_EQ_INT(l.button.height, 52);
    CHECK(l.dots.y > l.message.y && l.dots.y - bottom_of(l.message) == 20);
}

static void too_small_still_defined(void) {
    exteria_welcome_metrics m = metrics(320, 200, 0, 0, 0);
    exteria_welcome_layout l;
    CHECK_EQ_INT(exteria_welcome_layout_compute(&m, &l), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(l.art.width, 48);
    CHECK_EQ_INT(l.art.y, 0);
    CHECK(l.button.width == 292);
}

static void rejects_bad_input(void) {
    exteria_welcome_layout l;
    exteria_welcome_metrics m = metrics(320, 480, 0, 0, 0);
    exteria_welcome_metrics bad;
    CHECK_EQ_INT(exteria_welcome_layout_compute(NULL, &l), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_welcome_layout_compute(&m, NULL), EXTERIA_E_ARG);
    bad = metrics(NAN, 480, 0, 0, 0);
    CHECK_EQ_INT(exteria_welcome_layout_compute(&bad, &l), EXTERIA_E_ARG);
    CHECK_EQ_INT(l.button.width, 0);
    bad = metrics(320, INFINITY, 0, 0, 0);
    CHECK_EQ_INT(exteria_welcome_layout_compute(&bad, &l), EXTERIA_E_ARG);
    bad = metrics(0, 480, 0, 0, 0);
    CHECK_EQ_INT(exteria_welcome_layout_compute(&bad, &l), EXTERIA_E_ARG);
    bad = metrics(320, -1, 0, 0, 0);
    CHECK_EQ_INT(exteria_welcome_layout_compute(&bad, &l), EXTERIA_E_ARG);
    bad = metrics(320, 480, -1, 0, 0);
    CHECK_EQ_INT(exteria_welcome_layout_compute(&bad, &l), EXTERIA_E_ARG);
    bad = m;
    bad.pages = 0;
    CHECK_EQ_INT(exteria_welcome_layout_compute(&bad, &l), EXTERIA_E_ARG);
    bad.pages = EXTERIA_WELCOME_MAX_PAGES + 1;
    CHECK_EQ_INT(exteria_welcome_layout_compute(&bad, &l), EXTERIA_E_ARG);
    bad.pages = EXTERIA_WELCOME_MAX_PAGES;
    CHECK_EQ_INT(exteria_welcome_layout_compute(&bad, &l), EXTERIA_OK);
}

static void pager_progress_and_page(void) {
    CHECK(exteria_pager_progress(-40, 320, 6) == 0);
    CHECK(exteria_pager_progress(160, 320, 6) == 0.5);
    CHECK(exteria_pager_progress(1600, 320, 6) == 5);
    CHECK(exteria_pager_progress(99999, 320, 6) == 5);
    CHECK(exteria_pager_progress(100, 0, 6) == 0);
    CHECK(exteria_pager_progress(100, -5, 6) == 0);
    CHECK(exteria_pager_progress(NAN, 320, 6) == 0);
    CHECK(exteria_pager_progress(100, 320, 0) == 0);
    CHECK_EQ_INT(exteria_pager_page(159, 320, 6), 0);
    CHECK_EQ_INT(exteria_pager_page(160, 320, 6), 1);
    CHECK_EQ_INT(exteria_pager_page(-300, 320, 6), 0);
    CHECK_EQ_INT(exteria_pager_page(5000, 320, 6), 5);
    CHECK_EQ_INT(exteria_pager_page(320, 320, 1), 0);
}

static void pager_dot_weight(void) {
    CHECK(exteria_pager_dot_weight(2.0, 2) == 1.0);
    CHECK(exteria_pager_dot_weight(2.25, 2) == 0.75);
    CHECK(exteria_pager_dot_weight(2.25, 3) == 0.25);
    CHECK(exteria_pager_dot_weight(2.0, 3) == 0.0);
    CHECK(exteria_pager_dot_weight(2.0, 0) == 0.0);
    CHECK(exteria_pager_dot_weight(NAN, 0) == 0.0);
}

int main(void) {
    supported_screens();
    reference_proportions();
    too_small_still_defined();
    rejects_bad_input();
    pager_progress_and_page();
    pager_dot_weight();
    return test_finish("test_welcome");
}
