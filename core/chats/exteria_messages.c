#include "exteria_messages.h"

#include <stdio.h>
#include <string.h>

#include "exteria_store.h"
#include "exteria_tl_ids.h"

/* the largest size worth a bubble on a small screen; a photo goes for the smallest size that covers it */
#define PHOTO_TARGET 640
#define STICKER_PREVIEW_TARGET 100

static void copy_text(char *dst, size_t cap, const exteria_tl_value *object, const char *field, int keep_lines) {
    const uint8_t *data;
    size_t len, i;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK) return;
    if (len >= cap) {
        len = cap - 1;
        /* a sequence that did not fit whole goes with its lead byte */
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    for (i = 0; i < len; ++i) {
        uint8_t c = data[i];
        if (!keep_lines && (c == '\n' || c == '\r' || c == '\t')) c = ' ';
        dst[i] = (char)c;
    }
    dst[len] = 0;
}

static int is_vec(const exteria_tl_value *v) {
    return v && v->kind == EXTERIA_TL_V_VEC;
}

/* a type letter such as "m" or "x"; longer ones are not photo sizes */
static int size_type(const exteria_tl_value *size, char *type, size_t cap) {
    const uint8_t *data;
    size_t len;
    if (exteria_tl_get_bytes(size, "type", &data, &len) != EXTERIA_OK || len == 0 || len >= cap) return 0;
    memcpy(type, data, len);
    type[len] = 0;
    return 1;
}

/* picks the size of a photo or document thumbnail list that suits target pixels: the smallest that covers it, else
   the largest there is */
static int pick_size(const exteria_tl_value *sizes, int32_t target, char *type, int32_t *w, int32_t *h, int64_t *bytes) {
    uint32_t i;
    int found = 0;
    int32_t best_side = 0;
    if (!is_vec(sizes)) return 0;
    for (i = 0; i < sizes->u.vec.count; ++i) {
        const exteria_tl_value *s = sizes->u.vec.items[i];
        char t[8];
        int32_t sw = 0, sh = 0, side;
        int64_t sb = 0;
        if (exteria_tl_is(s, EXTERIA_TL_ID_photoSize)) {
            int32_t v = 0;
            if (exteria_tl_get_i32(s, "size", &v) == EXTERIA_OK) sb = v;
        } else if (exteria_tl_is(s, EXTERIA_TL_ID_photoSizeProgressive)) {
            const exteria_tl_value *list = exteria_tl_get(s, "sizes");
            if (is_vec(list) && list->u.vec.count > 0 && list->u.vec.items[list->u.vec.count - 1]->kind == EXTERIA_TL_V_I32)
                sb = list->u.vec.items[list->u.vec.count - 1]->u.i32;
        } else {
            continue;
        }
        if (!size_type(s, t, sizeof(t)) || exteria_tl_get_i32(s, "w", &sw) != EXTERIA_OK ||
            exteria_tl_get_i32(s, "h", &sh) != EXTERIA_OK || sw <= 0 || sh <= 0) continue;
        side = sw > sh ? sw : sh;
        if (!found || (best_side < target && side > best_side) || (best_side >= target && side >= target && side < best_side)) {
            found = 1;
            best_side = side;
            memcpy(type, t, strlen(t) + 1);
            *w = sw;
            *h = sh;
            *bytes = sb;
        }
    }
    return found;
}

/* the same pick over the video thumbnails of a document (type "v"); a gif or a video that Telegram stores with
   only a stripped picture and one of these has no photo size, and the clip is then the only file there is to make
   a picture of */
static int pick_video_size(const exteria_tl_value *sizes, int32_t target, char *type) {
    uint32_t i;
    int found = 0;
    int32_t best_side = 0;
    if (!is_vec(sizes)) return 0;
    for (i = 0; i < sizes->u.vec.count; ++i) {
        const exteria_tl_value *s = sizes->u.vec.items[i];
        char t[8];
        int32_t sw = 0, sh = 0, side;
        if (!exteria_tl_is(s, EXTERIA_TL_ID_videoSize) || !size_type(s, t, sizeof(t)) || exteria_tl_get_i32(s, "w", &sw) != EXTERIA_OK ||
            exteria_tl_get_i32(s, "h", &sh) != EXTERIA_OK || sw <= 0 || sh <= 0) continue;
        side = sw > sh ? sw : sh;
        if (!found || (best_side < target && side > best_side) || (best_side >= target && side >= target && side < best_side)) {
            found = 1;
            best_side = side;
            memcpy(type, t, strlen(t) + 1);
        }
    }
    return found;
}

static void ref_from(exteria_media_ref *ref, exteria_media_source source, const exteria_tl_value *object, int32_t dc, const char *thumb) {
    const uint8_t *data;
    size_t len;
    memset(ref, 0, sizeof(*ref));
    if (exteria_tl_get_i64(object, "id", &ref->id) != EXTERIA_OK ||
        exteria_tl_get_i64(object, "access_hash", &ref->access_hash) != EXTERIA_OK ||
        exteria_tl_get_bytes(object, "file_reference", &data, &len) != EXTERIA_OK || len > EXTERIA_MEDIA_REF_MAX || dc <= 0) {
        memset(ref, 0, sizeof(*ref));
        return;
    }
    memcpy(ref->file_ref, data, len);
    ref->ref_len = (uint8_t)len;
    ref->dc = dc;
    ref->source = (uint8_t)source;
    if (thumb) {
        strncpy(ref->thumb, thumb, sizeof(ref->thumb) - 1);
        ref->thumb[sizeof(ref->thumb) - 1] = 0;
    }
}

static void read_photo(const exteria_tl_value *photo, int32_t target, exteria_media_info *out) {
    int32_t dc = 0, w = 0, h = 0;
    int64_t bytes = 0;
    char type[8];
    out->kind = EXTERIA_PREVIEW_PHOTO;
    if (!exteria_tl_is(photo, EXTERIA_TL_ID_photo)) return;
    if (exteria_tl_get_i32(photo, "dc_id", &dc) != EXTERIA_OK) return;
    if (!pick_size(exteria_tl_get(photo, "sizes"), target, type, &w, &h, &bytes)) return;
    ref_from(&out->ref, EXTERIA_MEDIA_SOURCE_PHOTO, photo, dc, type);
    out->width = w;
    out->height = h;
    out->size = bytes;
    /* the viewer needs the largest file when zoomed, while bubbles keep a retina-sized thumbnail */
    if (pick_size(exteria_tl_get(photo, "sizes"), INT32_MAX, type, &w, &h, &bytes)) {
        ref_from(&out->full_photo, EXTERIA_MEDIA_SOURCE_PHOTO, photo, dc, type);
        out->full_photo_size = bytes;
    }
}

static int flac_document(const exteria_media_info *media) {
    size_t n = strlen(media->name);
    if (!strcmp(media->mime, "audio/flac") || !strcmp(media->mime, "audio/x-flac")) return 1;
    return n >= 5 && media->name[n - 5] == '.' &&
           (media->name[n - 4] == 'f' || media->name[n - 4] == 'F') && (media->name[n - 3] == 'l' || media->name[n - 3] == 'L') &&
           (media->name[n - 2] == 'a' || media->name[n - 2] == 'A') && (media->name[n - 1] == 'c' || media->name[n - 1] == 'C');
}

static void read_document(const exteria_tl_value *document, const exteria_tl_value *media, exteria_media_info *out) {
    const exteria_tl_value *attributes = exteria_tl_get(document, "attributes");
    int32_t dc = 0, w = 0, h = 0;
    int64_t bytes = 0;
    int animated = 0, sticker = 0, voice = media && exteria_tl_has(media, "voice"), round = media && exteria_tl_has(media, "round");
    char type[8];
    uint32_t i;
    const uint8_t *wave;
    size_t wave_len;
    out->kind = EXTERIA_PREVIEW_FILE;
    if (!exteria_tl_is(document, EXTERIA_TL_ID_document)) {
        /* an expired or empty document still says what it was through the media flags */
        if (voice) out->kind = EXTERIA_PREVIEW_VOICE;
        else if (round) out->kind = EXTERIA_PREVIEW_VIDEO_MESSAGE;
        else if (media && exteria_tl_has(media, "video")) out->kind = EXTERIA_PREVIEW_VIDEO;
        return;
    }
    exteria_tl_get_i32(document, "dc_id", &dc);
    exteria_tl_get_i64(document, "size", &out->size);
    copy_text(out->mime, sizeof(out->mime), document, "mime_type", 0);
    ref_from(&out->ref, EXTERIA_MEDIA_SOURCE_DOCUMENT, document, dc, "");
    if (is_vec(attributes)) {
        for (i = 0; i < attributes->u.vec.count; ++i) {
            const exteria_tl_value *a = attributes->u.vec.items[i];
            if (exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeSticker)) {
                const exteria_tl_value *named = exteria_tl_get(a, "stickerset");
                if (!exteria_tl_has(a, "mask")) sticker = 1;
                copy_text(out->alt, sizeof(out->alt), a, "alt", 0);
                if (named && exteria_tl_is(named, EXTERIA_TL_ID_inputStickerSetID)) {
                    exteria_tl_get_i64(named, "id", &out->sticker_set_id);
                    exteria_tl_get_i64(named, "access_hash", &out->sticker_set_hash);
                }
            } else if (exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeAnimated)) {
                animated = 1;
            } else if (exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeImageSize)) {
                exteria_tl_get_i32(a, "w", &out->width);
                exteria_tl_get_i32(a, "h", &out->height);
            } else if (exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeVideo)) {
                double seconds = 0;
                out->kind = EXTERIA_PREVIEW_VIDEO;
                if (exteria_tl_has(a, "round_message")) round = 1;
                exteria_tl_get_i32(a, "w", &out->width);
                exteria_tl_get_i32(a, "h", &out->height);
                if (exteria_tl_get_f64(a, "duration", &seconds) == EXTERIA_OK && seconds > 0 && seconds < 2147483647.0) out->duration = (int32_t)seconds;
            } else if (exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeAudio)) {
                if (exteria_tl_has(a, "voice")) voice = 1;
                if (out->kind == EXTERIA_PREVIEW_FILE) out->kind = EXTERIA_PREVIEW_AUDIO;
                exteria_tl_get_i32(a, "duration", &out->duration);
                copy_text(out->title, sizeof(out->title), a, "title", 0);
                copy_text(out->performer, sizeof(out->performer), a, "performer", 0);
                if (exteria_tl_get_bytes(a, "waveform", &wave, &wave_len) == EXTERIA_OK && wave && wave_len > 0 && wave_len <= sizeof(out->waveform)) {
                    memcpy(out->waveform, wave, wave_len);
                    out->waveform_len = (uint16_t)wave_len;
                }
            } else if (exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeFilename)) {
                copy_text(out->name, sizeof(out->name), a, "file_name", 0);
            }
        }
    }
    if (out->kind == EXTERIA_PREVIEW_FILE && flac_document(out)) out->kind = EXTERIA_PREVIEW_AUDIO;
    if (sticker) {
        out->kind = EXTERIA_PREVIEW_STICKER;
        if (!strcmp(out->mime, "application/x-tgsticker")) out->sticker = EXTERIA_STICKER_ANIMATED;
        else if (!strcmp(out->mime, "video/webm")) out->sticker = EXTERIA_STICKER_VIDEO;
        else out->sticker = EXTERIA_STICKER_STATIC;
    } else if (voice) {
        out->kind = EXTERIA_PREVIEW_VOICE;
    } else if (round) {
        out->kind = EXTERIA_PREVIEW_VIDEO_MESSAGE;
    } else if (animated) {
        out->kind = EXTERIA_PREVIEW_GIF;
    }
    if (pick_size(exteria_tl_get(document, "thumbs"), STICKER_PREVIEW_TARGET, type, &w, &h, &bytes))
        ref_from(&out->preview, EXTERIA_MEDIA_SOURCE_DOCUMENT, document, dc, type);
    else if ((out->kind == EXTERIA_PREVIEW_GIF || out->kind == EXTERIA_PREVIEW_VIDEO) && pick_video_size(exteria_tl_get(document, "video_thumbs"), STICKER_PREVIEW_TARGET, type))
        ref_from(&out->preview, EXTERIA_MEDIA_SOURCE_DOCUMENT, document, dc, type);
}

