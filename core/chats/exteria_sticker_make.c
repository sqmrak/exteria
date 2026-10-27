#include "exteria_sticker_make.h"

#include <string.h>

#include "exteria_tl_ids.h"

/* the length of the UTF-8 sequence at s and its code point, or zero when the bytes are not well formed */
static size_t decode(const unsigned char *s, size_t left, uint32_t *cp) {
    if (left >= 1 && s[0] < 0x80u) {
        *cp = s[0];
        return 1;
    }
    if (left >= 2 && (s[0] & 0xE0u) == 0xC0u && (s[1] & 0xC0u) == 0x80u) {
        *cp = ((uint32_t)(s[0] & 0x1Fu) << 6) | (s[1] & 0x3Fu);
        return *cp >= 0x80u ? 2 : 0;
    }
    if (left >= 3 && (s[0] & 0xF0u) == 0xE0u && (s[1] & 0xC0u) == 0x80u && (s[2] & 0xC0u) == 0x80u) {
        *cp = ((uint32_t)(s[0] & 0x0Fu) << 12) | ((uint32_t)(s[1] & 0x3Fu) << 6) | (s[2] & 0x3Fu);
        return *cp >= 0x800u && (*cp < 0xD800u || *cp > 0xDFFFu) ? 3 : 0;
    }
    if (left >= 4 && (s[0] & 0xF8u) == 0xF0u && (s[1] & 0xC0u) == 0x80u && (s[2] & 0xC0u) == 0x80u && (s[3] & 0xC0u) == 0x80u) {
        *cp = ((uint32_t)(s[0] & 0x07u) << 18) | ((uint32_t)(s[1] & 0x3Fu) << 12) | ((uint32_t)(s[2] & 0x3Fu) << 6) | (s[3] & 0x3Fu);
        return *cp >= 0x10000u && *cp <= 0x10FFFFu ? 4 : 0;
    }
    return 0;
}

int exteria_sticker_title_valid(const char *title) {
    const unsigned char *s = (const unsigned char *)title;
    size_t len, at = 0, chars = 0;
    int visible = 0;
    if (!title) return 0;
    len = strlen(title);
    while (at < len) {
        uint32_t cp = 0;
        size_t n = decode(s + at, len - at, &cp);
        if (!n || cp < 0x20u || cp == 0x7Fu) return 0;
        if (cp != ' ') visible = 1;
        ++chars;
        at += n;
    }
    return visible && chars >= 1 && chars <= EXTERIA_STICKER_TITLE_MAX;
}

int exteria_sticker_short_name_valid(const char *name) {
    size_t len, i;
    if (!name) return 0;
    len = strlen(name);
    if (len < 1 || len > EXTERIA_STICKER_SHORT_NAME_MAX) return 0;
    if (!((name[0] >= 'a' && name[0] <= 'z') || (name[0] >= 'A' && name[0] <= 'Z'))) return 0;
    if (name[len - 1] == '_') return 0;
    for (i = 0; i < len; ++i) {
        char c = name[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')) return 0;
        if (c == '_' && i + 1 < len && name[i + 1] == '_') return 0;
    }
    return 1;
}

int exteria_sticker_emoji_valid(const char *emoji) {
    const unsigned char *s = (const unsigned char *)emoji;
    size_t len, at = 0;
    int pictorial = 0;
    if (!emoji) return 0;
    len = strlen(emoji);
    if (len < 1 || len > EXTERIA_STICKER_EMOJI_MAX) return 0;
    while (at < len) {
        uint32_t cp = 0;
        size_t n = decode(s + at, len - at, &cp);
        if (!n) return 0;
        /* a plain ASCII letter, digit or blank is not an emoji; the digits that start a keycap sequence ride with U+20E3 and are allowed there */
        if (cp < 0x80u && !((cp >= '0' && cp <= '9') || cp == '#' || cp == '*')) return 0;
        if (cp >= 0x2190u) pictorial = 1;
        at += n;
    }
    return pictorial;
}

exteria_status exteria_sticker_upload_request(exteria_arena *arena, exteria_tl_value *file, const char *file_name, exteria_tl_value **out) {
    exteria_tl_value *request, *media, *peer, *attributes, *name_attribute;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !file || !file_name || !file_name[0] || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.uploadMedia");
    media = exteria_tl_new_obj(arena, "inputMediaUploadedDocument");
    peer = exteria_tl_new_obj(arena, "inputPeerSelf");
    attributes = exteria_tl_new_vec(arena, 1);
    name_attribute = exteria_tl_new_obj(arena, "documentAttributeFilename");
    if (!request || !media || !peer || !attributes || !name_attribute) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, name_attribute, "file_name", file_name);
    if (status == EXTERIA_OK) status = exteria_tl_vec_set(attributes, 0, name_attribute);
    if (status == EXTERIA_OK) status = exteria_tl_set(media, "file", file);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "mime_type", "image/png");
    if (status == EXTERIA_OK) status = exteria_tl_set(media, "attributes", attributes);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "media", media);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_sticker_upload_parse(const exteria_tl_value *answer, exteria_input_document *out) {
    const exteria_tl_value *document;
    const uint8_t *reference;
    size_t length;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messageMediaDocument)) return EXTERIA_E_MALFORMED;
    document = exteria_tl_get(answer, "document");
    if (!exteria_tl_is(document, EXTERIA_TL_ID_document) || exteria_tl_get_i64(document, "id", &out->id) != EXTERIA_OK ||
        exteria_tl_get_i64(document, "access_hash", &out->access_hash) != EXTERIA_OK ||
        exteria_tl_get_bytes(document, "file_reference", &reference, &length) != EXTERIA_OK || length > EXTERIA_STICKER_REF_MAX || out->id == 0) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    memcpy(out->file_reference, reference, length);
    out->file_reference_len = length;
    return EXTERIA_OK;
}

