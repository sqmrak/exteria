#include "test_util.h"
#include "exteria_report.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void wire_roundtrip(exteria_tl_value *request) {
    exteria_writer wire;
    exteria_tl_value *decoded = NULL;
    exteria_writer_init(&wire, 4096);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, wire.data, wire.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), EXTERIA_TL_ID_account_reportPeer);
    exteria_writer_free(&wire);
}

static void test_reasons(void) {
    static const uint32_t ids[EXTERIA_REPORT_REASON_COUNT] = {
        EXTERIA_TL_ID_inputReportReasonSpam, EXTERIA_TL_ID_inputReportReasonViolence, EXTERIA_TL_ID_inputReportReasonPornography,
        EXTERIA_TL_ID_inputReportReasonChildAbuse, EXTERIA_TL_ID_inputReportReasonCopyright, EXTERIA_TL_ID_inputReportReasonIllegalDrugs,
        EXTERIA_TL_ID_inputReportReasonPersonalDetails, EXTERIA_TL_ID_inputReportReasonOther,
    };
    exteria_peer_ref channel = {3, 500, 7, 0, 0};
    int reason;
    for (reason = 0; reason < EXTERIA_REPORT_REASON_COUNT; ++reason) {
        exteria_tl_value *request = NULL;
        const char *text = reason == EXTERIA_REPORT_OTHER ? "it sells fakes" : NULL;
        CHECK_EQ_INT(exteria_report_request(&arena, &channel, (exteria_report_reason)reason, text, &request), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_account_reportPeer);
        CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "reason")), ids[reason]);
        CHECK(exteria_tl_is(exteria_tl_get(request, "peer"), EXTERIA_TL_ID_inputPeerChannel));
        wire_roundtrip(request);
    }
}