static int document_is_avc(const exteria_tl_value *document) {
    const exteria_tl_value *attributes = exteria_tl_get(document, "attributes");
    if (!is_vec(attributes)) return 0;
    for (uint32_t i = 0; i < attributes->u.vec.count; ++i) {
        const exteria_tl_value *attribute = attributes->u.vec.items[i];
        const uint8_t *codec;
        size_t length;
        if (!exteria_tl_is(attribute, EXTERIA_TL_ID_documentAttributeVideo) ||
            exteria_tl_get_bytes(attribute, "video_codec", &codec, &length) != EXTERIA_OK) continue;
        if ((length == 3 && !memcmp(codec, "avc", 3)) || (length == 4 && !memcmp(codec, "h264", 4))) return 1;
    }
    return 0;
}

static void read_video_variant(const exteria_tl_value *media, int32_t target, exteria_media_info *out) {
    const exteria_tl_value *alternatives = exteria_tl_get(media, "alt_documents");
    int32_t best_side = 0;
    if (out->kind != EXTERIA_PREVIEW_VIDEO || document_is_avc(exteria_tl_get(media, "document")) ||
        !is_vec(alternatives) || alternatives->u.vec.count > 64) return;
    /* ios 5 through 10 cannot decode HEVC, Telegram supplies AVC in alt_documents */
    for (uint32_t i = 0; i < alternatives->u.vec.count; ++i) {
        const exteria_tl_value *document = alternatives->u.vec.items[i];
        exteria_media_info candidate;
        if (!document_is_avc(document)) continue;
        memset(&candidate, 0, sizeof(candidate));
        read_document(document, media, &candidate);
        if (candidate.kind != EXTERIA_PREVIEW_VIDEO || candidate.ref.source != EXTERIA_MEDIA_SOURCE_DOCUMENT ||
            candidate.size <= 0 || candidate.width <= 0 || candidate.height <= 0 || strcmp(candidate.mime, "video/mp4")) continue;
        int32_t side = candidate.width > candidate.height ? candidate.width : candidate.height;
        if (!best_side || (best_side < target && side > best_side) ||
            (best_side >= target && side >= target && side < best_side)) {
            best_side = side;
            *out = candidate;
        }
    }
}

/* a negative or missing value is ordinary media: a hostile server cannot make a message look timed with a bad number */
static void read_ttl(const exteria_tl_value *media, exteria_media_info *out) {
    int32_t ttl = 0;
    if (exteria_tl_has(media, "ttl_seconds") && exteria_tl_get_i32(media, "ttl_seconds", &ttl) == EXTERIA_OK && ttl > 0) out->ttl_seconds = ttl;
}

void exteria_media_classify_sized(const exteria_tl_value *media, int32_t photo_target, exteria_media_info *out) {
    memset(out, 0, sizeof(*out));
    out->kind = EXTERIA_PREVIEW_TEXT;
    if (!media || exteria_tl_is(media, EXTERIA_TL_ID_messageMediaEmpty) ||
        exteria_tl_is(media, EXTERIA_TL_ID_messageMediaWebPage)) return;
    if (exteria_tl_is(media, EXTERIA_TL_ID_messageMediaPhoto)) {
        read_photo(exteria_tl_get(media, "photo"), photo_target, out);
        out->spoiler = exteria_tl_has(media, "spoiler") ? 1 : 0;
        read_ttl(media, out);
    } else if (exteria_tl_is(media, EXTERIA_TL_ID_messageMediaDocument)) {
        read_document(exteria_tl_get(media, "document"), media, out);
        read_video_variant(media, photo_target, out);
        out->spoiler = exteria_tl_has(media, "spoiler") ? 1 : 0;
        read_ttl(media, out);
    } else if (exteria_tl_is(media, EXTERIA_TL_ID_messageMediaGeo) || exteria_tl_is(media, EXTERIA_TL_ID_messageMediaGeoLive) ||
               exteria_tl_is(media, EXTERIA_TL_ID_messageMediaVenue)) {
        out->kind = EXTERIA_PREVIEW_LOCATION;
        exteria_geo_read(exteria_tl_get(media, "geo"), exteria_tl_is(media, EXTERIA_TL_ID_messageMediaVenue) ? media : NULL, &out->location);
        out->width = 320;
        out->height = 180;
    } else if (exteria_tl_is(media, EXTERIA_TL_ID_messageMediaContact)) {
        out->kind = EXTERIA_PREVIEW_CONTACT;
    } else if (exteria_tl_is(media, EXTERIA_TL_ID_messageMediaPoll)) {
        out->kind = EXTERIA_PREVIEW_POLL;
    } else {
        out->kind = EXTERIA_PREVIEW_OTHER;
    }
}

void exteria_media_classify(const exteria_tl_value *media, exteria_media_info *out) {
    exteria_media_classify_sized(media, PHOTO_TARGET, out);
}

int exteria_media_uses_picture(exteria_preview_kind kind, int has_file, int has_preview, int has_local_preview) {
    if (kind == EXTERIA_PREVIEW_PHOTO) return has_file || has_local_preview;
    if (kind == EXTERIA_PREVIEW_VIDEO || kind == EXTERIA_PREVIEW_VIDEO_MESSAGE || kind == EXTERIA_PREVIEW_GIF)
        return has_file || has_preview || has_local_preview;
    return 0;
}

int exteria_media_opens_viewer(exteria_preview_kind kind) {
    return kind == EXTERIA_PREVIEW_PHOTO || kind == EXTERIA_PREVIEW_VIDEO;
}


void exteria_photo_read(const exteria_tl_value *photo, int32_t target, exteria_media_info *out) {
    memset(out, 0, sizeof(*out));
    read_photo(photo, target, out);
}

void exteria_document_read(const exteria_tl_value *document, exteria_media_info *out) {
    memset(out, 0, sizeof(*out));
    out->kind = EXTERIA_PREVIEW_FILE;
    read_document(document, NULL, out);
}

exteria_status exteria_sticker_read(const exteria_tl_value *document, exteria_sticker_row *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    read_document(document, NULL, &out->media);
    if (out->media.kind != EXTERIA_PREVIEW_STICKER || out->media.ref.source == EXTERIA_MEDIA_SOURCE_NONE) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    return EXTERIA_OK;
}

static exteria_entity_kind entity_kind(const exteria_tl_value *e) {
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityBold)) return EXTERIA_ENTITY_BOLD;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityItalic)) return EXTERIA_ENTITY_ITALIC;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityUnderline)) return EXTERIA_ENTITY_UNDERLINE;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityStrike)) return EXTERIA_ENTITY_STRIKE;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityCode)) return EXTERIA_ENTITY_CODE;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityPre)) return EXTERIA_ENTITY_PRE;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntitySpoiler)) return EXTERIA_ENTITY_SPOILER;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityBlockquote)) return EXTERIA_ENTITY_BLOCKQUOTE;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityMentionName)) return EXTERIA_ENTITY_MENTION_NAME;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityFormattedDate)) return EXTERIA_ENTITY_FORMATTED_DATE;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityUrl)) return EXTERIA_ENTITY_URL;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityTextUrl)) return EXTERIA_ENTITY_TEXT_URL;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityEmail)) return EXTERIA_ENTITY_EMAIL;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityMention)) return EXTERIA_ENTITY_MENTION;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityHashtag)) return EXTERIA_ENTITY_HASHTAG;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityCustomEmoji)) return EXTERIA_ENTITY_CUSTOM_EMOJI;
    if (exteria_tl_is(e, EXTERIA_TL_ID_messageEntityBotCommand)) return EXTERIA_ENTITY_BOT_COMMAND;
    return (exteria_entity_kind)0;
}

void exteria_entities_read(const exteria_tl_value *message, exteria_entity *entities, size_t capacity,
                           char *urls, size_t urls_capacity, uint8_t *count) {
    const exteria_tl_value *list = exteria_tl_get(message, "entities");
    size_t pool = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!count || !entities || !urls || capacity > EXTERIA_MESSAGE_ENTITIES_MAX || urls_capacity > INT16_MAX) return;
    if (!is_vec(list)) return;
    for (i = 0; i < list->u.vec.count && *count < capacity; ++i) {
        const exteria_tl_value *e = list->u.vec.items[i];
        exteria_entity *out = &entities[*count];
        exteria_entity_kind kind = entity_kind(e);
        int32_t offset, length;
        if (!kind || exteria_tl_get_i32(e, "offset", &offset) != EXTERIA_OK || exteria_tl_get_i32(e, "length", &length) != EXTERIA_OK ||
            offset < 0 || length <= 0) continue;
        out->kind = (uint8_t)kind;
        out->offset = offset;
        out->length = length;
        out->url_offset = -1;
        out->url_length = 0;
        out->document_id = 0;
        out->user_id = 0;
        out->date = 0;
        out->flags = 0;
        /* an emoji without its document has nothing to draw, so the plain text stays */
        if (kind == EXTERIA_ENTITY_CUSTOM_EMOJI && (exteria_tl_get_i64(e, "document_id", &out->document_id) != EXTERIA_OK || out->document_id == 0)) continue;
        /* a name that points at nobody opens nothing, so it stays plain text */
        if (kind == EXTERIA_ENTITY_MENTION_NAME && (exteria_tl_get_i64(e, "user_id", &out->user_id) != EXTERIA_OK || out->user_id <= 0)) continue;
        if (kind == EXTERIA_ENTITY_BLOCKQUOTE && exteria_tl_has(e, "collapsed")) out->flags |= EXTERIA_ENTITY_COLLAPSED;
        if (kind == EXTERIA_ENTITY_FORMATTED_DATE) {
            static const char *const names[] = {"relative", "short_time", "long_time", "short_date", "long_date", "day_of_week"};
            size_t k;
            if (exteria_tl_get_i32(e, "date", &out->date) != EXTERIA_OK) continue;
            for (k = 0; k < sizeof(names) / sizeof(names[0]); ++k) {
                if (exteria_tl_has(e, names[k])) out->flags |= (uint8_t)(1u << k);
            }
        }
        if (kind == EXTERIA_ENTITY_PRE) {
            const uint8_t *language;
            size_t len;
            /* a block of code without a readable language is still a block of code */
            if (exteria_tl_get_bytes(e, "language", &language, &len) == EXTERIA_OK && len > 0 && len < urls_capacity - pool) {
                memcpy(urls + pool, language, len);
                urls[pool + len] = 0;
                out->url_offset = (int16_t)pool;
                out->url_length = (int16_t)len;
                pool += len + 1;
            }
        }
        if (kind == EXTERIA_ENTITY_TEXT_URL) {
            const uint8_t *url;
            size_t len;
            /* a link whose address does not fit the pool is shown as plain text, not with a wrong target */
            if (exteria_tl_get_bytes(e, "url", &url, &len) != EXTERIA_OK || len == 0 || len >= urls_capacity - pool) continue;
            memcpy(urls + pool, url, len);
            urls[pool + len] = 0;
            out->url_offset = (int16_t)pool;
            out->url_length = (int16_t)len;
            pool += len + 1;
        }
        ++*count;
    }
}

