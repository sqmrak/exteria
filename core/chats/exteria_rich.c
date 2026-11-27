#include "exteria_rich.h"

#include <stdio.h>
#include <string.h>

#include "exteria_geo.h"
#include "exteria_tl_ids.h"

/* the size photos of an article are fetched at: it fills a bubble on a retina phone */
#define RICH_PHOTO_TARGET 800
/* blocks and texts nest; a document deeper than this is cut there rather than walked further */
#define RICH_BLOCK_DEPTH_MAX 12
#define RICH_TEXT_DEPTH_MAX 32
#define RICH_ITEMS_MAX 1024
#define RICH_ROWS_MAX 512

typedef struct {
    exteria_rich_doc *doc;
    const exteria_tl_value *photos;
    const exteria_tl_value *documents;
    uint8_t indent;
    uint8_t quote;
} rich_ctx;

/* the text of the block being written: the UTF-16 units so far, which entity offsets count in */
typedef struct {
    exteria_rich_block *block;
    uint32_t units;
} rich_span;

static int rich_is_vec(const exteria_tl_value *v) {
    return v && v->kind == EXTERIA_TL_V_VEC;
}

static exteria_rich_block *rich_begin(rich_ctx *c, exteria_rich_kind kind) {
    exteria_rich_doc *doc = c->doc;
    exteria_rich_block *b;
    if (doc->block_count >= EXTERIA_RICH_BLOCKS_MAX) {
        doc->truncated = 1;
        return NULL;
    }
    b = &doc->blocks[doc->block_count++];
    memset(b, 0, sizeof(*b));
    b->kind = (uint8_t)kind;
    b->indent = c->indent;
    b->quote = c->quote;
    b->colspan = 1;
    b->rowspan = 1;
    b->text_offset = doc->text_length;
    b->entity_start = doc->entity_count;
    return b;
}

static void rich_end(rich_ctx *c, exteria_rich_block *b) {
    b->text_length = c->doc->text_length - b->text_offset;
    b->entity_count = (uint16_t)(c->doc->entity_count - b->entity_start);
}

/* drops a block that came out empty, together with whatever it wrote */
static void rich_drop_if_empty(rich_ctx *c, exteria_rich_block *b) {
    exteria_rich_doc *doc = c->doc;
    if (b->text_length > 0 || b != &doc->blocks[doc->block_count - 1]) return;
    doc->entity_count = b->entity_start;
    doc->text_length = b->text_offset;
    --doc->block_count;
}

/* the length of the UTF-8 sequence at p, 0 when it is not a valid one (an overlong form, a surrogate, past U+10FFFF or cut short) */
static size_t rich_utf8_sequence(const uint8_t *p, size_t len) {
    uint8_t c = p[0];
    size_t need, i;
    uint32_t cp;
    if (c < 0x80u) return 1;
    if (c >= 0xC2u && c <= 0xDFu) { need = 2; cp = c & 0x1Fu; }
    else if (c >= 0xE0u && c <= 0xEFu) { need = 3; cp = c & 0x0Fu; }
    else if (c >= 0xF0u && c <= 0xF4u) { need = 4; cp = c & 0x07u; }
    else return 0;
    if (len < need) return 0;
    for (i = 1; i < need; ++i) {
        if ((p[i] & 0xC0u) != 0x80u) return 0;
        cp = (cp << 6) | (p[i] & 0x3Fu);
    }
    if ((need == 3 && (cp < 0x800u || (cp >= 0xD800u && cp <= 0xDFFFu))) || (need == 4 && (cp < 0x10000u || cp > 0x10FFFFu))) return 0;
    return need;
}

static int rich_utf8_valid(const uint8_t *p, size_t len) {
    size_t i = 0;
    while (i < len) {
        size_t n = rich_utf8_sequence(p + i, len - i);
        if (!n) return 0;
        i += n;
    }
    return 1;
}

/* appends text to the pool as valid UTF-8, a broken sequence becoming U+FFFD, so the offsets the app counts match the string it makes; stops at the pool's end */
static void rich_put(rich_ctx *c, rich_span *s, const uint8_t *data, size_t len) {
    static const uint8_t replacement[3] = {0xEFu, 0xBFu, 0xBDu};
    exteria_rich_doc *doc = c->doc;
    size_t i = 0;
    while (i < len) {
        size_t n = rich_utf8_sequence(data + i, len - i);
        const uint8_t *from = n ? data + i : replacement;
        size_t take = n ? n : sizeof(replacement);
        if (take > EXTERIA_RICH_TEXT_MAX - doc->text_length) {
            doc->truncated = 1;
            return;
        }
        memcpy(doc->text + doc->text_length, from, take);
        doc->text_length += (uint32_t)take;
        s->units += take == 4 ? 2u : 1u;
        i += n ? n : 1;
    }
}

