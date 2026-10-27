#include "test_util.h"
#include "exteria_content.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void test_requests(void) {
    exteria_tl_value *request = NULL;
    exteria_writer wire;
    CHECK_EQ_INT(exteria_content_settings_request(&arena, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_account_getContentSettings);
    exteria_writer_init(&wire, 64);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_content_set_request(&arena, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_account_setContentSettings);
    CHECK(exteria_tl_has(request, "sensitive_enabled"));
    exteria_writer_init(&wire, 64);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_content_set_request(&arena, 0, &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(request, "sensitive_enabled"));
    CHECK_EQ_INT(exteria_content_settings_request(NULL, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_content_settings_request(&arena, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_content_set_request(&arena, 1, NULL), EXTERIA_E_ARG);
}

static void test_parse(void) {
    exteria_content_settings out;
    exteria_tl_value *answer = obj("account.contentSettings");
    CHECK_EQ_INT(exteria_content_settings_parse(answer, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.sensitive_enabled, 0);
    CHECK_EQ_INT(out.sensitive_can_change, 0);
    CHECK_EQ_INT(exteria_tl_set_flag(answer, "sensitive_enabled"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_flag(answer, "sensitive_can_change"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_content_settings_parse(answer, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.sensitive_enabled, 1);
    CHECK_EQ_INT(out.sensitive_can_change, 1);
    /* a wrong answer leaves nothing behind, and a missing output is refused */
    CHECK_EQ_INT(exteria_content_settings_parse(obj("boolTrue"), &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(out.sensitive_enabled, 0);
    CHECK_EQ_INT(exteria_content_settings_parse(NULL, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_content_settings_parse(answer, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_content_set_parse(obj("boolTrue")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_content_set_parse(obj("boolFalse")), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_content_set_parse(obj("updates")), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_content_set_parse(NULL), EXTERIA_E_MALFORMED);
}

int main(void) {
    exteria_arena_init(&arena, 1024u * 1024u);
    test_requests();
    test_parse();
    exteria_arena_free(&arena);
    return test_finish("test_content");
}