static exteria_service_kind service_kind(const exteria_tl_value *action) {
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatCreate)) return EXTERIA_SERVICE_CHAT_CREATE;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatEditTitle)) return EXTERIA_SERVICE_TITLE;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatEditPhoto)) return EXTERIA_SERVICE_PHOTO_CHANGED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatDeletePhoto)) return EXTERIA_SERVICE_PHOTO_DELETED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatAddUser)) return EXTERIA_SERVICE_USER_ADDED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatDeleteUser)) return EXTERIA_SERVICE_USER_REMOVED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatJoinedByLink) ||
        exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatJoinedByRequest)) return EXTERIA_SERVICE_JOINED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionChannelCreate)) return EXTERIA_SERVICE_CHANNEL_CREATE;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionPinMessage)) return EXTERIA_SERVICE_PIN;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionPhoneCall)) return EXTERIA_SERVICE_CALL;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionStarGift) || exteria_tl_is(action, EXTERIA_TL_ID_messageActionStarGiftUnique))
        return EXTERIA_SERVICE_GIFT;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionContactSignUp)) return EXTERIA_SERVICE_CONTACT_JOINED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionScreenshotTaken)) return EXTERIA_SERVICE_SCREENSHOT;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionHistoryClear)) return EXTERIA_SERVICE_HISTORY_CLEAR;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatMigrateTo) ||
        exteria_tl_is(action, EXTERIA_TL_ID_messageActionChannelMigrateFrom)) return EXTERIA_SERVICE_MIGRATED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionCustomAction)) return EXTERIA_SERVICE_CUSTOM;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionGroupCall) ||
        exteria_tl_is(action, EXTERIA_TL_ID_messageActionGroupCallScheduled)) return EXTERIA_SERVICE_VIDEO_CHAT;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionInviteToGroupCall)) return EXTERIA_SERVICE_VIDEO_CHAT_INVITE;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionTopicCreate)) return EXTERIA_SERVICE_TOPIC_CREATE;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionTopicEdit)) return EXTERIA_SERVICE_TOPIC_EDIT;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionSetMessagesTTL)) return EXTERIA_SERVICE_TTL;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionBoostApply)) return EXTERIA_SERVICE_BOOST;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionPaymentSent) || exteria_tl_is(action, EXTERIA_TL_ID_messageActionPaymentSentMe))
        return EXTERIA_SERVICE_PAYMENT;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionBotAllowed)) return EXTERIA_SERVICE_BOT_ALLOWED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionGiftPremium) || exteria_tl_is(action, EXTERIA_TL_ID_messageActionGiftCode))
        return EXTERIA_SERVICE_PREMIUM_GIFT;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionSetChatTheme)) return EXTERIA_SERVICE_THEME;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionSetChatWallPaper)) return EXTERIA_SERVICE_WALLPAPER;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionSuggestProfilePhoto)) return EXTERIA_SERVICE_PHOTO_SUGGESTED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionGameScore)) return EXTERIA_SERVICE_GAME_SCORE;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionGiveawayLaunch)) return EXTERIA_SERVICE_GIVEAWAY;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionGiveawayResults)) return EXTERIA_SERVICE_GIVEAWAY_RESULTS;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionPaymentRefunded)) return EXTERIA_SERVICE_PAYMENT_REFUNDED;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionNoForwardsRequest)) return EXTERIA_SERVICE_SHARING_REQUEST;
    if (exteria_tl_is(action, EXTERIA_TL_ID_messageActionNoForwardsToggle)) return EXTERIA_SERVICE_SHARING_TOGGLE;
    return EXTERIA_SERVICE_OTHER;
}

/* "messageActionGiftPremium" as "Gift premium": the app has no wording for the action, so it says what the server called it */
static void humanize_action(const exteria_tl_value *action, char *text, size_t cap) {
    static const char prefix[] = "messageAction";
    const char *name;
    size_t at = 0;
    if (!text || !cap || !action || action->kind != EXTERIA_TL_V_OBJ || !action->u.obj.ctor || !action->u.obj.ctor->name) return;
    name = action->u.obj.ctor->name;
    if (strncmp(name, prefix, sizeof(prefix) - 1) == 0) name += sizeof(prefix) - 1;
    for (; *name && at + 2 < cap; ++name) {
        if (at && *name >= 'A' && *name <= 'Z') {
            text[at++] = ' ';
            text[at++] = (char)(*name - 'A' + 'a');
        } else text[at++] = *name;
    }
    text[at] = 0;
}

uint8_t exteria_service_summary(const exteria_tl_value *action, char *text, size_t cap, int32_t *value, int64_t *target) {
    exteria_service_kind kind = service_kind(action);
    const exteria_tl_value *users;
    if (text && cap) text[0] = 0;
    if (value) *value = 0;
    if (target) *target = 0;
    if (!action) return (uint8_t)(EXTERIA_SERVICE_OTHER + 1);
    if (text && cap) {
        if (kind == EXTERIA_SERVICE_TITLE || kind == EXTERIA_SERVICE_CHAT_CREATE || kind == EXTERIA_SERVICE_CHANNEL_CREATE ||
            kind == EXTERIA_SERVICE_TOPIC_CREATE || kind == EXTERIA_SERVICE_MIGRATED) copy_text(text, cap, action, "title", 0);
        if (kind == EXTERIA_SERVICE_TOPIC_EDIT && exteria_tl_has(action, "title")) copy_text(text, cap, action, "title", 0);
        if (kind == EXTERIA_SERVICE_CUSTOM) copy_text(text, cap, action, "message", 1);
        if (kind == EXTERIA_SERVICE_THEME) {
            const exteria_tl_value *theme = exteria_tl_get(action, "theme");
            if (theme) copy_text(text, cap, theme, "emoticon", 0);
        }
    }
    if (target) {
        if (kind == EXTERIA_SERVICE_USER_REMOVED) exteria_tl_get_i64(action, "user_id", target);
        if (kind == EXTERIA_SERVICE_JOINED) exteria_tl_get_i64(action, "inviter_id", target);
        users = exteria_tl_get(action, "users");
        if ((kind == EXTERIA_SERVICE_USER_ADDED || kind == EXTERIA_SERVICE_VIDEO_CHAT_INVITE) && is_vec(users) && users->u.vec.count > 0 &&
            users->u.vec.items[0]->kind == EXTERIA_TL_V_I64) *target = users->u.vec.items[0]->u.i64;
    }
    if (value) {
        if (kind == EXTERIA_SERVICE_SHARING_REQUEST || kind == EXTERIA_SERVICE_SHARING_TOGGLE) {
            if (exteria_tl_is(exteria_tl_get(action, "prev_value"), EXTERIA_TL_ID_boolTrue)) *value |= 1;
            if (exteria_tl_is(exteria_tl_get(action, "new_value"), EXTERIA_TL_ID_boolTrue)) *value |= 2;
            if (kind == EXTERIA_SERVICE_SHARING_REQUEST && exteria_tl_has(action, "expired")) *value |= 4;
        }
        if (kind == EXTERIA_SERVICE_VIDEO_CHAT) exteria_tl_get_i32(action, "duration", value);
        if (kind == EXTERIA_SERVICE_TTL) exteria_tl_get_i32(action, "period", value);
        if (kind == EXTERIA_SERVICE_BOOST) exteria_tl_get_i32(action, "boosts", value);
        if (kind == EXTERIA_SERVICE_CALL) exteria_tl_get_i32(action, "duration", value);
        if (kind == EXTERIA_SERVICE_PREMIUM_GIFT) {
            /* the layers count the subscription in days now, and older ones in months; the line says months */
            int32_t days = 0;
            if (exteria_tl_get_i32(action, "days", &days) == EXTERIA_OK && days > 0) *value = (days + 15) / 30;
            else exteria_tl_get_i32(action, "months", value);
        }
        if (kind == EXTERIA_SERVICE_GAME_SCORE) exteria_tl_get_i32(action, "score", value);
        if (kind == EXTERIA_SERVICE_GIVEAWAY_RESULTS) exteria_tl_get_i32(action, "winners_count", value);
        if (kind == EXTERIA_SERVICE_TOPIC_EDIT) {
            if (exteria_tl_is(exteria_tl_get(action, "closed"), EXTERIA_TL_ID_boolTrue)) *value = 1;
            else if (exteria_tl_is(exteria_tl_get(action, "closed"), EXTERIA_TL_ID_boolFalse)) *value = 2;
        }
        if (*value < 0) *value = 0;
    }
    if (kind == EXTERIA_SERVICE_OTHER) humanize_action(action, text, cap);
    return (uint8_t)(kind + 1);
}

static void read_service(const exteria_tl_value *action, exteria_message_row *row) {
    row->service = exteria_service_summary(action, row->text, sizeof(row->text), &row->service_value, &row->target_id);
    if (row->service - 1 == EXTERIA_SERVICE_CALL) {
        const exteria_tl_value *reason = exteria_tl_get(action, "reason");
        row->call_video = exteria_tl_has(action, "video") ? 1 : 0;
        if (exteria_tl_is(reason, EXTERIA_TL_ID_phoneCallDiscardReasonMissed)) row->call_reason = EXTERIA_OUTCOME_MISSED;
        else if (exteria_tl_is(reason, EXTERIA_TL_ID_phoneCallDiscardReasonBusy)) row->call_reason = EXTERIA_OUTCOME_BUSY;
        else if (exteria_tl_is(reason, EXTERIA_TL_ID_phoneCallDiscardReasonDisconnect)) row->call_reason = EXTERIA_OUTCOME_DISCONNECTED;
    }
    if (row->service - 1 == EXTERIA_SERVICE_GIFT) {
        const exteria_tl_value *note = exteria_tl_get(action, "message");
        /* a gift that cannot be read stays a plain service line without a picture */
        if (exteria_gift_read(exteria_tl_get(action, "gift"), &row->gift) != EXTERIA_OK) memset(&row->gift, 0, sizeof(row->gift));
        if (note) copy_text(row->text, sizeof(row->text), note, "text", 1);
    }
}

/* a messageReplies of a post: the comment count and the first few commenters who are users */
static void read_comments(const exteria_tl_value *replies, exteria_message_row *out) {
    const exteria_tl_value *list;
    uint32_t i;
    int32_t count = 0;
    if (!exteria_tl_is(replies, EXTERIA_TL_ID_messageReplies) || !exteria_tl_has(replies, "comments")) return;
    exteria_tl_get_i32(replies, "replies", &count);
    out->has_comments = 1;
    out->comments = count > 0 ? count : 0;
    exteria_tl_get_i64(replies, "channel_id", &out->discussion_id);
    list = exteria_tl_get(replies, "recent_repliers");
    for (i = 0; list && list->kind == EXTERIA_TL_V_VEC && i < list->u.vec.count && out->commenter_count < 3; ++i) {
        exteria_peer who;
        if (exteria_peer_from_tl(list->u.vec.items[i], &who) == EXTERIA_OK && who.kind == 1) out->commenters[out->commenter_count++] = who.id;
    }
}

/* UTF-16 units of a UTF-8 string, which is how entity offsets count */
static int32_t utf16_units(const char *s) {
    int32_t units = 0;
    for (; *s; ++s) {
        unsigned char c = (unsigned char)*s;
        if ((c & 0xC0u) == 0x80u) continue;
        units += c >= 0xF0u ? 2 : 1;
    }
    return units;
}

/* a bot's invoice has no text of its own: the title in bold, the description and, for an invoice in stars, the price take its place, so the
   bubble says what it sells above the button that pays */
