#include <math.h>

#include "test_util.h"
#include "exteria_messages.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void set_i32(exteria_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, f, x), EXTERIA_OK); }
static void set_i64(exteria_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, f, x), EXTERIA_OK); }
static void set_f64(exteria_tl_value *v, const char *f, double x) { CHECK_EQ_INT(exteria_tl_set_f64(&arena, v, f, x), EXTERIA_OK); }
static void set_str(exteria_tl_value *v, const char *f, const char *x) { CHECK_EQ_INT(exteria_tl_set_str(&arena, v, f, x), EXTERIA_OK); }
static void set_flag(exteria_tl_value *v, const char *f) { CHECK_EQ_INT(exteria_tl_set_flag(v, f), EXTERIA_OK); }
static void set(exteria_tl_value *v, const char *f, exteria_tl_value *x) { CHECK_EQ_INT(exteria_tl_set(v, f, x), EXTERIA_OK); }

static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *v = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(v != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(v, i, items[i]), EXTERIA_OK);
    return v;
}

static exteria_tl_value *peer_user(int64_t id) {
    exteria_tl_value *p = obj("peerUser");
    set_i64(p, "user_id", id);
    return p;
}

static exteria_tl_value *message(int32_t id, const char *text) {
    exteria_tl_value *m = obj("message");
    set_i32(m, "id", id);
    set(m, "peer_id", peer_user(5));
    set_i32(m, "date", 1000 + id);
    set_str(m, "message", text);
    return m;
}

static exteria_tl_value *size(const char *type, int32_t w, int32_t h, int32_t bytes) {
    exteria_tl_value *s = obj("photoSize");
    set_str(s, "type", type);
    set_i32(s, "w", w);
    set_i32(s, "h", h);
    set_i32(s, "size", bytes);
    return s;
}

static exteria_tl_value *document(int64_t id, const char *mime, exteria_tl_value **attributes, uint32_t n) {
    static const uint8_t reference[] = {1, 2, 3, 4};
    exteria_tl_value *d = obj("document"), *thumbs[2];
    set_i64(d, "id", id);
    set_i64(d, "access_hash", id * 3);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, d, "file_reference", reference, sizeof(reference)), EXTERIA_OK);
    set_i32(d, "date", 5);
    set_str(d, "mime_type", mime);
    set_i64(d, "size", 40960);
    set_i32(d, "dc_id", 2);
    set(d, "attributes", vec_of(attributes, n));
    thumbs[0] = size("s", 50, 50, 1000);
    thumbs[1] = size("m", 128, 128, 4000);
    set(d, "thumbs", vec_of(thumbs, 2));
    return d;
}

static exteria_tl_value *media_document(exteria_tl_value *doc) {
    exteria_tl_value *m = obj("messageMediaDocument");
    set(m, "document", doc);
    return m;
}

static exteria_tl_value *sticker_attribute(const char *alt) {
    exteria_tl_value *a = obj("documentAttributeSticker");
    set_str(a, "alt", alt);
    set(a, "stickerset", obj("inputStickerSetEmpty"));
    return a;
}

static exteria_tl_value *answer(const char *ctor, exteria_tl_value **messages, uint32_t n) {
    exteria_tl_value *a = obj(ctor);
    set(a, "messages", vec_of(messages, n));
    set(a, "topics", vec_of(NULL, 0));
    set(a, "chats", vec_of(NULL, 0));
    set(a, "users", vec_of(NULL, 0));
    if (!strcmp(ctor, "messages.channelMessages")) {
        set_i32(a, "pts", 1);
        set_i32(a, "count", (int32_t)n);
    }
    if (!strcmp(ctor, "messages.messagesSlice")) set_i32(a, "count", (int32_t)n);
    return a;
}

static void test_text_message(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(7, "line one\nline two");
    exteria_tl_value *reply = obj("messageReplyHeader"), *entities[3], *url;
    CHECK(row != NULL);
    set_flag(m, "out");
    set(m, "from_id", peer_user(9));
    set_i32(reply, "reply_to_msg_id", 3);
    set(m, "reply_to", reply);
    entities[0] = obj("messageEntityBold");
    set_i32(entities[0], "offset", 0);
    set_i32(entities[0], "length", 4);
    entities[1] = obj("messageEntityTextUrl");
    set_i32(entities[1], "offset", 5);
    set_i32(entities[1], "length", 3);
    set_str(entities[1], "url", "https://example.org/a");
    /* a negative offset and an unknown kind are dropped, the rest stays */
    entities[2] = obj("messageEntityItalic");
    set_i32(entities[2], "offset", -1);
    set_i32(entities[2], "length", 2);
    set(m, "entities", vec_of(entities, 3));
    url = obj("messageEntitySpoiler");
    set_i32(url, "offset", 0);
    set_i32(url, "length", 1);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->id, 7);
    CHECK_EQ_INT(row->date, 1007);
    CHECK_EQ_INT(row->out, 1);
    CHECK_EQ_INT(row->from_id, 9);
    CHECK_EQ_INT(row->reply_to, 3);
    CHECK_EQ_INT(row->reply_peer_kind, 0);
    CHECK_EQ_INT(row->reply_quote[0], 0);
    set(reply, "reply_to_peer_id", peer_user(91));
    set_str(reply, "quote_text", "quoted words");
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->reply_peer_kind, 1);
    CHECK_EQ_INT(row->reply_peer_id, 91);
    CHECK(!strcmp(row->reply_quote, "quoted words"));
    CHECK_EQ_INT(row->service, 0);
    CHECK_EQ_INT(row->media.kind, EXTERIA_PREVIEW_TEXT);
    CHECK(!strcmp(row->text, "line one\nline two"));
    CHECK_EQ_INT(row->entity_count, 2);
    CHECK_EQ_INT(row->entities[0].kind, EXTERIA_ENTITY_BOLD);
    CHECK_EQ_INT(row->entities[1].kind, EXTERIA_ENTITY_TEXT_URL);
    CHECK_EQ_INT(row->entities[1].url_length, 21);
    CHECK(!strcmp(row->urls + row->entities[1].url_offset, "https://example.org/a"));
    free(row);
}

static exteria_tl_value *gif_document(exteria_tl_value *thumbs, exteria_tl_value *video_thumbs) {
    exteria_tl_value *d = obj("document"), *media = obj("messageMediaDocument"), *animated = obj("documentAttributeAnimated"), *video = obj("documentAttributeVideo");
    exteria_tl_value *attributes[2];
    static const uint8_t reference[] = {1, 2, 3};
    set_i64(d, "id", 77);
    set_i64(d, "access_hash", 88);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, d, "file_reference", reference, sizeof(reference)), EXTERIA_OK);
    set_i32(d, "dc_id", 2);
    set_str(d, "mime_type", "video/mp4");
    set_i32(video, "w", 258);
    set_i32(video, "h", 258);
    attributes[0] = animated;
    attributes[1] = video;
    set(d, "attributes", vec_of(attributes, 2));
    if (thumbs) set(d, "thumbs", thumbs);
    if (video_thumbs) set(d, "video_thumbs", video_thumbs);
    set(media, "document", d);
    return media;
}

static exteria_tl_value *size_item(const char *name, const char *type, int32_t w, int32_t h) {
    exteria_tl_value *s = obj(name);
    set_str(s, "type", type);
    set_i32(s, "w", w);
    set_i32(s, "h", h);
    set_i32(s, "size", 1000);
    return s;
}

static void test_gif_preview(void) {
    exteria_media_info info;
    exteria_tl_value *items[2];
    exteria_tl_value *stripped = obj("photoStrippedSize");
    set_str(stripped, "type", "i");
    /* a photo size wins when there is one */
    items[0] = stripped;
    items[1] = size_item("photoSize", "m", 180, 180);
    exteria_media_classify(gif_document(vec_of(items, 2), vec_of(items + 1, 0)), &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_GIF);
    CHECK(strcmp(info.preview.thumb, "m") == 0);
    /* only a stripped picture and a clip: the clip is the preview */
    items[0] = stripped;
    exteria_media_classify(gif_document(vec_of(items, 1), vec_of((exteria_tl_value *[]){size_item("videoSize", "v", 150, 150)}, 1)), &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_GIF);
    CHECK(strcmp(info.preview.thumb, "v") == 0);
    CHECK_EQ_INT(info.preview.dc, 2);
    /* nothing to fetch: no preview at all */
    exteria_media_classify(gif_document(vec_of(items, 1), NULL), &info);
    CHECK_EQ_INT(info.preview.thumb[0], 0);
}

static void test_edit_hide(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m;
    CHECK(row != NULL);
    if (!row) return;
    m = message(40, "text");
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->edit_date, 0);
    CHECK_EQ_INT(row->edit_hide, 0);
    /* an edit date with the hide flag is a change of the server and not of the words */
    m = message(41, "text");
    set_i32(m, "edit_date", 5000);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->edit_date, 5000);
    CHECK_EQ_INT(row->edit_hide, 0);
    m = message(42, "text");
    set_i32(m, "edit_date", 5000);
    set_flag(m, "edit_hide");
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->edit_date, 5000);
    CHECK_EQ_INT(row->edit_hide, 1);
    free(row);
}

static void test_custom_emoji_entity(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(8, "a\xF0\x9F\x98\x80 b"), *entities[2];
    CHECK(row != NULL);
    entities[0] = obj("messageEntityCustomEmoji");
    set_i32(entities[0], "offset", 1);
    set_i32(entities[0], "length", 2);
    set_i64(entities[0], "document_id", 5368324170671202286ll);
    /* without a document there is nothing to draw, so the entity is dropped and the text stays */
    entities[1] = obj("messageEntityCustomEmoji");
    set_i32(entities[1], "offset", 3);
    set_i32(entities[1], "length", 1);
    set_i64(entities[1], "document_id", 0);
    set(m, "entities", vec_of(entities, 2));
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->entity_count, 1);
    CHECK_EQ_INT(row->entities[0].kind, EXTERIA_ENTITY_CUSTOM_EMOJI);
    CHECK_EQ_INT(row->entities[0].offset, 1);
    CHECK_EQ_INT(row->entities[0].length, 2);
    CHECK(row->entities[0].document_id == 5368324170671202286ll);
    free(row);
}

