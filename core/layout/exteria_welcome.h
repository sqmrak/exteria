#ifndef EXTERIA_WELCOME_H
#define EXTERIA_WELCOME_H

#include "exteria_status.h"

#define EXTERIA_WELCOME_MAX_PAGES 16

typedef struct exteria_rect {
    double x;
    double y;
    double width;
    double height;
} exteria_rect;

typedef struct exteria_welcome_metrics {
    double width;
    double height;
    double top_inset;
    double bottom_inset;
    int wide;
    int pages;
} exteria_welcome_metrics;

typedef struct exteria_welcome_layout {
    exteria_rect art;
    exteria_rect title;
    exteria_rect message;
    exteria_rect dots;
    exteria_rect button;
    double title_size;
    double message_size;
    double button_size;
    double button_radius;
    double dot_diameter;
} exteria_welcome_layout;

/* fills out on every path; EXTERIA_E_LIMIT means the stack overflows the stage at the smallest art */
exteria_status exteria_welcome_layout_compute(const exteria_welcome_metrics *metrics,
                                              exteria_welcome_layout *out);

double exteria_pager_progress(double offset, double page_width, int pages);
int exteria_pager_page(double offset, double page_width, int pages);
double exteria_pager_dot_weight(double progress, int dot);

#endif
