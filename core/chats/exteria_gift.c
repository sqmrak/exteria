#include "exteria_gift.h"

#include <string.h>

#include "exteria_tl_ids.h"

static void copy_string(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

/* the animation of a gift is a tgs document; a gift document that lacks the sticker attribute is still one */
static void read_picture(const exteria_tl_value *document, exteria_media_info *out) {
    exteria_document_read(document, out);
    if (out->ref.source != EXTERIA_MEDIA_SOURCE_DOCUMENT) return;
    out->kind = EXTERIA_PREVIEW_STICKER;
    if (!strcmp(out->mime, "application/x-tgsticker")) out->sticker = EXTERIA_STICKER_ANIMATED;
    else if (!strcmp(out->mime, "video/webm")) out->sticker = EXTERIA_STICKER_VIDEO;
    else out->sticker = EXTERIA_STICKER_STATIC;
}

static uint32_t rgb(int32_t color) {
    return (uint32_t)color & 0xffffffu;
}

/* a starGiftAttributeRarity holds thousandths only in its plain form; the ranked forms (uncommon, rare, epic) carry none */
static int32_t read_permille(const exteria_tl_value *attribute) {
    int32_t permille = 0;
    const exteria_tl_value *rarity = exteria_tl_get(attribute, "rarity");
    if (!exteria_tl_is(rarity, EXTERIA_TL_ID_starGiftAttributeRarity) || exteria_tl_get_i32(rarity, "permille", &permille) != EXTERIA_OK ||
        permille < 0) return 0;
    return permille;
}

static void read_attributes(const exteria_tl_value *list, exteria_gift *out) {
    uint32_t i;
    int have_model = 0, have_pattern = 0;
    if (!list || list->kind != EXTERIA_TL_V_VEC) return;
    for (i = 0; i < list->u.vec.count; ++i) {
        const exteria_tl_value *a = list->u.vec.items[i];
        if (exteria_tl_is(a, EXTERIA_TL_ID_starGiftAttributeModel) && !have_model) {
            copy_string(out->model, sizeof(out->model), a, "name");
            read_picture(exteria_tl_get(a, "document"), &out->sticker);
            out->model_permille = read_permille(a);
            have_model = 1;
        } else if (exteria_tl_is(a, EXTERIA_TL_ID_starGiftAttributePattern) && !have_pattern) {
            copy_string(out->pattern, sizeof(out->pattern), a, "name");
            read_picture(exteria_tl_get(a, "document"), &out->pattern_sticker);
            out->pattern_permille = read_permille(a);
            have_pattern = 1;
        } else if (exteria_tl_is(a, EXTERIA_TL_ID_starGiftAttributeBackdrop) && !out->has_backdrop) {
            int32_t center, edge, text, pattern_color;
            copy_string(out->backdrop, sizeof(out->backdrop), a, "name");
            if (exteria_tl_get_i32(a, "center_color", &center) == EXTERIA_OK && exteria_tl_get_i32(a, "edge_color", &edge) == EXTERIA_OK &&
                exteria_tl_get_i32(a, "text_color", &text) == EXTERIA_OK) {
                out->backdrop_center = rgb(center);
                out->backdrop_edge = rgb(edge);
                out->backdrop_text = rgb(text);
                if (exteria_tl_get_i32(a, "pattern_color", &pattern_color) == EXTERIA_OK) out->backdrop_pattern = rgb(pattern_color);
                else out->backdrop_pattern = rgb(text);
                out->backdrop_permille = read_permille(a);
                out->has_backdrop = 1;
            }
        }
    }
}

static exteria_status read_unique(const exteria_tl_value *gift, exteria_gift *out) {
    if (exteria_tl_get_i64(gift, "id", &out->id) != EXTERIA_OK || out->id <= 0) return EXTERIA_E_MALFORMED;
    out->unique = 1;
    if (exteria_tl_get_i64(gift, "gift_id", &out->catalog_id) != EXTERIA_OK) out->catalog_id = 0;
    copy_string(out->title, sizeof(out->title), gift, "title");
    copy_string(out->slug, sizeof(out->slug), gift, "slug");
    copy_string(out->owner_name, sizeof(out->owner_name), gift, "owner_name");
    if (!out->title[0] || exteria_tl_get_i32(gift, "num", &out->num) != EXTERIA_OK || out->num <= 0) return EXTERIA_E_MALFORMED;
    exteria_tl_get_i32(gift, "availability_issued", &out->remains);
    exteria_tl_get_i32(gift, "availability_total", &out->total);
    if (exteria_tl_has(gift, "owner_id")) {
        const exteria_tl_value *owner = exteria_tl_get(gift, "owner_id");
        if (exteria_tl_is(owner, EXTERIA_TL_ID_peerUser)) exteria_tl_get_i64(owner, "user_id", &out->owner_id);
    }
    out->require_premium = exteria_tl_has(gift, "require_premium") ? 1 : 0;
    read_attributes(exteria_tl_get(gift, "attributes"), out);
    return EXTERIA_OK;
}

exteria_status exteria_gift_read(const exteria_tl_value *gift, exteria_gift *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    out->sticker.kind = EXTERIA_PREVIEW_STICKER;
    if (gift && exteria_tl_is(gift, EXTERIA_TL_ID_starGiftUnique)) {
        exteria_status status = read_unique(gift, out);
        if (status != EXTERIA_OK) memset(out, 0, sizeof(*out));
        return status;
    }
    if (!gift || !exteria_tl_is(gift, EXTERIA_TL_ID_starGift) || exteria_tl_get_i64(gift, "id", &out->id) != EXTERIA_OK ||
        out->id <= 0 || exteria_tl_get_i64(gift, "stars", &out->stars) != EXTERIA_OK || out->stars < 0) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    out->catalog_id = out->id;
    out->limited = exteria_tl_has(gift, "limited") ? 1 : 0;
    out->sold_out = exteria_tl_has(gift, "sold_out") ? 1 : 0;
    out->birthday = exteria_tl_has(gift, "birthday") ? 1 : 0;
    out->require_premium = exteria_tl_has(gift, "require_premium") ? 1 : 0;
    out->auction = exteria_tl_has(gift, "auction") ? 1 : 0;
    exteria_tl_get_i64(gift, "convert_stars", &out->convert_stars);
    exteria_tl_get_i64(gift, "upgrade_stars", &out->upgrade_stars);
    if (out->limited) {
        exteria_tl_get_i32(gift, "availability_remains", &out->remains);
        exteria_tl_get_i32(gift, "availability_total", &out->total);
    }
    copy_string(out->title, sizeof(out->title), gift, "title");
    read_picture(exteria_tl_get(gift, "sticker"), &out->sticker);
    return EXTERIA_OK;
}
