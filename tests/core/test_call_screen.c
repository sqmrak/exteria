#include "exteria_call_screen.h"
#include "test_util.h"

#include <math.h>

typedef struct size_case {
    double width;
    double height;
    double top;
    double bottom;
} size_case;

/* iphone 4 and 5 on ios 5 and 6 (no insets), iphone 6 and x on ios 7 and later, both landscape, two ipad sizes */
static const size_case sizes[] = {
    {320, 460, 0, 0}, {320, 548, 0, 0}, {375, 667, 20, 0}, {414, 896, 44, 34},
    {480, 300, 0, 0}, {568, 300, 0, 0}, {812, 375, 0, 21}, {768, 1004, 20, 0}, {1024, 748, 20, 0}
};

static double bottom_of(exteria_rect r) { return r.y + r.height; }

static int inside(exteria_rect r, const exteria_call_screen_metrics *m) {
    return r.x >= -1e-9 && r.y >= m->top_inset - 1e-9 && r.x + r.width <= m->width + 1e-9 &&
           bottom_of(r) <= m->height - m->bottom_inset + 1e-9;
}

static int overlaps(exteria_rect a, exteria_rect b) {
    return a.x < b.x + b.width && b.x < a.x + a.width && a.y < bottom_of(b) && bottom_of(b) > a.y && b.y < bottom_of(a);
}

static void check_one(const size_case *s, int incoming, int count, int video) {
    exteria_call_screen_metrics m;
    exteria_call_screen_layout l;
    int i;
    m.width = s->width;
    m.height = s->height;
    m.top_inset = s->top;
    m.bottom_inset = s->bottom;
    m.incoming = incoming;
    m.button_count = count;
    m.video = video;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_OK);
    CHECK_EQ_INT(l.button_count, incoming ? 2 : count);
    CHECK(inside(l.avatar, &m));
    CHECK(inside(l.title, &m));
    CHECK(inside(l.status, &m));
    CHECK(inside(l.emoji, &m));
    CHECK(inside(l.card, &m));
    CHECK(fabs(l.avatar.x * 2 + l.avatar.width - m.width) < 1e-9);
    CHECK_EQ_INT(l.avatar.width == l.avatar.height, 1);
    CHECK(l.avatar.width >= 72 && l.avatar.width <= 180);
    CHECK(bottom_of(l.title) <= l.status.y);
    if (!video) {
        CHECK(bottom_of(l.avatar) <= l.title.y);
    } else if (m.width > m.height) {
        /* a wide screen puts the name left of the pill */
        CHECK(l.title.x + l.title.width <= l.emoji.x);
        CHECK(l.title.y >= m.top_inset);
    } else {
        CHECK(l.title.y >= bottom_of(l.emoji));
    }
    CHECK(inside(l.preview, &m));
    CHECK(l.preview.x + l.preview.width <= m.width - 16 + 1e-9);
    CHECK(m.width > m.height ? l.preview.width > l.preview.height : l.preview.width < l.preview.height);
    CHECK(!overlaps(l.preview, l.emoji));
    CHECK(!overlaps(l.emoji, l.avatar));
    for (i = 0; i < l.button_count; ++i) {
        CHECK(inside(l.buttons[i], &m));
        CHECK(inside(l.captions[i], &m));
        CHECK(l.buttons[i].width == l.buttons[i].height);
        CHECK(bottom_of(l.status) <= l.buttons[i].y);
        CHECK(bottom_of(l.buttons[i]) <= l.captions[i].y);
        CHECK(!overlaps(l.buttons[i], l.avatar));
        CHECK(!overlaps(l.buttons[i], l.preview));
        CHECK(!overlaps(l.captions[i], l.preview));
        if (i > 0) CHECK(l.buttons[i].x >= l.buttons[i - 1].x + l.buttons[i - 1].width);
    }
    if (!incoming) {
        /* the row is centered whatever the count */
        double left = l.buttons[0].x, right = m.width - (l.buttons[count - 1].x + l.buttons[count - 1].width);
        CHECK(fabs(left - right) < 1e-9);
    }
}

static void every_screen_every_phase(void) {
    size_t i;
    int count;
    for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
        check_one(&sizes[i], 1, 2, 0);
        for (count = 1; count <= EXTERIA_CALL_SCREEN_MAX_BUTTONS; ++count) {
            check_one(&sizes[i], 0, count, 0);
            check_one(&sizes[i], 0, count, 1);
        }
    }
}

static void phone_portrait_values(void) {
    exteria_call_screen_metrics m = {320, 548, 0, 0, 0, 3, 0};
    exteria_call_screen_layout l;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_OK);
    CHECK(l.avatar.width == 135);
    CHECK(l.buttons[0].width == 52);
    /* three slots of 104 points: the row is narrower than the screen */
    CHECK(fabs(l.buttons[1].x + 26 - 160) < 1e-9);
    m.incoming = 1;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_OK);
    CHECK(l.buttons[0].width == 64);
    CHECK(fabs(l.buttons[0].x + 32 - 80) < 1e-9);
    CHECK(fabs(l.buttons[1].x + 32 - 240) < 1e-9);
}

