#include "exteria_sticker_make.h"
#include "test_util.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static exteria_input_document document(void) {
    exteria_input_document d;
    memset(&d, 0, sizeof(d));
    d.id = 77;
    d.access_hash = 88;
    d.file_reference[0] = 9;
    d.file_reference[1] = 8;
    d.file_reference_len = 2;
    return d;
}

static void roundtrip(exteria_tl_value *request, uint32_t id) {
    exteria_writer wire;
    exteria_tl_value *decoded = NULL;
    exteria_writer_init(&wire, 4096);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, wire.data, wire.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), id);
    exteria_writer_free(&wire);
}

static void test_validators(void) {
    CHECK(exteria_sticker_title_valid("My cats"));
    CHECK(exteria_sticker_title_valid("\xD0\x9A\xD0\xBE\xD1\x82\xD1\x8B"));
    CHECK(!exteria_sticker_title_valid(""));
    CHECK(!exteria_sticker_title_valid("   "));
    CHECK(!exteria_sticker_title_valid(NULL));
    CHECK(!exteria_sticker_title_valid("tab\there"));
    CHECK(!exteria_sticker_title_valid("bad \xC3"));
    {
        char longest[80];
        memset(longest, 'a', sizeof(longest));
        longest[EXTERIA_STICKER_TITLE_MAX] = 0;
        CHECK(exteria_sticker_title_valid(longest));
        longest[EXTERIA_STICKER_TITLE_MAX] = 'a';
        longest[EXTERIA_STICKER_TITLE_MAX + 1] = 0;
        CHECK(!exteria_sticker_title_valid(longest));
    }
    CHECK(exteria_sticker_short_name_valid("cats"));
    CHECK(exteria_sticker_short_name_valid("My_cats_2"));
    CHECK(!exteria_sticker_short_name_valid(""));
    CHECK(!exteria_sticker_short_name_valid("2cats"));
    CHECK(!exteria_sticker_short_name_valid("_cats"));
    CHECK(!exteria_sticker_short_name_valid("cats_"));
    CHECK(!exteria_sticker_short_name_valid("my__cats"));
    CHECK(!exteria_sticker_short_name_valid("my-cats"));
    CHECK(!exteria_sticker_short_name_valid("\xD0\xBA\xD0\xBE\xD1\x82"));
    CHECK(!exteria_sticker_short_name_valid(NULL));
    CHECK(exteria_sticker_emoji_valid("\xF0\x9F\x98\x80"));
    CHECK(exteria_sticker_emoji_valid("\xF0\x9F\x98\x80\xF0\x9F\x90\xB1"));
    CHECK(exteria_sticker_emoji_valid("\xE2\x9D\xA4\xEF\xB8\x8F"));
    CHECK(exteria_sticker_emoji_valid("1\xEF\xB8\x8F\xE2\x83\xA3"));
    CHECK(!exteria_sticker_emoji_valid(""));
    CHECK(!exteria_sticker_emoji_valid("a"));
    CHECK(!exteria_sticker_emoji_valid("\xF0\x9F\x98\x80 "));
    CHECK(!exteria_sticker_emoji_valid("1"));
    CHECK(!exteria_sticker_emoji_valid(NULL));
    CHECK(!exteria_sticker_emoji_valid("\xF0\x9F"));
}

