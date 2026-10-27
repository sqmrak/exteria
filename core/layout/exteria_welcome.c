#include "exteria_welcome.h"

#include <math.h>
#include <string.h>

#define ART_MIN 48.0
#define DOTS_HEIGHT 12.0
/* the longest message wraps to three lines on a 320 pt screen, so every page reserves them */
#define MESSAGE_LINES 3.0
#define COMPACT_STAGE_HEIGHT 400.0
/* optical centre: the stack sits a little above the middle, as in the reference screens */
#define STACK_BIAS 0.42

typedef struct profile {
    double title_size;
    double message_size;
    double button_size;
    double button_height;
    double button_bottom;
    double stage_gap;
    double art_gap_min;
    double title_gap;
    double dots_gap;
    double dot_pitch;
    double dot_diameter;
    double button_radius;
} profile;

static const profile wide_profile = {44, 22, 22, 56, 56, 32, 16, 12, 28, 18, 9, 14};
static const profile phone_profile = {34, 17, 19, 52, 16, 16, 12, 8, 20, 14, 7, 12};
static const profile compact_profile = {28, 15, 17, 44, 12, 8, 8, 6, 12, 14, 7, 10};

static double clamp(double value, double low, double high) {
    if (value < low) return low;
    if (value > high) return high;
    return value;
}

static double positive(double value) {
    return value > 0 ? value : 0;
}

static int finite_metrics(const exteria_welcome_metrics *m) {
    return isfinite(m->width) && isfinite(m->height) && isfinite(m->top_inset) &&
           isfinite(m->bottom_inset) && m->width > 0 && m->height > 0 &&
           m->top_inset >= 0 && m->bottom_inset >= 0;
}

exteria_status exteria_welcome_layout_compute(const exteria_welcome_metrics *metrics,
                                              exteria_welcome_layout *out) {
    const profile *p;
    double usable, art_max, art, stack, avail, top, column, button_width, rest;
    double title_height, message_height, art_gap;
    exteria_status status = EXTERIA_OK;

    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!metrics || !finite_metrics(metrics)) return EXTERIA_E_ARG;
    if (metrics->pages < 1 || metrics->pages > EXTERIA_WELCOME_MAX_PAGES) return EXTERIA_E_ARG;

    usable = metrics->height - metrics->top_inset - metrics->bottom_inset;
    if (metrics->wide) p = &wide_profile;
    else p = usable < COMPACT_STAGE_HEIGHT ? &compact_profile : &phone_profile;

    button_width = metrics->wide ? fmin(positive(metrics->width - 80), 400.0)
                                 : positive(metrics->width - 28);
    out->button.width = button_width;
    out->button.height = p->button_height;
    out->button.x = (metrics->width - button_width) / 2;
    out->button.y = metrics->height - metrics->bottom_inset - p->button_bottom - p->button_height;

    title_height = ceil(p->title_size * 1.25);
    message_height = ceil(p->message_size * 1.3 * MESSAGE_LINES);
    art_max = metrics->wide ? clamp(0.28 * fmin(metrics->width, metrics->height), ART_MIN, 200.0)
                            : clamp(0.4 * metrics->width, 112.0, 176.0);

    avail = out->button.y - p->stage_gap - metrics->top_inset;
    art_gap = clamp(0.1 * art_max, p->art_gap_min, 28.0);
    rest = art_gap + title_height + p->title_gap + message_height + p->dots_gap + DOTS_HEIGHT;
    art = fmin(art_max, avail - rest);
    if (art < ART_MIN) {
        art = ART_MIN;
        status = EXTERIA_E_LIMIT;
    }
    stack = art + rest;
    top = metrics->top_inset + positive(avail - stack) * STACK_BIAS;
    column = metrics->wide ? fmin(positive(metrics->width - 64), 560.0) : positive(metrics->width - 40);

    out->art.width = out->art.height = art;
    out->art.x = (metrics->width - art) / 2;
    out->art.y = top;
    out->title.x = out->message.x = (metrics->width - column) / 2;
    out->title.width = out->message.width = column;
    out->title.y = out->art.y + art + art_gap;
    out->title.height = title_height;
    out->message.y = out->title.y + title_height + p->title_gap;
    out->message.height = message_height;
    out->dots.width = p->dot_pitch * metrics->pages;
    out->dots.height = DOTS_HEIGHT;
    out->dots.x = (metrics->width - out->dots.width) / 2;
    out->dots.y = out->message.y + message_height + p->dots_gap;
    out->title_size = p->title_size;
    out->message_size = p->message_size;
    out->button_size = p->button_size;
    out->button_radius = p->button_radius;
    out->dot_diameter = p->dot_diameter;
    return status;
}

double exteria_pager_progress(double offset, double page_width, int pages) {
    if (!isfinite(offset) || !isfinite(page_width) || page_width <= 0 || pages < 1) return 0;
    return clamp(offset / page_width, 0, pages - 1);
}

int exteria_pager_page(double offset, double page_width, int pages) {
    return (int)floor(exteria_pager_progress(offset, page_width, pages) + 0.5);
}

double exteria_pager_dot_weight(double progress, int dot) {
    double distance;
    if (!isfinite(progress)) return 0;
    distance = fabs(progress - dot);
    return distance < 1 ? 1 - distance : 0;
}
