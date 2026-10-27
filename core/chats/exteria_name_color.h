#ifndef EXTERIA_NAME_COLOR_H
#define EXTERIA_NAME_COLOR_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_tl.h"

/* the color of a name in group chats, from the Change Name Color screen (PeerColorActivity) */

#define EXTERIA_NAME_COLOR_MAX 20
#define EXTERIA_NAME_COLORS_MAX 64

typedef struct exteria_name_color_option {
    int32_t id;
    uint32_t light;             /* 0xRRGGBB of the name on a light theme */
    uint32_t dark;              /* and on a dark one; the light color when the server gives none */
    uint8_t hidden;             /* the server keeps the color out of the list unless it is in use */
} exteria_name_color_option;

/* help.getPeerColors; the hash zero asks for the whole list */
exteria_status exteria_name_colors_request(exteria_arena *arena, exteria_tl_value **out);
/* the options of the answer, in server order, at most cap; the ones that carry no color (the profile palettes, ids
   it has no colors for) are left out */
exteria_status exteria_name_colors_parse(const exteria_tl_value *answer, exteria_name_color_option *rows, size_t cap, size_t *count);

/* account.updateColor for the name (not the profile): id 0 to EXTERIA_NAME_COLOR_MAX */
exteria_status exteria_name_color_set_request(exteria_arena *arena, int32_t id, exteria_tl_value **out);
/* the Bool it answers: EXTERIA_OK for true, EXTERIA_E_STATE for false, EXTERIA_E_MALFORMED otherwise */
exteria_status exteria_name_color_set_parse(const exteria_tl_value *answer);

#endif
