#include "exteria_effects.h"

#include <string.h>

#include "exteria_tl_ids.h"

exteria_status exteria_effects_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getAvailableEffects");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_effects_parse(const exteria_tl_value *answer, exteria_effect *rows, size_t cap, size_t *count) {
    const exteria_tl_value *list, *docs = NULL;
    uint32_t i;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_availableEffects)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "effects", &list) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "documents", &docs) != EXTERIA_OK) docs = NULL;
    for (i = 0; i < list->u.vec.count && *count < cap; ++i) {
        const exteria_tl_value *item = list->u.vec.items[i];
        const uint8_t *emoticon;
        size_t length;
        exteria_effect *row = &rows[*count];
        if (!item || !exteria_tl_is(item, EXTERIA_TL_ID_availableEffect)) continue;
        memset(row, 0, sizeof(*row));
        if (exteria_tl_get_i64(item, "id", &row->id) != EXTERIA_OK || row->id == 0) continue;
        if (exteria_tl_get_bytes(item, "emoticon", &emoticon, &length) != EXTERIA_OK || length == 0 || length >= sizeof(row->emoticon) || memchr(emoticon, 0, length)) continue;
        memcpy(row->emoticon, emoticon, length);
        row->emoticon[length] = 0;
        row->premium = exteria_tl_has(item, "premium_required") ? 1 : 0;
        if (exteria_tl_has(item, "static_icon_id")) exteria_tl_get_i64(item, "static_icon_id", &row->sticker_id);
        if (exteria_tl_has(item, "effect_animation_id")) exteria_tl_get_i64(item, "effect_animation_id", &row->animation_id);
        {
            int64_t sticker_id = 0;
            exteria_tl_get_i64(item, "effect_sticker_id", &sticker_id);
            if (docs) {
                uint32_t k;
                for (k = 0; k < docs->u.vec.count; ++k) {
                    const exteria_tl_value *doc = docs->u.vec.items[k];
                    int64_t doc_id = 0;
                    if (!doc || exteria_tl_get_i64(doc, "id", &doc_id) != EXTERIA_OK) continue;
                    if (row->animation_id && doc_id == row->animation_id) exteria_document_picture_read(doc, "", &row->animation);
                    if (sticker_id && doc_id == sticker_id) exteria_document_picture_read(doc, "", &row->sticker);
                }
            }
        }
        ++*count;
    }
    return EXTERIA_OK;
}

exteria_status exteria_set_effect(exteria_arena *arena, exteria_tl_value *request, int64_t effect) {
    if (!arena || !request || effect == 0) return EXTERIA_E_ARG;
    return exteria_tl_set_i64(arena, request, "effect", effect);
}