static void rich_put_string(rich_ctx *c, rich_span *s, const char *text) {
    rich_put(c, s, (const uint8_t *)text, strlen(text));
}

/* an entity over the text written since start; url, when given, goes to the url pool */
static void rich_entity(rich_ctx *c, rich_span *s, exteria_entity_kind kind, uint32_t start, const uint8_t *url, size_t url_len, exteria_entity **made) {
    exteria_rich_doc *doc = c->doc;
    exteria_entity *e;
    if (made) *made = NULL;
    if (s->units <= start) return;
    if (doc->entity_count >= EXTERIA_RICH_ENTITIES_MAX) {
        doc->truncated = 1;
        return;
    }
    if (url && (url_len == 0 || url_len > INT16_MAX || url_len + 1 > EXTERIA_RICH_URLS_MAX - doc->urls_length)) {
        /* a link that does not fit keeps its words as plain text */
        doc->truncated = 1;
        return;
    }
    e = &doc->entities[doc->entity_count++];
    memset(e, 0, sizeof(*e));
    e->kind = (uint8_t)kind;
    e->offset = (int32_t)start;
    e->length = (int32_t)(s->units - start);
    e->url_offset = -1;
    if (url) {
        e->url_offset = (int16_t)doc->urls_length;
        e->url_length = (int16_t)url_len;
        memcpy(doc->urls + doc->urls_length, url, url_len);
        doc->urls[doc->urls_length + url_len] = 0;
        doc->urls_length += (uint32_t)(url_len + 1);
    }
    if (made) *made = e;
}

/* a link with a scheme before its address: mailto: for an email, tel: for a phone */
static void rich_link_entity(rich_ctx *c, rich_span *s, uint32_t start, const char *scheme, const uint8_t *target, size_t target_len) {
    char url[512];
    size_t scheme_len = strlen(scheme);
    if (!target || target_len == 0 || scheme_len + target_len >= sizeof(url)) return;
    memcpy(url, scheme, scheme_len);
    memcpy(url + scheme_len, target, target_len);
    rich_entity(c, s, EXTERIA_ENTITY_TEXT_URL, start, (const uint8_t *)url, scheme_len + target_len, NULL);
}

