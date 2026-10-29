#include <string.h>

#include "exteria_group_call.h"
#include "exteria_tl_ids.h"
#include "test_util.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *vec = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(vec, i, items[i]), EXTERIA_OK);
    return vec;
}

static exteria_tl_value *user(int64_t id, const char *name) {
    exteria_tl_value *v = obj("user");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "access_hash", id * 3), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, "first_name", name), EXTERIA_OK);
    return v;
}

static exteria_tl_value *peer_user(int64_t id) {
    exteria_tl_value *p = obj("peerUser");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, p, "user_id", id), EXTERIA_OK);
    return p;
}

static exteria_tl_value *member(int64_t id, int32_t source, int muted, int left, int self, int32_t active) {
    exteria_tl_value *p = obj("groupCallParticipant");
    CHECK_EQ_INT(exteria_tl_set(p, "peer", peer_user(id)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, p, "source", source), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, p, "date", 1000), EXTERIA_OK);
    if (muted) CHECK_EQ_INT(exteria_tl_set_flag(p, "muted"), EXTERIA_OK);
    if (left) CHECK_EQ_INT(exteria_tl_set_flag(p, "left"), EXTERIA_OK);
    if (self) CHECK_EQ_INT(exteria_tl_set_flag(p, "self"), EXTERIA_OK);
    if (active) CHECK_EQ_INT(exteria_tl_set_i32(&arena, p, "active_date", active), EXTERIA_OK);
    return p;
}

static exteria_tl_value *group_call(int64_t id, const char *title) {
    exteria_tl_value *c = obj("groupCall");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, c, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, c, "access_hash", id + 5), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, c, "participants_count", 3), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, c, "version", 17), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, c, "unmuted_video_limit", 30), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_flag(c, "join_muted"), EXTERIA_OK);
    if (title) CHECK_EQ_INT(exteria_tl_set_str(&arena, c, "title", title), EXTERIA_OK);
    return c;
}

static void encodes(const exteria_tl_value *request) {
    exteria_writer w;
    exteria_writer_init(&w, 4096);
    CHECK_EQ_INT(exteria_tl_encode(request, &w, NULL), EXTERIA_OK);
    exteria_writer_free(&w);
}

