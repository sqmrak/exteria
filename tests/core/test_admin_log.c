#include "test_util.h"
#include "exteria_admin_log.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set_i32(exteria_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, f, x), EXTERIA_OK); }
static void set_i64(exteria_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, f, x), EXTERIA_OK); }
static void set_str(exteria_tl_value *v, const char *f, const char *x) { CHECK_EQ_INT(exteria_tl_set_str(&arena, v, f, x), EXTERIA_OK); }
static void set_flag(exteria_tl_value *v, const char *f) { CHECK_EQ_INT(exteria_tl_set_flag(v, f), EXTERIA_OK); }
static void set(exteria_tl_value *v, const char *f, exteria_tl_value *x) { CHECK_EQ_INT(exteria_tl_set(v, f, x), EXTERIA_OK); }

static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *v = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(v, i, items[i]), EXTERIA_OK);
    return v;
}

static exteria_tl_value *user(int64_t id, const char *name, const char *username) {
    exteria_tl_value *u = obj("user");
    set_i64(u, "id", id);
    set_i64(u, "access_hash", id * 3);
    set_str(u, "first_name", name);
    if (username) set_str(u, "username", username);
    return u;
}

static exteria_tl_value *event(int64_t id, int32_t date, int64_t actor, exteria_tl_value *action) {
    exteria_tl_value *e = obj("channelAdminLogEvent");
    set_i64(e, "id", id);
    set_i32(e, "date", date);
    set_i64(e, "user_id", actor);
    set(e, "action", action);
    return e;
}

static exteria_tl_value *text_message(int32_t id, const char *text) {
    exteria_tl_value *m = obj("message");
    set_i32(m, "id", id);
    set_str(m, "message", text);
    return m;
}

static exteria_tl_value *banned(int64_t user_id, int view_messages) {
    exteria_tl_value *p = obj("channelParticipantBanned"), *peer = obj("peerUser"), *rights = obj("chatBannedRights");
    set_i64(peer, "user_id", user_id);
    set(p, "peer", peer);
    if (view_messages) set_flag(rights, "view_messages");
    else set_flag(rights, "send_messages");
    set(p, "banned_rights", rights);
    return p;
}

static exteria_tl_value *plain(int64_t user_id) {
    exteria_tl_value *p = obj("channelParticipant");
    set_i64(p, "user_id", user_id);
    return p;
}

static exteria_tl_value *admin(int64_t user_id, const char *rank) {
    exteria_tl_value *p = obj("channelParticipantAdmin");
    set_i64(p, "user_id", user_id);
    set(p, "admin_rights", obj("chatAdminRights"));
    if (rank) set_str(p, "rank", rank);
    return p;
}

static exteria_tl_value *answer(exteria_tl_value **events, uint32_t n) {
    exteria_tl_value *a = obj("channels.adminLogResults");
    exteria_tl_value *users[3];
    users[0] = user(1, "Ann", "ann");
    users[1] = user(2, "Bob", NULL);
    users[2] = user(3, "Cy", "cy");
    set(a, "events", vec_of(events, n));
    set(a, "chats", vec_of(NULL, 0));
    set(a, "users", vec_of(users, 3));
    return a;
}

static exteria_tl_value *action_new_value(const char *name, int on) {
    exteria_tl_value *a = obj(name);
    set(a, "new_value", obj(on ? "boolTrue" : "boolFalse"));
    return a;
}

