#ifndef EXTERIA_CALL_SCREEN_H
#define EXTERIA_CALL_SCREEN_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_welcome.h"

/* the geometry of the call screen and the colors behind it, kept out of UIKit so a table of screen sizes can check
   them */

#define EXTERIA_CALL_SCREEN_MAX_BUTTONS 4
#define EXTERIA_CALL_MESH_MAX_SIDE 64

typedef struct exteria_call_screen_metrics {
    double width;
    double height;
    double top_inset;
    double bottom_inset;
    /* an incoming call shows two answer buttons (decline, accept); any other phase shows button_count control
       buttons from 1 to EXTERIA_CALL_SCREEN_MAX_BUTTONS, the last of them the one that ends the call */
    int incoming;
    int button_count;
    /* the picture of the other side fills the screen: the name and the status move to the top, out of the way of the picture */
    int video;
} exteria_call_screen_metrics;

typedef struct exteria_call_screen_layout {
    exteria_rect avatar;
    exteria_rect title;
    exteria_rect status;
    /* the pill with the four emoji of the key, and the card that explains them when the pill is tapped */
    exteria_rect emoji;
    exteria_rect card;
    /* the small view of the own camera, above the row of buttons at the right edge */
    exteria_rect preview;
    int button_count;
    exteria_rect buttons[EXTERIA_CALL_SCREEN_MAX_BUTTONS];
    exteria_rect captions[EXTERIA_CALL_SCREEN_MAX_BUTTONS];
    double title_size;
    double status_size;
    double caption_size;
} exteria_call_screen_layout;

/* fills out on every path; EXTERIA_E_ARG for a size that is not finite and positive or a button count out of
   range; a screen too small for everything still gets a defined layout */
exteria_status exteria_call_screen_layout_compute(const exteria_call_screen_metrics *metrics,
                                                  exteria_call_screen_layout *out);

typedef enum exteria_call_mood {
    EXTERIA_CALL_MOOD_CONNECTING,   /* blue to violet: ringing, key exchange, connecting */
    EXTERIA_CALL_MOOD_TALKING,      /* blue to green: the audio is up */
    EXTERIA_CALL_MOOD_WEAK,         /* orange to red: the link broke while talking */
    EXTERIA_CALL_MOOD_COUNT
} exteria_call_mood;

/* the four colors of a mood as 0xRRGGBB: top left, top right, bottom right, bottom left. dark picks the muted set the
   classic theme uses */
exteria_status exteria_call_mood_colors(exteria_call_mood mood, int dark, uint32_t out[4]);

/* a width by height RGBA bitmap that blends the four corner colors bilinearly; every side from 2 to
   EXTERIA_CALL_MESH_MAX_SIDE; capacity is the size of rgba in bytes and must hold width * height * 4 */
exteria_status exteria_call_mesh_fill(uint8_t *rgba, size_t capacity, int width, int height, const uint32_t colors[4]);

#endif