static void read_invoice(const exteria_tl_value *media, exteria_message_row *row) {
    char title[256], description[EXTERIA_MESSAGE_TEXT_MAX / 2];
    const uint8_t *currency;
    size_t currency_len, used;
    int64_t total = 0;
    if (!exteria_tl_is(media, EXTERIA_TL_ID_messageMediaInvoice) || row->text[0]) return;
    copy_text(title, sizeof(title), media, "title", 0);
    copy_text(description, sizeof(description), media, "description", 1);
    if (!title[0] && !description[0]) return;
    used = (size_t)snprintf(row->text, sizeof(row->text), "%s%s%s", title, title[0] && description[0] ? "\n" : "", description);
    if (used >= sizeof(row->text)) used = sizeof(row->text) - 1;
    if (title[0] && row->entity_count < EXTERIA_MESSAGE_ENTITIES_MAX) {
        exteria_entity *bold = &row->entities[row->entity_count++];
        memset(bold, 0, sizeof(*bold));
        bold->kind = EXTERIA_ENTITY_BOLD;
        bold->offset = 0;
        bold->length = utf16_units(title);
        bold->url_offset = -1;
    }
    if (exteria_tl_get_bytes(media, "currency", &currency, &currency_len) == EXTERIA_OK && currency_len == 3 && !memcmp(currency, "XTR", 3) &&
        exteria_tl_get_i64(media, "total_amount", &total) == EXTERIA_OK && total > 0 && used + 24 < sizeof(row->text))
        snprintf(row->text + used, sizeof(row->text) - used, "\n\n\xE2\xAD\x90 %lld", (long long)total);
}

exteria_status exteria_message_read(const exteria_tl_value *m, exteria_message_row *out) {
    exteria_peer from;
    const exteria_tl_value *header;
    int service;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(m, EXTERIA_TL_ID_messageEmpty)) return EXTERIA_E_NOTFOUND;
    service = exteria_tl_is(m, EXTERIA_TL_ID_messageService);
    if ((!service && !exteria_tl_is(m, EXTERIA_TL_ID_message)) || exteria_tl_get_i32(m, "id", &out->id) != EXTERIA_OK ||
        out->id <= 0 || exteria_tl_get_i32(m, "date", &out->date) != EXTERIA_OK) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    {
        exteria_status status = exteria_reactions_read(exteria_tl_get(m, "reactions"), &out->reactions);
        if (status != EXTERIA_OK) { memset(out, 0, sizeof(*out)); return status; }
    }
    out->has_reactions = exteria_tl_has(m, "reactions") ? 1 : 0;
    out->reactions_possible = !service || exteria_tl_has(m, "reactions_are_possible");
    out->out = exteria_tl_has(m, "out") ? 1 : 0;
    out->unread_mention = exteria_tl_has(m, "mentioned") && exteria_tl_has(m, "media_unread") ? 1 : 0;
    out->post = exteria_tl_has(m, "post") ? 1 : 0;
    if (exteria_peer_from_tl(exteria_tl_get(m, "from_id"), &from) == EXTERIA_OK) {
        if (from.kind == 1) out->from_id = from.id;
        else if (from.kind == 3) out->from_channel = from.id;
    }
    header = exteria_tl_get(m, "reply_to");
    if (header) {
        exteria_tl_get_i32(header, "reply_to_msg_id", &out->reply_to);
        if (exteria_tl_get_i32(header, "reply_to_top_id", &out->thread_id) != EXTERIA_OK || out->thread_id <= 0) out->thread_id = out->reply_to;
        const exteria_tl_value *reply_peer = exteria_tl_get(header, "reply_to_peer_id");
        if (reply_peer) {
            exteria_peer origin;
            if (exteria_peer_from_tl(reply_peer, &origin) != EXTERIA_OK) {
                memset(out, 0, sizeof(*out));
                return EXTERIA_E_MALFORMED;
            }
            out->reply_peer_kind = origin.kind;
            out->reply_peer_id = origin.id;
        }
        copy_text(out->reply_quote, sizeof(out->reply_quote), header, "quote_text", 0);
    }
    out->topic_id = 1;
    if (header && exteria_tl_has(header, "forum_topic")) {
        /* inside a topic the thread root is in reply_to_top_id, or in reply_to_msg_id for a message that answers the root itself */
        int32_t top = 0;
        if (exteria_tl_get_i32(header, "reply_to_top_id", &top) != EXTERIA_OK || top <= 0) top = out->reply_to;
        if (top > 0) out->topic_id = top;
        if (out->reply_to == out->topic_id) out->reply_to = 0;
    }
    out->media.kind = EXTERIA_PREVIEW_TEXT;
    if (service) {
        read_service(exteria_tl_get(m, "action"), out);
        out->media.kind = EXTERIA_PREVIEW_SERVICE;
        return EXTERIA_OK;
    }
    exteria_tl_get_i32(m, "edit_date", &out->edit_date);
    out->edit_hide = exteria_tl_has(m, "edit_hide") ? 1 : 0;
    copy_text(out->from_rank, sizeof(out->from_rank), m, "from_rank", 0);
    exteria_tl_get_i32(m, "views", &out->views);
    if (out->views < 0) out->views = 0;
    read_comments(exteria_tl_get(m, "replies"), out);
    if (exteria_tl_has(m, "via_bot_id")) exteria_tl_get_i64(m, "via_bot_id", &out->via_bot_id);
    out->has_markup = exteria_tl_has(m, "reply_markup") ? 1 : 0;
    {
        exteria_peer origin;
        if (exteria_peer_from_tl(exteria_tl_get(m, "saved_peer_id"), &origin) == EXTERIA_OK) {
            out->saved_peer_kind = origin.kind;
            out->saved_peer_id = origin.id;
        }
    }
    header = exteria_tl_get(m, "fwd_from");
    if (header) {
        exteria_peer origin;
        out->forwarded = 1;
        out->forward_saved_out = exteria_tl_has(header, "saved_out") ? 1 : 0;
        copy_text(out->forward_name, sizeof(out->forward_name), header, "from_name", 0);
        exteria_tl_get_i32(header, "date", &out->forward_date);
        if (exteria_peer_from_tl(exteria_tl_get(header, "from_id"), &origin) == EXTERIA_OK) {
            if (origin.kind == 1) out->forward_from = origin.id;
            else if (origin.kind == 3) out->forward_from = -origin.id;
        }
    }
    if (exteria_tl_has(m, "grouped_id")) exteria_tl_get_i64(m, "grouped_id", &out->grouped_id);
    copy_text(out->text, sizeof(out->text), m, "message", 1);
    exteria_media_classify(exteria_tl_get(m, "media"), &out->media);
    exteria_entities_read(m, out->entities, EXTERIA_MESSAGE_ENTITIES_MAX, out->urls, sizeof(out->urls), &out->entity_count);
    read_invoice(exteria_tl_get(m, "media"), out);
    exteria_poll_read(exteria_tl_get(m, "media"), &out->poll);
    return EXTERIA_OK;
}

exteria_status exteria_messages_parse(const exteria_tl_value *answer, exteria_message_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *messages;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_messagesNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_messages) && !exteria_tl_is(answer, EXTERIA_TL_ID_messages_messagesSlice) &&
        !exteria_tl_is(answer, EXTERIA_TL_ID_messages_channelMessages)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "messages", &messages) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < messages->u.vec.count && n < cap; ++i) {
        if (exteria_message_read(messages->u.vec.items[i], &rows[n]) == EXTERIA_OK) ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

static void read_set(const exteria_tl_value *s, exteria_sticker_set_row *set) {
    int32_t value;
    const exteria_tl_value *thumbs;
    memset(set, 0, sizeof(*set));
    exteria_tl_get_i64(s, "id", &set->id);
    exteria_tl_get_i64(s, "access_hash", &set->access_hash);
    if (exteria_tl_get_i32(s, "count", &value) == EXTERIA_OK) set->count = value;
    if (exteria_tl_get_i32(s, "hash", &value) == EXTERIA_OK) set->hash = value;
    set->official = exteria_tl_has(s, "official") ? 1 : 0;
    set->installed = exteria_tl_has(s, "installed_date") ? 1 : 0;
    exteria_tl_get_i64(s, "thumb_document_id", &set->thumb_document_id);
    copy_text(set->title, sizeof(set->title), s, "title", 0);
    copy_text(set->short_name, sizeof(set->short_name), s, "short_name", 0);
    thumbs = exteria_tl_get(s, "thumbs");
    if (is_vec(thumbs) && thumbs->u.vec.count > 0) {
        if (exteria_tl_get_i32(s, "thumb_dc_id", &value) == EXTERIA_OK) set->thumb_dc = value;
        if (exteria_tl_get_i32(s, "thumb_version", &value) == EXTERIA_OK) set->thumb_version = value;
    }
}

static exteria_status sets_parse(const exteria_tl_value *answer, exteria_sticker_set_row *sets, size_t cap, size_t *count, int emojis) {
    const exteria_tl_value *list;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !sets || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_allStickersNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_allStickers) || exteria_tl_get_vec(answer, "sets", &list) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *s = list->u.vec.items[i];
        if (!exteria_tl_is(s, EXTERIA_TL_ID_stickerSet) || exteria_tl_has(s, "masks") || exteria_tl_has(s, "archived") ||
            (exteria_tl_has(s, "emojis") ? 1 : 0) != emojis) continue;
        read_set(s, &sets[n]);
        if (sets[n].id == 0) continue;
        ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_sticker_sets_parse(const exteria_tl_value *answer, exteria_sticker_set_row *sets, size_t cap, size_t *count) {
    return sets_parse(answer, sets, cap, count, 0);
}

exteria_status exteria_emoji_sets_parse(const exteria_tl_value *answer, exteria_sticker_set_row *sets, size_t cap, size_t *count) {
    return sets_parse(answer, sets, cap, count, 1);
}

/* the sets of a list of StickerSetCovered, every constructor of which carries its header in "set" */
static exteria_status covered_parse(const exteria_tl_value *list, exteria_sticker_set_row *sets, size_t cap, size_t *count, int archive) {
    uint32_t i;
    size_t n = 0;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *s = exteria_tl_get(list->u.vec.items[i], "set");
        if (!exteria_tl_is(s, EXTERIA_TL_ID_stickerSet) || exteria_tl_has(s, "masks") || exteria_tl_has(s, "emojis")) continue;
        read_set(s, &sets[n]);
        if (sets[n].id == 0) continue;
        /* a set in the archive has an installed date too, and is not among the ones the panel shows */
        if (exteria_tl_has(s, "archived") || archive) sets[n].installed = 0;
        ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_featured_stickers_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getFeaturedStickers");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_featured_stickers_parse(const exteria_tl_value *answer, exteria_sticker_set_row *sets, size_t cap, size_t *count) {
    const exteria_tl_value *list;
    if (count) *count = 0;
    if (!answer || !sets || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_featuredStickersNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_featuredStickers) || exteria_tl_get_vec(answer, "sets", &list) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    return covered_parse(list, sets, cap, count, 0);
}

exteria_status exteria_archived_stickers_request(exteria_arena *arena, int64_t offset_id, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || limit < 1 || limit > 100 || offset_id < 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getArchivedStickers");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, request, "offset_id", offset_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_archived_stickers_parse(const exteria_tl_value *answer, exteria_sticker_set_row *sets, size_t cap, size_t *count, int32_t *total) {
    const exteria_tl_value *list;
    int32_t all = 0;
    exteria_status status;
    if (count) *count = 0;
    if (total) *total = 0;
    if (!answer || !sets || !count || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_archivedStickers) || exteria_tl_get_vec(answer, "sets", &list) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    status = covered_parse(list, sets, cap, count, 1);
    if (status == EXTERIA_OK && total) {
        if (exteria_tl_get_i32(answer, "count", &all) != EXTERIA_OK || all < 0) all = (int32_t)*count;
        *total = all;
    }
    return status;
}

exteria_status exteria_emoji_sets_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!arena || !out) return EXTERIA_E_ARG;
    *out = NULL;
    request = exteria_tl_new_obj(arena, "messages.getEmojiStickers");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_emoji_set_parse(const exteria_tl_value *answer, exteria_sticker_set_row *set, exteria_custom_emoji *rows,
                                       size_t cap, size_t *count) {
    const exteria_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !set || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickerSetNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickerSet) || !exteria_tl_is(exteria_tl_get(answer, "set"), EXTERIA_TL_ID_stickerSet) ||
        exteria_tl_get_vec(answer, "documents", &documents) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    read_set(exteria_tl_get(answer, "set"), set);
    return exteria_custom_emoji_parse(documents, rows, cap, count);
}

