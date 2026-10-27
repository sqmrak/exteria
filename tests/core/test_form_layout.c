#include "exteria_form_layout.h"
#include "test_util.h"

#include <math.h>

static exteria_form_metrics metrics(double w, double h, double top, double bottom, int wide, int rows) {
    exteria_form_metrics m;
    m.width = w;
    m.height = h;
    m.top_inset = top;
    m.bottom_inset = bottom;
    m.wide = wide;
    m.rows = rows;
    return m;
}

static double bottom_of(exteria_rect r) {
    return r.y + r.height;
}

static void check_geometry(const exteria_form_metrics *m, const exteria_form_layout *l) {
    int i;
    CHECK(l->card.y >= m->top_inset + 44);
    CHECK(bottom_of(l->card) <= m->height - m->bottom_inset + 1e-9);
    if (l->action.height > 0) {
        CHECK(bottom_of(l->action) <= m->height - m->bottom_inset + 1e-9);
        CHECK(bottom_of(l->card) <= l->error.y);
        CHECK(bottom_of(l->error) <= l->action.y + 1e-9);
    } else {
        CHECK_EQ_INT(l->error.height, 0);
    }
    CHECK(l->card.x >= 0 && l->card.x + l->card.width <= m->width + 1e-9);
    CHECK(fabs(l->card.x * 2 + l->card.width - m->width) < 1e-9);
    CHECK(fabs(l->rows[0].y - l->card.y) < 1e-9);
    for (i = 1; i < m->rows; ++i) CHECK(fabs(bottom_of(l->rows[i - 1]) - l->rows[i].y) < 1e-9);
    CHECK(fabs(bottom_of(l->rows[m->rows - 1]) - bottom_of(l->card)) < 1e-9);
    for (i = m->rows; i < EXTERIA_FORM_MAX_ROWS; ++i) CHECK_EQ_INT(l->rows[i].height, 0);
    if (l->art.height > 0) {
        CHECK(l->art.height >= 56 && fabs(l->art.width - l->art.height) < 1e-9);
        CHECK(l->art.y >= m->top_inset + 44);
        CHECK(fabs(l->art.x * 2 + l->art.width - m->width) < 1e-9);
        CHECK(bottom_of(l->art) <= l->card.y);
        if (l->title.height > 0) CHECK(bottom_of(l->art) <= l->title.y);
    }
    if (l->title.height > 0) CHECK(l->art.height > 0);
    if (l->message.height > 0) {
        CHECK(l->title.height > 0);
        CHECK(bottom_of(l->title) <= l->message.y);
        CHECK(bottom_of(l->message) <= l->card.y);
    }
    if (l->title.height > 0) {
        CHECK(l->title.y >= m->top_inset + 44);
        CHECK(bottom_of(l->title) <= l->card.y);
    }
}

static void screens_without_keyboard(void) {
    static const struct {
        double w, h, top, bottom;
        int wide;
    } screens[] = {
        {320, 460, 0, 0, 0}, {320, 480, 20, 0, 0}, {375, 667, 20, 0, 0}, {414, 896, 44, 34, 0},
        {768, 1004, 0, 0, 1}, {1024, 768, 20, 0, 1}, {1366, 1024, 24, 20, 1}, {320, 1024, 20, 0, 1}
    };
    size_t i;
    int rows;
    for (i = 0; i < sizeof(screens) / sizeof(screens[0]); ++i) {
        for (rows = 1; rows <= EXTERIA_FORM_MAX_ROWS; ++rows) {
            exteria_form_metrics m = metrics(screens[i].w, screens[i].h, screens[i].top, screens[i].bottom,
                                             screens[i].wide, rows);
            exteria_form_layout l;
            CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_OK);
            CHECK(l.art.height > 0);
            CHECK(l.action.height >= 36);
            /* a short screen drops the text before the sticker, a tall one keeps everything */
            if (screens[i].h >= 667 && rows <= 2) {
                CHECK(l.title.height > 0);
                CHECK(l.message.height > 0);
            }
            check_geometry(&m, &l);
        }
    }
}

static void keyboard_makes_room(void) {
    exteria_form_layout l;
    exteria_form_metrics m = metrics(320, 480 - 216, 20, 0, 0, 1);
    /* iphone 4 with the keyboard up keeps the sticker, the card, the error and the action; the text goes */
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_OK);
    CHECK(l.art.height >= 56);
    CHECK_EQ_INT(l.title.height, 0);
    CHECK_EQ_INT(l.message.height, 0);
    CHECK(l.action.height > 0);
    check_geometry(&m, &l);

    /* a name form with two rows has no room for the sticker on that screen, but keeps its action */
    m = metrics(320, 480 - 216, 20, 0, 0, 2);
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_OK);
    CHECK_EQ_INT(l.art.height, 0);
    CHECK(l.action.height > 0);
    check_geometry(&m, &l);

    /* iphone 5 with the keyboard keeps the sticker and the title */
    m = metrics(320, 568 - 216, 20, 0, 0, 1);
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_OK);
    CHECK(l.art.height >= 56);
    check_geometry(&m, &l);

    /* a phone in landscape under its keyboard has room for the card alone */
    m = metrics(480, 320 - 162, 0, 0, 0, 1);
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_OK);
    CHECK_EQ_INT(l.action.height, 0);
    CHECK_EQ_INT(l.title.height, 0);
    CHECK_EQ_INT(l.art.height, 0);
    check_geometry(&m, &l);
}

static void too_small_reports_limit(void) {
    exteria_form_layout l;
    exteria_form_metrics m = metrics(320, 150, 20, 0, 0, 3);
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_E_LIMIT);
    CHECK(l.card.height > 0);
}

static void rejects_bad_input(void) {
    exteria_form_layout l;
    exteria_form_metrics m = metrics(320, 480, 0, 0, 0, 1);
    CHECK_EQ_INT(exteria_form_layout_compute(NULL, &l), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_form_layout_compute(&m, NULL), EXTERIA_E_ARG);
    m.rows = 0;
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_E_ARG);
    CHECK_EQ_INT(l.card.height, 0);
    m.rows = EXTERIA_FORM_MAX_ROWS + 1;
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_E_ARG);
    m = metrics(0, 480, 0, 0, 0, 1);
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_E_ARG);
    m = metrics(320, 480, -1, 0, 0, 1);
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_E_ARG);
    m = metrics(NAN, 480, 0, 0, 0, 1);
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_E_ARG);
}

static void wide_card_is_capped(void) {
    exteria_form_layout l;
    exteria_form_metrics m = metrics(1366, 1024, 24, 20, 1, 1);
    CHECK_EQ_INT(exteria_form_layout_compute(&m, &l), EXTERIA_OK);
    CHECK_EQ_INT(l.card.width, 460);
}

int main(void) {
    screens_without_keyboard();
    keyboard_makes_room();
    too_small_reports_limit();
    rejects_bad_input();
    wide_card_is_capped();
    if (g_failures) {
        fprintf(stderr, "test_form_layout: %d of %d checks failed\n", g_failures, g_checks);
        return 1;
    }
    printf("test_form_layout: %d checks passed\n", g_checks);
    return 0;
}