static void test_formatting_entities(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(10, "hidden code quote name when"), *entities[7];
    CHECK(row != NULL);
    entities[0] = obj("messageEntitySpoiler");
    set_i32(entities[0], "offset", 0);
    set_i32(entities[0], "length", 6);
    entities[1] = obj("messageEntityPre");
    set_i32(entities[1], "offset", 7);
    set_i32(entities[1], "length", 4);
    set_str(entities[1], "language", "c");
    entities[2] = obj("messageEntityBlockquote");
    set_flag(entities[2], "collapsed");
    set_i32(entities[2], "offset", 12);
    set_i32(entities[2], "length", 5);
    entities[3] = obj("messageEntityMentionName");
    set_i32(entities[3], "offset", 18);
    set_i32(entities[3], "length", 4);
    set_i64(entities[3], "user_id", 77);
    entities[4] = obj("messageEntityFormattedDate");
    set_flag(entities[4], "long_date");
    set_flag(entities[4], "day_of_week");
    set_i32(entities[4], "offset", 23);
    set_i32(entities[4], "length", 4);
    set_i32(entities[4], "date", 1700000000);
    /* a name that points at nobody and a date without its moment stay plain text */
    entities[5] = obj("messageEntityMentionName");
    set_i32(entities[5], "offset", 0);
    set_i32(entities[5], "length", 2);
    set_i64(entities[5], "user_id", 0);
    entities[6] = obj("messageEntityFormattedDate");
    set_i32(entities[6], "offset", 0);
    set_i32(entities[6], "length", 2);
    set(m, "entities", vec_of(entities, 7));
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->entity_count, 5);
    CHECK_EQ_INT(row->entities[0].kind, EXTERIA_ENTITY_SPOILER);
    CHECK_EQ_INT(row->entities[1].kind, EXTERIA_ENTITY_PRE);
    CHECK(!strcmp(row->urls + row->entities[1].url_offset, "c"));
    CHECK_EQ_INT(row->entities[2].kind, EXTERIA_ENTITY_BLOCKQUOTE);
    CHECK_EQ_INT(row->entities[2].flags, EXTERIA_ENTITY_COLLAPSED);
    CHECK_EQ_INT(row->entities[3].kind, EXTERIA_ENTITY_MENTION_NAME);
    CHECK(row->entities[3].user_id == 77);
    CHECK_EQ_INT(row->entities[4].kind, EXTERIA_ENTITY_FORMATTED_DATE);
    CHECK_EQ_INT(row->entities[4].date, 1700000000);
    CHECK_EQ_INT(row->entities[4].flags, EXTERIA_DATE_LONG_DATE | EXTERIA_DATE_DAY_OF_WEEK);
    free(row);
}

static void test_sticker_set_reference(void) {
    exteria_media_info info;
    exteria_tl_value *document = obj("document"), *attributes[1], *attribute = obj("documentAttributeSticker"), *named = obj("inputStickerSetID");
    set_i64(document, "id", 5);
    set_i64(document, "access_hash", 6);
    set_i32(document, "dc_id", 2);
    set_str(document, "mime_type", "image/webp");
    set_str(attribute, "alt", "x");
    set_i64(named, "id", 1234);
    set_i64(named, "access_hash", 5678);
    set(attribute, "stickerset", named);
    attributes[0] = attribute;
    set(document, "attributes", vec_of(attributes, 1));
    memset(&info, 0, sizeof(info));
    exteria_document_read(document, &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_STICKER);
    CHECK(info.sticker_set_id == 1234);
    CHECK(info.sticker_set_hash == 5678);
}

static void test_bot_message(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(9, "/start now"), *entities[1], *markup = obj("replyInlineMarkup");
    CHECK(row != NULL);
    entities[0] = obj("messageEntityBotCommand");
    set_i32(entities[0], "offset", 0);
    set_i32(entities[0], "length", 6);
    set(m, "entities", vec_of(entities, 1));
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->entity_count, 1);
    CHECK_EQ_INT(row->entities[0].kind, EXTERIA_ENTITY_BOT_COMMAND);
    CHECK_EQ_INT(row->entities[0].length, 6);
    CHECK_EQ_INT(row->via_bot_id, 0);
    CHECK_EQ_INT(row->has_markup, 0);
    set_i64(m, "via_bot_id", 4242);
    set(markup, "rows", vec_of(NULL, 0));
    set(m, "reply_markup", markup);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->via_bot_id, 4242);
    CHECK_EQ_INT(row->has_markup, 1);
    free(row);
}

static void test_invoice_message(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(10, ""), *media = obj("messageMediaInvoice");
    CHECK(row != NULL);
    set_str(media, "title", "Pack \xF0\x9F\x98\x80");
    set_str(media, "description", "Ten stickers");
    set_str(media, "currency", "XTR");
    set_i64(media, "total_amount", 150);
    set_str(media, "start_param", "p");
    set(m, "media", media);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK(!strcmp(row->text, "Pack \xF0\x9F\x98\x80\nTen stickers\n\n\xE2\xAD\x90 150"));
    CHECK_EQ_INT(row->entity_count, 1);
    CHECK_EQ_INT(row->entities[0].kind, EXTERIA_ENTITY_BOLD);
    CHECK_EQ_INT(row->entities[0].offset, 0);
    /* the emoji counts as two units, the way the server counts */
    CHECK_EQ_INT(row->entities[0].length, 7);
    CHECK_EQ_INT(row->media.kind, EXTERIA_PREVIEW_OTHER);
    set_str(media, "currency", "USD");
    m = message(11, "");
    set(m, "media", media);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK(!strcmp(row->text, "Pack \xF0\x9F\x98\x80\nTen stickers"));
    /* a message that has its own text keeps it */
    m = message(12, "own words");
    set(m, "media", media);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK(!strcmp(row->text, "own words"));
    CHECK_EQ_INT(row->entity_count, 0);
    free(row);
}

static void test_text_limits(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    char *long_text = malloc(EXTERIA_MESSAGE_TEXT_MAX + 50);
    size_t i;
    CHECK(row && long_text);
    /* a two byte letter lands across the cut, it must go whole */
    for (i = 0; i < EXTERIA_MESSAGE_TEXT_MAX + 40; ++i) long_text[i] = 'a';
    long_text[EXTERIA_MESSAGE_TEXT_MAX + 40] = 0;
    long_text[EXTERIA_MESSAGE_TEXT_MAX - 2] = (char)0xD0;
    long_text[EXTERIA_MESSAGE_TEXT_MAX - 1] = (char)0xB1;
    CHECK_EQ_INT(exteria_message_read(message(1, long_text), row), EXTERIA_OK);
    CHECK_EQ_INT(strlen(row->text), EXTERIA_MESSAGE_TEXT_MAX - 2);
    CHECK_EQ_INT((uint8_t)row->text[strlen(row->text) - 1], 'a');
    CHECK_EQ_INT(exteria_message_read(message(2, ""), row), EXTERIA_OK);
    CHECK_EQ_INT(row->text[0], 0);
    free(long_text);
    free(row);
}

static void test_url_pool_overflow(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(1, "x"), *entities[4];
    char url[400];
    int i;
    CHECK(row != NULL);
    memset(url, 'u', sizeof(url) - 1);
    url[sizeof(url) - 1] = 0;
    for (i = 0; i < 4; ++i) {
        entities[i] = obj("messageEntityTextUrl");
        set_i32(entities[i], "offset", i);
        set_i32(entities[i], "length", 1);
        set_str(entities[i], "url", url);
    }
    set(m, "entities", vec_of(entities, 4));
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    /* 1024 bytes of pool hold two 399 byte addresses, the others are left out instead of cut */
    CHECK_EQ_INT(row->entity_count, 2);
    CHECK_EQ_INT(strlen(row->urls + row->entities[1].url_offset), 399);
    free(row);
}

static void test_sticker(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *attributes[2], *m = message(2, "");
    attributes[0] = sticker_attribute("\xF0\x9F\x98\x80");
    attributes[1] = obj("documentAttributeImageSize");
    set_i32(attributes[1], "w", 512);
    set_i32(attributes[1], "h", 480);
    set(m, "media", media_document(document(77, "image/webp", attributes, 2)));
    CHECK(row != NULL);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->media.kind, EXTERIA_PREVIEW_STICKER);
    CHECK_EQ_INT(row->media.sticker, EXTERIA_STICKER_STATIC);
    CHECK_EQ_INT(row->media.width, 512);
    CHECK_EQ_INT(row->media.height, 480);
    CHECK_EQ_INT(row->media.ref.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);
    CHECK_EQ_INT(row->media.ref.id, 77);
    CHECK_EQ_INT(row->media.ref.dc, 2);
    CHECK_EQ_INT(row->media.ref.ref_len, 4);
    CHECK_EQ_INT(row->media.ref.thumb[0], 0);
    CHECK(!strcmp(row->media.alt, "\xF0\x9F\x98\x80"));
    /* the preview is the thumbnail that covers 100 pixels, not the 50 pixel one */
    CHECK_EQ_INT(row->media.preview.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);
    CHECK(!strcmp(row->media.preview.thumb, "m"));

    attributes[0] = sticker_attribute("x");
    m = message(3, "");
    set(m, "media", media_document(document(78, "application/x-tgsticker", attributes, 1)));
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->media.sticker, EXTERIA_STICKER_ANIMATED);
    attributes[0] = sticker_attribute("x");
    m = message(4, "");
    set(m, "media", media_document(document(79, "video/webm", attributes, 1)));
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->media.sticker, EXTERIA_STICKER_VIDEO);
    free(row);
}

static exteria_tl_value *video_document(int64_t id, const char *codec, int32_t width, int32_t height) {
    exteria_tl_value *video = obj("documentAttributeVideo"), *attributes[] = {video};
    set_f64(video, "duration", 11.6);
    set_i32(video, "w", width);
    set_i32(video, "h", height);
    if (codec) set_str(video, "video_codec", codec);
    return document(id, "video/mp4", attributes, 1);
}

static void test_video_variants(void) {
    exteria_media_info info;
    exteria_tl_value *original = video_document(21, "hevc", 720, 1280);
    exteria_tl_value *media = media_document(original);
    exteria_media_classify_sized(media, 1280, &info);
    CHECK_EQ_INT(info.ref.id, 21);
    exteria_tl_value *alternatives[] = {
        video_document(22, "h264", 1080, 1920), video_document(23, "avc", 720, 1280),
        video_document(24, "h264", 360, 640), video_document(25, "hevc", 720, 1280),
        video_document(26, NULL, 720, 1280), obj("documentEmpty")
    };
    set(media, "alt_documents", vec_of(alternatives, 6));
    exteria_media_classify_sized(media, 1280, &info);
    CHECK_EQ_INT(info.ref.id, 23);
    CHECK_EQ_INT(info.preview.id, 23);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_VIDEO);
    CHECK_EQ_INT(info.width, 720);
    CHECK_EQ_INT(info.height, 1280);
    CHECK_EQ_INT(info.duration, 11);
    exteria_media_classify_sized(media, 320, &info);
    CHECK_EQ_INT(info.ref.id, 24);
    exteria_media_classify_sized(media, 4096, &info);
    CHECK_EQ_INT(info.ref.id, 22);
    /* an already compatible primary document stays the same */
    set(media, "document", video_document(27, "h264", 720, 1280));
    exteria_media_classify_sized(media, 320, &info);
    CHECK_EQ_INT(info.ref.id, 27);
    set(media, "document", original);
    set_i32(alternatives[0], "dc_id", 0);
    set_i64(alternatives[1], "size", 0);
    set_str(alternatives[2], "mime_type", "video/webm");
    exteria_media_classify_sized(media, 1280, &info);
    CHECK_EQ_INT(info.ref.id, 21);
    exteria_tl_value *malformed = vec_of(NULL, 0);
    set(media, "alt_documents", malformed);
    malformed->kind = EXTERIA_TL_V_I32;
    exteria_media_classify_sized(media, 1280, &info);
    CHECK_EQ_INT(info.ref.id, 21);
    exteria_tl_value *many = exteria_tl_new_vec(&arena, 65);
    CHECK(many != NULL);
    set(media, "alt_documents", many);
    exteria_media_classify_sized(media, 1280, &info);
    CHECK_EQ_INT(info.ref.id, 21);
    set(media, "alt_documents", vec_of(NULL, 0));
    exteria_media_classify_sized(media, 1280, &info);
    CHECK_EQ_INT(info.ref.id, 21);
}