static void rich_text(rich_ctx *c, rich_span *s, const exteria_tl_value *v, unsigned depth) {
    const uint8_t *data;
    size_t len;
    uint32_t start = s->units;
    const exteria_tl_value *inner;
    if (!v || depth > RICH_TEXT_DEPTH_MAX) return;
    if (exteria_tl_is(v, EXTERIA_TL_ID_textEmpty) || exteria_tl_is(v, EXTERIA_TL_ID_textImage)) return;
    if (exteria_tl_is(v, EXTERIA_TL_ID_textPlain)) {
        if (exteria_tl_get_bytes(v, "text", &data, &len) == EXTERIA_OK) rich_put(c, s, data, len);
        return;
    }
    if (exteria_tl_is(v, EXTERIA_TL_ID_textConcat)) {
        const exteria_tl_value *parts = exteria_tl_get(v, "texts");
        if (!rich_is_vec(parts)) return;
        for (uint32_t i = 0; i < parts->u.vec.count && i < RICH_ITEMS_MAX; ++i) rich_text(c, s, parts->u.vec.items[i], depth + 1);
        return;
    }
    /* a custom emoji shows the emoji it stands for, a formula its source in code */
    if (exteria_tl_is(v, EXTERIA_TL_ID_textCustomEmoji)) {
        if (exteria_tl_get_bytes(v, "alt", &data, &len) == EXTERIA_OK) rich_put(c, s, data, len);
        return;
    }
    if (exteria_tl_is(v, EXTERIA_TL_ID_textMath)) {
        if (exteria_tl_get_bytes(v, "source", &data, &len) == EXTERIA_OK) rich_put(c, s, data, len);
        rich_entity(c, s, EXTERIA_ENTITY_CODE, start, NULL, 0, NULL);
        return;
    }
    inner = exteria_tl_get(v, "text");
    rich_text(c, s, inner, depth + 1);
    if (exteria_tl_is(v, EXTERIA_TL_ID_textBold)) rich_entity(c, s, EXTERIA_ENTITY_BOLD, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textItalic)) rich_entity(c, s, EXTERIA_ENTITY_ITALIC, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textUnderline)) rich_entity(c, s, EXTERIA_ENTITY_UNDERLINE, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textStrike)) rich_entity(c, s, EXTERIA_ENTITY_STRIKE, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textFixed)) rich_entity(c, s, EXTERIA_ENTITY_CODE, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textSpoiler)) rich_entity(c, s, EXTERIA_ENTITY_SPOILER, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textMention)) rich_entity(c, s, EXTERIA_ENTITY_MENTION, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textHashtag)) rich_entity(c, s, EXTERIA_ENTITY_HASHTAG, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textCashtag)) rich_entity(c, s, EXTERIA_ENTITY_CASHTAG, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textBotCommand)) rich_entity(c, s, EXTERIA_ENTITY_BOT_COMMAND, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textAutoUrl)) rich_entity(c, s, EXTERIA_ENTITY_URL, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textAutoEmail)) rich_entity(c, s, EXTERIA_ENTITY_EMAIL, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textAutoPhone)) rich_entity(c, s, EXTERIA_ENTITY_PHONE, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textBankCard)) rich_entity(c, s, EXTERIA_ENTITY_BANK_CARD, start, NULL, 0, NULL);
    else if (exteria_tl_is(v, EXTERIA_TL_ID_textUrl)) {
        if (exteria_tl_get_bytes(v, "url", &data, &len) == EXTERIA_OK) rich_entity(c, s, EXTERIA_ENTITY_TEXT_URL, start, data, len, NULL);
    } else if (exteria_tl_is(v, EXTERIA_TL_ID_textEmail)) {
        if (exteria_tl_get_bytes(v, "email", &data, &len) == EXTERIA_OK) rich_link_entity(c, s, start, "mailto:", data, len);
    } else if (exteria_tl_is(v, EXTERIA_TL_ID_textPhone)) {
        if (exteria_tl_get_bytes(v, "phone", &data, &len) == EXTERIA_OK) rich_link_entity(c, s, start, "tel:", data, len);
    } else if (exteria_tl_is(v, EXTERIA_TL_ID_textMentionName)) {
        int64_t user = 0;
        exteria_entity *e;
        if (exteria_tl_get_i64(v, "user_id", &user) == EXTERIA_OK && user > 0) {
            rich_entity(c, s, EXTERIA_ENTITY_MENTION_NAME, start, NULL, 0, &e);
            if (e) e->user_id = user;
        }
    } else if (exteria_tl_is(v, EXTERIA_TL_ID_textDate)) {
        /* the same flag bits as a messageEntityFormattedDate */
        static const char *const names[] = {"relative", "short_time", "long_time", "short_date", "long_date", "day_of_week"};
        int32_t date = 0;
        exteria_entity *e;
        if (exteria_tl_get_i32(v, "date", &date) == EXTERIA_OK && date > 0) {
            rich_entity(c, s, EXTERIA_ENTITY_FORMATTED_DATE, start, NULL, 0, &e);
            if (e) {
                e->date = date;
                for (size_t k = 0; k < sizeof(names) / sizeof(names[0]); ++k) {
                    if (exteria_tl_has(v, names[k])) e->flags |= (uint8_t)(1u << k);
                }
            }
        }
    }
    /* subscript, superscript, marked, anchor, diff and button keep their words without a style of their own */
}

/* a whole block of one text */
static exteria_rich_block *rich_text_block(rich_ctx *c, exteria_rich_kind kind, uint8_t level, const exteria_tl_value *text) {
    rich_span s;
    exteria_rich_block *b = rich_begin(c, kind);
    if (!b) return NULL;
    b->level = level;
    s.block = b;
    s.units = 0;
    rich_text(c, &s, text, 0);
    rich_end(c, b);
    rich_drop_if_empty(c, b);
    return b->text_length ? b : NULL;
}

static void rich_caption(rich_ctx *c, const exteria_tl_value *caption) {
    if (!caption) return;
    if (exteria_tl_is(caption, EXTERIA_TL_ID_pageCaption)) {
        rich_text_block(c, EXTERIA_RICH_CAPTION, 0, exteria_tl_get(caption, "text"));
        rich_text_block(c, EXTERIA_RICH_CAPTION, 0, exteria_tl_get(caption, "credit"));
    } else {
        rich_text_block(c, EXTERIA_RICH_CAPTION, 0, caption);
    }
}

static const exteria_tl_value *rich_find(const exteria_tl_value *list, int64_t id) {
    int64_t have;
    if (!rich_is_vec(list) || id == 0) return NULL;
    for (uint32_t i = 0; i < list->u.vec.count; ++i) {
        const exteria_tl_value *item = list->u.vec.items[i];
        if (exteria_tl_get_i64(item, "id", &have) == EXTERIA_OK && have == id) return item;
    }
    return NULL;
}

