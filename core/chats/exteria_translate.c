#include "exteria_translate.h"

#include <string.h>

#include "exteria_tl_ids.h"

static int valid_lang(const char *lang) {
    size_t i;
    if (!lang || !lang[0]) return 0;
    for (i = 0; lang[i]; ++i) {
        char c = lang[i];
        if (i + 1 >= EXTERIA_TRANSLATE_LANG_MAX) return 0;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-')) return 0;
    }
    return 1;
}

exteria_status exteria_translate_request(exteria_arena *arena, const char *text, const char *to_lang, exteria_tl_value **out) {
    exteria_tl_value *request, *item, *list;
    exteria_status status;
    size_t length;
    if (out) *out = NULL;
    if (!arena || !text || !out || !valid_lang(to_lang)) return EXTERIA_E_ARG;
    length = strlen(text);
    if (!length || length > EXTERIA_TRANSLATE_TEXT_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.translateText");
    item = exteria_tl_new_obj(arena, "textWithEntities");
    list = exteria_tl_new_vec(arena, 1);
    if (!request || !item || !list) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, item, "text", text);
    if (status == EXTERIA_OK) status = exteria_tl_set(item, "entities", exteria_tl_new_vec(arena, 0));
    if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, 0, item);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "text", list);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "to_lang", to_lang);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_translate_parse(const exteria_tl_value *answer, char *out, size_t cap) {
    const exteria_tl_value *list, *item;
    const uint8_t *data;
    size_t len;
    if (!out || !cap) return EXTERIA_E_ARG;
    out[0] = 0;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_translateResult)) return EXTERIA_E_MALFORMED;
    list = exteria_tl_get(answer, "result");
    if (!list || list->kind != EXTERIA_TL_V_VEC || list->u.vec.count < 1) return EXTERIA_E_MALFORMED;
    item = list->u.vec.items[0];
    if (!exteria_tl_is(item, EXTERIA_TL_ID_textWithEntities) || exteria_tl_get_bytes(item, "text", &data, &len) != EXTERIA_OK || !data) return EXTERIA_E_MALFORMED;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(out, data, len);
    out[len] = 0;
    return EXTERIA_OK;
}