static size_t read_stickers(const exteria_tl_value *documents, exteria_sticker_row *stickers, size_t cap) {
    uint32_t i;
    size_t n = 0;
    for (i = 0; i < documents->u.vec.count && n < cap; ++i) {
        if (exteria_sticker_read(documents->u.vec.items[i], &stickers[n]) == EXTERIA_OK) ++n;
    }
    return n;
}

exteria_status exteria_sticker_set_parse(const exteria_tl_value *answer, exteria_sticker_set_row *set,
                                         exteria_sticker_row *stickers, size_t cap, size_t *count) {
    const exteria_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !set || !stickers || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickerSetNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickerSet) || !exteria_tl_is(exteria_tl_get(answer, "set"), EXTERIA_TL_ID_stickerSet) ||
        exteria_tl_get_vec(answer, "documents", &documents) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    read_set(exteria_tl_get(answer, "set"), set);
    *count = read_stickers(documents, stickers, cap);
    return EXTERIA_OK;
}

exteria_status exteria_sticker_set_by_name_request(exteria_arena *arena, const char *short_name, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !short_name || !out) return EXTERIA_E_ARG;
    for (i = 0; short_name[i]; ++i) {
        char c = short_name[i];
        if (i >= 64 || !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')) return EXTERIA_E_ARG;
    }
    if (i == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getStickerSet");
    input = exteria_tl_new_obj(arena, "inputStickerSetShortName");
    if (!request || !input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, input, "short_name", short_name);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "stickerset", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_animated_emoji_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getStickerSet");
    input = exteria_tl_new_obj(arena, "inputStickerSetAnimatedEmoji");
    if (!request || !input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "stickerset", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_animated_emoji_parse(const exteria_tl_value *answer, exteria_sticker_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *packs, *documents;
    size_t written = 0;
    if (count) *count = 0;
    if (!answer || !rows || !cap || !count) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickerSetNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickerSet) ||
        !exteria_tl_is(exteria_tl_get(answer, "set"), EXTERIA_TL_ID_stickerSet) ||
        exteria_tl_get_vec(answer, "packs", &packs) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "documents", &documents) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (packs->u.vec.count > EXTERIA_ANIMATED_EMOJI_MAX || documents->u.vec.count > EXTERIA_ANIMATED_EMOJI_MAX) return EXTERIA_E_LIMIT;
    for (uint32_t i = 0; i < packs->u.vec.count && written < cap; ++i) {
        const exteria_tl_value *pack = packs->u.vec.items[i], *ids;
        const uint8_t *emoticon;
        size_t length;
        if (!exteria_tl_is(pack, EXTERIA_TL_ID_stickerPack) ||
            exteria_tl_get_bytes(pack, "emoticon", &emoticon, &length) != EXTERIA_OK || !length ||
            length >= sizeof(rows[0].media.alt) || memchr(emoticon, 0, length) ||
            exteria_tl_get_vec(pack, "documents", &ids) != EXTERIA_OK || !ids->u.vec.count) continue;
        const exteria_tl_value *first = ids->u.vec.items[0];
        if (!first || first->kind != EXTERIA_TL_V_I64 || first->u.i64 <= 0) continue;
        for (uint32_t j = 0; j < documents->u.vec.count; ++j) {
            int64_t id = 0;
            const exteria_tl_value *document = documents->u.vec.items[j];
            if (exteria_tl_get_i64(document, "id", &id) != EXTERIA_OK || id != first->u.i64) continue;
            exteria_sticker_row row;
            if (exteria_sticker_read(document, &row) != EXTERIA_OK || row.media.sticker != EXTERIA_STICKER_ANIMATED ||
                row.media.size <= 0 || row.media.size > EXTERIA_ANIMATED_EMOJI_BYTES_MAX) break;
            memcpy(row.media.alt, emoticon, length);
            row.media.alt[length] = 0;
            rows[written++] = row;
            break;
        }
    }
    *count = written;
    return EXTERIA_OK;
}

exteria_status exteria_recent_stickers_parse(const exteria_tl_value *answer, exteria_sticker_row *stickers, size_t cap, size_t *count) {
    const exteria_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !stickers || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_recentStickersNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_recentStickers) || exteria_tl_get_vec(answer, "stickers", &documents) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    *count = read_stickers(documents, stickers, cap);
    return EXTERIA_OK;
}

static int sent_in_update(const exteria_tl_value *update, int64_t random_id, int32_t *id) {
    int64_t random;
    if (!exteria_tl_is(update, EXTERIA_TL_ID_updateMessageID) || exteria_tl_get_i64(update, "random_id", &random) != EXTERIA_OK ||
        random != random_id) return 0;
    return exteria_tl_get_i32(update, "id", id) == EXTERIA_OK && *id > 0;
}

exteria_status exteria_sent_parse(const exteria_tl_value *updates, int64_t random_id, int32_t *id) {
    const exteria_tl_value *list;
    uint32_t i;
    if (!updates || !id) return EXTERIA_E_ARG;
    *id = 0;
    if (exteria_tl_is(updates, EXTERIA_TL_ID_updateShortSentMessage)) {
        return exteria_tl_get_i32(updates, "id", id) == EXTERIA_OK && *id > 0 ? EXTERIA_OK : EXTERIA_E_MALFORMED;
    }
    if (exteria_tl_is(updates, EXTERIA_TL_ID_updateShort)) return sent_in_update(exteria_tl_get(updates, "update"), random_id, id) ? EXTERIA_OK : EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(updates, EXTERIA_TL_ID_updates) && !exteria_tl_is(updates, EXTERIA_TL_ID_updatesCombined)) return EXTERIA_E_NOTFOUND;
    list = exteria_tl_get(updates, "updates");
    if (!is_vec(list)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < list->u.vec.count; ++i) if (sent_in_update(list->u.vec.items[i], random_id, id)) return EXTERIA_OK;
    return EXTERIA_E_NOTFOUND;
}

exteria_status exteria_input_peer(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out) {
    exteria_tl_value *v;
    exteria_status status;
    if (!arena || !peer || !out) return EXTERIA_E_ARG;
    *out = NULL;
    if (peer->self) {
        v = exteria_tl_new_obj(arena, "inputPeerSelf");
        if (!v) return EXTERIA_E_NOMEM;
        *out = v;
        return EXTERIA_OK;
    }
    if (peer->id <= 0 || peer->kind < 1 || peer->kind > 3 || (peer->kind != 2 && peer->access_hash == 0)) return EXTERIA_E_ARG;
    v = exteria_tl_new_obj(arena, peer->kind == 1 ? "inputPeerUser" : peer->kind == 2 ? "inputPeerChat" : "inputPeerChannel");
    if (!v) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, v, peer->kind == 1 ? "user_id" : peer->kind == 2 ? "chat_id" : "channel_id", peer->id);
    if (status == EXTERIA_OK && peer->kind != 2) status = exteria_tl_set_i64(arena, v, "access_hash", peer->access_hash);
    if (status == EXTERIA_OK) *out = v;
    return status;
}

exteria_status exteria_peer_dialogs_request(exteria_arena *arena, const exteria_peer_ref *peers, size_t count, exteria_tl_value **out) {
    exteria_tl_value *call, *list;
    exteria_status status = EXTERIA_OK;
    if (out) *out = NULL;
    if (!arena || !peers || !out || count == 0 || count > 100) return EXTERIA_E_ARG;
    call = exteria_tl_new_obj(arena, "messages.getPeerDialogs");
    list = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!call || !list) return EXTERIA_E_NOMEM;
    for (size_t i = 0; i < count && status == EXTERIA_OK; ++i) {
        exteria_tl_value *input = NULL;
        exteria_tl_value *entry = exteria_tl_new_obj(arena, "inputDialogPeer");
        if (!entry) return EXTERIA_E_NOMEM;
        status = exteria_input_peer(arena, &peers[i], &input);
        if (status == EXTERIA_OK) status = exteria_tl_set(entry, "peer", input);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, (uint32_t)i, entry);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(call, "peers", list);
    if (status == EXTERIA_OK) *out = call;
    return status;
}

/* a message sent into a topic answers the topic root, which is how the server files it; General has no root to answer */
exteria_status exteria_set_topic_reply(exteria_arena *arena, exteria_tl_value *request, const exteria_peer_ref *peer) {
    exteria_tl_value *reply;
    exteria_status status;
    if (peer->topic_id <= 1) return EXTERIA_OK;
    reply = exteria_tl_new_obj(arena, "inputReplyToMessage");
    if (!reply) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, reply, "reply_to_msg_id", peer->topic_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, reply, "top_msg_id", peer->topic_id);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "reply_to", reply);
    return status;
}

/* a reply names the message it answers; inside a topic it also names the topic, so the server files the reply there */
exteria_status exteria_set_reply(exteria_arena *arena, exteria_tl_value *request, const exteria_peer_ref *peer, int32_t reply_to) {
    exteria_tl_value *reply;
    exteria_status status;
    if (!arena || !request || !peer || reply_to < 0) return EXTERIA_E_ARG;
    if (reply_to == 0) return exteria_set_topic_reply(arena, request, peer);
    reply = exteria_tl_new_obj(arena, "inputReplyToMessage");
    if (!reply) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, reply, "reply_to_msg_id", reply_to);
    if (status == EXTERIA_OK && peer->topic_id > 1) status = exteria_tl_set_i32(arena, reply, "top_msg_id", peer->topic_id);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "reply_to", reply);
    return status;
}

exteria_status exteria_stickers_request(exteria_arena *arena, const char *emoticon, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !emoticon || !out || !emoticon[0] || strlen(emoticon) > EXTERIA_STICKER_EMOTICON_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getStickers");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "emoticon", emoticon);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status != EXTERIA_OK) return status;
    *out = request;
    return EXTERIA_OK;
}

exteria_status exteria_stickers_parse(const exteria_tl_value *answer, exteria_sticker_row *stickers, size_t cap, size_t *count) {
    const exteria_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !stickers || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickersNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_stickers) || exteria_tl_get_vec(answer, "stickers", &documents) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    *count = read_stickers(documents, stickers, cap);
    return EXTERIA_OK;
}

/* messages.search of one chat with a filter and a text; everything else of the request stays at its neutral value */
static exteria_status chat_search_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_peer_ref *from, const char *query,
                                          const char *filter_name, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *filter, *sender = NULL;
    exteria_status status;
    if (!arena || !out || limit < 1 || limit > EXTERIA_MESSAGES_MAX) return EXTERIA_E_ARG;
    *out = NULL;
    status = exteria_input_peer(arena, peer, &input);
    if (status == EXTERIA_OK && from) status = exteria_input_peer(arena, from, &sender);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.search");
    filter = exteria_tl_new_obj(arena, filter_name);
    if (!request || !filter) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "q", query);
    if (status == EXTERIA_OK && sender) status = exteria_tl_set(request, "from_id", sender);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "filter", filter);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "min_date", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "max_date", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "add_offset", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "max_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "min_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_pinned_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!peer || !out || peer->topic_id < 0 || (peer->topic_id > 0 && peer->kind != 3)) return EXTERIA_E_ARG;
    status = chat_search_request(arena, peer, NULL, "", "inputMessagesFilterPinned", limit, &request);
    if (status == EXTERIA_OK && peer->topic_id > 0) status = exteria_tl_set_i32(arena, request, "top_msg_id", peer->topic_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* messages.getUnreadReactions or messages.readReactions of a chat or its topic; the history one takes the newest limit and nothing else */
static exteria_status reactions_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *name, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || peer->topic_id < 0 || (peer->topic_id > 0 && peer->kind != 3)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, name);
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK && peer->topic_id > 0) status = exteria_tl_set_i32(arena, request, "top_msg_id", peer->topic_id);
    if (status == EXTERIA_OK && limit > 0) status = exteria_tl_set_i32(arena, request, "offset_id", 0);
    if (status == EXTERIA_OK && limit > 0) status = exteria_tl_set_i32(arena, request, "add_offset", 0);
    if (status == EXTERIA_OK && limit > 0) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK && limit > 0) status = exteria_tl_set_i32(arena, request, "max_id", 0);
    if (status == EXTERIA_OK && limit > 0) status = exteria_tl_set_i32(arena, request, "min_id", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_unread_reactions_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t limit, exteria_tl_value **out) {
    if (limit < 1 || limit > EXTERIA_MESSAGES_MAX) return EXTERIA_E_ARG;
    return reactions_request(arena, peer, "messages.getUnreadReactions", limit, out);
}

