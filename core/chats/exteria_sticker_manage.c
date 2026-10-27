#include "exteria_sticker_manage.h"

#include "exteria_tl_ids.h"

exteria_status exteria_sticker_uninstall_request(exteria_arena *arena, int64_t id, int64_t access_hash, exteria_tl_value **out) {
    exteria_tl_value *request, *set;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || id <= 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.uninstallStickerSet");
    set = exteria_tl_new_obj(arena, "inputStickerSetID");
    if (!request || !set) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, set, "id", id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, set, "access_hash", access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "stickerset", set);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_sticker_install_request(exteria_arena *arena, int64_t id, int64_t access_hash, exteria_tl_value **out) {
    exteria_tl_value *request, *set;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || id <= 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.installStickerSet");
    set = exteria_tl_new_obj(arena, "inputStickerSetID");
    if (!request || !set) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, set, "id", id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, set, "access_hash", access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "stickerset", set);
    /* the Bool of archived: false, the set goes into the installed ones */
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "archived", exteria_tl_new_obj(arena, "boolFalse"));
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_sticker_reorder_request(exteria_arena *arena, const int64_t *ids, size_t count, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    size_t i, j;
    if (out) *out = NULL;
    if (!arena || !out || !ids || count == 0 || count > EXTERIA_STICKER_ORDER_MAX) return EXTERIA_E_ARG;
    for (i = 0; i < count; ++i) {
        if (ids[i] <= 0) return EXTERIA_E_ARG;
        for (j = 0; j < i; ++j) {
            if (ids[j] == ids[i]) return EXTERIA_E_ARG;
        }
    }
    request = exteria_tl_new_obj(arena, "messages.reorderStickerSets");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64_vec(arena, request, "order", ids, (uint32_t)count);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_sticker_install_parse(const exteria_tl_value *answer) {
    /* an archived answer lists the sets that made room; the set itself is in either way */
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickerSetInstallResultSuccess) || exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickerSetInstallResultArchive)) return EXTERIA_OK;
    return EXTERIA_E_MALFORMED;
}

exteria_status exteria_sticker_manage_parse(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolTrue)) return EXTERIA_OK;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolFalse)) return EXTERIA_E_STATE;
    return EXTERIA_E_MALFORMED;
}