static exteria_status input_document(exteria_arena *arena, const exteria_input_document *document, exteria_tl_value **out) {
    exteria_tl_value *input = exteria_tl_new_obj(arena, "inputDocument");
    exteria_status status;
    *out = NULL;
    if (!input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "id", document->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", document->access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, input, "file_reference", document->file_reference, document->file_reference_len);
    if (status == EXTERIA_OK) *out = input;
    return status;
}

/* the inputStickerSetItem both calls carry */
static exteria_status set_item(exteria_arena *arena, const exteria_input_document *document, const char *emoji, exteria_tl_value **out) {
    exteria_tl_value *item, *input;
    exteria_status status;
    *out = NULL;
    if (!document || document->id == 0 || !exteria_sticker_emoji_valid(emoji)) return EXTERIA_E_ARG;
    status = input_document(arena, document, &input);
    if (status != EXTERIA_OK) return status;
    item = exteria_tl_new_obj(arena, "inputStickerSetItem");
    if (!item) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(item, "document", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, item, "emoji", emoji);
    if (status == EXTERIA_OK) *out = item;
    return status;
}

exteria_status exteria_sticker_create_request(exteria_arena *arena, const char *title, const char *short_name, const exteria_input_document *document,
                                              const char *emoji, exteria_tl_value **out) {
    exteria_tl_value *request, *item, *list, *user;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !exteria_sticker_title_valid(title) || !exteria_sticker_short_name_valid(short_name)) return EXTERIA_E_ARG;
    status = set_item(arena, document, emoji, &item);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "stickers.createStickerSet");
    user = exteria_tl_new_obj(arena, "inputUserSelf");
    list = exteria_tl_new_vec(arena, 1);
    if (!request || !user || !list) return EXTERIA_E_NOMEM;
    status = exteria_tl_vec_set(list, 0, item);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "user_id", user);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "title", title);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "short_name", short_name);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "stickers", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_sticker_add_request(exteria_arena *arena, const char *short_name, const exteria_input_document *document, const char *emoji,
                                           exteria_tl_value **out) {
    exteria_tl_value *request, *item, *set;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !exteria_sticker_short_name_valid(short_name)) return EXTERIA_E_ARG;
    status = set_item(arena, document, emoji, &item);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "stickers.addStickerToSet");
    set = exteria_tl_new_obj(arena, "inputStickerSetShortName");
    if (!request || !set) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, set, "short_name", short_name);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "stickerset", set);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "sticker", item);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_sticker_check_request(exteria_arena *arena, const char *short_name, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !exteria_sticker_short_name_valid(short_name)) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "stickers.checkShortName");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "short_name", short_name);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_sticker_check_parse(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolTrue)) return EXTERIA_OK;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolFalse)) return EXTERIA_E_STATE;
    return EXTERIA_E_MALFORMED;
}

exteria_status exteria_sticker_set_name_parse(const exteria_tl_value *answer, char *short_name, size_t cap) {
    const exteria_tl_value *set;
    const uint8_t *data;
    size_t length;
    if (short_name && cap) short_name[0] = 0;
    if (!short_name || cap < 2) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickerSet)) return EXTERIA_E_MALFORMED;
    set = exteria_tl_get(answer, "set");
    if (!exteria_tl_is(set, EXTERIA_TL_ID_stickerSet) || exteria_tl_get_bytes(set, "short_name", &data, &length) != EXTERIA_OK || !length || length >= cap) return EXTERIA_E_MALFORMED;
    memcpy(short_name, data, length);
    short_name[length] = 0;
    return EXTERIA_OK;
}
