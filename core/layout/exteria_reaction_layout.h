#ifndef EXTERIA_REACTION_LAYOUT_H
#define EXTERIA_REACTION_LAYOUT_H

#include <stddef.h>
#include "exteria_welcome.h"

/* chips wrap at the host width, each remains a full height touch target. scale resizes a chip, its gaps and its
   smallest width together, one for the size at rest */
exteria_status exteria_reaction_layout_compute(double width, double scale, const double *chip_widths, size_t count,
                                               exteria_rect *frames, size_t cap, double *height);

/* positions the reaction pill and the menu below the visible message, moving the message up if needed */
exteria_status exteria_reaction_menu_stack(double top, double bottom, double bubble_bottom, double pill_height,
                                           double card_height, double gap, double *pill_y, double *card_y, double *bubble_shift);

#endif