static void rich_media(rich_ctx *c, const exteria_tl_value *photo, const exteria_tl_value *document, int spoiler) {
    exteria_rich_doc *doc = c->doc;
    exteria_media_info *media;
    exteria_rich_block *b;
    if (!photo && !document) return;
    if (doc->media_count >= EXTERIA_RICH_MEDIA_MAX) {
        doc->truncated = 1;
        return;
    }
    media = &doc->media[doc->media_count];
    memset(media, 0, sizeof(*media));
    if (photo) exteria_photo_read(photo, RICH_PHOTO_TARGET, media);
    else exteria_document_read(document, media);
    /* a picture without a file, or a document that is not a picture or a video, has nothing to show in the column */
    if (media->ref.source == EXTERIA_MEDIA_SOURCE_NONE || media->width <= 0 || media->height <= 0 ||
        (media->kind != EXTERIA_PREVIEW_PHOTO && media->kind != EXTERIA_PREVIEW_VIDEO && media->kind != EXTERIA_PREVIEW_GIF)) return;
    media->spoiler = spoiler ? 1 : 0;
    b = rich_begin(c, EXTERIA_RICH_MEDIA);
    if (!b) return;
    b->media = doc->media_count++;
    rich_end(c, b);
}

/* a map of the article: the point and the zoom the author chose, shown at the shape of the box they gave */
static void rich_map(rich_ctx *c, const exteria_tl_value *b) {
    exteria_rich_doc *doc = c->doc;
    exteria_media_info *media;
    exteria_rich_block *out;
    int32_t zoom = 15, w = 0, h = 0;
    if (doc->media_count >= EXTERIA_RICH_MEDIA_MAX) {
        doc->truncated = 1;
        return;
    }
    media = &doc->media[doc->media_count];
    memset(media, 0, sizeof(*media));
    if (exteria_geo_read(exteria_tl_get(b, "geo"), NULL, &media->location) != EXTERIA_OK || !media->location.valid) return;
    media->kind = EXTERIA_PREVIEW_LOCATION;
    if (exteria_tl_get_i32(b, "w", &w) != EXTERIA_OK || exteria_tl_get_i32(b, "h", &h) != EXTERIA_OK || w <= 0 || h <= 0) {
        w = 4;
        h = 3;
    }
    media->width = w;
    media->height = h;
    if (exteria_tl_get_i32(b, "zoom", &zoom) != EXTERIA_OK || zoom < 1 || zoom > 19) zoom = 15;
    out = rich_begin(c, EXTERIA_RICH_MEDIA);
    if (!out) return;
    out->level = (uint8_t)zoom;
    out->media = doc->media_count++;
    rich_end(c, out);
}

/* the address an embed shows: its own url, or the src of the first frame in its html, which is how most players and posts are embedded; the html itself is never run */
static int rich_embed_url(const exteria_tl_value *b, const uint8_t **url, size_t *len) {
    const uint8_t *html;
    size_t html_len;
    if (exteria_tl_get_bytes(b, "url", url, len) == EXTERIA_OK && *len > 0) return 1;
    if (exteria_tl_get_bytes(b, "html", &html, &html_len) != EXTERIA_OK) return 0;
    for (size_t i = 0; i + 5 < html_len; ++i) {
        uint8_t quote;
        size_t start, end;
        if ((html[i] | 0x20u) != 's' || (html[i + 1] | 0x20u) != 'r' || (html[i + 2] | 0x20u) != 'c' || html[i + 3] != '=') continue;
        quote = html[i + 4];
        if (quote != '"' && quote != '\'') continue;
        start = i + 5;
        for (end = start; end < html_len && html[end] != quote; ++end) {}
        if (end >= html_len) return 0;
        /* a frame with a protocol relative address is fetched over https; a data: or script source is passed over */
        if (end - start > 8 && (!memcmp(html + start, "https://", 8) || !memcmp(html + start, "http://", 7) || !memcmp(html + start, "//", 2))) {
            *url = html + start;
            *len = end - start;
            return 1;
        }
        i = end;
    }
    return 0;
}

/* a line that opens an address, its words the address itself after a mark */
static void rich_link_line(rich_ctx *c, const char *mark, const uint8_t *url, size_t len) {
    exteria_rich_block *b = rich_begin(c, EXTERIA_RICH_PARAGRAPH);
    rich_span s;
    uint32_t start;
    char full[1024];
    size_t full_len = len;
    if (!b) return;
    s.block = b;
    s.units = 0;
    rich_put_string(c, &s, mark);
    start = s.units;
    rich_put(c, &s, url, len);
    if (len >= 2 && url[0] == '/' && url[1] == '/') {
        if (len + 6 >= sizeof(full)) {
            rich_end(c, b);
            return;
        }
        memcpy(full, "https:", 6);
        memcpy(full + 6, url, len);
        full_len = len + 6;
        url = (const uint8_t *)full;
    }
    rich_entity(c, &s, EXTERIA_ENTITY_TEXT_URL, start, url, full_len, NULL);
    rich_end(c, b);
}

