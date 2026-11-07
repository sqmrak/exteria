#include "test_util.h"
#include "exteria_invite.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
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

static exteria_tl_value *invite(const char *link, const char *title) {
    exteria_tl_value *v = obj("chatInviteExported");
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, "link", link), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "admin_id", 7), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "date", 1700000000), EXTERIA_OK);
    if (title) CHECK_EQ_INT(exteria_tl_set_str(&arena, v, "title", title), EXTERIA_OK);
    return v;
}

static void test_list_request(void) {
    exteria_peer_ref channel = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0};
    exteria_tl_value *request = NULL;
    int32_t value = -1;
    CHECK_EQ_INT(exteria_invite_list_request(&arena, &channel, 0, 0, NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getExportedChatInvites);
    CHECK(exteria_tl_is(exteria_tl_get(request, "admin_id"), EXTERIA_TL_ID_inputUserSelf));
    CHECK_EQ_INT(exteria_tl_has(request, "revoked"), 0);
    CHECK_EQ_INT(exteria_tl_has(request, "offset_link"), 0);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "limit", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, EXTERIA_INVITES_PAGE);
    roundtrip(request, EXTERIA_TL_ID_messages_getExportedChatInvites);
    /* the next page names the date and the link of the last one */
    CHECK_EQ_INT(exteria_invite_list_request(&arena, &channel, 1, 1700000000, "https://t.me/+abc", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "revoked"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "offset_link"), 1);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "offset_date", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 1700000000);
    roundtrip(request, EXTERIA_TL_ID_messages_getExportedChatInvites);
    CHECK_EQ_INT(exteria_invite_list_request(&arena, &nohash, 0, 0, NULL, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_invite_list_request(&arena, NULL, 0, 0, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_invite_list_request(&arena, &channel, 0, -1, NULL, &request), EXTERIA_E_ARG);
}

static void test_list_parse(void) {
    exteria_tl_value *answer = obj("messages.exportedChatInvites"), *list = exteria_tl_new_vec(&arena, 3), *full = invite("https://t.me/+one", "Friends");
    exteria_invite rows[4];
    size_t count = 9;
    int32_t total = 0;
    CHECK_EQ_INT(exteria_tl_set_flag(full, "request_needed"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, full, "expire_date", 1800000000), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, full, "usage", 4), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, full), EXTERIA_OK);
    /* an entry that is no link is skipped, not an error */
    CHECK_EQ_INT(exteria_tl_vec_set(list, 1, obj("chatInvitePublicJoinRequests")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 2, invite("https://t.me/+two", NULL)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, answer, "count", 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "invites", list), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "users", exteria_tl_new_vec(&arena, 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_invite_list_parse(answer, rows, 4, &count, &total), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(total, 2);
    CHECK(strcmp(rows[0].link, "https://t.me/+one") == 0);
    CHECK(strcmp(rows[0].title, "Friends") == 0);
    CHECK_EQ_INT(rows[0].request_needed, 1);
    CHECK_EQ_INT(rows[0].expire_date, 1800000000);
    CHECK_EQ_INT(rows[0].usage, 4);
    CHECK_EQ_INT(rows[0].usage_limit, 0);
    CHECK_EQ_INT(rows[0].admin_id, 7);
    CHECK(strcmp(rows[1].link, "https://t.me/+two") == 0);
    CHECK_EQ_INT(rows[1].title[0], 0);
    /* more entries than the caller holds, and a wrong answer, leave nothing behind */
    CHECK_EQ_INT(exteria_invite_list_parse(answer, rows, 2, &count, &total), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_invite_list_parse(obj("boolTrue"), rows, 4, &count, &total), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_invite_list_parse(answer, NULL, 4, &count, &total), EXTERIA_E_ARG);
    /* a link with no address is malformed */
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, obj("chatInviteExported")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_invite_list_parse(answer, rows, 4, &count, &total), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
}

static void test_create_edit(void) {
    exteria_peer_ref channel = {3, 500, 7, 0, 0};
    exteria_invite_spec spec;
    exteria_tl_value *request = NULL;
    int32_t value = -1;
    memset(&spec, 0, sizeof(spec));
    CHECK_EQ_INT(exteria_invite_create_request(&arena, &channel, &spec, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_exportChatInvite);
    CHECK_EQ_INT(exteria_tl_has(request, "expire_date"), 0);
    CHECK_EQ_INT(exteria_tl_has(request, "usage_limit"), 0);
    CHECK_EQ_INT(exteria_tl_has(request, "title"), 0);
    CHECK_EQ_INT(exteria_tl_has(request, "request_needed"), 0);
    roundtrip(request, EXTERIA_TL_ID_messages_exportChatInvite);
    spec.expire_date = 1800000000;
    spec.usage_limit = 25;
    snprintf(spec.title, sizeof(spec.title), "%s", "Launch");
    CHECK_EQ_INT(exteria_invite_create_request(&arena, &channel, &spec, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "expire_date", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 1800000000);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "usage_limit", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 25);
    roundtrip(request, EXTERIA_TL_ID_messages_exportChatInvite);
    /* approval and a limit on joins exclude each other */
    spec.request_needed = 1;
    CHECK_EQ_INT(exteria_invite_create_request(&arena, &channel, &spec, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    spec.usage_limit = 0;
    CHECK_EQ_INT(exteria_invite_create_request(&arena, &channel, &spec, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "request_needed"), 1);
    spec.usage_limit = EXTERIA_INVITE_LIMIT_MAX + 1;
    spec.request_needed = 0;
    CHECK_EQ_INT(exteria_invite_create_request(&arena, &channel, &spec, &request), EXTERIA_E_ARG);
    spec.usage_limit = -1;
    CHECK_EQ_INT(exteria_invite_create_request(&arena, &channel, &spec, &request), EXTERIA_E_ARG);
    spec.usage_limit = 0;
    spec.expire_date = -5;
    CHECK_EQ_INT(exteria_invite_create_request(&arena, &channel, &spec, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_invite_create_request(&arena, &channel, NULL, &request), EXTERIA_E_ARG);
    /* an edit that drops both limits says so in zeros, or the server keeps the old ones */
    memset(&spec, 0, sizeof(spec));
    CHECK_EQ_INT(exteria_invite_edit_request(&arena, &channel, "https://t.me/+abc", &spec, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_editExportedChatInvite);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "expire_date", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 0);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "usage_limit", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 0);
    CHECK(exteria_tl_is(exteria_tl_get(request, "request_needed"), EXTERIA_TL_ID_boolFalse));
    CHECK_EQ_INT(exteria_tl_has(request, "revoked"), 0);
    roundtrip(request, EXTERIA_TL_ID_messages_editExportedChatInvite);
    spec.request_needed = 1;
    CHECK_EQ_INT(exteria_invite_edit_request(&arena, &channel, "https://t.me/+abc", &spec, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "request_needed"), EXTERIA_TL_ID_boolTrue));
    CHECK_EQ_INT(exteria_invite_edit_request(&arena, &channel, "", &spec, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_invite_edit_request(&arena, &channel, NULL, &spec, &request), EXTERIA_E_ARG);
}

static void test_revoke_delete(void) {
    exteria_peer_ref group = {2, 40, 0, 0, 0};
    exteria_tl_value *request = NULL;
    char long_link[EXTERIA_INVITE_LINK_MAX + 8];
    CHECK_EQ_INT(exteria_invite_revoke_request(&arena, &group, "https://t.me/+abc", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_editExportedChatInvite);
    CHECK_EQ_INT(exteria_tl_has(request, "revoked"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "expire_date"), 0);
    CHECK(exteria_tl_is(exteria_tl_get(request, "peer"), EXTERIA_TL_ID_inputPeerChat));
    roundtrip(request, EXTERIA_TL_ID_messages_editExportedChatInvite);
    CHECK_EQ_INT(exteria_invite_delete_request(&arena, &group, "https://t.me/+abc", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_deleteExportedChatInvite);
    roundtrip(request, EXTERIA_TL_ID_messages_deleteExportedChatInvite);
    CHECK_EQ_INT(exteria_invite_delete_revoked_request(&arena, &group, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_deleteRevokedExportedChatInvites);
    CHECK(exteria_tl_is(exteria_tl_get(request, "admin_id"), EXTERIA_TL_ID_inputUserSelf));
    roundtrip(request, EXTERIA_TL_ID_messages_deleteRevokedExportedChatInvites);
    memset(long_link, 'a', sizeof(long_link));
    long_link[sizeof(long_link) - 1] = 0;
    CHECK_EQ_INT(exteria_invite_delete_request(&arena, &group, long_link, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_invite_revoke_request(&arena, &group, NULL, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

static void test_answer(void) {
    exteria_invite one, two;
    int replaced = 5;
    exteria_tl_value *replaced_answer = obj("messages.exportedChatInviteReplaced"), *wrapped = obj("messages.exportedChatInvite");
    CHECK_EQ_INT(exteria_invite_answer_parse(invite("https://t.me/+a", "A"), &one, NULL, &replaced), EXTERIA_OK);
    CHECK_EQ_INT(replaced, 0);
    CHECK(strcmp(one.link, "https://t.me/+a") == 0);
    CHECK_EQ_INT(exteria_tl_set(wrapped, "invite", invite("https://t.me/+b", NULL)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_invite_answer_parse(wrapped, &one, NULL, &replaced), EXTERIA_OK);
    CHECK(strcmp(one.link, "https://t.me/+b") == 0);
    /* revoking the permanent link of a chat answers with the link that took its place */
    CHECK_EQ_INT(exteria_tl_set(replaced_answer, "invite", invite("https://t.me/+old", NULL)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(replaced_answer, "new_invite", invite("https://t.me/+new", NULL)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_invite_answer_parse(replaced_answer, &one, &two, &replaced), EXTERIA_OK);
    CHECK_EQ_INT(replaced, 1);
    CHECK(strcmp(one.link, "https://t.me/+old") == 0);
    CHECK(strcmp(two.link, "https://t.me/+new") == 0);
    CHECK_EQ_INT(exteria_invite_answer_parse(replaced_answer, &one, NULL, &replaced), EXTERIA_OK);
    CHECK_EQ_INT(exteria_invite_answer_parse(obj("boolTrue"), &one, NULL, &replaced), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_invite_answer_parse(NULL, &one, NULL, &replaced), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_list_request();
    test_list_parse();
    test_create_edit();
    test_revoke_delete();
    test_answer();
    exteria_arena_free(&arena);
    return test_finish("test_invite");
}
