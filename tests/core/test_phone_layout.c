#include "exteria_phone_layout.h"
#include "test_util.h"

#include <math.h>

static exteria_phone_metrics metrics(double w, double h, double top, double bottom, int wide) {
    exteria_phone_metrics m;
    m.width = w;
    m.height = h;
    m.top_inset = top;
    m.bottom_inset = bottom;
    m.wide = wide;
    return m;
}

static double bottom_of(exteria_rect r) {
    return r.y + r.height;
}

static void check_geometry(const exteria_phone_metrics *m, const exteria_phone_layout *l) {
    CHECK(l->card.y >= m->top_inset + 44);
    CHECK(bottom_of(l->card) <= m->height - m->bottom_inset + 1e-9);
    CHECK(l->card.x >= 0 && l->card.x + l->card.width <= m->width + 1e-9);
    CHECK(fabs(l->card.x * 2 + l->card.width - m->width) < 1e-9);
    CHECK(fabs(bottom_of(l->country_row) - l->code_cell.y) < 1e-9);
    CHECK(fabs(l->code_cell.x + l->code_cell.width - l->number_cell.x) < 1e-9);
    CHECK(fabs(l->number_cell.x + l->number_cell.width - (l->card.x + l->card.width)) < 1e-9);
    CHECK(bottom_of(l->code_cell) == bottom_of(l->card));
    if (l->message.height > 0) {
        CHECK(l->title.y >= m->top_inset + 44);
        CHECK(bottom_of(l->title) <= l->message.y);
        CHECK(bottom_of(l->message) <= l->card.y);
    }
    if (l->art.width > 0) {
        CHECK(l->art.y >= m->top_inset + 44);
        CHECK(bottom_of(l->art) <= l->title.y);
        CHECK(fabs(l->art.x * 2 + l->art.width - m->width) < 1e-9);
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
    for (i = 0; i < sizeof(screens) / sizeof(screens[0]); ++i) {
        exteria_phone_metrics m = metrics(screens[i].w, screens[i].h, screens[i].top, screens[i].bottom,
                                          screens[i].wide);
        exteria_phone_layout l;
        CHECK_EQ_INT(exteria_phone_layout_compute(&m, &l), EXTERIA_OK);
        CHECK(l.art.width >= 72);
        CHECK(l.message.height > 0);
        check_geometry(&m, &l);
    }
}

static void keyboard_makes_room(void) {
    exteria_phone_metrics m = metrics(320, 480 - 216, 20, 0, 0);
    exteria_phone_layout l;
    /* iphone 4 with the keyboard up keeps the title and drops the sticker and the message */
    CHECK_EQ_INT(exteria_phone_layout_compute(&m, &l), EXTERIA_OK);
    CHECK_EQ_INT(l.art.width, 0);
    CHECK_EQ_INT(l.message.height, 0);
    CHECK(l.title.height > 0);
    check_geometry(&m, &l);

    /* iphone 5 keeps the sticker and gives up the message */
    m = metrics(320, 568 - 216, 20, 0, 0);
    CHECK_EQ_INT(exteria_phone_layout_compute(&m, &l), EXTERIA_OK);
    CHECK(l.art.width >= 64);
    CHECK_EQ_INT(l.message.height, 0);
    CHECK(l.title.height > 0);
    check_geometry(&m, &l);

    m = metrics(480, 320 - 162, 0, 0, 0);
    CHECK_EQ_INT(exteria_phone_layout_compute(&m, &l), EXTERIA_OK);
    CHECK_EQ_INT(l.art.width, 0);
    CHECK_EQ_INT(l.title.height, 0);
    check_geometry(&m, &l);

    m = metrics(1024, 768 - 352, 20, 0, 1);
    CHECK_EQ_INT(exteria_phone_layout_compute(&m, &l), EXTERIA_OK);
    CHECK(l.art.width >= 64);
    check_geometry(&m, &l);
}

static void too_small_still_defined(void) {
    exteria_phone_metrics m = metrics(320, 120, 0, 0, 0);
    exteria_phone_layout l;
    CHECK_EQ_INT(exteria_phone_layout_compute(&m, &l), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(l.art.width, 0);
    CHECK(l.card.width > 0 && l.card.height == 108);
    CHECK_EQ_INT(l.title.height, 0);
}

static void rejects_bad_input(void) {
    exteria_phone_layout l;
    exteria_phone_metrics m = metrics(320, 480, 0, 0, 0);
    exteria_phone_metrics bad;
    CHECK_EQ_INT(exteria_phone_layout_compute(NULL, &l), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_phone_layout_compute(&m, NULL), EXTERIA_E_ARG);
    bad = metrics(NAN, 480, 0, 0, 0);
    CHECK_EQ_INT(exteria_phone_layout_compute(&bad, &l), EXTERIA_E_ARG);
    CHECK_EQ_INT(l.card.width, 0);
    bad = metrics(320, 0, 0, 0, 0);
    CHECK_EQ_INT(exteria_phone_layout_compute(&bad, &l), EXTERIA_E_ARG);
    bad = metrics(320, 480, -1, 0, 0);
    CHECK_EQ_INT(exteria_phone_layout_compute(&bad, &l), EXTERIA_E_ARG);
    bad = metrics(320, 480, 0, INFINITY, 0);
    CHECK_EQ_INT(exteria_phone_layout_compute(&bad, &l), EXTERIA_E_ARG);
}

int main(void) {
    screens_without_keyboard();
    keyboard_makes_room();
    too_small_still_defined();
    rejects_bad_input();
    return test_finish("test_phone_layout");
}