exteria_status exteria_read_reactions_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out) {
    return reactions_request(arena, peer, "messages.readReactions", 0, out);
}

exteria_status exteria_chat_photos_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t limit, exteria_tl_value **out) {
    return chat_search_request(arena, peer, NULL, "", "inputMessagesFilterChatPhotos", limit, out);
}

exteria_status exteria_chat_search_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *query, int32_t limit,
                                           exteria_tl_value **out) {
    size_t len;
    if (out) *out = NULL;
    if (!query) return EXTERIA_E_ARG;
    len = strlen(query);
    if (len == 0) return EXTERIA_E_ARG;
    if (len > EXTERIA_CHAT_SEARCH_QUERY_MAX) return EXTERIA_E_LIMIT;
    return chat_search_request(arena, peer, NULL, query, "inputMessagesFilterEmpty", limit, out);
}

exteria_status exteria_chat_from_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_peer_ref *from, int32_t limit,
                                         exteria_tl_value **out) {
    if (out) *out = NULL;
    /* only a person can be searched for; a channel or a group has no history of its own in a chat it speaks in */
    if (!from || from->kind != 1) return EXTERIA_E_ARG;
    return chat_search_request(arena, peer, from, "", "inputMessagesFilterEmpty", limit, out);
}

exteria_status exteria_messages_by_id_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count, exteria_tl_value **out) {
    exteria_tl_value *request, *list, *channel = NULL;
    exteria_status status = EXTERIA_OK;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !peer || !out || !ids || count < 1 || count > EXTERIA_MESSAGES_MAX || peer->self) return EXTERIA_E_ARG;
    if (peer->kind == 3) {
        if (peer->id <= 0 || peer->access_hash == 0) return EXTERIA_E_ARG;
        channel = exteria_tl_new_obj(arena, "inputChannel");
        if (!channel) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i64(arena, channel, "channel_id", peer->id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, channel, "access_hash", peer->access_hash);
    } else if (peer->kind != 1 && peer->kind != 2) {
        return EXTERIA_E_ARG;
    }
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, channel ? "channels.getMessages" : "messages.getMessages");
    list = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!request || !list) return EXTERIA_E_NOMEM;
    for (i = 0; i < count && status == EXTERIA_OK; ++i) {
        exteria_tl_value *item;
        if (ids[i] <= 0) return EXTERIA_E_ARG;
        item = exteria_tl_new_obj(arena, "inputMessageID");
        if (!item) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i32(arena, item, "id", ids[i]);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, (uint32_t)i, item);
    }
    if (status == EXTERIA_OK && channel) status = exteria_tl_set(request, "channel", channel);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_history_window_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset_id, int32_t add_offset, int32_t limit,
                                              exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !peer || offset_id < 0 || limit < 1 || limit > EXTERIA_MESSAGES_MAX || add_offset > 0 || -add_offset >= limit) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, peer->topic_id > 0 ? "messages.getReplies" : "messages.getHistory");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK && peer->topic_id > 0) status = exteria_tl_set_i32(arena, request, "msg_id", peer->topic_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_date", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "add_offset", add_offset);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "max_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "min_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_history_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset_id, int32_t limit,
                                      exteria_tl_value **out) {
    return exteria_history_window_request(arena, peer, offset_id, 0, limit, out);
}

exteria_status exteria_saved_history_window_request(exteria_arena *arena, const exteria_peer_ref *source, int32_t offset_id, int32_t add_offset, int32_t limit,
                                                    exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || offset_id < 0 || limit < 1 || limit > EXTERIA_MESSAGES_MAX || add_offset > 0 || -add_offset >= limit) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, source, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.getSavedHistory");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_date", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "add_offset", add_offset);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "max_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "min_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_saved_history_request(exteria_arena *arena, const exteria_peer_ref *source, int32_t offset_id, int32_t limit,
                                             exteria_tl_value **out) {
    return exteria_saved_history_window_request(arena, source, offset_id, 0, limit, out);
}

exteria_status exteria_set_schedule(exteria_arena *arena, exteria_tl_value *request, int32_t date) {
    if (!arena || !request || date <= 0) return EXTERIA_E_ARG;
    return exteria_tl_set_i32(arena, request, "schedule_date", date);
}

exteria_status exteria_message_link_request(exteria_arena *arena, const exteria_peer_ref *channel, int32_t id, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !channel || !out || id <= 0 || channel->kind != 3 || channel->id <= 0 || channel->access_hash == 0) return EXTERIA_E_ARG;
    input = exteria_tl_new_obj(arena, "inputChannel");
    request = exteria_tl_new_obj(arena, "channels.exportMessageLink");
    if (!input || !request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "channel_id", channel->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", channel->access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "channel", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "id", id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_message_link_parse(const exteria_tl_value *answer, char *link, size_t cap) {
    const uint8_t *data;
    size_t len;
    if (link && cap) link[0] = 0;
    if (!link || cap < 2) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_exportedMessageLink) || exteria_tl_get_bytes(answer, "link", &data, &len) != EXTERIA_OK || !len) return EXTERIA_E_MALFORMED;
    if (len >= cap || len > 255) return EXTERIA_E_LIMIT;
    memcpy(link, data, len);
    link[len] = 0;
    return EXTERIA_OK;
}

/* the TL constructor of an entity the client sends, NULL for the kinds the server finds in the text by itself */
static const char *send_entity_name(uint8_t kind) {
    switch (kind) {
    case EXTERIA_ENTITY_BOLD: return "messageEntityBold";
    case EXTERIA_ENTITY_ITALIC: return "messageEntityItalic";
    case EXTERIA_ENTITY_UNDERLINE: return "messageEntityUnderline";
    case EXTERIA_ENTITY_STRIKE: return "messageEntityStrike";
    case EXTERIA_ENTITY_CODE: return "messageEntityCode";
    case EXTERIA_ENTITY_PRE: return "messageEntityPre";
    case EXTERIA_ENTITY_SPOILER: return "messageEntitySpoiler";
    case EXTERIA_ENTITY_BLOCKQUOTE: return "messageEntityBlockquote";
    case EXTERIA_ENTITY_TEXT_URL: return "messageEntityTextUrl";
    case EXTERIA_ENTITY_MENTION_NAME: return "inputMessageEntityMentionName";
    case EXTERIA_ENTITY_FORMATTED_DATE: return "messageEntityFormattedDate";
    case EXTERIA_ENTITY_CUSTOM_EMOJI: return "messageEntityCustomEmoji";
    default: return NULL;
    }
}

/* what the server would reject the whole message for: a range outside the text, or a kind without what it points at */
static int send_entity_valid(const exteria_send_entity *e, size_t units) {
    if (e->offset < 0 || e->length <= 0 || (size_t)e->offset + (size_t)e->length > units) return 0;
    switch (e->kind) {
    case EXTERIA_ENTITY_CUSTOM_EMOJI: return e->id != 0;
    case EXTERIA_ENTITY_TEXT_URL: return e->text && e->text[0];
    case EXTERIA_ENTITY_MENTION_NAME: return e->id > 0 && e->access_hash != 0;
    case EXTERIA_ENTITY_FORMATTED_DATE: return e->date > 0;
    default: return 1;
    }
}

static exteria_status build_send_entity(exteria_arena *arena, const exteria_send_entity *e, exteria_tl_value **out) {
    static const char *const date_flags[] = {"relative", "short_time", "long_time", "short_date", "long_date", "day_of_week"};
    exteria_tl_value *entity = exteria_tl_new_obj(arena, send_entity_name(e->kind)), *user;
    exteria_status status;
    size_t k;
    if (!entity) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, entity, "offset", e->offset);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, entity, "length", e->length);
    if (status != EXTERIA_OK) return status;
    switch (e->kind) {
    case EXTERIA_ENTITY_CUSTOM_EMOJI:
        status = exteria_tl_set_i64(arena, entity, "document_id", e->id);
        break;
    case EXTERIA_ENTITY_TEXT_URL:
        status = exteria_tl_set_str(arena, entity, "url", e->text);
        break;
    case EXTERIA_ENTITY_PRE:
        status = exteria_tl_set_str(arena, entity, "language", e->text ? e->text : "");
        break;
    case EXTERIA_ENTITY_BLOCKQUOTE:
        if (e->flags & EXTERIA_ENTITY_COLLAPSED) status = exteria_tl_set_flag(entity, "collapsed");
        break;
    case EXTERIA_ENTITY_MENTION_NAME:
        user = exteria_tl_new_obj(arena, "inputUser");
        if (!user) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i64(arena, user, "user_id", e->id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, user, "access_hash", e->access_hash);
        if (status == EXTERIA_OK) status = exteria_tl_set(entity, "user_id", user);
        break;
    case EXTERIA_ENTITY_FORMATTED_DATE:
        status = exteria_tl_set_i32(arena, entity, "date", e->date);
        for (k = 0; k < sizeof(date_flags) / sizeof(date_flags[0]) && status == EXTERIA_OK; ++k) {
            if (e->flags & (1u << k)) status = exteria_tl_set_flag(entity, date_flags[k]);
        }
        break;
    default:
        break;
    }
    if (status == EXTERIA_OK) *out = entity;
    return status;
}

/* the entity vector of a text being sent or kept as a draft; *out stays NULL when no entity is one the client sends. A range outside the text, or a kind
   without what it points at, would make the server reject the whole message, so it is EXTERIA_E_ARG here */
exteria_status exteria_send_entities_build(exteria_arena *arena, const char *text, const exteria_send_entity *entities, size_t entity_count,
                                          exteria_tl_value **out) {
    exteria_tl_value *list;
    exteria_status status = EXTERIA_OK;
    size_t i, at = 0, sent = 0, units = 0;
    if (out) *out = NULL;
    if (!arena || !text || !out || (entity_count && !entities) || entity_count > EXTERIA_MESSAGE_ENTITIES_MAX) return EXTERIA_E_ARG;
    for (i = 0; text[i]; ++i) {
        unsigned char c = (unsigned char)text[i];
        if ((c & 0xC0u) == 0x80u) continue;
        units += c >= 0xF0u ? 2 : 1;
    }
    for (i = 0; i < entity_count; ++i) {
        if (!send_entity_name(entities[i].kind)) continue;
        if (!send_entity_valid(&entities[i], units)) return EXTERIA_E_ARG;
        ++sent;
    }
    if (!sent) return EXTERIA_OK;
    list = exteria_tl_new_vec(arena, (uint32_t)sent);
    if (!list) return EXTERIA_E_NOMEM;
    for (i = 0; i < entity_count && status == EXTERIA_OK; ++i) {
        exteria_tl_value *entity = NULL;
        if (!send_entity_name(entities[i].kind)) continue;
        status = build_send_entity(arena, &entities[i], &entity);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, (uint32_t)at++, entity);
    }
    if (status == EXTERIA_OK) *out = list;
    return status;
}