static void test_request(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref ok = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0}, user_peer = {1, 500, 7, 0, 0};
    exteria_writer wire;
    int64_t max_id = -1;
    int32_t limit = 0;
    char long_query[EXTERIA_ADMIN_LOG_QUERY_MAX + 8];
    CHECK_EQ_INT(exteria_admin_log_request(&arena, &ok, "", 0, 50, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_getAdminLog);
    CHECK_EQ_INT(exteria_tl_get_i64(request, "max_id", &max_id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "limit", &limit), EXTERIA_OK);
    CHECK_EQ_INT(max_id, 0);
    CHECK_EQ_INT(limit, 50);
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_admin_log_request(&arena, &ok, "spam", 9000000000LL, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i64(request, "max_id", &max_id), EXTERIA_OK);
    CHECK_EQ_INT(max_id, 9000000000LL);
    /* a channel without a hash, a user, a negative id, no room and a query that is too long are refused before they reach the wire */
    CHECK_EQ_INT(exteria_admin_log_request(&arena, &nohash, NULL, 0, 50, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_admin_log_request(&arena, &user_peer, NULL, 0, 50, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_admin_log_request(&arena, &ok, NULL, -1, 50, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_admin_log_request(&arena, &ok, NULL, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_admin_log_request(&arena, &ok, NULL, 0, EXTERIA_ADMIN_LOG_PAGE + 1, &request), EXTERIA_E_ARG);
    memset(long_query, 'a', sizeof(long_query) - 1);
    long_query[sizeof(long_query) - 1] = 0;
    CHECK_EQ_INT(exteria_admin_log_request(&arena, &ok, long_query, 0, 50, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_admin_log_request(NULL, &ok, NULL, 0, 50, &request), EXTERIA_E_ARG);
}

static void test_people_and_text(void) {
    exteria_admin_event rows[16];
    exteria_tl_value *items[8], *action;
    size_t count = 99;
    action = obj("channelAdminLogEventActionChangeTitle");
    set_str(action, "prev_value", "Old");
    set_str(action, "new_value", "New");
    items[0] = event(900, 1000, 1, action);
    action = obj("channelAdminLogEventActionParticipantInvite");
    set(action, "participant", plain(2));
    items[1] = event(800, 990, 3, action);
    action = obj("channelAdminLogEventActionParticipantEditRank");
    set_i64(action, "user_id", 2);
    set_str(action, "prev_rank", "a");
    set_str(action, "new_rank", "b");
    items[2] = event(700, 980, 1, action);
    action = obj("channelAdminLogEventActionToggleSlowMode");
    set_i32(action, "prev_value", 0);
    set_i32(action, "new_value", 30);
    items[3] = event(600, 970, 1, action);
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 4), rows, 16, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 4);
    CHECK_EQ_INT(rows[0].id, 900);
    CHECK_EQ_INT(rows[0].date, 1000);
    CHECK_EQ_INT(rows[0].kind, EXTERIA_LOG_TITLE);
    CHECK(!strcmp(rows[0].actor_name, "Ann"));
    CHECK(!strcmp(rows[0].actor_username, "ann"));
    CHECK(!strcmp(rows[0].old_text, "Old"));
    CHECK(!strcmp(rows[0].new_text, "New"));
    CHECK_EQ_INT(rows[1].kind, EXTERIA_LOG_INVITE);
    CHECK(!strcmp(rows[1].actor_name, "Cy"));
    CHECK_EQ_INT(rows[1].has_target, 1);
    CHECK_EQ_INT(rows[1].target_id, 2);
    CHECK(!strcmp(rows[1].target_name, "Bob"));
    CHECK_EQ_INT(rows[2].kind, EXTERIA_LOG_EDIT_RANK);
    CHECK(!strcmp(rows[2].old_text, "a"));
    CHECK(!strcmp(rows[2].new_text, "b"));
    CHECK_EQ_INT(rows[3].kind, EXTERIA_LOG_SLOW_MODE);
    CHECK_EQ_INT(rows[3].new_number, 30);
    /* an actor the answer does not describe is still a row, with no name */
    items[0] = event(5, 1, 77, obj("channelAdminLogEventActionParticipantJoin"));
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 1), rows, 16, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].kind, EXTERIA_LOG_JOIN);
    CHECK_EQ_INT(rows[0].actor_id, 77);
    CHECK_EQ_INT(rows[0].actor_name[0], 0);
}

