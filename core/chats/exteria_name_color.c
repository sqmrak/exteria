#include "exteria_name_color.h"

#include <string.h>

#include "exteria_tl_ids.h"

exteria_status exteria_name_colors_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "help.getPeerColors");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* the first color of a help.peerColorSet, as 0xRRGGBB; EXTERIA_E_NOTFOUND when the set is of another kind or has none */
static exteria_status first_color(const exteria_tl_value *set, uint32_t *color) {
    const exteria_tl_value *list = NULL;
    if (!exteria_tl_is(set, EXTERIA_TL_ID_help_peerColorSet) || exteria_tl_get_vec(set, "colors", &list) != EXTERIA_OK || list->u.vec.count == 0 ||
        !list->u.vec.items[0] || list->u.vec.items[0]->kind != EXTERIA_TL_V_I32) return EXTERIA_E_NOTFOUND;
    *color = (uint32_t)list->u.vec.items[0]->u.i32 & 0xFFFFFFu;
    return EXTERIA_OK;
}

exteria_status exteria_name_colors_parse(const exteria_tl_value *answer, exteria_name_color_option *rows, size_t cap, size_t *count) {
    const exteria_tl_value *options = NULL;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!answer || !rows || !cap || !count) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_help_peerColorsNotModified)) return EXTERIA_OK;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_help_peerColors) || exteria_tl_get_vec(answer, "colors", &options) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (options->u.vec.count > cap) return EXTERIA_E_LIMIT;
    for (i = 0; i < options->u.vec.count; ++i) {
        const exteria_tl_value *option = options->u.vec.items[i];
        exteria_name_color_option row;
        int32_t id = 0;
        memset(&row, 0, sizeof(row));
        if (!exteria_tl_is(option, EXTERIA_TL_ID_help_peerColorOption) || exteria_tl_get_i32(option, "color_id", &id) != EXTERIA_OK || id < 0 ||
            id > EXTERIA_NAME_COLOR_MAX) continue;
        if (first_color(exteria_tl_get(option, "colors"), &row.light) != EXTERIA_OK) continue;
        if (first_color(exteria_tl_get(option, "dark_colors"), &row.dark) != EXTERIA_OK) row.dark = row.light;
        row.id = id;
        row.hidden = exteria_tl_has(option, "hidden") ? 1 : 0;
        rows[n++] = row;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_name_color_set_request(exteria_arena *arena, int32_t id, exteria_tl_value **out) {
    exteria_tl_value *request, *color;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || id < 0 || id > EXTERIA_NAME_COLOR_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.updateColor");
    color = exteria_tl_new_obj(arena, "peerColor");
    if (!request || !color) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, color, "color", id);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "color", color);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_name_color_set_parse(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolTrue)) return EXTERIA_OK;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolFalse)) return EXTERIA_E_STATE;
    return EXTERIA_E_MALFORMED;
}