static void test_media_kinds(void) {
    exteria_media_info info;
    exteria_tl_value *attributes[3], *media, *photo, *sizes[6];
    attributes[0] = obj("documentAttributeFilename");
    set_str(attributes[0], "file_name", "Exteria_icon.png");
    media = media_document(document(10, "image/png", attributes, 1));
    exteria_media_classify(media, &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_FILE);
    CHECK(!strcmp(info.name, "Exteria_icon.png"));
    CHECK_EQ_INT(info.size, 40960);

    attributes[0] = obj("documentAttributeVideo");
    set_f64(attributes[0], "duration", 12.7);
    set_i32(attributes[0], "w", 320);
    set_i32(attributes[0], "h", 240);
    media = media_document(document(11, "video/mp4", attributes, 1));
    exteria_media_classify(media, &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_VIDEO);
    CHECK_EQ_INT(info.duration, 12);
    attributes[0] = obj("documentAttributeVideo");
    set_f64(attributes[0], "duration", 3);
    set_i32(attributes[0], "w", 240);
    set_i32(attributes[0], "h", 240);
    set_flag(attributes[0], "round_message");
    exteria_media_classify(media_document(document(12, "video/mp4", attributes, 1)), &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_VIDEO_MESSAGE);

    attributes[0] = obj("documentAttributeAudio");
    set_i32(attributes[0], "duration", 9);
    set_flag(attributes[0], "voice");
    exteria_media_classify(media_document(document(13, "audio/ogg", attributes, 1)), &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_VOICE);
    CHECK_EQ_INT(info.duration, 9);
    /* the waveform of a note rides along when it fits, and is left out when it does not */
    {
        static const uint8_t wave[4] = {1, 2, 3, 4};
        uint8_t big[EXTERIA_MEDIA_WAVEFORM_MAX + 1] = {0};
        CHECK_EQ_INT(info.waveform_len, 0);
        attributes[0] = obj("documentAttributeAudio");
        set_i32(attributes[0], "duration", 9);
        set_flag(attributes[0], "voice");
        CHECK_EQ_INT(exteria_tl_set_bytes(&arena, attributes[0], "waveform", wave, sizeof(wave)), EXTERIA_OK);
        exteria_media_classify(media_document(document(13, "audio/ogg", attributes, 1)), &info);
        CHECK_EQ_INT(info.waveform_len, 4);
        CHECK_EQ_INT(info.waveform[3], 4);
        attributes[0] = obj("documentAttributeAudio");
        set_flag(attributes[0], "voice");
        CHECK_EQ_INT(exteria_tl_set_bytes(&arena, attributes[0], "waveform", big, sizeof(big)), EXTERIA_OK);
        exteria_media_classify(media_document(document(13, "audio/ogg", attributes, 1)), &info);
        CHECK_EQ_INT(info.waveform_len, 0);
        attributes[0] = obj("documentAttributeAudio");
        set_i32(attributes[0], "duration", 9);
        set_flag(attributes[0], "voice");
        exteria_media_classify(media_document(document(13, "audio/ogg", attributes, 1)), &info);
    }
    attributes[0] = obj("documentAttributeAudio");
    set_i32(attributes[0], "duration", 200);
    exteria_media_classify(media_document(document(14, "audio/mpeg", attributes, 1)), &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_AUDIO);
    attributes[0] = obj("documentAttributeAnimated");
    attributes[1] = obj("documentAttributeVideo");
    set_f64(attributes[1], "duration", 2);
    set_i32(attributes[1], "w", 100);
    set_i32(attributes[1], "h", 100);
    exteria_media_classify(media_document(document(15, "video/mp4", attributes, 2)), &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_GIF);

    /* retina bubbles need more than 320 pixels; stripped sizes have no file */
    sizes[0] = obj("photoStrippedSize");
    set_str(sizes[0], "type", "i");
    sizes[1] = size("s", 90, 160, 800);
    sizes[2] = size("m", 180, 320, 9000);
    sizes[3] = size("x", 450, 800, 40000);
    photo = obj("photo");
    set_i64(photo, "id", 31);
    set_i64(photo, "access_hash", 32);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, photo, "file_reference", "abc", 3), EXTERIA_OK);
    set_i32(photo, "date", 1);
    set(photo, "sizes", vec_of(sizes, 4));
    set_i32(photo, "dc_id", 4);
    media = obj("messageMediaPhoto");
    set(media, "photo", photo);
    exteria_media_classify(media, &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_PHOTO);
    CHECK_EQ_INT(info.spoiler, 0);
    CHECK_EQ_INT(info.ref.source, EXTERIA_MEDIA_SOURCE_PHOTO);
    CHECK(!strcmp(info.ref.thumb, "x"));
    CHECK_EQ_INT(info.width, 450);
    CHECK_EQ_INT(info.height, 800);
    CHECK_EQ_INT(info.ref.dc, 4);
    CHECK_EQ_INT(info.full_photo.source, EXTERIA_MEDIA_SOURCE_PHOTO);
    CHECK(!strcmp(info.full_photo.thumb, "x"));
    CHECK_EQ_INT(info.full_photo_size, 40000);
    CHECK_EQ_INT(info.full_photo.id, info.ref.id);
    CHECK_EQ_INT(info.full_photo.dc, info.ref.dc);
    /* a photo the sender hid under a spoiler says so */
    set_flag(media, "spoiler");
    exteria_media_classify(media, &info);
    CHECK_EQ_INT(info.spoiler, 1);
    /* a story asks for a size near 1280 px; with no size that large the largest one is the best left */
    exteria_media_classify_sized(media, 1280, &info);
    CHECK(!strcmp(info.ref.thumb, "x"));
    CHECK_EQ_INT(info.width, 450);
    exteria_media_classify_sized(media, 320, &info);
    CHECK(!strcmp(info.ref.thumb, "m"));

    sizes[4] = size("w", 1440, 2560, 2000000);
    sizes[5] = size("y", 720, 1280, 400000);
    set(photo, "sizes", vec_of(sizes, 6));
    exteria_media_classify(media, &info);
    CHECK(!strcmp(info.ref.thumb, "x"));
    CHECK(!strcmp(info.full_photo.thumb, "w"));
    CHECK_EQ_INT(info.full_photo_size, 2000000);
    exteria_media_classify_sized(media, 1280, &info);
    CHECK(!strcmp(info.ref.thumb, "y"));
    CHECK(!strcmp(info.full_photo.thumb, "w"));

    /* a photo that expired keeps its kind but has nothing to fetch */
    media = obj("messageMediaPhoto");
    exteria_media_classify(media, &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_PHOTO);
    CHECK_EQ_INT(info.ref.source, EXTERIA_MEDIA_SOURCE_NONE);

    exteria_media_classify(obj("messageMediaWebPage"), &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_TEXT);
    exteria_media_classify(NULL, &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_TEXT);
    exteria_media_classify(obj("messageMediaPoll"), &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_POLL);
}

static void test_reference_limit(void) {
    exteria_media_info info;
    exteria_tl_value *attributes[1];
    uint8_t big[EXTERIA_MEDIA_REF_MAX + 1];
    exteria_tl_value *doc;
    memset(big, 7, sizeof(big));
    attributes[0] = obj("documentAttributeFilename");
    set_str(attributes[0], "file_name", "a");
    doc = document(5, "text/plain", attributes, 1);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, doc, "file_reference", big, sizeof(big)), EXTERIA_OK);
    exteria_media_classify(media_document(doc), &info);
    /* a reference longer than the cap cannot be sent back, so the file is not offered */
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_FILE);
    CHECK_EQ_INT(info.ref.source, EXTERIA_MEDIA_SOURCE_NONE);
    CHECK_EQ_INT(info.ref.ref_len, 0);
}

static void test_service(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = obj("messageService"), *action = obj("messageActionChatEditTitle");
    CHECK(row != NULL);
    set_i32(m, "id", 40);
    set(m, "peer_id", peer_user(5));
    set_i32(m, "date", 9);
    set(m, "from_id", peer_user(8));
    set_str(action, "title", "New name");
    set(m, "action", action);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->service, EXTERIA_SERVICE_TITLE + 1);
    CHECK_EQ_INT(row->media.kind, EXTERIA_PREVIEW_SERVICE);
    CHECK_EQ_INT(row->from_id, 8);
    CHECK(!strcmp(row->text, "New name"));
    free(row);
}

/* a message written in a group on behalf of a channel names the channel, not a user */
static void test_sent_as_channel(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(12, "as the channel"), *from = obj("peerChannel");
    CHECK(row != NULL);
    set_i64(from, "channel_id", 4321);
    set(m, "from_id", from);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->from_id, 0);
    CHECK_EQ_INT(row->from_channel, 4321);
    set(m, "from_id", peer_user(9));
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->from_id, 9);
    CHECK_EQ_INT(row->from_channel, 0);
    free(row);
}

static void test_post_counters(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(14, "post"), *replies = obj("messageReplies"), *who[4];
    int i;
    CHECK(row != NULL);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->views, 0);
    CHECK_EQ_INT(row->has_comments, 0);
    set_i32(m, "views", 79);
    set_flag(replies, "comments");
    set_i32(replies, "replies", 10);
    set_i32(replies, "replies_pts", 1);
    set_i64(replies, "channel_id", 600);
    for (i = 0; i < 4; ++i) who[i] = peer_user(20 + i);
    set(replies, "recent_repliers", vec_of(who, 4));
    set(m, "replies", replies);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->views, 79);
    CHECK_EQ_INT(row->has_comments, 1);
    CHECK_EQ_INT(row->comments, 10);
    CHECK_EQ_INT(row->discussion_id, 600);
    /* only the first three commenters are kept */
    CHECK_EQ_INT(row->commenter_count, 3);
    CHECK_EQ_INT(row->commenters[0], 20);
    CHECK_EQ_INT(row->commenters[2], 22);
    /* replies of a thread inside a group are not a post's comments */
    replies = obj("messageReplies");
    set_i32(replies, "replies", 3);
    set_i32(replies, "replies_pts", 1);
    set(m, "replies", replies);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->has_comments, 0);
    free(row);
}