static void reading(void) {
    exteria_group_call_info info;
    exteria_group_call_ref ref;
    exteria_group_participant list[8], one;
    exteria_tl_value *items[3], *users[2], *answer, *input, *update;
    size_t count = 99;
    char offset[16];
    int32_t version = 0;

    CHECK_EQ_INT(exteria_group_call_info_read(group_call(77, "Late night"), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.ref.id, 77);
    CHECK_EQ_INT(info.ref.access_hash, 82);
    CHECK_EQ_INT(info.participants_count, 3);
    CHECK_EQ_INT(info.version, 17);
    CHECK_EQ_INT(info.join_muted, 1);
    CHECK_EQ_INT(info.conference, 0);
    CHECK_EQ_INT(info.discarded, 0);
    CHECK(!strcmp(info.title, "Late night"));
    CHECK_EQ_INT(exteria_group_call_info_read(group_call(77, NULL), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.title[0], 0);
    {
        exteria_tl_value *dead = obj("groupCallDiscarded");
        CHECK_EQ_INT(exteria_tl_set_i64(&arena, dead, "id", 77), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i64(&arena, dead, "access_hash", 1), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(&arena, dead, "duration", 600), EXTERIA_OK);
        CHECK_EQ_INT(exteria_group_call_info_read(dead, &info), EXTERIA_OK);
        CHECK_EQ_INT(info.discarded, 1);
        CHECK_EQ_INT(info.duration, 600);
    }
    CHECK_EQ_INT(exteria_group_call_info_read(group_call(0, NULL), &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_group_call_info_read(obj("user"), &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_group_call_info_read(NULL, &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_group_call_info_read(NULL, NULL), EXTERIA_E_ARG);

    input = obj("inputGroupCall");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, input, "id", 5), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, input, "access_hash", 6), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_call_ref_read(input, &ref), EXTERIA_OK);
    CHECK_EQ_INT(ref.id, 5);
    CHECK_EQ_INT(ref.access_hash, 6);
    CHECK_EQ_INT(exteria_group_call_ref_read(obj("inputGroupCall"), &ref), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(ref.id, 0);

    users[0] = user(7, "Ann");
    users[1] = user(8, "Bob");
    CHECK_EQ_INT(exteria_group_participant_read(member(7, -5, 1, 0, 0, 0), vec_of(users, 2), NULL, &one), EXTERIA_OK);
    CHECK_EQ_INT(one.peer_id, 7);
    CHECK_EQ_INT(one.peer_kind, 1);
    CHECK_EQ_INT(one.source, 0xFFFFFFFBu);
    CHECK_EQ_INT(one.muted, 1);
    CHECK_EQ_INT(one.access_hash, 21);
    CHECK(!strcmp(one.name, "Ann"));
    CHECK_EQ_INT(exteria_group_participant_read(member(9, 1, 0, 0, 0, 0), vec_of(users, 2), NULL, &one), EXTERIA_OK);
    CHECK_EQ_INT(one.name[0], 0);
    CHECK_EQ_INT(exteria_group_participant_read(obj("user"), NULL, NULL, &one), EXTERIA_E_MALFORMED);

    items[0] = member(7, 100, 0, 0, 1, 1500);
    items[1] = obj("groupCallParticipantVideo");
    items[2] = member(8, 200, 1, 1, 0, 0);
    CHECK_EQ_INT(exteria_group_participants_read(vec_of(items, 3), vec_of(users, 2), NULL, list, 8, &count), EXTERIA_OK);
    /* the object that is no participant is skipped */
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(list[0].self, 1);
    CHECK_EQ_INT(list[0].active_date, 1500);
    CHECK_EQ_INT(list[1].left, 1);
    CHECK_EQ_INT(exteria_group_participants_read(vec_of(items, 3), vec_of(users, 2), NULL, list, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_group_participants_read(obj("user"), NULL, NULL, list, 8, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);

    answer = obj("phone.groupCall");
    items[0] = member(7, 100, 0, 0, 0, 0);
    CHECK_EQ_INT(exteria_tl_set(answer, "call", group_call(77, "T")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "participants", vec_of(items, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "users", vec_of(users, 2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, answer, "participants_next_offset", "abc"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_call_answer_parse(answer, &info, list, 8, &count, offset, sizeof(offset)), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK(!strcmp(offset, "abc"));
    CHECK_EQ_INT(info.ref.id, 77);
    CHECK(!strcmp(list[0].name, "Ann"));
    CHECK_EQ_INT(exteria_group_call_answer_parse(obj("user"), &info, list, 8, &count, offset, sizeof(offset)), EXTERIA_E_MALFORMED);

    answer = obj("phone.groupParticipants");
    CHECK_EQ_INT(exteria_tl_set(answer, "participants", vec_of(items, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "users", vec_of(users, 2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, answer, "version", 21), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_participants_answer_parse(answer, list, 8, &count, &version, offset, sizeof(offset)), EXTERIA_OK);
    CHECK_EQ_INT(version, 21);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(offset[0], 0);

    update = obj("updateGroupCall");
    CHECK_EQ_INT(exteria_tl_set(update, "call", group_call(77, "U")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_update_call(update, &info), EXTERIA_OK);
    CHECK(!strcmp(info.title, "U"));
    CHECK_EQ_INT(exteria_group_update_call(obj("updateGroupCallParticipants"), &info), EXTERIA_E_MALFORMED);

    /* the participants of an update take their names from the users of the container it came in */
    update = obj("updateGroupCallParticipants");
    items[0] = member(8, 300, 0, 0, 0, 0);
    CHECK_EQ_INT(exteria_tl_set(update, "call", input), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(update, "participants", vec_of(items, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, update, "version", 30), EXTERIA_OK);
    {
        exteria_tl_value *container = obj("updates");
        CHECK_EQ_INT(exteria_tl_set(container, "users", vec_of(users, 2)), EXTERIA_OK);
        CHECK_EQ_INT(exteria_group_update_participants(update, container, &ref, list, 8, &count, &version), EXTERIA_OK);
        CHECK_EQ_INT(ref.id, 5);
        CHECK_EQ_INT(version, 30);
        CHECK(!strcmp(list[0].name, "Bob"));
        CHECK_EQ_INT(exteria_group_update_participants(update, NULL, &ref, list, 8, &count, &version), EXTERIA_OK);
        CHECK_EQ_INT(list[0].name[0], 0);
    }

    {
        const char *json = NULL;
        size_t len = 0;
        int presentation = 5;
        exteria_tl_value *connection = obj("updateGroupCallConnection"), *data = obj("dataJSON");
        CHECK_EQ_INT(exteria_tl_set_bytes(&arena, data, "data", "{\"a\":1}", 7), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(connection, "params", data), EXTERIA_OK);
        CHECK_EQ_INT(exteria_group_update_connection(connection, &json, &len, &presentation), EXTERIA_OK);
        CHECK_EQ_INT(len, 7);
        CHECK_EQ_INT(presentation, 0);
        CHECK(!memcmp(json, "{\"a\":1}", 7));
        CHECK_EQ_INT(exteria_tl_set_flag(connection, "presentation"), EXTERIA_OK);
        CHECK_EQ_INT(exteria_group_update_connection(connection, &json, &len, &presentation), EXTERIA_OK);
        CHECK_EQ_INT(presentation, 1);
        CHECK_EQ_INT(exteria_group_update_connection(obj("updateGroupCall"), &json, &len, &presentation), EXTERIA_E_MALFORMED);
        CHECK(json == NULL);
    }
}

static void requests(void) {
    exteria_group_call_ref call = {77, 82}, none = {0, 0};
    exteria_peer_ref chat = {2, 5, 0, 0, 0}, channel = {3, 6, 99, 0, 0}, user_peer = {1, 7, 21, 0, 0}, me = {1, 0, 0, 1, 0};
    exteria_tl_value *request;
    int32_t sources[2] = {5, 6};
    char link[64];
    int present = 9;

    CHECK_EQ_INT(exteria_group_call_get_request(&arena, &call, 20, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_phone_getGroupCall));
    encodes(request);
    CHECK_EQ_INT(exteria_group_call_get_request(&arena, &none, 20, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_group_call_get_request(&arena, &call, 201, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_group_call_get_request(&arena, &call, -1, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_group_participants_get_request(&arena, &call, "", 50, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_phone_getGroupParticipants));
    encodes(request);
    CHECK_EQ_INT(exteria_group_participants_get_request(&arena, &call, NULL, 0, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_group_join_request(&arena, &call, 1, "{\"ssrc\":1}", 10, NULL, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_phone_joinGroupCall));
    CHECK(exteria_tl_has(request, "muted"));
    CHECK(!exteria_tl_has(request, "invite_hash"));
    CHECK(exteria_tl_is(exteria_tl_get(request, "join_as"), EXTERIA_TL_ID_inputPeerSelf));
    encodes(request);
    CHECK_EQ_INT(exteria_group_join_request(&arena, &call, 0, "{\"ssrc\":1}", 10, "hash", &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(request, "muted"));
    CHECK(exteria_tl_has(request, "invite_hash"));
    encodes(request);
    CHECK_EQ_INT(exteria_group_join_request(&arena, &call, 0, "", 0, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_group_join_request(&arena, &call, 0, "{}", 2, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_group_join_request(&arena, &call, 0, "a\0b", 3, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_group_join_request(&arena, &none, 0, "{}", 2, NULL, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_group_leave_request(&arena, &call, 0xFFFFFFFEu, &request), EXTERIA_OK);
    {
        int32_t source = 0;
        CHECK_EQ_INT(exteria_tl_get_i32(request, "source", &source), EXTERIA_OK);
        CHECK_EQ_INT(source, -2);
    }
    encodes(request);

    CHECK_EQ_INT(exteria_group_create_request(&arena, &chat, 1234, "Title", &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_phone_createGroupCall));
    CHECK(exteria_tl_has(request, "title"));
    encodes(request);
    CHECK_EQ_INT(exteria_group_create_request(&arena, &channel, 1234, NULL, &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(request, "title"));
    encodes(request);
    CHECK_EQ_INT(exteria_group_create_request(&arena, &user_peer, 1, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_group_create_request(&arena, &me, 1, NULL, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_group_discard_request(&arena, &call, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_phone_discardGroupCall));

    CHECK_EQ_INT(exteria_group_edit_request(&arena, &call, &me, 1, 1, 0, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_phone_editGroupCallParticipant));
    CHECK(exteria_tl_is(exteria_tl_get(request, "muted"), EXTERIA_TL_ID_boolTrue));
    encodes(request);
    CHECK_EQ_INT(exteria_group_edit_request(&arena, &call, &user_peer, 1, 0, 5000, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "muted"), EXTERIA_TL_ID_boolFalse));
    CHECK(exteria_tl_has(request, "volume"));
    encodes(request);
    /* a volume alone leaves the microphone of the member as it is */
    CHECK_EQ_INT(exteria_group_edit_request(&arena, &call, &user_peer, 0, 0, EXTERIA_GROUP_VOLUME_MAX, &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(request, "muted"));
    CHECK(exteria_tl_has(request, "volume"));
    encodes(request);
    CHECK_EQ_INT(exteria_group_edit_request(&arena, &call, &user_peer, 0, 0, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_edit_request(&arena, &call, &user_peer, 0, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_group_edit_request(&arena, &call, &user_peer, 0, 0, 20001, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_group_invite_link_request(&arena, &call, 1, &request), EXTERIA_OK);
    CHECK(exteria_tl_has(request, "can_self_unmute"));
    encodes(request);
    {
        exteria_tl_value *answer = obj("phone.exportedGroupCallInvite");
        CHECK_EQ_INT(exteria_group_invite_link_parse(answer, link, sizeof(link)), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(exteria_tl_set_str(&arena, answer, "link", "https://t.me/g?videochat=abc"), EXTERIA_OK);
        CHECK_EQ_INT(exteria_group_invite_link_parse(answer, link, sizeof(link)), EXTERIA_OK);
        CHECK(!strcmp(link, "https://t.me/g?videochat=abc"));
        CHECK_EQ_INT(exteria_group_invite_link_parse(obj("user"), link, sizeof(link)), EXTERIA_E_MALFORMED);
    }

    CHECK_EQ_INT(exteria_group_check_request(&arena, &call, sources, 2, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_phone_checkGroupCall));
    encodes(request);
    CHECK_EQ_INT(exteria_group_check_request(&arena, &call, sources, 0, &request), EXTERIA_E_ARG);
    {
        exteria_tl_value *five = exteria_tl_new_i32(&arena, 5), *answer;
        answer = vec_of(&five, 1);
        CHECK_EQ_INT(exteria_group_check_parse(answer, 5, &present), EXTERIA_OK);
        CHECK_EQ_INT(present, 1);
        CHECK_EQ_INT(exteria_group_check_parse(answer, 6, &present), EXTERIA_OK);
        CHECK_EQ_INT(present, 0);
        CHECK_EQ_INT(exteria_group_check_parse(obj("user"), 5, &present), EXTERIA_E_MALFORMED);
    }
}

static void found_in_updates(void) {
    exteria_group_call_info info;
    exteria_tl_value *update = obj("updateGroupCall"), *other = obj("updateGroupCallParticipants"), *items[2], *container = obj("updates");
    CHECK_EQ_INT(exteria_tl_set(update, "call", group_call(31, "New")), EXTERIA_OK);
    items[0] = other;
    items[1] = update;
    CHECK_EQ_INT(exteria_tl_set(container, "updates", vec_of(items, 2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_updates_find_call(container, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.ref.id, 31);
    container = obj("updateShort");
    CHECK_EQ_INT(exteria_tl_set(container, "update", update), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_updates_find_call(container, &info), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_updates_find_call(obj("updates"), &info), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(info.ref.id, 0);
    CHECK_EQ_INT(exteria_group_updates_find_call(obj("updates"), NULL), EXTERIA_E_ARG);
}

static void full_chats(void) {
    exteria_peer_ref chat = {2, 5, 0, 0, 0}, channel = {3, 6, 99, 0, 0}, nohash = {3, 6, 0, 0, 0};
    exteria_tl_value *request, *answer, *full, *input;
    exteria_group_call_ref ref;
    CHECK_EQ_INT(exteria_group_full_chat_request(&arena, &chat, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_messages_getFullChat));
    encodes(request);
    CHECK_EQ_INT(exteria_group_full_chat_request(&arena, &channel, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_channels_getFullChannel));
    encodes(request);
    CHECK_EQ_INT(exteria_group_full_chat_request(&arena, &nohash, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(request == NULL, 1);

    answer = obj("messages.chatFull");
    full = obj("channelFull");
    CHECK_EQ_INT(exteria_tl_set(answer, "full_chat", full), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_full_chat_call(answer, &ref), EXTERIA_E_NOTFOUND);
    input = obj("inputGroupCall");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, input, "id", 9), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, input, "access_hash", 10), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(full, "call", input), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_full_chat_call(answer, &ref), EXTERIA_OK);
    CHECK_EQ_INT(ref.id, 9);
    CHECK_EQ_INT(ref.access_hash, 10);
    CHECK_EQ_INT(exteria_group_full_chat_call(obj("user"), &ref), EXTERIA_E_MALFORMED);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    reading();
    requests();
    full_chats();
    found_in_updates();
    return test_finish("test_group_call");
}