/* a file or a song of the article named on a line of its own, since the column has no player for it */
static void rich_file_line(rich_ctx *c, const exteria_tl_value *document) {
    exteria_media_info media;
    rich_span s;
    exteria_rich_block *b;
    const char *name;
    if (!document) return;
    memset(&media, 0, sizeof(media));
    exteria_document_read(document, &media);
    name = media.title[0] ? media.title : media.name;
    if (!name[0]) return;
    b = rich_begin(c, EXTERIA_RICH_PARAGRAPH);
    if (!b) return;
    s.block = b;
    s.units = 0;
    rich_put_string(c, &s, "\xF0\x9F\x93\x8E ");
    if (media.performer[0] && media.title[0]) {
        rich_put_string(c, &s, media.performer);
        rich_put_string(c, &s, " - ");
    }
    rich_put_string(c, &s, name);
    rich_end(c, b);
}

static void rich_blocks(rich_ctx *c, const exteria_tl_value *blocks, unsigned depth);
static void rich_block(rich_ctx *c, const exteria_tl_value *b, unsigned depth);

/* a list item: its words, or its first paragraph, beside the label; the rest of its blocks under it, one level in */
static void rich_list_item(rich_ctx *c, const exteria_tl_value *item, const char *label, unsigned depth) {
    const exteria_tl_value *blocks = exteria_tl_get(item, "blocks");
    const exteria_tl_value *first = rich_is_vec(blocks) && blocks->u.vec.count ? blocks->u.vec.items[0] : NULL;
    const exteria_tl_value *text = exteria_tl_get(item, "text");
    uint32_t skip = 0;
    rich_span s;
    exteria_rich_block *b = rich_begin(c, EXTERIA_RICH_LIST_ITEM);
    if (!b) return;
    snprintf(b->label, sizeof(b->label), "%s", label);
    if (exteria_tl_has(item, "checkbox")) b->flags |= EXTERIA_RICH_CHECKBOX;
    if (exteria_tl_has(item, "checked")) b->flags |= EXTERIA_RICH_CHECKED;
    if (!text && first && exteria_tl_is(first, EXTERIA_TL_ID_pageBlockParagraph)) {
        text = exteria_tl_get(first, "text");
        skip = 1;
    }
    s.block = b;
    s.units = 0;
    rich_text(c, &s, text, 0);
    rich_end(c, b);
    if (rich_is_vec(blocks) && depth < RICH_BLOCK_DEPTH_MAX) {
        uint8_t indent = c->indent;
        if (c->indent < UINT8_MAX) ++c->indent;
        for (uint32_t i = skip; i < blocks->u.vec.count && i < RICH_ITEMS_MAX; ++i) rich_block(c, blocks->u.vec.items[i], depth + 1);
        c->indent = indent;
    }
}

static void rich_list(rich_ctx *c, const exteria_tl_value *b, int ordered, unsigned depth) {
    const exteria_tl_value *items = exteria_tl_get(b, "items");
    int32_t start = 1, value;
    uint32_t count;
    int reversed = ordered && exteria_tl_has(b, "reversed");
    if (!rich_is_vec(items)) return;
    count = items->u.vec.count < RICH_ITEMS_MAX ? items->u.vec.count : RICH_ITEMS_MAX;
    if (ordered && exteria_tl_get_i32(b, "start", &start) != EXTERIA_OK) start = reversed ? (int32_t)count : 1;
    for (uint32_t i = 0; i < count; ++i) {
        const exteria_tl_value *item = items->u.vec.items[i];
        const uint8_t *num;
        size_t num_len;
        char label[EXTERIA_RICH_LABEL_MAX];
        if (!ordered) {
            snprintf(label, sizeof(label), "\xE2\x80\xA2");
        } else if (exteria_tl_get_bytes(item, "num", &num, &num_len) == EXTERIA_OK && num_len > 0 && num_len < sizeof(label) && rich_utf8_valid(num, num_len)) {
            memcpy(label, num, num_len);
            label[num_len] = 0;
        } else {
            /* counted in 64 bits, since a start near the end of int32 would overflow */
            int64_t number = exteria_tl_get_i32(item, "value", &value) == EXTERIA_OK ? value : (reversed ? (int64_t)start - i : (int64_t)start + i);
            snprintf(label, sizeof(label), "%lld.", (long long)number);
        }
        rich_list_item(c, item, label, depth);
    }
}