static void test_upload(void) {
    exteria_tl_value *request = NULL, *file = obj("inputFile"), *answer_value, *doc;
    exteria_input_document out;
    const uint8_t ref[3] = {1, 2, 3};
    CHECK_EQ_INT(exteria_sticker_upload_request(&arena, file, "sticker.webp", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_uploadMedia);
    CHECK(exteria_tl_is(exteria_tl_get(request, "peer"), EXTERIA_TL_ID_inputPeerSelf));
    CHECK(exteria_tl_is(exteria_tl_get(request, "media"), EXTERIA_TL_ID_inputMediaUploadedDocument));
    CHECK_EQ_INT(exteria_sticker_upload_request(&arena, NULL, "x", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_sticker_upload_request(&arena, file, "", &request), EXTERIA_E_ARG);
    /* the answer */
    answer_value = obj("messageMediaDocument");
    doc = obj("document");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, doc, "id", 55), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, doc, "access_hash", 66), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, doc, "file_reference", ref, 3), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer_value, "document", doc), EXTERIA_OK);
    CHECK_EQ_INT(exteria_sticker_upload_parse(answer_value, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.id, 55);
    CHECK_EQ_INT(out.access_hash, 66);
    CHECK_EQ_INT(out.file_reference_len, 3);
    CHECK_MEM(out.file_reference, ref, 3);
    CHECK_EQ_INT(exteria_sticker_upload_parse(obj("boolTrue"), &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(out.id, 0);
    CHECK_EQ_INT(exteria_sticker_upload_parse(NULL, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_sticker_upload_parse(answer_value, NULL), EXTERIA_E_ARG);
    {
        uint8_t big[EXTERIA_STICKER_REF_MAX + 1];
        memset(big, 1, sizeof(big));
        CHECK_EQ_INT(exteria_tl_set_bytes(&arena, doc, "file_reference", big, sizeof(big)), EXTERIA_OK);
        CHECK_EQ_INT(exteria_sticker_upload_parse(answer_value, &out), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(out.file_reference_len, 0);
    }
}

static void test_requests(void) {
    exteria_tl_value *request = NULL;
    exteria_input_document d = document(), empty;
    memset(&empty, 0, sizeof(empty));
    CHECK_EQ_INT(exteria_sticker_create_request(&arena, "My cats", "my_cats", &d, "\xF0\x9F\x90\xB1", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_stickers_createStickerSet);
    CHECK(exteria_tl_is(exteria_tl_get(request, "user_id"), EXTERIA_TL_ID_inputUserSelf));
    roundtrip(request, EXTERIA_TL_ID_stickers_createStickerSet);
    CHECK_EQ_INT(exteria_sticker_create_request(&arena, "", "my_cats", &d, "\xF0\x9F\x90\xB1", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_sticker_create_request(&arena, "t", "bad name", &d, "\xF0\x9F\x90\xB1", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_create_request(&arena, "t", "name", &d, "x", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_create_request(&arena, "t", "name", &empty, "\xF0\x9F\x90\xB1", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_create_request(&arena, "t", "name", NULL, "\xF0\x9F\x90\xB1", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_add_request(&arena, "my_cats", &d, "\xF0\x9F\x90\xB1", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_stickers_addStickerToSet);
    CHECK(exteria_tl_is(exteria_tl_get(request, "stickerset"), EXTERIA_TL_ID_inputStickerSetShortName));
    roundtrip(request, EXTERIA_TL_ID_stickers_addStickerToSet);
    CHECK_EQ_INT(exteria_sticker_add_request(&arena, "2bad", &d, "\xF0\x9F\x90\xB1", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_check_request(&arena, "my_cats", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_stickers_checkShortName);
    CHECK_EQ_INT(exteria_sticker_check_request(&arena, "bad__name", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_check_parse(obj("boolTrue")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_sticker_check_parse(obj("boolFalse")), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_sticker_check_parse(obj("updates")), EXTERIA_E_MALFORMED);
}

static void test_set_name(void) {
    exteria_tl_value *answer_value = obj("messages.stickerSet"), *set = obj("stickerSet");
    char name[16];
    CHECK_EQ_INT(exteria_tl_set_str(&arena, set, "short_name", "my_cats"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer_value, "set", set), EXTERIA_OK);
    CHECK_EQ_INT(exteria_sticker_set_name_parse(answer_value, name, sizeof(name)), EXTERIA_OK);
    CHECK(strcmp(name, "my_cats") == 0);
    CHECK_EQ_INT(exteria_sticker_set_name_parse(answer_value, name, 5), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(name[0], 0);
    CHECK_EQ_INT(exteria_sticker_set_name_parse(obj("boolTrue"), name, sizeof(name)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_sticker_set_name_parse(answer_value, NULL, 8), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_validators();
    test_upload();
    test_requests();
    test_set_name();
    exteria_arena_free(&arena);
    return test_finish("test_sticker_make");
}
