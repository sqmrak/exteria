#ifndef EXTERIA_FORM_LAYOUT_H
#define EXTERIA_FORM_LAYOUT_H

#include "exteria_welcome.h"

#define EXTERIA_FORM_MAX_ROWS 3

typedef struct exteria_form_metrics {
    double width;
    double height;
    double top_inset;
    double bottom_inset;
    int wide;
    int rows;
} exteria_form_metrics;

typedef struct exteria_form_layout {
    exteria_rect back;
    exteria_rect next;
    exteria_rect art;
    exteria_rect title;
    exteria_rect message;
    exteria_rect card;
    exteria_rect rows[EXTERIA_FORM_MAX_ROWS];
    exteria_rect error;
    exteria_rect action;
    double title_size;
    double message_size;
    double field_size;
    double note_size;
    double bar_size;
    double card_radius;
} exteria_form_layout;

/* the code, password and name screens: an animated sticker, a title, a message, a card of one to three fields, an
   error line and one action under it. height is what is left above the keyboard */
exteria_status exteria_form_layout_compute(const exteria_form_metrics *metrics, exteria_form_layout *out);

#endif