static void test_peers(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref user = {1, 5, 9, 0, 0}, group = {2, 40, 0, 0, 0}, self = {1, 1, 0, 1, 0}, nohash = {3, 500, 0, 0, 0};
    CHECK_EQ_INT(exteria_report_request(&arena, &user, EXTERIA_REPORT_SPAM, "", &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "peer"), EXTERIA_TL_ID_inputPeerUser));
    CHECK_EQ_INT(exteria_report_request(&arena, &group, EXTERIA_REPORT_SPAM, "", &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "peer"), EXTERIA_TL_ID_inputPeerChat));
    CHECK_EQ_INT(exteria_report_request(&arena, &self, EXTERIA_REPORT_SPAM, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_report_request(&arena, &nohash, EXTERIA_REPORT_SPAM, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_report_request(&arena, NULL, EXTERIA_REPORT_SPAM, "", &request), EXTERIA_E_ARG);
}

static void test_message(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref user = {1, 5, 9, 0, 0};
    char longest[EXTERIA_REPORT_MESSAGE_MAX + 2];
    const uint8_t *data;
    size_t len;
    /* another reason carries the comment as it is, and an empty or missing one is the empty string */
    CHECK_EQ_INT(exteria_report_request(&arena, &user, EXTERIA_REPORT_VIOLENCE, "threats", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "message", &data, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 7);
    CHECK_MEM(data, "threats", 7);
    CHECK_EQ_INT(exteria_report_request(&arena, &user, EXTERIA_REPORT_VIOLENCE, NULL, &request), EXTERIA_OK);
    /* the server rejects "other" with nothing to read */
    CHECK_EQ_INT(exteria_report_request(&arena, &user, EXTERIA_REPORT_OTHER, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_report_request(&arena, &user, EXTERIA_REPORT_OTHER, NULL, &request), EXTERIA_E_ARG);
    memset(longest, 'a', sizeof(longest));
    longest[EXTERIA_REPORT_MESSAGE_MAX] = '\0';
    CHECK_EQ_INT(exteria_report_request(&arena, &user, EXTERIA_REPORT_OTHER, longest, &request), EXTERIA_OK);
    longest[EXTERIA_REPORT_MESSAGE_MAX] = 'a';
    longest[EXTERIA_REPORT_MESSAGE_MAX + 1] = '\0';
    CHECK_EQ_INT(exteria_report_request(&arena, &user, EXTERIA_REPORT_OTHER, longest, &request), EXTERIA_E_LIMIT);
    CHECK(request == NULL);
}

static void test_arguments(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref user = {1, 5, 9, 0, 0};
    CHECK_EQ_INT(exteria_report_request(&arena, &user, EXTERIA_REPORT_REASON_COUNT, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_report_request(&arena, &user, (exteria_report_reason)-1, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_report_request(NULL, &user, EXTERIA_REPORT_SPAM, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_report_request(&arena, &user, EXTERIA_REPORT_SPAM, "", NULL), EXTERIA_E_ARG);
}

static void test_parse(void) {
    CHECK_EQ_INT(exteria_report_parse(obj("boolTrue")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_report_parse(obj("boolFalse")), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_report_parse(obj("updates")), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_report_parse(NULL), EXTERIA_E_MALFORMED);
}

static void test_message_report(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref group = {2, 500, 0, 0, 0}, self = {1, 1, 0, 1, 0};
    int32_t ids[2] = {10, 11}, bad[2] = {10, 0};
    const uint8_t token[3] = {1, 2, 3};
    const uint8_t *data;
    size_t len;
    exteria_writer wire;
    exteria_tl_value *decoded = NULL;
    CHECK_EQ_INT(exteria_message_report_request(&arena, &group, ids, 2, NULL, 0, NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_report);
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "option", &data, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_message_report_request(&arena, &group, ids, 1, token, 3, "why", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "option", &data, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 3);
    CHECK_MEM(data, token, 3);
    exteria_writer_init(&wire, 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, wire.data, wire.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), EXTERIA_TL_ID_messages_report);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_message_report_request(&arena, &group, bad, 2, NULL, 0, NULL, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_message_report_request(&arena, &group, ids, 0, NULL, 0, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_message_report_request(&arena, &self, ids, 1, NULL, 0, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_message_report_request(&arena, &group, ids, 1, NULL, 3, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_message_report_request(&arena, &group, ids, 1, token, EXTERIA_REPORT_TOKEN_MAX + 1, NULL, &request), EXTERIA_E_LIMIT);
}

static void test_message_report_parse(void) {
    exteria_message_report_answer out;
    exteria_tl_value *choose = obj("reportResultChooseOption"), *list = exteria_tl_new_vec(&arena, 3), *a = obj("messageReportOption"), *b = obj("messageReportOption"),
                     *empty = obj("messageReportOption"), *comment = obj("reportResultAddComment");
    const uint8_t t1[2] = {7, 8}, t2[1] = {9};
    CHECK_EQ_INT(exteria_message_report_parse(obj("reportResultReported"), &out), EXTERIA_OK);
    CHECK_EQ_INT(out.step, EXTERIA_REPORT_STEP_DONE);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, a, "text", "Spam"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, a, "option", t1, 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, b, "text", "Violence"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, b, "option", t2, 1), EXTERIA_OK);
    /* an option without words cannot be shown, so it is left out */
    CHECK_EQ_INT(exteria_tl_set_str(&arena, empty, "text", ""), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, empty, "option", t2, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, a), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 1, empty), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 2, b), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, choose, "title", "What is wrong?"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(choose, "options", list), EXTERIA_OK);
    CHECK_EQ_INT(exteria_message_report_parse(choose, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.step, EXTERIA_REPORT_STEP_CHOOSE);
    CHECK_EQ_INT(out.option_count, 2);
    CHECK_MEM(out.title, "What is wrong?", 15);
    CHECK_MEM(out.options[1].text, "Violence", 9);
    CHECK_EQ_INT(out.options[0].token_len, 2);
    CHECK_MEM(out.options[0].token, t1, 2);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, comment, "option", t1, 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_flag(comment, "optional"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_message_report_parse(comment, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.step, EXTERIA_REPORT_STEP_COMMENT);
    CHECK_EQ_INT(out.comment_optional, 1);
    CHECK_EQ_INT(out.token_len, 2);
    /* a list with nothing usable, and anything else, is malformed and leaves the output cleared */
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, empty), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 2, empty), EXTERIA_OK);
    CHECK_EQ_INT(exteria_message_report_parse(choose, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(out.step, 0);
    CHECK_EQ_INT(exteria_message_report_parse(obj("boolTrue"), &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_message_report_parse(NULL, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_message_report_parse(choose, NULL), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_reasons();
    test_peers();
    test_message();
    test_arguments();
    test_parse();
    test_message_report();
    test_message_report_parse();
    exteria_arena_free(&arena);
    return test_finish("test_report");
}
