#ifndef EXTERIA_PHONE_LAYOUT_H
#define EXTERIA_PHONE_LAYOUT_H

#include "exteria_welcome.h"

typedef struct exteria_phone_metrics {
    double width;
    double height;
    double top_inset;
    double bottom_inset;
    int wide;
} exteria_phone_metrics;

typedef struct exteria_phone_layout {
    exteria_rect back;
    exteria_rect next;
    exteria_rect art;
    exteria_rect title;
    exteria_rect message;
    exteria_rect card;
    exteria_rect country_row;
    exteria_rect code_cell;
    exteria_rect number_cell;
    double title_size;
    double message_size;
    double field_size;
    double bar_size;
    double card_radius;
    double flag_width;
    double flag_height;
} exteria_phone_layout;

/* height is what is left above the keyboard; the sticker, then the text, make room for the card first.
   fills out on every path; EXTERIA_E_LIMIT means even the bare card does not fit */
exteria_status exteria_phone_layout_compute(const exteria_phone_metrics *metrics,
                                            exteria_phone_layout *out);

#endif