static exteria_status send_text(exteria_arena *arena, const exteria_peer_ref *peer, const char *text, const exteria_send_entity *entities,
                                size_t entity_count, int64_t random_id, int32_t reply_to, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *list = NULL;
    exteria_status status;
    if (!arena || !text || !out || !text[0] || random_id == 0 || strlen(text) > EXTERIA_MESSAGE_TEXT_MAX - 4) return EXTERIA_E_ARG;
    *out = NULL;
    status = exteria_send_entities_build(arena, text, entities, entity_count, &list);
    if (status != EXTERIA_OK) return status;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.sendMessage");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_set_reply(arena, request, peer, reply_to);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", text);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK && list) status = exteria_tl_set(request, "entities", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_send_text_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *text,
                                        const exteria_send_entity *entities, size_t entity_count, int64_t random_id, exteria_tl_value **out) {
    return send_text(arena, peer, text, entities, entity_count, random_id, 0, out);
}

exteria_status exteria_send_text_reply_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *text,
                                               const exteria_send_entity *entities, size_t entity_count, int64_t random_id, int32_t reply_to,
                                               exteria_tl_value **out) {
    if (reply_to < 0) return EXTERIA_E_ARG;
    return send_text(arena, peer, text, entities, entity_count, random_id, reply_to, out);
}

static exteria_status document_input(exteria_arena *arena, const exteria_media_ref *ref, exteria_tl_value **out) {
    exteria_tl_value *document = exteria_tl_new_obj(arena, "inputDocument");
    exteria_status status;
    if (!document) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, document, "id", ref->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, document, "access_hash", ref->access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, document, "file_reference", ref->file_ref, ref->ref_len);
    if (status == EXTERIA_OK) *out = document;
    return status;
}

exteria_status exteria_faved_stickers_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getFavedStickers");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_saved_gifs_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getSavedGifs");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_faved_stickers_parse(const exteria_tl_value *answer, exteria_sticker_row *stickers, size_t cap, size_t *count) {
    const exteria_tl_value *documents;
    if (count) *count = 0;
    if (!answer || !stickers || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_favedStickersNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_favedStickers) || exteria_tl_get_vec(answer, "stickers", &documents) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    *count = read_stickers(documents, stickers, cap);
    return EXTERIA_OK;
}

exteria_status exteria_saved_gifs_parse(const exteria_tl_value *answer, exteria_sticker_row *gifs, size_t cap, size_t *count) {
    const exteria_tl_value *documents;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !gifs || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_savedGifsNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_savedGifs) || exteria_tl_get_vec(answer, "gifs", &documents) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < documents->u.vec.count && n < cap; ++i) {
        exteria_sticker_row *row = &gifs[n];
        memset(row, 0, sizeof(*row));
        read_document(documents->u.vec.items[i], NULL, &row->media);
        /* a document the server still lists but no longer has, or one that is no animation, has nothing to play */
        if (row->media.kind == EXTERIA_PREVIEW_GIF && row->media.ref.source == EXTERIA_MEDIA_SOURCE_DOCUMENT) ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_fave_sticker_request(exteria_arena *arena, const exteria_media_ref *sticker, int unfave, exteria_tl_value **out) {
    exteria_tl_value *request, *document, *flag;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !sticker || !out || sticker->source != EXTERIA_MEDIA_SOURCE_DOCUMENT || sticker->thumb[0] || sticker->id == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.faveSticker");
    flag = exteria_tl_new_obj(arena, unfave ? "boolTrue" : "boolFalse");
    if (!request || !flag) return EXTERIA_E_NOMEM;
    status = document_input(arena, sticker, &document);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", document);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "unfave", flag);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_clear_recent_stickers_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.clearRecentStickers");
    if (!request) return EXTERIA_E_NOMEM;
    *out = request;
    return EXTERIA_OK;
}

exteria_status exteria_send_sticker_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_media_ref *sticker,
                                           int64_t random_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *media, *document;
    exteria_status status;
    if (!arena || !sticker || !out || random_id == 0 || sticker->source != EXTERIA_MEDIA_SOURCE_DOCUMENT || sticker->thumb[0]) return EXTERIA_E_ARG;
    *out = NULL;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    media = exteria_tl_new_obj(arena, "inputMediaDocument");
    request = exteria_tl_new_obj(arena, "messages.sendMedia");
    if (!media || !request) return EXTERIA_E_NOMEM;
    status = document_input(arena, sticker, &document);
    if (status == EXTERIA_OK) status = exteria_tl_set(media, "id", document);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_set_topic_reply(arena, request, peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "media", media);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", "");
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* the document attributes of a kind, or NULL when the spec does not carry what the kind needs */
static exteria_tl_value *upload_attribute(exteria_arena *arena, const exteria_upload_spec *spec, exteria_status *status) {
    exteria_tl_value *attribute = NULL;
    *status = EXTERIA_E_ARG;
    switch (spec->kind) {
    case EXTERIA_UPLOAD_VOICE:
        if (spec->duration_ms <= 0 || !spec->waveform || spec->waveform_len != EXTERIA_WAVEFORM_BYTES) return NULL;
        attribute = exteria_tl_new_obj(arena, "documentAttributeAudio");
        *status = attribute ? exteria_tl_set_flag(attribute, "voice") : EXTERIA_E_NOMEM;
        if (*status == EXTERIA_OK) *status = exteria_tl_set_i32(arena, attribute, "duration", (spec->duration_ms + 500) / 1000);
        if (*status == EXTERIA_OK) *status = exteria_tl_set_bytes(arena, attribute, "waveform", spec->waveform, spec->waveform_len);
        break;
    case EXTERIA_UPLOAD_ROUND:
    case EXTERIA_UPLOAD_VIDEO:
        if (spec->duration_ms <= 0 || spec->width <= 0 || (spec->kind == EXTERIA_UPLOAD_VIDEO && spec->height <= 0) || spec->waveform_len) return NULL;
        attribute = exteria_tl_new_obj(arena, "documentAttributeVideo");
        *status = attribute ? exteria_tl_set_flag(attribute, spec->kind == EXTERIA_UPLOAD_ROUND ? "round_message" : "supports_streaming") : EXTERIA_E_NOMEM;
        if (*status == EXTERIA_OK) *status = exteria_tl_set_f64(arena, attribute, "duration", (double)spec->duration_ms / 1000.0);
        if (*status == EXTERIA_OK) *status = exteria_tl_set_i32(arena, attribute, "w", spec->width);
        if (*status == EXTERIA_OK) *status = exteria_tl_set_i32(arena, attribute, "h", spec->kind == EXTERIA_UPLOAD_ROUND ? spec->width : spec->height);
        break;
    case EXTERIA_UPLOAD_FILE:
        if (!spec->name[0] || !spec->mime[0]) return NULL;
        attribute = exteria_tl_new_obj(arena, "documentAttributeFilename");
        *status = attribute ? exteria_tl_set_str(arena, attribute, "file_name", spec->name) : EXTERIA_E_NOMEM;
        break;
    case EXTERIA_UPLOAD_PHOTO:
        break;
    }
    return attribute;
}

/* the input media a spec and an uploaded file make: a photo, or a document with the attributes of its kind */
static exteria_status upload_media(exteria_arena *arena, exteria_tl_value *file, const exteria_upload_spec *spec, exteria_tl_value **out) {
    exteria_tl_value *media, *attributes = NULL, *attribute = NULL;
    exteria_status status;
    const char *mime;
    *out = NULL;
    if (spec->kind == EXTERIA_UPLOAD_PHOTO) {
        media = exteria_tl_new_obj(arena, "inputMediaUploadedPhoto");
        if (!media) return EXTERIA_E_NOMEM;
        status = exteria_tl_set(media, "file", file);
        if (status == EXTERIA_OK && spec->spoiler) status = exteria_tl_set_flag(media, "spoiler");
        if (status == EXTERIA_OK && spec->view_once) status = exteria_tl_set_i32(arena, media, "ttl_seconds", EXTERIA_VIEW_ONCE_TTL);
    } else {
        attribute = upload_attribute(arena, spec, &status);
        if (!attribute) return status == EXTERIA_OK ? EXTERIA_E_ARG : status;
        mime = spec->kind == EXTERIA_UPLOAD_VOICE ? "audio/ogg" : (spec->kind == EXTERIA_UPLOAD_FILE ? spec->mime : "video/mp4");
        media = exteria_tl_new_obj(arena, "inputMediaUploadedDocument");
        attributes = exteria_tl_new_vec(arena, 1);
        if (!media || !attributes) return EXTERIA_E_NOMEM;
        status = exteria_tl_vec_set(attributes, 0, attribute);
        if (status == EXTERIA_OK) status = exteria_tl_set(media, "file", file);
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "mime_type", mime);
        if (status == EXTERIA_OK) status = exteria_tl_set(media, "attributes", attributes);
        /* a sent video is not played in a circle, and a file is never turned into a picture on the other side */
        if (status == EXTERIA_OK && spec->kind == EXTERIA_UPLOAD_FILE) status = exteria_tl_set_flag(media, "force_file");
        if (status == EXTERIA_OK && spec->kind == EXTERIA_UPLOAD_VIDEO && spec->spoiler) status = exteria_tl_set_flag(media, "spoiler");
        if (status == EXTERIA_OK && spec->view_once) status = exteria_tl_set_i32(arena, media, "ttl_seconds", EXTERIA_VIEW_ONCE_TTL);
    }
    if (status == EXTERIA_OK) *out = media;
    return status;
}

static int upload_spec_valid(const exteria_upload_spec *spec) {
    /* a document sent as a file keeps its bytes for good, so a one-time file is a mistake of the caller */
    return spec->kind >= EXTERIA_UPLOAD_VOICE && spec->kind <= EXTERIA_UPLOAD_FILE && !(spec->view_once && spec->kind == EXTERIA_UPLOAD_FILE) && memchr(spec->name, 0, sizeof(spec->name)) != NULL &&
           memchr(spec->mime, 0, sizeof(spec->mime)) != NULL && memchr(spec->caption, 0, sizeof(spec->caption)) != NULL;
}