/* a table's cells in reading order, each told the first free column of its row: a cell that spans rows keeps its columns busy in the rows below it */
static void rich_table(rich_ctx *c, const exteria_tl_value *b) {
    const exteria_tl_value *rows = exteria_tl_get(b, "rows");
    uint16_t busy[EXTERIA_RICH_TABLE_COLUMNS_MAX];
    uint16_t columns = 0, row_count = 0;
    exteria_rich_block *table = rich_begin(c, EXTERIA_RICH_TABLE);
    rich_span s;
    if (!table) return;
    if (exteria_tl_has(b, "bordered")) table->flags |= EXTERIA_RICH_BORDERED;
    if (exteria_tl_has(b, "striped")) table->flags |= EXTERIA_RICH_STRIPED;
    s.block = table;
    s.units = 0;
    rich_text(c, &s, exteria_tl_get(b, "title"), 0);
    rich_end(c, table);
    memset(busy, 0, sizeof(busy));
    if (rich_is_vec(rows)) {
        for (uint32_t r = 0; r < rows->u.vec.count && r < RICH_ROWS_MAX; ++r) {
            const exteria_tl_value *cells = exteria_tl_get(rows->u.vec.items[r], "cells");
            uint16_t column = 0;
            if (rich_is_vec(cells)) {
                for (uint32_t k = 0; k < cells->u.vec.count && k < RICH_ITEMS_MAX; ++k) {
                    const exteria_tl_value *cell = cells->u.vec.items[k];
                    int32_t colspan = 1, rowspan = 1;
                    exteria_rich_block *out;
                    while (column < EXTERIA_RICH_TABLE_COLUMNS_MAX && busy[column]) ++column;
                    if (column >= EXTERIA_RICH_TABLE_COLUMNS_MAX) {
                        c->doc->truncated = 1;
                        break;
                    }
                    if (exteria_tl_get_i32(cell, "colspan", &colspan) != EXTERIA_OK || colspan < 1) colspan = 1;
                    if (exteria_tl_get_i32(cell, "rowspan", &rowspan) != EXTERIA_OK || rowspan < 1) rowspan = 1;
                    if (colspan > EXTERIA_RICH_TABLE_COLUMNS_MAX - column) colspan = EXTERIA_RICH_TABLE_COLUMNS_MAX - column;
                    if (rowspan > RICH_ROWS_MAX) rowspan = RICH_ROWS_MAX;
                    out = rich_begin(c, EXTERIA_RICH_CELL);
                    if (!out) break;
                    out->row = (uint16_t)r;
                    out->column = column;
                    out->colspan = (uint16_t)colspan;
                    out->rowspan = (uint16_t)rowspan;
                    if (exteria_tl_has(cell, "header")) out->flags |= EXTERIA_RICH_HEADER_CELL;
                    if (exteria_tl_has(cell, "align_center")) out->flags |= EXTERIA_RICH_ALIGN_CENTER;
                    if (exteria_tl_has(cell, "align_right")) out->flags |= EXTERIA_RICH_ALIGN_RIGHT;
                    s.block = out;
                    s.units = 0;
                    rich_text(c, &s, exteria_tl_get(cell, "text"), 0);
                    rich_end(c, out);
                    for (int32_t k2 = 0; k2 < colspan; ++k2) busy[column + k2] = (uint16_t)rowspan;
                    column = (uint16_t)(column + colspan);
                    if (column > columns) columns = column;
                }
            }
            /* a row ends: the columns a taller cell holds stay busy one row less */
            for (uint16_t k = 0; k < EXTERIA_RICH_TABLE_COLUMNS_MAX; ++k) if (busy[k]) --busy[k];
            row_count = (uint16_t)(r + 1);
        }
    }
    table->row = row_count;
    table->column = columns;
}

