#include "exteria_theme_link.h"

#include <string.h>

#include "exteria_tl_ids.h"

static int slug_ok(const char *s) {
    size_t i;
    if (!s || !s[0]) return 0;
    for (i = 0; s[i]; ++i) {
        char c = s[i];
        int letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        int extra = (c >= '0' && c <= '9') || c == '-' || c == '_';
        if (i >= EXTERIA_THEME_SLUG_MAX || !(letter || extra)) return 0;
    }
    return 1;
}

exteria_status exteria_theme_link_request(exteria_arena *arena, const char *slug, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !slug_ok(slug)) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.getTheme");
    input = exteria_tl_new_obj(arena, "inputThemeSlug");
    if (!request || !input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, input, "slug", slug);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "format", "ios");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "theme", input);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* a theme made in an app with accent colors carries them as a list of settings, one for each base look it was made for; the first one stands for the theme. A list that does
   not read is no colors, and the theme is then judged by its file alone */
static void read_colors(const exteria_tl_value *theme, exteria_theme_link_info *out) {
    const exteria_tl_value *list, *settings, *base;
    int32_t accent = 0;
    uint32_t id;
    if (exteria_tl_get_vec(theme, "settings", &list) != EXTERIA_OK || list->u.vec.count == 0) return;
    settings = list->u.vec.items[0];
    if (!exteria_tl_is(settings, EXTERIA_TL_ID_themeSettings) || exteria_tl_get_i32(settings, "accent_color", &accent) != EXTERIA_OK) return;
    base = exteria_tl_get(settings, "base_theme");
    id = exteria_tl_id(base);
    if (id != EXTERIA_TL_ID_baseThemeClassic && id != EXTERIA_TL_ID_baseThemeDay && id != EXTERIA_TL_ID_baseThemeNight && id != EXTERIA_TL_ID_baseThemeTinted &&
        id != EXTERIA_TL_ID_baseThemeArctic) return;
    out->has_colors = 1;
    out->dark = id == EXTERIA_TL_ID_baseThemeNight || id == EXTERIA_TL_ID_baseThemeTinted;
    out->accent = (uint32_t)accent & 0xFFFFFFu;
}

exteria_status exteria_theme_link_parse(const exteria_tl_value *answer, exteria_theme_link_info *out) {
    const uint8_t *data;
    size_t len;
    const exteria_tl_value *document;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_theme)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_bytes(answer, "title", &data, &len) != EXTERIA_OK || (!data && len)) return EXTERIA_E_MALFORMED;
    if (len >= sizeof(out->title)) {
        len = sizeof(out->title) - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    if (len) memcpy(out->title, data, len);
    out->title[len] = 0;
    read_colors(answer, out);
    if (!exteria_tl_has(answer, "document")) return EXTERIA_OK;
    if (exteria_tl_get_obj(answer, "document", &document) != EXTERIA_OK) goto malformed;
    exteria_document_read(document, &out->file);
    if (out->file.ref.source != EXTERIA_MEDIA_SOURCE_DOCUMENT) goto malformed;
    out->has_file = 1;
    return EXTERIA_OK;
malformed:
    memset(out, 0, sizeof(*out));
    return EXTERIA_E_MALFORMED;
}