exteria_status exteria_send_upload_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value *file,
                                           const exteria_upload_spec *spec, int64_t random_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *media;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !file || !spec || !out || random_id == 0 || !upload_spec_valid(spec)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    status = upload_media(arena, file, spec, &media);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.sendMedia");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_set_reply(arena, request, peer, spec->reply_to);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "media", media);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", spec->caption);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_album_upload_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value *file, const exteria_upload_spec *spec,
                                            exteria_tl_value **out) {
    exteria_tl_value *request, *input, *media;
    exteria_status status;
    if (out) *out = NULL;
    /* only a photo or a video goes into an album */
    if (!arena || !file || !spec || !out || !upload_spec_valid(spec) || (spec->kind != EXTERIA_UPLOAD_PHOTO && spec->kind != EXTERIA_UPLOAD_VIDEO)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    status = upload_media(arena, file, spec, &media);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.uploadMedia");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "media", media);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_album_media_parse(const exteria_tl_value *answer, exteria_album_media *out) {
    const exteria_tl_value *object;
    const uint8_t *reference;
    size_t length;
    int photo;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    photo = exteria_tl_is(answer, EXTERIA_TL_ID_messageMediaPhoto);
    if (!photo && !exteria_tl_is(answer, EXTERIA_TL_ID_messageMediaDocument)) return EXTERIA_E_MALFORMED;
    object = exteria_tl_get(answer, photo ? "photo" : "document");
    if (!exteria_tl_is(object, photo ? EXTERIA_TL_ID_photo : EXTERIA_TL_ID_document) || exteria_tl_get_i64(object, "id", &out->id) != EXTERIA_OK ||
        exteria_tl_get_i64(object, "access_hash", &out->access_hash) != EXTERIA_OK ||
        exteria_tl_get_bytes(object, "file_reference", &reference, &length) != EXTERIA_OK || length > EXTERIA_ALBUM_REF_MAX || out->id == 0) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    memcpy(out->file_reference, reference, length);
    out->file_reference_len = length;
    out->is_photo = photo ? 1 : 0;
    return EXTERIA_OK;
}

exteria_status exteria_album_send_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_album_media *items, const int64_t *random_ids,
                                          const char *const *captions, size_t count, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *list;
    exteria_status status;
    size_t i, j;
    if (out) *out = NULL;
    if (!arena || !peer || !items || !random_ids || !out || count < 2 || count > EXTERIA_ALBUM_ITEMS_MAX) return EXTERIA_E_ARG;
    for (i = 0; i < count; ++i) {
        if (random_ids[i] == 0 || items[i].id == 0) return EXTERIA_E_ARG;
        for (j = 0; j < i; ++j) if (random_ids[j] == random_ids[i]) return EXTERIA_E_ARG;
    }
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.sendMultiMedia");
    list = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!request || !list) return EXTERIA_E_NOMEM;
    for (i = 0; i < count && status == EXTERIA_OK; ++i) {
        exteria_tl_value *single = exteria_tl_new_obj(arena, "inputSingleMedia");
        exteria_tl_value *media = exteria_tl_new_obj(arena, items[i].is_photo ? "inputMediaPhoto" : "inputMediaDocument");
        exteria_tl_value *reference = exteria_tl_new_obj(arena, items[i].is_photo ? "inputPhoto" : "inputDocument");
        const char *caption = captions && captions[i] ? captions[i] : "";
        if (!single || !media || !reference) return EXTERIA_E_NOMEM;
        if (strlen(caption) >= EXTERIA_UPLOAD_CAPTION_MAX) return EXTERIA_E_LIMIT;
        status = exteria_tl_set_i64(arena, reference, "id", items[i].id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, reference, "access_hash", items[i].access_hash);
        if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, reference, "file_reference", items[i].file_reference, items[i].file_reference_len);
        if (status == EXTERIA_OK) status = exteria_tl_set(media, "id", reference);
        if (status == EXTERIA_OK && items[i].spoiler) status = exteria_tl_set_flag(media, "spoiler");
        if (status == EXTERIA_OK) status = exteria_tl_set(single, "media", media);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, single, "random_id", random_ids[i]);
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, single, "message", caption);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, (uint32_t)i, single);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_set_topic_reply(arena, request, peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "multi_media", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_shared_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_shared_kind kind, int32_t offset_id, int32_t limit, exteria_tl_value **out) {
    static const char *const filters[] = {"inputMessagesFilterPhotoVideo", "inputMessagesFilterDocument", "inputMessagesFilterUrl", "inputMessagesFilterMusic", "inputMessagesFilterRoundVoice"};
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || (unsigned)kind > EXTERIA_SHARED_VOICE || offset_id < 0) return EXTERIA_E_ARG;
    status = chat_search_request(arena, peer, NULL, "", filters[kind], limit, out);
    if (status == EXTERIA_OK && offset_id) status = exteria_tl_set_i32(arena, *out, "offset_id", offset_id);
    if (status != EXTERIA_OK) *out = NULL;
    return status;
}

exteria_status exteria_send_geo_request(exteria_arena *arena, const exteria_peer_ref *peer, double latitude, double longitude,
                                        int64_t random_id, exteria_tl_value **out) {
    exteria_geo_point location;
    memset(&location, 0, sizeof(location));
    location.valid = 1;
    location.latitude = latitude;
    location.longitude = longitude;
    return exteria_send_location_request(arena, peer, &location, random_id, out);
}

exteria_status exteria_send_location_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_geo_point *location,
                                            int64_t random_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *media, *point;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !location || random_id == 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status == EXTERIA_OK) status = exteria_geo_input(arena, location, &point);
    if (status != EXTERIA_OK) return status;
    media = exteria_tl_new_obj(arena, location->venue ? "inputMediaVenue" : "inputMediaGeoPoint");
    request = exteria_tl_new_obj(arena, "messages.sendMedia");
    if (!point || !media || !request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(media, "geo_point", point);
    if (location->venue) {
        if (!memchr(location->title, 0, sizeof(location->title)) || !memchr(location->address, 0, sizeof(location->address)) ||
            !memchr(location->provider, 0, sizeof(location->provider)) || !memchr(location->venue_id, 0, sizeof(location->venue_id)) ||
            !memchr(location->venue_type, 0, sizeof(location->venue_type))) return EXTERIA_E_ARG;
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "title", location->title);
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "address", location->address);
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "provider", location->provider);
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "venue_id", location->venue_id);
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "venue_type", location->venue_type);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_set_topic_reply(arena, request, peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "media", media);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", "");
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_custom_emoji_request(exteria_arena *arena, const int64_t *ids, size_t count, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!arena || !ids || !out || count < 1 || count > EXTERIA_CUSTOM_EMOJI_MAX) return EXTERIA_E_ARG;
    *out = NULL;
    request = exteria_tl_new_obj(arena, "messages.getCustomEmojiDocuments");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64_vec(arena, request, "document_id", ids, (uint32_t)count);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_custom_emoji_parse(const exteria_tl_value *answer, exteria_custom_emoji *rows, size_t cap, size_t *count) {
    uint32_t i, j;
    size_t n = 0;
    if (count) *count = 0;
    if (!rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (!is_vec(answer)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < answer->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *document = answer->u.vec.items[i];
        const exteria_tl_value *attributes;
        int64_t id;
        if (!exteria_tl_is(document, EXTERIA_TL_ID_document) || exteria_tl_get_i64(document, "id", &id) != EXTERIA_OK) continue;
        attributes = exteria_tl_get(document, "attributes");
        if (!is_vec(attributes)) continue;
        for (j = 0; j < attributes->u.vec.count; ++j) {
            const exteria_tl_value *a = attributes->u.vec.items[j];
            if (!exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeCustomEmoji)) continue;
            memset(&rows[n], 0, sizeof(rows[n]));
            rows[n].id = id;
            copy_text(rows[n].alt, sizeof(rows[n].alt), a, "alt", 0);
            if (!rows[n].alt[0]) break;
            {
                exteria_media_info info;
                memset(&info, 0, sizeof(info));
                read_document(document, NULL, &info);
                rows[n].ref = info.ref;
                rows[n].preview = info.preview;
                rows[n].format = !strcmp(info.mime, "application/x-tgsticker") ? EXTERIA_STICKER_ANIMATED
                                 : !strcmp(info.mime, "video/webm") ? EXTERIA_STICKER_VIDEO : EXTERIA_STICKER_STATIC;
            }
            ++n;
            break;
        }
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_search_request(exteria_arena *arena, const char *query, exteria_search_kind kind, int32_t offset_rate,
                                      int32_t limit, exteria_tl_value **out) {
    static const char *const filters[] = {"inputMessagesFilterEmpty", "inputMessagesFilterEmpty", "inputMessagesFilterPhotoVideo",
                                          "inputMessagesFilterUrl", "inputMessagesFilterDocument", "inputMessagesFilterMusic",
                                          "inputMessagesFilterVoice"};
    exteria_tl_value *request, *filter, *empty;
    exteria_status status;
    if (!arena || !query || !out || kind < EXTERIA_SEARCH_ALL || kind > EXTERIA_SEARCH_VOICE || offset_rate < 0 || limit < 1 ||
        limit > EXTERIA_MESSAGES_MAX || strlen(query) > 256) return EXTERIA_E_ARG;
    *out = NULL;
    request = exteria_tl_new_obj(arena, "messages.searchGlobal");
    filter = exteria_tl_new_obj(arena, filters[kind]);
    empty = exteria_tl_new_obj(arena, "inputPeerEmpty");
    if (!request || !filter || !empty) return EXTERIA_E_NOMEM;
    status = EXTERIA_OK;
    if (kind == EXTERIA_SEARCH_POSTS) status = exteria_tl_set_flag(request, "broadcasts_only");
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "q", query);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "filter", filter);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "min_date", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "max_date", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_rate", offset_rate);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "offset_peer", empty);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_read_history_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t max_id,
                                           exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (!arena || !peer || !out || max_id <= 0) return EXTERIA_E_ARG;
    *out = NULL;
    if (peer->topic_id > 0) {
        status = exteria_input_peer(arena, peer, &input);
        if (status != EXTERIA_OK) return status;
        request = exteria_tl_new_obj(arena, "messages.readDiscussion");
        if (!request) return EXTERIA_E_NOMEM;
        status = exteria_tl_set(request, "peer", input);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", peer->topic_id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "read_max_id", max_id);
        if (status == EXTERIA_OK) *out = request;
        return status;
    }
    if (peer->kind == 3 && !peer->self) {
        exteria_tl_value *channel = exteria_tl_new_obj(arena, "inputChannel");
        request = exteria_tl_new_obj(arena, "channels.readHistory");
        if (!channel || !request) return EXTERIA_E_NOMEM;
        if (peer->id <= 0 || peer->access_hash == 0) return EXTERIA_E_ARG;
        status = exteria_tl_set_i64(arena, channel, "channel_id", peer->id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, channel, "access_hash", peer->access_hash);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "channel", channel);
    } else {
        status = exteria_input_peer(arena, peer, &input);
        if (status != EXTERIA_OK) return status;
        request = exteria_tl_new_obj(arena, "messages.readHistory");
        if (!request) return EXTERIA_E_NOMEM;
        status = exteria_tl_set(request, "peer", input);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "max_id", max_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_media_location(exteria_arena *arena, const exteria_media_ref *ref, exteria_tl_value **out) {
    exteria_tl_value *location;
    exteria_status status;
    if (!arena || !ref || !out || ref->source == EXTERIA_MEDIA_SOURCE_NONE) return EXTERIA_E_ARG;
    *out = NULL;
    location = exteria_tl_new_obj(arena, ref->source == EXTERIA_MEDIA_SOURCE_PHOTO ? "inputPhotoFileLocation" : "inputDocumentFileLocation");
    if (!location) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, location, "id", ref->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, location, "access_hash", ref->access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, location, "file_reference", ref->file_ref, ref->ref_len);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, location, "thumb_size", ref->thumb);
    if (status == EXTERIA_OK) *out = location;
    return status;
}

static exteria_status set_input(exteria_arena *arena, const exteria_sticker_set_row *set, exteria_tl_value **out) {
    exteria_tl_value *input = exteria_tl_new_obj(arena, "inputStickerSetID");
    exteria_status status;
    if (!input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "id", set->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", set->access_hash);
    if (status == EXTERIA_OK) *out = input;
    return status;
}

exteria_status exteria_sticker_set_thumb_location(exteria_arena *arena, const exteria_sticker_set_row *set, exteria_tl_value **out) {
    exteria_tl_value *location, *input;
    exteria_status status;
    if (!arena || !set || !out || set->id == 0 || set->thumb_dc <= 0) return EXTERIA_E_ARG;
    *out = NULL;
    location = exteria_tl_new_obj(arena, "inputStickerSetThumb");
    if (!location) return EXTERIA_E_NOMEM;
    status = set_input(arena, set, &input);
    if (status == EXTERIA_OK) status = exteria_tl_set(location, "stickerset", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, location, "thumb_version", set->thumb_version);
    if (status == EXTERIA_OK) *out = location;
    return status;
}

exteria_status exteria_sticker_set_request(exteria_arena *arena, const exteria_sticker_set_row *set, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (!arena || !set || !out || set->id == 0) return EXTERIA_E_ARG;
    *out = NULL;
    request = exteria_tl_new_obj(arena, "messages.getStickerSet");
    if (!request) return EXTERIA_E_NOMEM;
    status = set_input(arena, set, &input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "stickerset", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}