static void rich_block(rich_ctx *c, const exteria_tl_value *b, unsigned depth) {
    uint8_t quote = c->quote, indent = c->indent;
    if (!b || depth > RICH_BLOCK_DEPTH_MAX) return;
    if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockTitle) || exteria_tl_is(b, EXTERIA_TL_ID_pageBlockHeading1)) {
        rich_text_block(c, EXTERIA_RICH_HEADING, 1, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockHeader) || exteria_tl_is(b, EXTERIA_TL_ID_pageBlockHeading2)) {
        rich_text_block(c, EXTERIA_RICH_HEADING, 2, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockSubheader) || exteria_tl_is(b, EXTERIA_TL_ID_pageBlockHeading3)) {
        rich_text_block(c, EXTERIA_RICH_HEADING, 3, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockHeading4)) {
        rich_text_block(c, EXTERIA_RICH_HEADING, 4, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockHeading5)) {
        rich_text_block(c, EXTERIA_RICH_HEADING, 5, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockHeading6)) {
        rich_text_block(c, EXTERIA_RICH_HEADING, 6, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockSubtitle) || exteria_tl_is(b, EXTERIA_TL_ID_pageBlockKicker)) {
        rich_text_block(c, EXTERIA_RICH_SUBTITLE, 0, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockParagraph)) {
        rich_text_block(c, EXTERIA_RICH_PARAGRAPH, 0, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockPreformatted)) {
        rich_text_block(c, EXTERIA_RICH_PREFORMATTED, 0, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockMath)) {
        const uint8_t *data;
        size_t len;
        exteria_rich_block *out;
        rich_span s;
        if (exteria_tl_get_bytes(b, "source", &data, &len) != EXTERIA_OK || !len || !(out = rich_begin(c, EXTERIA_RICH_PREFORMATTED))) return;
        s.block = out;
        s.units = 0;
        rich_put(c, &s, data, len);
        rich_end(c, out);
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockFooter)) {
        rich_text_block(c, EXTERIA_RICH_FOOTER, 0, exteria_tl_get(b, "text"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockAuthorDate)) {
        rich_text_block(c, EXTERIA_RICH_FOOTER, 0, exteria_tl_get(b, "author"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockDivider)) {
        exteria_rich_block *out = rich_begin(c, EXTERIA_RICH_DIVIDER);
        if (out) rich_end(c, out);
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockList)) {
        rich_list(c, b, 0, depth);
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockOrderedList)) {
        rich_list(c, b, 1, depth);
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockBlockquote) || exteria_tl_is(b, EXTERIA_TL_ID_pageBlockThinking)) {
        if (c->quote < UINT8_MAX) ++c->quote;
        rich_text_block(c, EXTERIA_RICH_PARAGRAPH, 0, exteria_tl_get(b, "text"));
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockBlockquoteBlocks)) {
        if (c->quote < UINT8_MAX) ++c->quote;
        rich_blocks(c, exteria_tl_get(b, "blocks"), depth + 1);
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockPullquote)) {
        rich_text_block(c, EXTERIA_RICH_PULLQUOTE, 0, exteria_tl_get(b, "text"));
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockPhoto)) {
        int64_t id = 0;
        exteria_tl_get_i64(b, "photo_id", &id);
        rich_media(c, rich_find(c->photos, id), NULL, exteria_tl_has(b, "spoiler"));
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockVideo)) {
        int64_t id = 0;
        exteria_tl_get_i64(b, "video_id", &id);
        rich_media(c, NULL, rich_find(c->documents, id), exteria_tl_has(b, "spoiler"));
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockAudio) || exteria_tl_is(b, EXTERIA_TL_ID_pageBlockDocument)) {
        int64_t id = 0;
        exteria_tl_get_i64(b, exteria_tl_is(b, EXTERIA_TL_ID_pageBlockAudio) ? "audio_id" : "document_id", &id);
        rich_file_line(c, rich_find(c->documents, id));
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockCollage) || exteria_tl_is(b, EXTERIA_TL_ID_pageBlockSlideshow)) {
        rich_blocks(c, exteria_tl_get(b, "items"), depth + 1);
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockCover)) {
        rich_block(c, exteria_tl_get(b, "cover"), depth + 1);
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockEmbedPost)) {
        if (c->quote < UINT8_MAX) ++c->quote;
        rich_blocks(c, exteria_tl_get(b, "blocks"), depth + 1);
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockTable)) {
        rich_table(c, b);
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockDetails)) {
        exteria_rich_block *summary = rich_text_block(c, EXTERIA_RICH_DETAILS, 0, exteria_tl_get(b, "title"));
        if (summary && exteria_tl_has(b, "open")) summary->flags |= EXTERIA_RICH_OPEN;
        if (c->indent < UINT8_MAX) ++c->indent;
        rich_blocks(c, exteria_tl_get(b, "blocks"), depth + 1);
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockButtonRow)) {
        const exteria_tl_value *buttons = exteria_tl_get(b, "buttons");
        exteria_rich_block *out;
        rich_span s;
        if (!rich_is_vec(buttons) || !(out = rich_begin(c, EXTERIA_RICH_PARAGRAPH))) return;
        s.block = out;
        s.units = 0;
        for (uint32_t i = 0; i < buttons->u.vec.count && i < RICH_ITEMS_MAX; ++i) {
            uint32_t before = s.units;
            if (i > 0 && s.units) rich_put_string(c, &s, "   ");
            rich_text(c, &s, exteria_tl_get(buttons->u.vec.items[i], "text"), 0);
            rich_entity(c, &s, EXTERIA_ENTITY_BOLD, before, NULL, 0, NULL);
        }
        rich_end(c, out);
        rich_drop_if_empty(c, out);
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockMap) || exteria_tl_is(b, EXTERIA_TL_ID_inputPageBlockMap)) {
        rich_map(c, b);
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockEmbed)) {
        const uint8_t *url;
        size_t len;
        int64_t poster = 0;
        if (exteria_tl_get_i64(b, "poster_photo_id", &poster) == EXTERIA_OK) rich_media(c, rich_find(c->photos, poster), NULL, 0);
        if (rich_embed_url(b, &url, &len)) rich_link_line(c, "\xF0\x9F\x94\x97 ", url, len);
        rich_caption(c, exteria_tl_get(b, "caption"));
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockChannel)) {
        const exteria_tl_value *chat = exteria_tl_get(b, "channel");
        const uint8_t *title, *username;
        size_t title_len, username_len;
        exteria_rich_block *out;
        rich_span s;
        char url[96];
        if (!chat || exteria_tl_get_bytes(chat, "title", &title, &title_len) != EXTERIA_OK || !title_len || !(out = rich_begin(c, EXTERIA_RICH_PARAGRAPH))) return;
        s.block = out;
        s.units = 0;
        rich_put_string(c, &s, "\xF0\x9F\x93\xA2 ");
        rich_put(c, &s, title, title_len);
        rich_entity(c, &s, EXTERIA_ENTITY_BOLD, 0, NULL, 0, NULL);
        /* a public channel opens by its name; a private one has nothing a link could carry */
        if (exteria_tl_get_bytes(chat, "username", &username, &username_len) == EXTERIA_OK && username_len > 0 && username_len < sizeof(url) - 14) {
            snprintf(url, sizeof(url), "https://t.me/%.*s", (int)username_len, (const char *)username);
            rich_entity(c, &s, EXTERIA_ENTITY_TEXT_URL, 0, (const uint8_t *)url, strlen(url), NULL);
        }
        rich_end(c, out);
    } else if (exteria_tl_is(b, EXTERIA_TL_ID_pageBlockRelatedArticles)) {
        const exteria_tl_value *articles = exteria_tl_get(b, "articles");
        rich_text_block(c, EXTERIA_RICH_HEADING, 4, exteria_tl_get(b, "title"));
        if (!rich_is_vec(articles)) return;
        for (uint32_t i = 0; i < articles->u.vec.count && i < RICH_ITEMS_MAX; ++i) {
            const exteria_tl_value *article = articles->u.vec.items[i];
            const uint8_t *url, *text;
            size_t url_len, text_len;
            exteria_rich_block *item;
            rich_span s;
            uint32_t start;
            if (exteria_tl_get_bytes(article, "url", &url, &url_len) != EXTERIA_OK || !url_len || !(item = rich_begin(c, EXTERIA_RICH_LIST_ITEM))) continue;
            snprintf(item->label, sizeof(item->label), "\xE2\x80\xA2");
            s.block = item;
            s.units = 0;
            start = s.units;
            if (exteria_tl_get_bytes(article, "title", &text, &text_len) == EXTERIA_OK && text_len) rich_put(c, &s, text, text_len);
            else rich_put(c, &s, url, url_len);
            rich_entity(c, &s, EXTERIA_ENTITY_TEXT_URL, start, url, url_len, NULL);
            rich_end(c, item);
            if (exteria_tl_get_bytes(article, "description", &text, &text_len) == EXTERIA_OK && text_len) {
                exteria_rich_block *line;
                /* the description stands one level in, under its title */
                if (c->indent < UINT8_MAX) ++c->indent;
                line = rich_begin(c, EXTERIA_RICH_CAPTION);
                c->indent = indent;
                if (!line) continue;
                s.block = line;
                s.units = 0;
                rich_put(c, &s, text, text_len);
                rich_end(c, line);
            }
        }
    }
    /* anchors and unsupported blocks have nothing to show */
    c->quote = quote;
    c->indent = indent;
}

static void rich_blocks(rich_ctx *c, const exteria_tl_value *blocks, unsigned depth) {
    if (!rich_is_vec(blocks) || depth > RICH_BLOCK_DEPTH_MAX) return;
    for (uint32_t i = 0; i < blocks->u.vec.count && i < RICH_ITEMS_MAX; ++i) rich_block(c, blocks->u.vec.items[i], depth);
}

exteria_status exteria_rich_read(const exteria_tl_value *message, exteria_rich_doc *out) {
    const exteria_tl_value *rich;
    rich_ctx c;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, offsetof(exteria_rich_doc, blocks));
    rich = message ? exteria_tl_get(message, "rich_message") : NULL;
    if (!rich || !exteria_tl_is(rich, EXTERIA_TL_ID_richMessage)) return EXTERIA_E_NOTFOUND;
    memset(&c, 0, sizeof(c));
    c.doc = out;
    c.photos = exteria_tl_get(rich, "photos");
    c.documents = exteria_tl_get(rich, "documents");
    out->rtl = exteria_tl_has(rich, "rtl") ? 1 : 0;
    rich_blocks(&c, exteria_tl_get(rich, "blocks"), 0);
    return out->block_count ? EXTERIA_OK : EXTERIA_E_MALFORMED;
}
