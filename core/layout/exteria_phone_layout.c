#include "exteria_phone_layout.h"

#include <math.h>
#include <string.h>

#define BAR_HEIGHT 44.0
#define ART_MIN 64.0
/* the message wraps to two lines at the narrowest width */
#define MESSAGE_LINES 2.0

typedef struct profile {
    double title_size;
    double message_size;
    double field_size;
    double row_height;
    double card_radius;
    double code_width;
    double side_margin;
    double art_max;
    double art_gap;
    double title_gap;
    double card_gap;
    double top_gap;
    double flag_width;
    double flag_height;
} profile;

static const profile wide_profile = {34, 19, 21, 62, 16, 96, 32, 180, 18, 12, 32, 16, 34, 24};
static const profile phone_profile = {28, 16, 19, 54, 12, 78, 16, 128, 14, 8, 24, 8, 28, 20};

static double positive(double value) {
    return value > 0 ? value : 0;
}

static int finite_metrics(const exteria_phone_metrics *m) {
    return isfinite(m->width) && isfinite(m->height) && isfinite(m->top_inset) &&
           isfinite(m->bottom_inset) && m->width > 0 && m->height > 0 &&
           m->top_inset >= 0 && m->bottom_inset >= 0;
}

static exteria_rect rect(double x, double y, double width, double height) {
    exteria_rect r;
    r.x = x;
    r.y = y;
    r.width = width;
    r.height = height;
    return r;
}

exteria_status exteria_phone_layout_compute(const exteria_phone_metrics *metrics,
                                            exteria_phone_layout *out) {
    const profile *p;
    double title_height, message_height, card_height, art, avail, stack, top, card_width, card_x;
    double bar_top, content_top, content_bottom;
    int show_art, show_title, show_message;
    double top_gap, base;
    exteria_status status = EXTERIA_OK;

    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!metrics || !finite_metrics(metrics)) return EXTERIA_E_ARG;

    p = metrics->wide ? &wide_profile : &phone_profile;
    bar_top = metrics->top_inset;
    content_top = bar_top + BAR_HEIGHT;
    content_bottom = metrics->height - metrics->bottom_inset;
    top_gap = p->top_gap;
    avail = content_bottom - content_top - top_gap;
    title_height = ceil(p->title_size * 1.25);
    message_height = ceil(p->message_size * 1.3 * MESSAGE_LINES);
    card_height = p->row_height * 2;
    card_width = metrics->wide ? fmin(positive(metrics->width - 2 * p->side_margin), 460.0)
                               : positive(metrics->width - 2 * p->side_margin);
    card_x = (metrics->width - card_width) / 2;

    /* the keyboard takes the message first so the sticker stays; then the sticker, then the title */
    base = card_height + p->card_gap + title_height + p->title_gap;
    show_title = avail >= base;
    show_message = 0;
    art = 0;
    if (show_title) {
        double with_message = fmin(p->art_max, avail - base - message_height - p->art_gap);
        double without_message = fmin(p->art_max, avail - base - p->art_gap);
        if (with_message >= ART_MIN) {
            art = with_message;
            show_message = 1;
        } else if (without_message >= ART_MIN) {
            art = without_message;
        } else if (avail >= base + message_height) {
            show_message = 1;
        }
    }
    show_art = art >= ART_MIN;
    stack = card_height;
    if (show_title) stack += p->card_gap + title_height + p->title_gap;
    if (show_message) stack += message_height;
    if (show_art) stack += art + p->art_gap;
    if (!show_title) {
        /* the card alone may use the gap above it as well */
        top_gap = 0;
        avail += p->top_gap;
        if (card_height > avail) status = EXTERIA_E_LIMIT;
    }
    top = content_top + top_gap + positive(avail - stack) * 0.25;

    out->back = rect(0, bar_top, 96, BAR_HEIGHT);
    out->next = rect(metrics->width - 96, bar_top, 96, BAR_HEIGHT);
    if (show_art) {
        out->art = rect((metrics->width - art) / 2, top, art, art);
        top += art + p->art_gap;
    }
    if (show_title) {
        out->title = rect(card_x, top, card_width, title_height);
        top += title_height + p->title_gap;
    }
    if (show_message) {
        out->message = rect(card_x, top, card_width, message_height);
        top += message_height;
    }
    if (show_title) top += p->card_gap;
    out->card = rect(card_x, top, card_width, card_height);
    out->country_row = rect(card_x, top, card_width, p->row_height);
    out->code_cell = rect(card_x, top + p->row_height, fmin(p->code_width, card_width), p->row_height);
    out->number_cell = rect(card_x + out->code_cell.width, top + p->row_height,
                            positive(card_width - out->code_cell.width), p->row_height);
    out->title_size = p->title_size;
    out->message_size = p->message_size;
    out->field_size = p->field_size;
    out->bar_size = 17;
    out->card_radius = p->card_radius;
    out->flag_width = p->flag_width;
    out->flag_height = p->flag_height;
    return status;
}