static void test_participant_changes(void) {
    exteria_admin_event rows[8];
    exteria_tl_value *items[6], *action;
    size_t count = 0;
    /* a ban that takes the view of the chat is a removal, one that does not only takes rights, and the way back is an unban */
    action = obj("channelAdminLogEventActionParticipantToggleBan");
    set(action, "prev_participant", plain(2));
    set(action, "new_participant", banned(2, 1));
    items[0] = event(6, 60, 1, action);
    action = obj("channelAdminLogEventActionParticipantToggleBan");
    set(action, "prev_participant", plain(2));
    set(action, "new_participant", banned(2, 0));
    items[1] = event(5, 50, 1, action);
    action = obj("channelAdminLogEventActionParticipantToggleBan");
    set(action, "prev_participant", banned(2, 1));
    set(action, "new_participant", plain(2));
    items[2] = event(4, 40, 1, action);
    /* a new admin, an admin whose rights changed, an admin who is none any more */
    action = obj("channelAdminLogEventActionParticipantToggleAdmin");
    set(action, "prev_participant", plain(3));
    set(action, "new_participant", admin(3, "boss"));
    items[3] = event(3, 30, 1, action);
    action = obj("channelAdminLogEventActionParticipantToggleAdmin");
    set(action, "prev_participant", admin(3, NULL));
    set(action, "new_participant", admin(3, NULL));
    items[4] = event(2, 20, 1, action);
    action = obj("channelAdminLogEventActionParticipantToggleAdmin");
    set(action, "prev_participant", admin(3, NULL));
    set(action, "new_participant", plain(3));
    items[5] = event(1, 10, 1, action);
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 6), rows, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 6);
    CHECK_EQ_INT(rows[0].kind, EXTERIA_LOG_BAN);
    CHECK(!strcmp(rows[0].target_name, "Bob"));
    CHECK_EQ_INT(rows[1].kind, EXTERIA_LOG_RESTRICT);
    CHECK_EQ_INT(rows[2].kind, EXTERIA_LOG_UNBAN);
    CHECK_EQ_INT(rows[2].target_id, 2);
    CHECK_EQ_INT(rows[3].kind, EXTERIA_LOG_PROMOTE);
    CHECK(!strcmp(rows[3].new_text, "boss"));
    CHECK(!strcmp(rows[3].target_name, "Cy"));
    CHECK_EQ_INT(rows[4].kind, EXTERIA_LOG_ADMIN_RIGHTS);
    CHECK_EQ_INT(rows[5].kind, EXTERIA_LOG_DEMOTE);
}

static void test_messages_and_switches(void) {
    exteria_admin_event rows[10];
    exteria_tl_value *items[10], *action, *with_media;
    size_t count = 0;
    action = obj("channelAdminLogEventActionEditMessage");
    set(action, "prev_message", text_message(10, "before"));
    set(action, "new_message", text_message(10, "after"));
    items[0] = event(10, 1, 1, action);
    action = obj("channelAdminLogEventActionDeleteMessage");
    with_media = obj("message");
    set_i32(with_media, "id", 11);
    set_str(with_media, "message", "");
    set(with_media, "media", obj("messageMediaPhoto"));
    set(action, "message", with_media);
    items[1] = event(9, 1, 1, action);
    action = obj("channelAdminLogEventActionUpdatePinned");
    with_media = text_message(12, "keep this");
    set_flag(with_media, "pinned");
    set(action, "message", with_media);
    items[2] = event(8, 1, 1, action);
    action = obj("channelAdminLogEventActionUpdatePinned");
    set(action, "message", text_message(12, "keep this"));
    items[3] = event(7, 1, 1, action);
    items[4] = event(6, 1, 1, action_new_value("channelAdminLogEventActionToggleInvites", 1));
    items[5] = event(5, 1, 1, action_new_value("channelAdminLogEventActionToggleNoForwards", 0));
    action = obj("channelAdminLogEventActionCreateTopic");
    set(action, "topic", obj("forumTopicDeleted"));
    items[6] = event(4, 1, 1, action);
    action = obj("channelAdminLogEventActionChangePhoto");
    set(action, "prev_photo", obj("photoEmpty"));
    set(action, "new_photo", obj("photoEmpty"));
    items[7] = event(3, 1, 1, action);
    action = obj("channelAdminLogEventActionChangeLinkedChat");
    set_i64(action, "prev_value", 0);
    set_i64(action, "new_value", 0);
    items[8] = event(2, 1, 1, action);
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 9), rows, 10, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 9);
    CHECK_EQ_INT(rows[0].kind, EXTERIA_LOG_EDIT_MESSAGE);
    CHECK_EQ_INT(rows[0].message_id, 10);
    CHECK(!strcmp(rows[0].old_text, "before"));
    CHECK(!strcmp(rows[0].new_text, "after"));
    CHECK_EQ_INT(rows[1].kind, EXTERIA_LOG_DELETE_MESSAGE);
    CHECK_EQ_INT(rows[1].has_media, 1);
    CHECK_EQ_INT(rows[1].old_text[0], 0);
    CHECK_EQ_INT(rows[2].kind, EXTERIA_LOG_PIN);
    CHECK(!strcmp(rows[2].new_text, "keep this"));
    CHECK_EQ_INT(rows[3].kind, EXTERIA_LOG_UNPIN);
    CHECK_EQ_INT(rows[4].kind, EXTERIA_LOG_INVITES);
    CHECK_EQ_INT(rows[4].flag, 1);
    CHECK_EQ_INT(rows[5].kind, EXTERIA_LOG_NO_FORWARDS);
    CHECK_EQ_INT(rows[5].flag, 0);
    CHECK_EQ_INT(rows[6].kind, EXTERIA_LOG_TOPIC_CREATE);
    CHECK_EQ_INT(rows[6].new_text[0], 0);
    CHECK_EQ_INT(rows[7].kind, EXTERIA_LOG_PHOTO);
    CHECK_EQ_INT(rows[8].kind, EXTERIA_LOG_LINKED_CHAT);
    CHECK_EQ_INT(rows[8].flag, 0);
}