static void test_pinned_request(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref channel = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0};
    CHECK_EQ_INT(exteria_pinned_request(&arena, &channel, 100, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_search);
    CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "filter")), EXTERIA_TL_ID_inputMessagesFilterPinned);
    CHECK_EQ_INT(exteria_pinned_request(&arena, &nohash, 100, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_pinned_request(&arena, &channel, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_pinned_request(&arena, &channel, EXTERIA_MESSAGES_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_pinned_request(&arena, &channel, 10, NULL), EXTERIA_E_ARG);
}

static void test_greeting_stickers(void) {
    exteria_tl_value *request = NULL, *docs[3], *s;
    exteria_sticker_row stickers[4];
    size_t count = 9;
    const uint8_t *text;
    size_t len;
    CHECK_EQ_INT(exteria_stickers_request(&arena, "\xf0\x9f\x91\x8b", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getStickers);
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "emoticon", &text, &len), EXTERIA_OK);
    CHECK_EQ_INT((int)len, 4);
    CHECK_EQ_INT(exteria_stickers_request(&arena, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_stickers_request(&arena, "0123456789012345678901234567890123", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_stickers_request(&arena, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_stickers_request(&arena, "a", NULL), EXTERIA_E_ARG);
    s = obj("messages.stickers");
    set_i64(s, "hash", 1);
    set(s, "stickers", vec_of(docs, 0));
    CHECK_EQ_INT(exteria_stickers_parse(s, stickers, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(exteria_stickers_parse(obj("messages.stickersNotModified"), stickers, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_stickers_parse(obj("messages.recentStickers"), stickers, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_stickers_parse(NULL, stickers, 4, &count), EXTERIA_E_ARG);
}

static void test_empty_and_malformed(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = obj("messageEmpty"), *bad = obj("message");
    CHECK(row != NULL);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_message_read(bad, row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_message_read(obj("user"), row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_message_read(NULL, row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_message_read(m, NULL), EXTERIA_E_ARG);
    free(row);
}

static void test_answers(void) {
    exteria_message_row *rows = calloc(4, sizeof(*rows));
    exteria_tl_value *list[3];
    size_t count = 99;
    CHECK(rows != NULL);
    list[0] = message(30, "newest");
    list[1] = obj("messageEmpty");
    list[2] = message(28, "older");
    CHECK_EQ_INT(exteria_messages_parse(answer("messages.messagesSlice", list, 3), rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].id, 30);
    CHECK_EQ_INT(rows[1].id, 28);
    CHECK_EQ_INT(exteria_messages_parse(answer("messages.channelMessages", list, 3), rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_messages_parse(answer("messages.messages", list, 0), rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_messages_parse(obj("messages.messagesNotModified"), rows, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_messages_parse(obj("contacts.contacts"), rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_messages_parse(NULL, rows, 4, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_messages_parse(answer("messages.messages", list, 1), rows, 0, &count), EXTERIA_E_ARG);
    free(rows);
}

static exteria_tl_value *sticker_set(int64_t id, const char *title, int flags_masks) {
    exteria_tl_value *s = obj("stickerSet"), *thumbs[1];
    set_i64(s, "id", id);
    set_i64(s, "access_hash", id + 1);
    set_str(s, "title", title);
    set_str(s, "short_name", "short");
    set_i32(s, "count", 3);
    set_i32(s, "hash", 99);
    if (flags_masks) set_flag(s, "masks");
    thumbs[0] = size("s", 100, 100, 3000);
    set(s, "thumbs", vec_of(thumbs, 1));
    set_i32(s, "thumb_dc_id", 5);
    set_i32(s, "thumb_version", 7);
    return s;
}

static void test_sticker_sets(void) {
    exteria_sticker_set_row sets[4], one;
    exteria_sticker_row stickers[4];
    exteria_tl_value *list[3], *attributes[1], *docs[3], *a, *s;
    size_t count;
    list[0] = sticker_set(1, "First", 0);
    set_i64(list[0], "thumb_document_id", 1234567890123LL);
    list[1] = sticker_set(2, "Masks", 1);
    list[2] = sticker_set(3, "Third", 0);
    a = obj("messages.allStickers");
    set_i64(a, "hash", 1);
    set(a, "sets", vec_of(list, 3));
    CHECK_EQ_INT(exteria_sticker_sets_parse(a, sets, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(sets[0].id, 1);
    CHECK_EQ_INT(sets[1].id, 3);
    CHECK_EQ_INT(sets[0].thumb_dc, 5);
    CHECK_EQ_INT(sets[0].thumb_version, 7);
    CHECK(sets[0].thumb_document_id == 1234567890123LL);
    CHECK(sets[1].thumb_document_id == 0);
    CHECK(!strcmp(sets[0].title, "First"));
    CHECK_EQ_INT(exteria_sticker_sets_parse(obj("messages.allStickersNotModified"), sets, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_sticker_sets_parse(obj("messages.recentStickers"), sets, 4, &count), EXTERIA_E_MALFORMED);

    attributes[0] = sticker_attribute("a");
    docs[0] = document(100, "image/webp", attributes, 1);
    attributes[0] = obj("documentAttributeFilename");
    set_str(attributes[0], "file_name", "not a sticker");
    docs[1] = document(101, "image/webp", attributes, 1);
    attributes[0] = sticker_attribute("b");
    docs[2] = document(102, "application/x-tgsticker", attributes, 1);
    s = obj("messages.stickerSet");
    set(s, "set", sticker_set(1, "First", 0));
    set(s, "packs", vec_of(NULL, 0));
    set(s, "keywords", vec_of(NULL, 0));
    set(s, "documents", vec_of(docs, 3));
    CHECK_EQ_INT(exteria_sticker_set_parse(s, &one, stickers, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(one.id, 1);
    CHECK_EQ_INT(one.installed, 0);
    CHECK_EQ_INT(stickers[0].media.ref.id, 100);
    CHECK_EQ_INT(stickers[1].media.sticker, EXTERIA_STICKER_ANIMATED);
    CHECK_EQ_INT(exteria_sticker_set_parse(s, &one, stickers, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    {
        /* the date the account added the set is what says it is installed */
        exteria_tl_value *header = sticker_set(2, "Mine", 0), *held = obj("messages.stickerSet");
        set_i32(header, "installed_date", 1700000000);
        set(held, "set", header);
        set(held, "packs", vec_of(NULL, 0));
        set(held, "keywords", vec_of(NULL, 0));
        set(held, "documents", vec_of(docs, 3));
        CHECK_EQ_INT(exteria_sticker_set_parse(held, &one, stickers, 4, &count), EXTERIA_OK);
        CHECK_EQ_INT(one.installed, 1);
    }
    CHECK_EQ_INT(exteria_sticker_set_parse(obj("messages.stickerSetNotModified"), &one, stickers, 4, &count), EXTERIA_E_NOTFOUND);

    s = obj("messages.recentStickers");
    set_i64(s, "hash", 1);
    set(s, "packs", vec_of(NULL, 0));
    set(s, "stickers", vec_of(docs, 3));
    set(s, "dates", vec_of(NULL, 0));
    CHECK_EQ_INT(exteria_recent_stickers_parse(s, stickers, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(exteria_recent_stickers_parse(obj("messages.recentStickersNotModified"), stickers, 4, &count), EXTERIA_E_NOTFOUND);
}

static void test_sent_parse(void) {
    exteria_tl_value *list[2], *u, *update;
    int32_t id = 0;
    list[0] = obj("updateMessageID");
    set_i32(list[0], "id", 55);
    set_i64(list[0], "random_id", 1234);
    list[1] = obj("updateMessageID");
    set_i32(list[1], "id", 56);
    set_i64(list[1], "random_id", 4321);
    u = obj("updates");
    set(u, "updates", vec_of(list, 2));
    set(u, "users", vec_of(NULL, 0));
    set(u, "chats", vec_of(NULL, 0));
    set_i32(u, "date", 1);
    set_i32(u, "seq", 1);
    CHECK_EQ_INT(exteria_sent_parse(u, 4321, &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 56);
    CHECK_EQ_INT(exteria_sent_parse(u, 999, &id), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(id, 0);

    update = obj("updateShort");
    set(update, "update", list[0]);
    set_i32(update, "date", 1);
    CHECK_EQ_INT(exteria_sent_parse(update, 1234, &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 55);

    u = obj("updateShortSentMessage");
    set_i32(u, "id", 77);
    set_i32(u, "pts", 1);
    set_i32(u, "pts_count", 1);
    set_i32(u, "date", 1);
    CHECK_EQ_INT(exteria_sent_parse(u, 5, &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 77);
    CHECK_EQ_INT(exteria_sent_parse(obj("updatesTooLong"), 5, &id), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_sent_parse(NULL, 5, &id), EXTERIA_E_ARG);
}

/* every request must encode against the schema, a missing required field fails here */
static void check_encodes(const exteria_tl_value *request, uint32_t constructor) {
    exteria_writer w;
    exteria_tl_error error;
    CHECK(request != NULL);
    if (!request) return;
    exteria_writer_init(&w, 4096);
    CHECK_EQ_INT(exteria_tl_encode(request, &w, &error), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), constructor);
    exteria_writer_free(&w);
}

static void test_emoji_sets(void) {
    exteria_sticker_set_row sets[4], one;
    exteria_custom_emoji rows[4];
    exteria_tl_value *list[4], *attributes[1], *docs[2], *a, *s, *request = NULL;
    size_t count;
    list[0] = sticker_set(1, "Pictures", 0);
    list[1] = sticker_set(2, "Faces", 0);
    set_flag(list[1], "emojis");
    list[2] = sticker_set(3, "Old faces", 0);
    set_flag(list[2], "emojis");
    set_flag(list[2], "archived");
    list[3] = sticker_set(4, "More faces", 0);
    set_flag(list[3], "emojis");
    a = obj("messages.allStickers");
    set_i64(a, "hash", 1);
    set(a, "sets", vec_of(list, 4));
    CHECK_EQ_INT(exteria_emoji_sets_request(&arena, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getEmojiStickers);
    CHECK_EQ_INT(exteria_emoji_sets_request(&arena, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_emoji_sets_parse(a, sets, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(sets[0].id, 2);
    CHECK_EQ_INT(sets[1].id, 4);
    /* the sticker list keeps its own sets and none of these */
    CHECK_EQ_INT(exteria_sticker_sets_parse(a, sets, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(sets[0].id, 1);
    CHECK_EQ_INT(exteria_emoji_sets_parse(obj("messages.allStickersNotModified"), sets, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_emoji_sets_parse(obj("messages.recentStickers"), sets, 4, &count), EXTERIA_E_MALFORMED);

    attributes[0] = obj("documentAttributeCustomEmoji");
    set_str(attributes[0], "alt", "\xF0\x9F\x98\x80");
    docs[0] = document(300, "application/x-tgsticker", attributes, 1);
    docs[1] = document(301, "image/webp", NULL, 0);
    s = obj("messages.stickerSet");
    set(s, "set", list[1]);
    set(s, "packs", vec_of(NULL, 0));
    set(s, "keywords", vec_of(NULL, 0));
    set(s, "documents", vec_of(docs, 2));
    CHECK_EQ_INT(exteria_emoji_set_parse(s, &one, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(one.id, 2);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].id, 300);
    CHECK_EQ_INT(rows[0].format, EXTERIA_STICKER_ANIMATED);
    CHECK_EQ_INT(exteria_emoji_set_parse(obj("messages.stickerSetNotModified"), &one, rows, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_emoji_set_parse(obj("messages.recentStickers"), &one, rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_emoji_set_parse(s, &one, rows, 0, &count), EXTERIA_E_ARG);
}

static exteria_tl_value *topic_message(int32_t id, int forum, int32_t reply_to, int32_t top) {
    exteria_tl_value *m = message(id, "x"), *header = obj("messageReplyHeader");
    if (forum) set_flag(header, "forum_topic");
    if (reply_to) set_i32(header, "reply_to_msg_id", reply_to);
    if (top) set_i32(header, "reply_to_top_id", top);
    set(m, "reply_to", header);
    return m;
}

static void test_topic_of_message(void) {
    exteria_message_row row;
    CHECK_EQ_INT(exteria_message_read(message(5, "x"), &row), EXTERIA_OK);
    CHECK_EQ_INT(row.topic_id, 1);
    /* a reply in General carries a header without the topic flag */
    CHECK_EQ_INT(exteria_message_read(topic_message(9, 0, 4, 0), &row), EXTERIA_OK);
    CHECK_EQ_INT(row.topic_id, 1);
    CHECK_EQ_INT(row.reply_to, 4);
    /* the first answer to the topic root is not a reply the reader should see */
    CHECK_EQ_INT(exteria_message_read(topic_message(10, 1, 7, 0), &row), EXTERIA_OK);
    CHECK_EQ_INT(row.topic_id, 7);
    CHECK_EQ_INT(row.reply_to, 0);
    CHECK_EQ_INT(exteria_message_read(topic_message(11, 1, 7, 7), &row), EXTERIA_OK);
    CHECK_EQ_INT(row.topic_id, 7);
    CHECK_EQ_INT(row.reply_to, 0);
    /* a real reply inside a topic keeps its target */
    CHECK_EQ_INT(exteria_message_read(topic_message(12, 1, 10, 7), &row), EXTERIA_OK);
    CHECK_EQ_INT(row.topic_id, 7);
    CHECK_EQ_INT(row.reply_to, 10);
}

static void check_media_reply(exteria_tl_value *request, const exteria_peer_ref *peer) {
    const exteria_tl_value *media = exteria_tl_get(request, "media");
    int32_t id = 0;
    CHECK(media != NULL);
    CHECK_EQ_INT(exteria_set_reply(&arena, request, peer, 77), EXTERIA_OK);
    CHECK(exteria_tl_get(request, "media") == media);
    const exteria_tl_value *reply = exteria_tl_get(request, "reply_to");
    CHECK_EQ_INT(exteria_tl_get_i32(reply, "reply_to_msg_id", &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 77);
    if (peer->topic_id > 1) {
        CHECK_EQ_INT(exteria_tl_get_i32(reply, "top_msg_id", &id), EXTERIA_OK);
        CHECK_EQ_INT(id, peer->topic_id);
    } else CHECK(!exteria_tl_has(reply, "top_msg_id"));
    check_encodes(request, EXTERIA_TL_ID_messages_sendMedia);
    CHECK_EQ_INT(exteria_set_reply(&arena, request, peer, -1), EXTERIA_E_ARG);
    CHECK(exteria_tl_get(request, "reply_to") == reply);
    CHECK_EQ_INT(exteria_set_reply(NULL, request, peer, 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_set_reply(&arena, NULL, peer, 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_set_reply(&arena, request, NULL, 1), EXTERIA_E_ARG);
}

static void test_saved_history(void) {
    exteria_peer_ref source = {1, 77, 555, 0, 0}, self = {1, 9, 0, 1, 0}, bare = {1, 77, 0, 0, 0};
    exteria_tl_value *request = NULL, *m;
    exteria_message_row row;
    int32_t value = 0;
    /* a chat the favorites hold messages of, and the account's own notes, are asked from the saved history */
    CHECK_EQ_INT(exteria_saved_history_request(&arena, &source, 30, 40, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getSavedHistory);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "offset_id", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 30);
    CHECK_EQ_INT(exteria_saved_history_request(&arena, &self, 0, 40, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getSavedHistory);
    CHECK_EQ_INT(exteria_saved_history_request(&arena, &bare, 0, 40, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_history_request(&arena, &source, -1, 40, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_history_request(&arena, &source, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_history_request(&arena, &source, 0, EXTERIA_MESSAGES_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_history_request(&arena, &source, 0, 40, NULL), EXTERIA_E_ARG);
    /* the message names where it came from */
    m = message(5, "kept");
    set(m, "saved_peer_id", peer_user(77));
    CHECK_EQ_INT(exteria_message_read(m, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.saved_peer_kind, 1);
    CHECK_EQ_INT(row.saved_peer_id, 77);
    CHECK_EQ_INT(exteria_message_read(message(6, "plain"), &row), EXTERIA_OK);
    CHECK_EQ_INT(row.saved_peer_kind, 0);
    CHECK_EQ_INT(row.saved_peer_id, 0);
}

static void test_topic_requests(void) {
    exteria_peer_ref forum = {3, 7, 88, 0, 12}, general = {3, 7, 88, 0, 1}, whole = {3, 7, 88, 0, 0};
    exteria_tl_value *request = NULL, *reply;
    int32_t value = 0;
    CHECK_EQ_INT(exteria_history_request(&arena, &forum, 50, 40, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getReplies);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "msg_id", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 12);
    CHECK_EQ_INT(exteria_history_request(&arena, &general, 0, 40, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getReplies);
    CHECK_EQ_INT(exteria_history_request(&arena, &whole, 0, 40, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getHistory);

    CHECK_EQ_INT(exteria_send_text_request(&arena, &forum, "hi", NULL, 0, 42, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_sendMessage);
    reply = (exteria_tl_value *)exteria_tl_get(request, "reply_to");
    CHECK(reply != NULL);
    CHECK_EQ_INT(exteria_tl_get_i32(reply, "reply_to_msg_id", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 12);
    CHECK_EQ_INT(exteria_tl_get_i32(reply, "top_msg_id", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 12);
    /* general is what the server files a message with no header under */
    CHECK_EQ_INT(exteria_send_text_request(&arena, &general, "hi", NULL, 0, 42, &request), EXTERIA_OK);
    CHECK(exteria_tl_get(request, "reply_to") == NULL);
    CHECK_EQ_INT(exteria_send_text_request(&arena, &whole, "hi", NULL, 0, 42, &request), EXTERIA_OK);
    CHECK(exteria_tl_get(request, "reply_to") == NULL);

    CHECK_EQ_INT(exteria_send_geo_request(&arena, &forum, 10.0, 20.0, 42, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_sendMedia);
    CHECK(exteria_tl_get(request, "reply_to") != NULL);
    check_media_reply(request, &forum);

    CHECK_EQ_INT(exteria_read_history_request(&arena, &forum, 30, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_readDiscussion);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "msg_id", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 12);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "read_max_id", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 30);
    CHECK_EQ_INT(exteria_read_history_request(&arena, &forum, 0, &request), EXTERIA_E_ARG);
}

static void test_requests(void) {
    exteria_peer_ref user = {1, 5, 77, 0, 0}, chat = {2, 6, 0, 0, 0}, channel = {3, 7, 88, 0, 0}, self = {1, 9, 0, 1, 0};
    exteria_tl_value *request = NULL;
    exteria_media_ref sticker;
    exteria_sticker_set_row set;
    memset(&sticker, 0, sizeof(sticker));
    memset(&set, 0, sizeof(set));
    CHECK_EQ_INT(exteria_history_request(&arena, &user, 0, 40, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getHistory);
    CHECK_EQ_INT(exteria_history_request(&arena, &chat, 120, 40, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getHistory);
    CHECK_EQ_INT(exteria_history_request(&arena, &channel, 120, 40, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_history_request(&arena, &self, 0, 40, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "peer")), EXTERIA_TL_ID_inputPeerSelf);
    CHECK_EQ_INT(exteria_history_request(&arena, &user, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_history_request(&arena, &user, 0, EXTERIA_MESSAGES_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_history_request(&arena, &user, -1, 10, &request), EXTERIA_E_ARG);
    user.access_hash = 0;
    CHECK_EQ_INT(exteria_history_request(&arena, &user, 0, 10, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    user.access_hash = 77;
    channel.access_hash = 0;
    CHECK_EQ_INT(exteria_input_peer(&arena, &channel, &request), EXTERIA_E_ARG);
    channel.access_hash = 88;

    CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "hello", NULL, 0, 42, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_sendMessage);
    CHECK_EQ_INT(exteria_send_text_reply_request(&arena, &user, "hello", NULL, 0, 42, 77, &request), EXTERIA_OK);
    {
        const exteria_tl_value *reply = exteria_tl_get(request, "reply_to");
        int32_t id = 0;
        CHECK_EQ_INT(exteria_tl_id(reply), EXTERIA_TL_ID_inputReplyToMessage);
        CHECK_EQ_INT(exteria_tl_get_i32(reply, "reply_to_msg_id", &id), EXTERIA_OK);
        CHECK_EQ_INT(id, 77);
        CHECK_EQ_INT(exteria_tl_has(reply, "top_msg_id"), 0);
    }
    {
        exteria_peer_ref topic = {3, 7, 88, 0, 12};
        CHECK_EQ_INT(exteria_send_text_reply_request(&arena, &topic, "hello", NULL, 0, 42, 77, &request), EXTERIA_OK);
        const exteria_tl_value *reply = exteria_tl_get(request, "reply_to");
        int32_t id = 0;
        CHECK_EQ_INT(exteria_tl_get_i32(reply, "top_msg_id", &id), EXTERIA_OK);
        CHECK_EQ_INT(id, 12);
        CHECK_EQ_INT(exteria_send_text_reply_request(&arena, &topic, "hello", NULL, 0, 42, 0, &request), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_get_i32(exteria_tl_get(request, "reply_to"), "reply_to_msg_id", &id), EXTERIA_OK);
        CHECK_EQ_INT(id, 12);
    }
    CHECK_EQ_INT(exteria_send_text_reply_request(&arena, &user, "hello", NULL, 0, 42, -1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "", NULL, 0, 42, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "x", NULL, 0, 0, &request), EXTERIA_E_ARG);
    {
        /* "a", a smiley of two UTF-16 units, "b": the emoji entity covers units 1 and 2 */
        exteria_send_entity custom[2];
        memset(custom, 0, sizeof(custom));
        custom[0].kind = EXTERIA_ENTITY_BOLD;
        custom[0].offset = 0;
        custom[0].length = 1;
        custom[1].kind = EXTERIA_ENTITY_CUSTOM_EMOJI;
        custom[1].offset = 1;
        custom[1].length = 2;
        custom[1].id = 5368324170671202286ll;
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "a\xF0\x9F\x98\x80" "b", custom, 2, 42, &request), EXTERIA_OK);
        check_encodes(request, EXTERIA_TL_ID_messages_sendMessage);
        CHECK(exteria_tl_has(request, "entities"));
        CHECK_EQ_INT(exteria_tl_get(request, "entities")->u.vec.count, 2);
        /* the kinds the server finds in the text itself are not sent, so the field is absent */
        custom[0].kind = EXTERIA_ENTITY_URL;
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "ab", custom, 1, 42, &request), EXTERIA_OK);
        CHECK(!exteria_tl_has(request, "entities"));
        custom[0].kind = EXTERIA_ENTITY_BOLD;
        custom[1].offset = 3;
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "a\xF0\x9F\x98\x80" "b", custom, 2, 42, &request), EXTERIA_E_ARG);
        custom[1].offset = 2;
        custom[1].length = 3;
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "a\xF0\x9F\x98\x80" "b", custom, 2, 42, &request), EXTERIA_E_ARG);
        custom[1].offset = 1;
        custom[1].length = 2;
        custom[1].id = 0;
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "a\xF0\x9F\x98\x80" "b", custom, 2, 42, &request), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "ab", NULL, 1, 42, &request), EXTERIA_E_ARG);
        /* a range of nothing, or one that starts before the text, is refused whatever its kind */
        custom[0].length = 0;
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "ab", custom, 1, 42, &request), EXTERIA_E_ARG);
        custom[0].length = 1;
        custom[0].offset = -1;
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "ab", custom, 1, 42, &request), EXTERIA_E_ARG);
    }
    {
        /* every kind a person can pick in the field, over "bold quote link name when" */
        exteria_send_entity fmt[12];
        const exteria_tl_value *list;
        memset(fmt, 0, sizeof(fmt));
        fmt[0].kind = EXTERIA_ENTITY_ITALIC;
        fmt[1].kind = EXTERIA_ENTITY_UNDERLINE;
        fmt[2].kind = EXTERIA_ENTITY_STRIKE;
        fmt[3].kind = EXTERIA_ENTITY_CODE;
        fmt[4].kind = EXTERIA_ENTITY_SPOILER;
        fmt[5].kind = EXTERIA_ENTITY_PRE;
        fmt[5].text = "c";
        fmt[6].kind = EXTERIA_ENTITY_BLOCKQUOTE;
        fmt[6].flags = EXTERIA_ENTITY_COLLAPSED;
        fmt[7].kind = EXTERIA_ENTITY_TEXT_URL;
        fmt[7].text = "https://example.org/";
        fmt[8].kind = EXTERIA_ENTITY_MENTION_NAME;
        fmt[8].id = 77;
        fmt[8].access_hash = 99;
        fmt[9].kind = EXTERIA_ENTITY_FORMATTED_DATE;
        fmt[9].date = 1700000000;
        fmt[9].flags = EXTERIA_DATE_SHORT_DATE | EXTERIA_DATE_SHORT_TIME;
        fmt[10].kind = EXTERIA_ENTITY_PRE;
        fmt[11].kind = EXTERIA_ENTITY_BOLD;
        for (int k = 0; k < 12; ++k) {
            fmt[k].offset = k % 3;
            fmt[k].length = 4;
        }
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "bold quote link name when", fmt, 12, 42, &request), EXTERIA_OK);
        check_encodes(request, EXTERIA_TL_ID_messages_sendMessage);
        list = exteria_tl_get(request, "entities");
        CHECK(list != NULL);
        CHECK_EQ_INT(list->u.vec.count, 12);
        CHECK(exteria_tl_is(list->u.vec.items[4], EXTERIA_TL_ID_messageEntitySpoiler));
        CHECK(exteria_tl_is(list->u.vec.items[5], EXTERIA_TL_ID_messageEntityPre));
        CHECK(exteria_tl_has(list->u.vec.items[6], "collapsed"));
        CHECK(exteria_tl_is(list->u.vec.items[8], EXTERIA_TL_ID_inputMessageEntityMentionName));
        CHECK(exteria_tl_has(list->u.vec.items[9], "short_date") && exteria_tl_has(list->u.vec.items[9], "short_time"));
        CHECK(!exteria_tl_has(list->u.vec.items[9], "relative"));
        /* a block of code with no language still goes out, with an empty one */
        CHECK(exteria_tl_is(list->u.vec.items[10], EXTERIA_TL_ID_messageEntityPre));
        /* a link without an address, a name without its hash and a date without a moment are refused: the server would drop the whole message */
        fmt[7].text = "";
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "bold quote link name when", fmt, 12, 42, &request), EXTERIA_E_ARG);
        fmt[7].text = "https://example.org/";
        fmt[8].access_hash = 0;
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "bold quote link name when", fmt, 12, 42, &request), EXTERIA_E_ARG);
        fmt[8].access_hash = 99;
        fmt[9].date = 0;
        CHECK_EQ_INT(exteria_send_text_request(&arena, &user, "bold quote link name when", fmt, 12, 42, &request), EXTERIA_E_ARG);
    }

    sticker.source = EXTERIA_MEDIA_SOURCE_DOCUMENT;
    sticker.id = 5;
    sticker.access_hash = 6;
    sticker.dc = 2;
    sticker.ref_len = 2;
    sticker.file_ref[0] = 9;
    CHECK_EQ_INT(exteria_send_sticker_request(&arena, &chat, &sticker, 43, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_sendMedia);
    check_media_reply(request, &chat);
    strcpy(sticker.thumb, "m");
    CHECK_EQ_INT(exteria_send_sticker_request(&arena, &chat, &sticker, 43, &request), EXTERIA_E_ARG);
    sticker.thumb[0] = 0;
    sticker.source = EXTERIA_MEDIA_SOURCE_PHOTO;
    CHECK_EQ_INT(exteria_send_sticker_request(&arena, &chat, &sticker, 43, &request), EXTERIA_E_ARG);

    {
        exteria_tl_value *file = exteria_tl_new_obj(&arena, "inputFile");
        uint8_t wave[EXTERIA_WAVEFORM_BYTES] = {1, 2, 3};
        const exteria_tl_value *media, *attributes;
        CHECK(file != NULL);
        CHECK_EQ_INT(exteria_tl_set_i64(&arena, file, "id", 77), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(&arena, file, "parts", 2), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_str(&arena, file, "name", "voice.ogg"), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_str(&arena, file, "md5_checksum", ""), EXTERIA_OK);
        exteria_upload_spec spec;
        memset(&spec, 0, sizeof(spec));
        spec.kind = EXTERIA_UPLOAD_VOICE;
        spec.duration_ms = 2600;
        spec.waveform = wave;
        spec.waveform_len = sizeof(wave);
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 51, &request), EXTERIA_OK);
        check_encodes(request, EXTERIA_TL_ID_messages_sendMedia);
        check_media_reply(request, &chat);
        media = exteria_tl_get(request, "media");
        attributes = exteria_tl_get(media, "attributes");
        CHECK_EQ_INT(exteria_tl_id(media), EXTERIA_TL_ID_inputMediaUploadedDocument);
        CHECK(attributes && attributes->u.vec.count == 1);
        CHECK(exteria_tl_has(attributes->u.vec.items[0], "voice"));
        {
            int32_t seconds = 0;
            CHECK_EQ_INT(exteria_tl_get_i32(attributes->u.vec.items[0], "duration", &seconds), EXTERIA_OK);
            CHECK_EQ_INT(seconds, 3);
        }
        spec.waveform_len = sizeof(wave) - 1;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 51, &request), EXTERIA_E_ARG);
        spec.waveform = NULL;
        spec.waveform_len = 0;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 51, &request), EXTERIA_E_ARG);
        spec.waveform = wave;
        spec.waveform_len = sizeof(wave);
        spec.duration_ms = 0;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 51, &request), EXTERIA_E_ARG);

        memset(&spec, 0, sizeof(spec));
        spec.kind = EXTERIA_UPLOAD_ROUND;
        spec.duration_ms = 4000;
        spec.width = 384;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 52, &request), EXTERIA_OK);
        check_encodes(request, EXTERIA_TL_ID_messages_sendMedia);
        check_media_reply(request, &chat);
        attributes = exteria_tl_get(exteria_tl_get(request, "media"), "attributes");
        CHECK(exteria_tl_has(attributes->u.vec.items[0], "round_message"));
        spec.width = 0;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 52, &request), EXTERIA_E_ARG);
        spec.width = 384;
        spec.waveform = wave;
        spec.waveform_len = sizeof(wave);
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 52, &request), EXTERIA_E_ARG);

        memset(&spec, 0, sizeof(spec));
        spec.kind = EXTERIA_UPLOAD_VIDEO;
        spec.duration_ms = 9000;
        spec.width = 640;
        spec.height = 480;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 53, &request), EXTERIA_OK);
        attributes = exteria_tl_get(exteria_tl_get(request, "media"), "attributes");
        CHECK(exteria_tl_has(attributes->u.vec.items[0], "supports_streaming"));
        CHECK(!exteria_tl_has(attributes->u.vec.items[0], "round_message"));
        spec.height = 0;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 53, &request), EXTERIA_E_ARG);

        memset(&spec, 0, sizeof(spec));
        spec.kind = EXTERIA_UPLOAD_FILE;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 54, &request), EXTERIA_E_ARG);
        strcpy(spec.name, "notes.txt");
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 54, &request), EXTERIA_E_ARG);
        strcpy(spec.mime, "text/plain");
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 54, &request), EXTERIA_OK);
        media = exteria_tl_get(request, "media");
        check_encodes(request, EXTERIA_TL_ID_messages_sendMedia);
        check_media_reply(request, &chat);
        CHECK(exteria_tl_has(media, "force_file"));
        CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(media, "attributes")->u.vec.items[0]), EXTERIA_TL_ID_documentAttributeFilename);
        /* a name that fills its buffer without an end would be read past it */
        memset(spec.name, 'a', sizeof(spec.name));
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 54, &request), EXTERIA_E_ARG);

        memset(&spec, 0, sizeof(spec));
        spec.kind = EXTERIA_UPLOAD_PHOTO;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 55, &request), EXTERIA_OK);
        check_encodes(request, EXTERIA_TL_ID_messages_sendMedia);
        check_media_reply(request, &chat);
        CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "media")), EXTERIA_TL_ID_inputMediaUploadedPhoto);
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, NULL, &spec, 55, &request), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 0, &request), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, NULL, 55, &request), EXTERIA_E_ARG);
        spec.kind = (exteria_upload_kind)9;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 55, &request), EXTERIA_E_ARG);
        spec.kind = (exteria_upload_kind)0;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &chat, file, &spec, 55, &request), EXTERIA_E_ARG);
    }

    CHECK_EQ_INT(exteria_send_geo_request(&arena, &chat, 55.75, 37.62, 56, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_sendMedia);
    check_media_reply(request, &chat);
    CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "media")), EXTERIA_TL_ID_inputMediaGeoPoint);
    CHECK_EQ_INT(exteria_send_geo_request(&arena, &chat, -90.0, 180.0, 56, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_send_geo_request(&arena, &chat, 90.1, 0, 56, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_send_geo_request(&arena, &chat, 0, -180.1, 56, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_send_geo_request(&arena, &chat, NAN, 0, 56, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_send_geo_request(&arena, &chat, 0, 0, 0, &request), EXTERIA_E_ARG);

    {
        const int64_t ids[2] = {11, 22};
        exteria_custom_emoji rows[4];
        exteria_tl_value *list = exteria_tl_new_vec(&arena, 3), *answer;
        size_t n = 0;
        CHECK_EQ_INT(exteria_custom_emoji_request(&arena, ids, 2, &request), EXTERIA_OK);
        check_encodes(request, EXTERIA_TL_ID_messages_getCustomEmojiDocuments);
        CHECK_EQ_INT(exteria_custom_emoji_request(&arena, ids, 0, &request), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_custom_emoji_request(&arena, ids, EXTERIA_CUSTOM_EMOJI_MAX + 1, &request), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_custom_emoji_request(&arena, NULL, 1, &request), EXTERIA_E_ARG);
        CHECK(list != NULL);
        for (int k = 0; k < 3; ++k) {
            exteria_tl_value *document = exteria_tl_new_obj(&arena, "document");
            exteria_tl_value *attributes = exteria_tl_new_vec(&arena, 1);
            exteria_tl_value *attribute = exteria_tl_new_obj(&arena, k == 1 ? "documentAttributeFilename" : "documentAttributeCustomEmoji");
            CHECK(document && attributes && attribute);
            CHECK_EQ_INT(exteria_tl_set_i64(&arena, document, "id", 100 + k), EXTERIA_OK);
            if (k == 1) CHECK_EQ_INT(exteria_tl_set_str(&arena, attribute, "file_name", "x"), EXTERIA_OK);
            else CHECK_EQ_INT(exteria_tl_set_str(&arena, attribute, "alt", k == 0 ? "\xF0\x9F\x98\x80" : ""), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_vec_set(attributes, 0, attribute), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set(document, "attributes", attributes), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_vec_set(list, (uint32_t)k, document), EXTERIA_OK);
        }
        answer = list;
        /* only the first document has the attribute with a text */
        CHECK_EQ_INT(exteria_custom_emoji_parse(answer, rows, 4, &n), EXTERIA_OK);
        CHECK_EQ_INT(n, 1);
        CHECK_EQ_INT(rows[0].id, 100);
        CHECK(!strcmp(rows[0].alt, "\xF0\x9F\x98\x80"));
        /* the files that draw it come with the row, and the format follows the mime type */
        CHECK_EQ_INT(rows[0].format, EXTERIA_STICKER_STATIC);
        {
            static const char *const mimes[3] = {"image/webp", "application/x-tgsticker", "video/webm"};
            for (int k = 0; k < 3; ++k) {
                exteria_tl_value *attribute = obj("documentAttributeCustomEmoji");
                exteria_tl_value *one = exteria_tl_new_vec(&arena, 1);
                set_str(attribute, "alt", "x");
                CHECK_EQ_INT(exteria_tl_vec_set(one, 0, document(40 + k, mimes[k], &attribute, 1)), EXTERIA_OK);
                CHECK_EQ_INT(exteria_custom_emoji_parse(one, rows, 4, &n), EXTERIA_OK);
                CHECK_EQ_INT(n, 1);
                CHECK_EQ_INT(rows[0].format, k == 0 ? EXTERIA_STICKER_STATIC : k == 1 ? EXTERIA_STICKER_ANIMATED : EXTERIA_STICKER_VIDEO);
                CHECK_EQ_INT(rows[0].ref.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);
                CHECK_EQ_INT(rows[0].ref.id, 40 + k);
                CHECK_EQ_INT(rows[0].ref.dc, 2);
                CHECK_EQ_INT(rows[0].preview.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);
            }
        }
        CHECK_EQ_INT(exteria_custom_emoji_parse(answer, rows, 0, &n), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_custom_emoji_parse(exteria_tl_new_obj(&arena, "boolTrue"), rows, 4, &n), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(n, 0);
    }

    CHECK_EQ_INT(exteria_search_request(&arena, "duck", EXTERIA_SEARCH_ALL, 0, 20, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_searchGlobal);
    CHECK_EQ_INT(exteria_search_request(&arena, "duck", EXTERIA_SEARCH_POSTS, 7, 20, &request), EXTERIA_OK);
    CHECK(exteria_tl_has(request, "broadcasts_only"));
    check_encodes(request, EXTERIA_TL_ID_messages_searchGlobal);
    CHECK_EQ_INT(exteria_search_request(&arena, "duck", EXTERIA_SEARCH_VOICE, 0, 20, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "filter")), EXTERIA_TL_ID_inputMessagesFilterVoice);
    CHECK_EQ_INT(exteria_search_request(&arena, "", EXTERIA_SEARCH_MEDIA, 0, 20, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_search_request(&arena, "duck", (exteria_search_kind)99, 0, 20, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_search_request(&arena, "duck", EXTERIA_SEARCH_ALL, -1, 20, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_search_request(&arena, "duck", EXTERIA_SEARCH_ALL, 0, 0, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_read_history_request(&arena, &user, 10, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_readHistory);
    CHECK_EQ_INT(exteria_read_history_request(&arena, &channel, 10, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_channels_readHistory);
    CHECK_EQ_INT(exteria_read_history_request(&arena, &user, 0, &request), EXTERIA_E_ARG);

    sticker.source = EXTERIA_MEDIA_SOURCE_DOCUMENT;
    CHECK_EQ_INT(exteria_media_location(&arena, &sticker, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_inputDocumentFileLocation);
    sticker.source = EXTERIA_MEDIA_SOURCE_PHOTO;
    strcpy(sticker.thumb, "x");
    CHECK_EQ_INT(exteria_media_location(&arena, &sticker, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_inputPhotoFileLocation);
    sticker.source = EXTERIA_MEDIA_SOURCE_NONE;
    CHECK_EQ_INT(exteria_media_location(&arena, &sticker, &request), EXTERIA_E_ARG);

    set.id = 3;
    set.access_hash = 4;
    CHECK_EQ_INT(exteria_sticker_set_thumb_location(&arena, &set, &request), EXTERIA_E_ARG);
    set.thumb_dc = 2;
    set.thumb_version = 1;
    CHECK_EQ_INT(exteria_sticker_set_thumb_location(&arena, &set, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_inputStickerSetThumb);
    CHECK_EQ_INT(exteria_sticker_set_request(&arena, &set, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getStickerSet);
}

static exteria_tl_value *emoji_pack(const char *emoticon, int64_t id) {
    exteria_tl_value *pack = obj("stickerPack");
    set_str(pack, "emoticon", emoticon);
    CHECK_EQ_INT(exteria_tl_set_i64_vec(&arena, pack, "documents", &id, 1), EXTERIA_OK);
    return pack;
}

static void test_animated_emoji(void) {
    exteria_tl_value *request = NULL;
    CHECK_EQ_INT(exteria_animated_emoji_request(&arena, &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getStickerSet);
    CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "stickerset")), EXTERIA_TL_ID_inputStickerSetAnimatedEmoji);
    int32_t hash = -1;
    CHECK_EQ_INT(exteria_tl_get_i32(request, "hash", &hash), EXTERIA_OK);
    CHECK_EQ_INT(hash, 0);
    CHECK_EQ_INT(exteria_animated_emoji_request(NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_set_by_name_request(&arena, "tg_placeholders_android", &request), EXTERIA_OK);
    check_encodes(request, EXTERIA_TL_ID_messages_getStickerSet);
    CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "stickerset")), EXTERIA_TL_ID_inputStickerSetShortName);
    CHECK_EQ_INT(exteria_sticker_set_by_name_request(&arena, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_sticker_set_by_name_request(&arena, "no spaces", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_set_by_name_request(&arena, "a/b", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_set_by_name_request(&arena, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_set_by_name_request(NULL, "x", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_animated_emoji_request(&arena, NULL), EXTERIA_E_ARG);

    exteria_tl_value *attributes[1] = {sticker_attribute("different document alt")};
    exteria_tl_value *docs[4];
    docs[0] = document(601, "application/x-tgsticker", attributes, 1);
    docs[1] = document(602, "image/webp", attributes, 1);
    docs[2] = document(603, "application/x-tgsticker", attributes, 1);
    docs[3] = document(604, "application/x-tgsticker", attributes, 1);
    set_i64(docs[2], "size", EXTERIA_ANIMATED_EMOJI_BYTES_MAX + 1);
    set_i64(docs[3], "size", EXTERIA_ANIMATED_EMOJI_BYTES_MAX);
    exteria_tl_value *packs[6] = {
        emoji_pack("\xf0\x9f\x98\x80", 601), emoji_pack("static", 602),
        emoji_pack("too big", 603), emoji_pack("missing", 605),
        emoji_pack("\xe2\x9d\xa4", 604), emoji_pack("", 601)
    };
    exteria_tl_value *answer = obj("messages.stickerSet");
    set(answer, "set", sticker_set(1, "AnimatedEmojies", 0));
    set(answer, "documents", vec_of(docs, 4));
    set(answer, "packs", vec_of(packs, 6));
    exteria_sticker_row rows[4];
    size_t count = 99;
    CHECK_EQ_INT(exteria_animated_emoji_parse(answer, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].media.ref.id, 601);
    CHECK(!strcmp(rows[0].media.alt, "\xf0\x9f\x98\x80"));
    CHECK_EQ_INT(rows[1].media.ref.id, 604);
    CHECK(!strcmp(rows[1].media.alt, "\xe2\x9d\xa4"));
    CHECK_EQ_INT(exteria_animated_emoji_parse(answer, rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    set(answer, "packs", vec_of(NULL, 0));
    CHECK_EQ_INT(exteria_animated_emoji_parse(answer, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    set(answer, "packs", exteria_tl_new_vec(&arena, EXTERIA_ANIMATED_EMOJI_MAX + 1));
    CHECK_EQ_INT(exteria_animated_emoji_parse(answer, rows, 4, &count), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_animated_emoji_parse(obj("messages.stickerSet"), rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_animated_emoji_parse(obj("messages.stickerSetNotModified"), rows, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_animated_emoji_parse(NULL, rows, 4, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_animated_emoji_parse(answer, rows, 0, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(count, 0);
}

static void test_sender_rank(void) {
    exteria_tl_value *m = message(12, "group message");
    exteria_message_row row;
    CHECK_EQ_INT(exteria_message_read(m, &row), EXTERIA_OK);
    CHECK(!row.from_rank[0]);
    set_str(m, "from_rank", "custom\nadmin");
    CHECK_EQ_INT(exteria_message_read(m, &row), EXTERIA_OK);
    CHECK(!strcmp(row.from_rank, "custom admin"));
    char rank[300];
    memset(rank, 'x', sizeof(rank) - 1);
    rank[sizeof(rank) - 1] = 0;
    set_str(m, "from_rank", rank);
    CHECK_EQ_INT(exteria_message_read(m, &row), EXTERIA_OK);
    CHECK_EQ_INT(strlen(row.from_rank), sizeof(row.from_rank) - 1);
}

static void test_service_summary(void) {
    char text[64];
    int32_t value = -1;
    int64_t target = -1;
    exteria_tl_value *action = obj("messageActionContactSignUp");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_CONTACT_JOINED + 1);
    CHECK_EQ_INT(value, 0);
    CHECK_EQ_INT(target, 0);
    CHECK(!text[0]);
    action = obj("messageActionCustomAction");
    set_str(action, "message", "Welcome back");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_CUSTOM + 1);
    CHECK(!strcmp(text, "Welcome back"));
    action = obj("messageActionGroupCall");
    set_i32(action, "duration", 125);
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_VIDEO_CHAT + 1);
    CHECK_EQ_INT(value, 125);
    action = obj("messageActionSetMessagesTTL");
    set_i32(action, "period", 86400);
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_TTL + 1);
    CHECK_EQ_INT(value, 86400);
    action = obj("messageActionTopicCreate");
    set_str(action, "title", "Rules");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_TOPIC_CREATE + 1);
    CHECK(!strcmp(text, "Rules"));
    /* a text longer than the room is cut, not overrun */
    set_str(action, "title", "a title that does not fit into the small buffer given to the call, which is only sixty-four bytes");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_TOPIC_CREATE + 1);
    CHECK(strlen(text) < sizeof(text));
    action = obj("messageActionPaymentSent");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_PAYMENT + 1);
    action = obj("messageActionEmpty");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_OTHER + 1);
    CHECK(!strcmp(text, "Empty"));
    action = obj("messageActionSuggestBirthday");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_OTHER + 1);
    CHECK(!strcmp(text, "Suggest birthday"));
    CHECK_EQ_INT(exteria_service_summary(action, text, 8, &value, &target), EXTERIA_SERVICE_OTHER + 1);
    CHECK(strlen(text) < 8);
    CHECK_EQ_INT(exteria_service_summary(NULL, text, sizeof(text), &value, &target), EXTERIA_SERVICE_OTHER + 1);
}

/* a forwarded message names who wrote it: a user by id, a channel by the negative of its id, and nobody when the header hides it */
static void test_forward_origin(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(50, "passed on"), *header = obj("messageFwdHeader"), *channel = obj("peerChannel");
    CHECK(row != NULL);
    set(header, "from_id", peer_user(77));
    set(m, "fwd_from", header);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->forwarded, 1);
    CHECK_EQ_INT(row->forward_from, 77);
    m = message(51, "from a channel");
    header = obj("messageFwdHeader");
    set_i64(channel, "channel_id", 900);
    set(header, "from_id", channel);
    set(m, "fwd_from", header);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->forward_from, -900);
    m = message(52, "hidden origin");
    header = obj("messageFwdHeader");
    set_str(header, "from_name", "Hidden Person");
    set(m, "fwd_from", header);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->forward_from, 0);
    CHECK(!strcmp(row->forward_name, "Hidden Person"));
    free(row);
}

/* a call service message keeps how it ended, whether it had video and how long it lasted */
static void test_call_message(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = obj("messageService"), *action = obj("messageActionPhoneCall");
    CHECK(row != NULL);
    set_i32(m, "id", 60);
    set(m, "peer_id", peer_user(5));
    set_i32(m, "date", 9);
    set(m, "from_id", peer_user(8));
    set_i32(action, "duration", 20);
    set(action, "reason", obj("phoneCallDiscardReasonBusy"));
    set_flag(action, "video");
    set(m, "action", action);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->service, EXTERIA_SERVICE_CALL + 1);
    CHECK_EQ_INT(row->service_value, 20);
    CHECK_EQ_INT(row->call_reason, EXTERIA_OUTCOME_BUSY);
    CHECK_EQ_INT(row->call_video, 1);
    /* a call that was talked through has no reason, and one without video says so */
    m = obj("messageService");
    action = obj("messageActionPhoneCall");
    set_i32(m, "id", 61);
    set(m, "peer_id", peer_user(5));
    set_i32(m, "date", 9);
    set_i32(action, "duration", 3);
    set(m, "action", action);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->call_reason, EXTERIA_OUTCOME_ENDED);
    CHECK_EQ_INT(row->call_video, 0);
    CHECK_EQ_INT(row->service_value, 3);
    free(row);
}

static void test_more_service_kinds(void) {
    char text[64];
    int32_t value = -1;
    int64_t target = -1;
    exteria_tl_value *action = obj("messageActionGiftPremium");
    set_i32(action, "days", 180);
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_PREMIUM_GIFT + 1);
    CHECK_EQ_INT(value, 6);
    action = obj("messageActionGameScore");
    set_i32(action, "score", 1200);
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_GAME_SCORE + 1);
    CHECK_EQ_INT(value, 1200);
    action = obj("messageActionGiveawayResults");
    set_i32(action, "winners_count", 3);
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_GIVEAWAY_RESULTS + 1);
    CHECK_EQ_INT(value, 3);
    action = obj("messageActionSetChatTheme");
    {
        exteria_tl_value *theme = obj("chatTheme");
        set_str(theme, "emoticon", "\xF0\x9F\x8E\x84");
        set(action, "theme", theme);
    }
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_THEME + 1);
    CHECK(!strcmp(text, "\xF0\x9F\x8E\x84"));
    action = obj("messageActionSetChatWallPaper");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_WALLPAPER + 1);
    action = obj("messageActionSuggestProfilePhoto");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_PHOTO_SUGGESTED + 1);
    action = obj("messageActionPaymentRefunded");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_PAYMENT_REFUNDED + 1);
    action = obj("messageActionGiveawayLaunch");
    CHECK_EQ_INT(exteria_service_summary(action, text, sizeof(text), &value, &target), EXTERIA_SERVICE_GIVEAWAY + 1);
}

static void test_reply_boundaries(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = message(101, "answer");
    exteria_tl_value *reply = obj("messageReplyHeader");
    char quote[1100];
    CHECK(row != NULL);
    set_i32(reply, "reply_to_msg_id", 5);
    set(m, "reply_to", reply);
    memset(quote, 'a', sizeof(quote));
    quote[1022] = (char)0xd0;
    quote[1023] = (char)0xb0;
    quote[sizeof(quote) - 1] = 0;
    set_str(reply, "quote_text", quote);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(strlen(row->reply_quote), 1022);
    set(reply, "reply_to_peer_id", obj("peerUser"));
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(row->id, 0);
    CHECK_EQ_INT(row->reply_to, 0);
    free(row);
}

static void test_uploaded_media_reply(void) {
    exteria_tl_value *file = obj("inputFile"), *request = NULL;
    set_i64(file, "id", 42);
    set_i32(file, "parts", 1);
    set_str(file, "name", "photo.jpg");
    set_str(file, "md5_checksum", "");
    exteria_upload_spec spec;
    memset(&spec, 0, sizeof(spec));
    spec.kind = EXTERIA_UPLOAD_PHOTO;
    exteria_peer_ref peer = {1, 7, 99, 0, 0};
    for (int topic = 0; topic < 2; ++topic) {
        peer.topic_id = topic ? 18 : 0;
        spec.reply_to = 77;
        CHECK_EQ_INT(exteria_send_upload_request(&arena, &peer, file, &spec, 42, &request), EXTERIA_OK);
        const exteria_tl_value *reply = exteria_tl_get(request, "reply_to");
        int32_t id = 0;
        CHECK_EQ_INT(exteria_tl_get_i32(reply, "reply_to_msg_id", &id), EXTERIA_OK);
        CHECK_EQ_INT(id, 77);
        if (topic) {
            CHECK_EQ_INT(exteria_tl_get_i32(reply, "top_msg_id", &id), EXTERIA_OK);
            CHECK_EQ_INT(id, 18);
        } else CHECK(!exteria_tl_has(reply, "top_msg_id"));
        check_encodes(request, EXTERIA_TL_ID_messages_sendMedia);
    }
    spec.reply_to = -1;
    CHECK_EQ_INT(exteria_send_upload_request(&arena, &peer, file, &spec, 42, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

int main(void) {
    exteria_arena_init(&arena, 1u << 20);
    test_text_message();
    test_edit_hide();
    test_gif_preview();
    test_reply_boundaries();
    test_uploaded_media_reply();
    test_custom_emoji_entity();
    test_sticker_set_reference();
    test_formatting_entities();
    test_bot_message();
    test_invoice_message();
    test_text_limits();
    test_url_pool_overflow();
    test_sticker();
    test_media_kinds();
    test_video_variants();
    test_reference_limit();
    test_service();
    test_empty_and_malformed();
    test_sent_as_channel();
    test_post_counters();
    test_pinned_request();
    test_greeting_stickers();
    test_answers();
    test_sticker_sets();
    test_animated_emoji();
    test_emoji_sets();
    test_sent_parse();
    test_requests();
    test_topic_of_message();
    test_topic_requests();
    test_saved_history();
    test_sender_rank();
    test_service_summary();
    test_forward_origin();
    test_call_message();
    test_more_service_kinds();
    exteria_arena_free(&arena);
    if (g_failures) {
        fprintf(stderr, "test_messages: %d of %d checks failed\n", g_failures, g_checks);
        return 1;
    }
    printf("test_messages: %d checks passed\n", g_checks);
    return 0;
}
