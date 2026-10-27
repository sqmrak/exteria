#include "exteria_form_layout.h"

#include <math.h>
#include <string.h>

#define BAR_HEIGHT 44.0
#define ART_MIN 56.0
/* the message wraps to three lines at the narrowest width, the error to two when there is room */
#define MESSAGE_LINES 3.0
#define NOTE_LINES 2.0

typedef struct profile {
    double title_size;
    double message_size;
    double field_size;
    double note_size;
    double row_height;
    double card_radius;
    double side_margin;
    double title_gap;
    double card_gap;
    double note_gap;
    double action_height;
    double compact_gap;
    double compact_action;
    double top_gap;
    double art_max;
    double art_gap;
} profile;

static const profile wide_profile = {34, 19, 21, 16, 62, 16, 32, 12, 24, 10, 44, 4, 36, 16, 160, 14};
static const profile phone_profile = {28, 16, 19, 14, 54, 12, 16, 8, 18, 8, 44, 2, 28, 8, 120, 10};

static double positive(double value) {
    return value > 0 ? value : 0;
}

static exteria_rect rect(double x, double y, double width, double height) {
    exteria_rect r;
    r.x = x;
    r.y = y;
    r.width = width;
    r.height = height;
    return r;
}

exteria_status exteria_form_layout_compute(const exteria_form_metrics *metrics, exteria_form_layout *out) {
    const profile *p;
    double title_height, message_height, card_height, note_height, foot, gap, action, avail, stack, top, art, base;
    double card_width, card_x, content_top, bar_top;
    int show_art, show_title, show_message, i;
    exteria_status status = EXTERIA_OK;

    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!metrics || !isfinite(metrics->width) || !isfinite(metrics->height) || !isfinite(metrics->top_inset) ||
        !isfinite(metrics->bottom_inset) || metrics->width <= 0 || metrics->height <= 0 ||
        metrics->top_inset < 0 || metrics->bottom_inset < 0 ||
        metrics->rows < 1 || metrics->rows > EXTERIA_FORM_MAX_ROWS) return EXTERIA_E_ARG;

    p = metrics->wide ? &wide_profile : &phone_profile;
    bar_top = metrics->top_inset;
    content_top = bar_top + BAR_HEIGHT;
    title_height = ceil(p->title_size * 1.25);
    message_height = ceil(p->message_size * 1.3 * MESSAGE_LINES);
    note_height = ceil(p->note_size * 1.3 * NOTE_LINES);
    card_height = p->row_height * metrics->rows;
    card_width = metrics->wide ? fmin(positive(metrics->width - 2 * p->side_margin), 460.0)
                               : positive(metrics->width - 2 * p->side_margin);
    card_x = (metrics->width - card_width) / 2;
    avail = metrics->height - metrics->bottom_inset - content_top - p->top_gap;

    /* the error and the action shrink before the sticker goes, and vanish before the card does: each size
       is tried first with room for the sticker, then without */
    {
        double full_gap = p->note_gap, full_note = note_height, full_action = p->action_height;
        double small_gap = p->compact_gap, small_note = note_height, small_action = p->compact_action;
        double room = ART_MIN + p->art_gap;
        if (card_height + full_gap + full_note + full_action + room <= avail) {
            gap = full_gap; note_height = full_note; action = full_action;
        } else if (card_height + small_gap + small_note + small_action + room <= avail) {
            gap = small_gap; note_height = small_note; action = small_action;
        } else if (card_height + full_gap + full_note + full_action <= avail) {
            gap = full_gap; note_height = full_note; action = full_action;
        } else if (card_height + small_gap + small_note + small_action <= avail) {
            gap = small_gap; note_height = small_note; action = small_action;
        } else {
            gap = 0; note_height = 0; action = 0;
        }
        foot = gap + note_height + action;
    }
    base = card_height + foot;
    art = fmin(p->art_max, avail - base - p->art_gap);
    show_art = art >= ART_MIN;
    if (show_art) base += art + p->art_gap;
    else art = 0;
    show_title = avail >= base + title_height + p->title_gap + p->card_gap;
    show_message = show_title && avail >= base + title_height + p->title_gap + message_height + p->card_gap;
    stack = base;
    if (show_title) stack += title_height + p->title_gap + p->card_gap;
    if (show_message) stack += message_height;
    if (stack > avail) status = EXTERIA_E_LIMIT;
    top = content_top + p->top_gap + positive(avail - stack) * 0.25;

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
    for (i = 0; i < metrics->rows; ++i) out->rows[i] = rect(card_x, top + i * p->row_height, card_width, p->row_height);
    top += card_height + gap;
    if (note_height > 0) {
        out->error = rect(card_x, top, card_width, note_height);
        out->action = rect(card_x, top + note_height, card_width, action);
    }
    out->title_size = p->title_size;
    out->message_size = p->message_size;
    out->field_size = p->field_size;
    out->note_size = p->note_size;
    out->bar_size = 17;
    out->card_radius = p->card_radius;
    return status;
}