static void test_limits_and_malformed(void) {
    exteria_admin_event rows[4];
    exteria_tl_value *items[3];
    exteria_tl_value *action;
    size_t count = 99;
    char big[EXTERIA_ADMIN_LOG_TEXT_MAX * 2];
    /* a text longer than the field is cut at a character, never in the middle of one */
    memset(big, 'x', sizeof(big) - 1);
    memcpy(big + EXTERIA_ADMIN_LOG_TEXT_MAX - 2, "\xD0\xB0\xD0\xB0", 4);
    big[sizeof(big) - 1] = 0;
    action = obj("channelAdminLogEventActionChangeAbout");
    set_str(action, "prev_value", "");
    set_str(action, "new_value", big);
    items[0] = event(1, 1, 1, action);
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 1), rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(strlen(rows[0].new_text), EXTERIA_ADMIN_LOG_TEXT_MAX - 2);
    /* an action this app has no sentence for stays a row */
    action = obj("channelAdminLogEventActionChangeWallpaper");
    set(action, "prev_value", obj("wallPaperNoFile"));
    set(action, "new_value", obj("wallPaperNoFile"));
    items[0] = event(2, 1, 1, action);
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 1), rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].kind, EXTERIA_LOG_OTHER);
    /* more events than room, an empty page, a foreign answer, an item that is no event, an event without an id */
    items[0] = event(3, 1, 1, obj("channelAdminLogEventActionParticipantJoin"));
    items[1] = event(2, 1, 1, obj("channelAdminLogEventActionParticipantJoin"));
    items[2] = event(1, 1, 1, obj("channelAdminLogEventActionParticipantJoin"));
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 3), rows, 2, &count), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 0), rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_admin_log_parse(obj("boolTrue"), rows, 4, &count), EXTERIA_E_MALFORMED);
    items[0] = obj("boolTrue");
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 1), rows, 4, &count), EXTERIA_E_MALFORMED);
    items[0] = event(0, 1, 1, obj("channelAdminLogEventActionParticipantJoin"));
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 1), rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_admin_log_parse(NULL, rows, 4, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_admin_log_parse(answer(items, 1), rows, 0, &count), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_request();
    test_people_and_text();
    test_participant_changes();
    test_messages_and_switches();
    test_limits_and_malformed();
    exteria_arena_free(&arena);
    return test_finish("test_admin_log");
}