static void too_small_still_defined(void) {
    exteria_call_screen_metrics m = {200, 120, 0, 0, 0, 3, 0};
    exteria_call_screen_layout l;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_OK);
    CHECK(l.avatar.width == 72);
    CHECK(l.button_count == 3);
}

static void rejects_bad_input(void) {
    exteria_call_screen_metrics m = {320, 480, 0, 0, 0, 3, 0};
    exteria_call_screen_layout l;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(NULL, &l), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, NULL), EXTERIA_E_ARG);
    m.button_count = 0;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_E_ARG);
    CHECK(l.button_count == 0 && l.avatar.width == 0);
    m.button_count = EXTERIA_CALL_SCREEN_MAX_BUTTONS + 1;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_E_ARG);
    m.button_count = 3;
    m.width = 0;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_E_ARG);
    m.width = NAN;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_E_ARG);
    m.width = 320;
    m.bottom_inset = INFINITY;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_E_ARG);
    m.bottom_inset = -1;
    CHECK_EQ_INT(exteria_call_screen_layout_compute(&m, &l), EXTERIA_E_ARG);
}

static void moods(void) {
    uint32_t light[4], dark[4], none[4];
    int mood;
    for (mood = 0; mood < EXTERIA_CALL_MOOD_COUNT; ++mood) {
        CHECK_EQ_INT(exteria_call_mood_colors((exteria_call_mood)mood, 0, light), EXTERIA_OK);
        CHECK_EQ_INT(exteria_call_mood_colors((exteria_call_mood)mood, 1, dark), EXTERIA_OK);
        CHECK(memcmp(light, dark, sizeof(light)) != 0);
        CHECK(light[0] <= 0xFFFFFF && dark[3] <= 0xFFFFFF);
    }
    CHECK_EQ_INT(exteria_call_mood_colors(EXTERIA_CALL_MOOD_CONNECTING, 0, light), EXTERIA_OK);
    CHECK(light[0] == 0xB456D8 && light[2] == 0x20A4D7);
    CHECK_EQ_INT(exteria_call_mood_colors(EXTERIA_CALL_MOOD_COUNT, 0, none), EXTERIA_E_ARG);
    CHECK(none[0] == 0);
    CHECK_EQ_INT(exteria_call_mood_colors((exteria_call_mood)-1, 0, none), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_mood_colors(EXTERIA_CALL_MOOD_TALKING, 0, NULL), EXTERIA_E_ARG);
}

static void mesh(void) {
    uint8_t px[4 * 3 * 4];
    uint8_t big[(EXTERIA_CALL_MESH_MAX_SIDE + 1) * 2 * 4];
    const uint32_t colors[4] = {0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF};
    /* corners are the colors exactly: top left, top right, bottom right, bottom left */
    CHECK_EQ_INT(exteria_call_mesh_fill(px, sizeof(px), 4, 3, colors), EXTERIA_OK);
    CHECK(px[0] == 0xFF && px[1] == 0 && px[2] == 0 && px[3] == 0xFF);
    CHECK(px[3 * 4] == 0 && px[3 * 4 + 1] == 0xFF && px[3 * 4 + 2] == 0);
    CHECK(px[(2 * 4 + 3) * 4] == 0 && px[(2 * 4 + 3) * 4 + 2] == 0xFF);
    CHECK(px[(2 * 4) * 4] == 0xFF && px[(2 * 4) * 4 + 1] == 0xFF && px[(2 * 4) * 4 + 2] == 0xFF);
    /* the middle row of a two column map averages the corners above and below each edge: red with white on the left,
       green with blue on the right */
    CHECK_EQ_INT(exteria_call_mesh_fill(px, sizeof(px), 2, 3, colors), EXTERIA_OK);
    CHECK(px[2 * 4] == 0xFF && px[2 * 4 + 1] == 0x80 && px[2 * 4 + 2] == 0x80);
    CHECK(px[3 * 4] == 0 && px[3 * 4 + 1] == 0x80 && px[3 * 4 + 2] == 0x80);
    CHECK_EQ_INT(exteria_call_mesh_fill(px, sizeof(px) - 1, 4, 3, colors), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_call_mesh_fill(px, sizeof(px), 1, 3, colors), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_mesh_fill(px, sizeof(px), 4, 0, colors), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_mesh_fill(big, sizeof(big), EXTERIA_CALL_MESH_MAX_SIDE + 1, 2, colors), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_mesh_fill(NULL, 1, 2, 2, colors), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_mesh_fill(px, sizeof(px), 2, 2, NULL), EXTERIA_E_ARG);
}

int main(void) {
    every_screen_every_phase();
    phone_portrait_values();
    too_small_still_defined();
    rejects_bad_input();
    moods();
    mesh();
    return test_finish("test_call_screen");
}
