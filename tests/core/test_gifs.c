#include "test_util.h"
#include "exteria_messages.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static exteria_tl_value *document(int64_t id, int animated, int sticker) {
    exteria_tl_value *doc = obj("document"), *attributes = exteria_tl_new_vec(&arena, 1), *attribute;
    const uint8_t ref[2] = {5, 6};
    CHECK(attributes != NULL);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, doc, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, doc, "access_hash", 99), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, doc, "file_reference", ref, 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, doc, "dc_id", 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, doc, "mime_type", "video/mp4"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, doc, "size", 1000), EXTERIA_OK);
    attribute = obj(sticker ? "documentAttributeSticker" : (animated ? "documentAttributeAnimated" : "documentAttributeFilename"));
    if (sticker) CHECK_EQ_INT(exteria_tl_set_str(&arena, attribute, "alt", "x"), EXTERIA_OK);
    if (!animated && !sticker) CHECK_EQ_INT(exteria_tl_set_str(&arena, attribute, "file_name", "a.mp4"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(attributes, 0, attribute), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(doc, "attributes", attributes), EXTERIA_OK);
    return doc;
}

static void test_saved_gifs(void) {
    exteria_sticker_row rows[4];
    size_t count;
    exteria_tl_value *answer_value = obj("messages.savedGifs"), *list = exteria_tl_new_vec(&arena, 3), *request = NULL;
    CHECK_EQ_INT(exteria_saved_gifs_request(&arena, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getSavedGifs);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, document(10, 1, 0)), EXTERIA_OK);
    /* a video that is no animation and a sticker are not gifs */
    CHECK_EQ_INT(exteria_tl_vec_set(list, 1, document(11, 0, 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 2, document(12, 1, 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer_value, "gifs", list), EXTERIA_OK);
    CHECK_EQ_INT(exteria_saved_gifs_parse(answer_value, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].media.kind, EXTERIA_PREVIEW_GIF);
    CHECK_EQ_INT(rows[0].media.ref.id, 10);
    CHECK_EQ_INT(rows[1].media.ref.id, 12);
    CHECK_EQ_INT(exteria_saved_gifs_parse(answer_value, rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_saved_gifs_parse(obj("messages.savedGifsNotModified"), rows, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_saved_gifs_parse(NULL, rows, 4, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_gifs_parse(answer_value, rows, 0, &count), EXTERIA_E_ARG);
}

static void test_animation_without_thumbnail(void) {
    exteria_media_info media;
    exteria_tl_value *doc = document(50, 1, 0);
    exteria_tl_value *attributes = exteria_tl_new_vec(&arena, 2), *video = obj("documentAttributeVideo");
    CHECK(attributes != NULL);
    CHECK_EQ_INT(exteria_tl_set_f64(&arena, video, "duration", 1.0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, video, "w", 320), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, video, "h", 240), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(attributes, 0, video), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(attributes, 1, obj("documentAttributeAnimated")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(doc, "attributes", attributes), EXTERIA_OK);
    exteria_document_read(doc, &media);
    CHECK_EQ_INT(media.kind, EXTERIA_PREVIEW_GIF);
    CHECK_EQ_INT(media.duration, 1);
    CHECK_EQ_INT(media.width, 320);
    CHECK_EQ_INT(media.height, 240);
    CHECK_EQ_INT(media.ref.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);
    CHECK_EQ_INT(media.ref.id, 50);
    CHECK_EQ_INT(media.preview.source, EXTERIA_MEDIA_SOURCE_NONE);
    CHECK(exteria_media_uses_picture(media.kind, media.ref.source != EXTERIA_MEDIA_SOURCE_NONE,
                                    media.preview.source != EXTERIA_MEDIA_SOURCE_NONE, 0));
    /* the same download and playback path also needs room when dimensions are absent */
    doc = document(51, 1, 0);
    exteria_document_read(doc, &media);
    CHECK_EQ_INT(media.width, 0);
    CHECK_EQ_INT(media.height, 0);
    CHECK(exteria_media_uses_picture(media.kind, media.ref.source != EXTERIA_MEDIA_SOURCE_NONE, 0, 0));
}

static void test_picture_sources(void) {
    static const struct {
        exteria_preview_kind kind;
        int file;
        int preview;
        int local;
        int picture;
    } cases[] = {
        {EXTERIA_PREVIEW_GIF, 1, 0, 0, 1},
        {EXTERIA_PREVIEW_GIF, 1, 1, 0, 1},
        {EXTERIA_PREVIEW_GIF, 0, 1, 0, 1},
        {EXTERIA_PREVIEW_GIF, 0, 0, 1, 1},
        {EXTERIA_PREVIEW_GIF, 0, 0, 0, 0},
        {EXTERIA_PREVIEW_VIDEO, 1, 0, 0, 1},
        {EXTERIA_PREVIEW_VIDEO, 0, 1, 0, 1},
        {EXTERIA_PREVIEW_VIDEO, 0, 0, 0, 0},
        {EXTERIA_PREVIEW_VIDEO_MESSAGE, 1, 0, 0, 1},
        {EXTERIA_PREVIEW_PHOTO, 1, 0, 0, 1},
        {EXTERIA_PREVIEW_PHOTO, 0, 0, 1, 1},
        {EXTERIA_PREVIEW_PHOTO, 0, 1, 0, 0},
        {EXTERIA_PREVIEW_FILE, 1, 1, 0, 0},
        {EXTERIA_PREVIEW_AUDIO, 1, 1, 0, 0},
        {EXTERIA_PREVIEW_VOICE, 1, 1, 0, 0},
        {EXTERIA_PREVIEW_STICKER, 1, 1, 0, 0},
        {EXTERIA_PREVIEW_NONE, 0, 0, 0, 0},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        CHECK_EQ_INT(exteria_media_uses_picture(cases[i].kind, cases[i].file, cases[i].preview, cases[i].local), cases[i].picture);
    }
}

static void test_viewer_kinds(void) {
    CHECK(exteria_media_opens_viewer(EXTERIA_PREVIEW_PHOTO));
    CHECK(exteria_media_opens_viewer(EXTERIA_PREVIEW_VIDEO));
    CHECK(!exteria_media_opens_viewer(EXTERIA_PREVIEW_GIF));
    CHECK(!exteria_media_opens_viewer(EXTERIA_PREVIEW_VIDEO_MESSAGE));
    CHECK(!exteria_media_opens_viewer(EXTERIA_PREVIEW_STICKER));
    CHECK(!exteria_media_opens_viewer(EXTERIA_PREVIEW_FILE));
    CHECK(!exteria_media_opens_viewer(EXTERIA_PREVIEW_AUDIO));
    CHECK(!exteria_media_opens_viewer(EXTERIA_PREVIEW_VOICE));
    CHECK(!exteria_media_opens_viewer(EXTERIA_PREVIEW_NONE));
    CHECK(!exteria_media_opens_viewer((exteria_preview_kind)-1));
}

static void test_faved(void) {
    exteria_sticker_row rows[4];
    size_t count;
    exteria_tl_value *answer_value = obj("messages.favedStickers"), *list = exteria_tl_new_vec(&arena, 2), *request = NULL;
    exteria_media_ref ref;
    exteria_writer wire;
    CHECK_EQ_INT(exteria_faved_stickers_request(&arena, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getFavedStickers);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, document(20, 0, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 1, document(21, 1, 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer_value, "stickers", list), EXTERIA_OK);
    CHECK_EQ_INT(exteria_faved_stickers_parse(answer_value, rows, 4, &count), EXTERIA_OK);
    /* only the sticker is read as one */
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].media.ref.id, 20);
    CHECK_EQ_INT(exteria_faved_stickers_parse(obj("messages.favedStickersNotModified"), rows, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_faved_stickers_parse(obj("boolTrue"), rows, 4, &count), EXTERIA_E_MALFORMED);
    ref = rows[0].media.ref;
    CHECK_EQ_INT(exteria_fave_sticker_request(&arena, &ref, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_faveSticker);
    CHECK(exteria_tl_is(exteria_tl_get(request, "unfave"), EXTERIA_TL_ID_boolFalse));
    exteria_writer_init(&wire, 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_fave_sticker_request(&arena, &ref, 1, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "unfave"), EXTERIA_TL_ID_boolTrue));
    /* a thumbnail of a sticker or a file with no source cannot be faved */
    ref.thumb[0] = 'm';
    CHECK_EQ_INT(exteria_fave_sticker_request(&arena, &ref, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    ref.thumb[0] = 0;
    ref.source = 0;
    CHECK_EQ_INT(exteria_fave_sticker_request(&arena, &ref, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_fave_sticker_request(&arena, NULL, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_clear_recent_stickers_request(&arena, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_clearRecentStickers);
    CHECK_EQ_INT(exteria_clear_recent_stickers_request(&arena, NULL), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_saved_gifs();
    test_animation_without_thumbnail();
    test_picture_sources();
    test_viewer_kinds();
    test_faved();
    exteria_arena_free(&arena);
    return test_finish("test_gifs");
}
