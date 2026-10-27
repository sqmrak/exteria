#include "test_util.h"
#include "exteria_translate.h"
#include "exteria_tl_ids.h"

#include <string.h>

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static exteria_tl_value *answer_of(const char *text) {
    exteria_tl_value *result = obj("messages.translateResult"), *item = obj("textWithEntities"), *vec = exteria_tl_new_vec(&arena, 1);
    CHECK(vec != NULL);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, item, "text", text), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(item, "entities", exteria_tl_new_vec(&arena, 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 0, item), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(result, "result", vec), EXTERIA_OK);
    return result;
}

static void test_request(void) {
    exteria_tl_value *request = NULL, *decoded = NULL;
    exteria_writer writer;
    char big[EXTERIA_TRANSLATE_TEXT_MAX + 2];
    CHECK_EQ_INT(exteria_translate_request(&arena, "hello", "ru", &request), EXTERIA_OK);
    exteria_writer_init(&writer, 4096);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, writer.data, writer.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), EXTERIA_TL_ID_messages_translateText);
    exteria_writer_free(&writer);
    CHECK_EQ_INT(exteria_translate_request(&arena, "x", "zh-CN", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_translate_request(&arena, "", "ru", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_translate_request(&arena, "x", "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_translate_request(&arena, "x", "ru;drop", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_translate_request(&arena, "x", "abcdefghijklmnop", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_translate_request(&arena, NULL, "ru", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_translate_request(&arena, "x", "ru", NULL), EXTERIA_E_ARG);
    memset(big, 'a', sizeof(big));
    big[EXTERIA_TRANSLATE_TEXT_MAX] = 0;
    CHECK_EQ_INT(exteria_translate_request(&arena, big, "ru", &request), EXTERIA_OK);
    big[EXTERIA_TRANSLATE_TEXT_MAX] = 'a';
    big[EXTERIA_TRANSLATE_TEXT_MAX + 1] = 0;
    CHECK_EQ_INT(exteria_translate_request(&arena, big, "ru", &request), EXTERIA_E_ARG);
}

static void test_parse(void) {
    char out[16];
    CHECK_EQ_INT(exteria_translate_parse(answer_of("Привет"), out, sizeof(out)), EXTERIA_OK);
    CHECK(!strcmp(out, "Привет"));
    /* cut at a character boundary, never inside one */
    CHECK_EQ_INT(exteria_translate_parse(answer_of("Привет"), out, 6), EXTERIA_OK);
    CHECK(!strcmp(out, "Пр"));
    CHECK_EQ_INT(exteria_translate_parse(obj("boolTrue"), out, sizeof(out)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(out[0], 0);
    {
        exteria_tl_value *empty = obj("messages.translateResult");
        CHECK_EQ_INT(exteria_tl_set(empty, "result", exteria_tl_new_vec(&arena, 0)), EXTERIA_OK);
        CHECK_EQ_INT(exteria_translate_parse(empty, out, sizeof(out)), EXTERIA_E_MALFORMED);
    }
    CHECK_EQ_INT(exteria_translate_parse(answer_of("x"), NULL, 4), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_translate_parse(answer_of("x"), out, 0), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_request();
    test_parse();
    exteria_arena_free(&arena);
    return test_finish("test_translate");
}
