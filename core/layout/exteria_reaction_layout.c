#include "exteria_reaction_layout.h"

#include <math.h>
#include <string.h>

#include "exteria_reactions.h"

exteria_status exteria_reaction_menu_stack(double top, double bottom, double bubble_top, double bubble_bottom, double pill_height,
                                           double card_height, double gap, double *pill_y, double *card_y, double *bubble_shift) {
    double pill_start, card_start, shift;
    if (pill_y) *pill_y = 0;
    if (card_y) *card_y = 0;
    if (bubble_shift) *bubble_shift = 0;
    if (!pill_y || !card_y || !bubble_shift || !isfinite(top) || !isfinite(bottom) || !isfinite(bubble_top) || !isfinite(bubble_bottom) ||
        !isfinite(pill_height) || !isfinite(card_height) || !isfinite(gap) || pill_height < 0 || card_height < 0 || gap < 0 ||
        bubble_bottom < bubble_top || bottom - top < pill_height + gap + card_height) return EXTERIA_E_ARG;
    pill_start = bubble_top - gap - pill_height;
    card_start = bubble_bottom + gap;
    /* a message too near the top comes down to make room for the pill; one too near the bottom goes up for the card, but never past the pill's room at the top */
    shift = pill_start < top ? top - pill_start : fmin(0, bottom - card_height - card_start);
    if (pill_start + shift < top) shift = top - pill_start;
    *pill_y = pill_start + shift;
    *card_y = fmin(card_start + shift, bottom - card_height);
    *bubble_shift = shift;
    return EXTERIA_OK;
}

exteria_status exteria_reaction_layout_compute(double width, double scale, const double *chip_widths, size_t count,
                                               exteria_rect *frames, size_t cap, double *height) {
    size_t i;
    double x = 0, y = 0, min_width, chip, pitch, gap;
    if (height) *height = 0;
    if (frames && cap <= EXTERIA_REACTION_CATALOG_MAX) memset(frames, 0, cap * sizeof(*frames));
    if (!height || !isfinite(width) || !isfinite(scale) || scale < 0.5 || scale > 2 || width < 44 * scale || count > EXTERIA_REACTION_CATALOG_MAX ||
        cap < count || cap > EXTERIA_REACTION_CATALOG_MAX || (count && (!chip_widths || !frames))) return EXTERIA_E_ARG;
    min_width = 44 * scale;
    chip = 36 * scale;
    pitch = 40 * scale;
    gap = 4 * scale;
    for (i = 0; i < count; ++i)
        if (!isfinite(chip_widths[i]) || chip_widths[i] < 0) return EXTERIA_E_ARG;
    for (i = 0; i < count; ++i) {
        double w = chip_widths[i] < min_width ? min_width : chip_widths[i];
        if (w > width) w = width;
        if (x > 0 && x + w > width) { x = 0; y += pitch; }
        frames[i].x = x;
        frames[i].y = y;
        frames[i].width = w;
        frames[i].height = chip;
        x += w + gap;
    }
    *height = count ? y + chip : 0;
    return EXTERIA_OK;
}
