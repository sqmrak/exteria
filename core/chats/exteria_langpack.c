#include "exteria_langpack.h"

#include <string.h>

#include "exteria_tl_ids.h"

#define PACK_NAME_MAX 17
#define CODE_INPUT_MAX 32

static int word_ok(const char *s, size_t max, int allow_digits) {
    size_t i;
    if (!s || !s[0]) return 0;
    for (i = 0; s[i]; ++i) {
        char c = s[i];
        int letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        int extra = (c >= '0' && c <= '9') || c == '-' || c == '_';
        if (i >= max || !(letter || (allow_digits && extra))) return 0;
    }
    return 1;
}

exteria_status exteria_langpack_request(exteria_arena *arena, const char *lang_pack, const char *lang_code, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !word_ok(lang_pack, PACK_NAME_MAX - 1, 0) || !word_ok(lang_code, CODE_INPUT_MAX, 1)) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "langpack.getLanguage");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "lang_pack", lang_pack);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "lang_code", lang_code);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* a string field into a buffer: whole when it fits, else cut at a character boundary when cut is set, else EXTERIA_E_MALFORMED */
static exteria_status take(const exteria_tl_value *obj, const char *field, char *dst, size_t cap, int cut, int required) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (!exteria_tl_has(obj, field)) return required ? EXTERIA_E_MALFORMED : EXTERIA_OK;
    if (exteria_tl_get_bytes(obj, field, &data, &len) != EXTERIA_OK || (!data && len)) return EXTERIA_E_MALFORMED;
    if (len >= cap) {
        if (!cut) return EXTERIA_E_MALFORMED;
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    if (len) memcpy(dst, data, len);
    dst[len] = 0;
    return EXTERIA_OK;
}

exteria_status exteria_langpack_parse(const exteria_tl_value *answer, exteria_langpack_info *out) {
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_langPackLanguage)) return EXTERIA_E_MALFORMED;
    out->official = exteria_tl_has(answer, "official");
    out->rtl = exteria_tl_has(answer, "rtl");
    status = take(answer, "name", out->name, sizeof(out->name), 1, 1);
    if (status == EXTERIA_OK) status = take(answer, "native_name", out->native_name, sizeof(out->native_name), 1, 1);
    if (status == EXTERIA_OK) status = take(answer, "lang_code", out->lang_code, sizeof(out->lang_code), 0, 1);
    if (status == EXTERIA_OK) status = take(answer, "base_lang_code", out->base_lang_code, sizeof(out->base_lang_code), 0, 0);
    if (status == EXTERIA_OK) status = take(answer, "translations_url", out->translations_url, sizeof(out->translations_url), 1, 0);
    if (status == EXTERIA_OK && !out->name[0]) status = EXTERIA_E_MALFORMED;
    if (status == EXTERIA_OK && !out->lang_code[0]) status = EXTERIA_E_MALFORMED;
    if (status == EXTERIA_OK) status = exteria_tl_get_i32(answer, "strings_count", &out->strings_count);
    if (status == EXTERIA_OK) status = exteria_tl_get_i32(answer, "translated_count", &out->translated_count);
    if (status == EXTERIA_OK && (out->strings_count < 0 || out->translated_count < 0)) status = EXTERIA_E_MALFORMED;
    if (status != EXTERIA_OK) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    return EXTERIA_OK;
}

int exteria_langpack_percent(int32_t translated, int32_t strings) {
    int64_t share;
    if (strings <= 0 || translated <= 0) return 0;
    if (translated >= strings) return 100;
    share = ((int64_t)translated * 100 + strings - 1) / strings;
    return (int)share;
}
