#include "test_util.h"
#include "exteria_call_log.h"
#include "exteria_tl_ids.h"

#include <string.h>

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

/* a service message of a call with the person: out for a call the account made, duration and the reason as the server says them */
static exteria_tl_value *call(int32_t id, int64_t peer, int out, int video, int32_t duration, const char *reason, int32_t date) {
    exteria_tl_value *m = obj("messageService"), *action = obj("messageActionPhoneCall"), *to = obj("peerUser");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, m, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, m, "date", date), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, to, "user_id", peer), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(m, "peer_id", to), EXTERIA_OK);
    if (out) CHECK_EQ_INT(exteria_tl_set_flag(m, "out"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, action, "call_id", id), EXTERIA_OK);
    if (video) CHECK_EQ_INT(exteria_tl_set_flag(action, "video"), EXTERIA_OK);
    if (duration) CHECK_EQ_INT(exteria_tl_set_i32(&arena, action, "duration", duration), EXTERIA_OK);
    if (reason) CHECK_EQ_INT(exteria_tl_set(action, "reason", obj(reason)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(m, "action", action), EXTERIA_OK);
    return m;
}

int main(void) {
    static exteria_call_log_row rows[8];
    size_t count = 99;
    exteria_tl_value *request, *messages[4], *users[2], *answer;

    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_call_log_request(&arena, 50, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_is(request, EXTERIA_TL_ID_messages_search), 1);
    CHECK(exteria_tl_is(exteria_tl_get(request, "peer"), EXTERIA_TL_ID_inputPeerEmpty));
    CHECK(exteria_tl_is(exteria_tl_get(request, "filter"), EXTERIA_TL_ID_inputMessagesFilterPhoneCalls));
    exteria_writer encoded;
    exteria_writer_init(&encoded, 4096);
    CHECK_EQ_INT(exteria_tl_encode(request, &encoded, NULL), EXTERIA_OK);
    exteria_writer_free(&encoded);
    CHECK_EQ_INT(exteria_call_log_request(&arena, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_log_request(&arena, EXTERIA_CALL_LOG_MAX + 1, &request), EXTERIA_E_ARG);

    messages[0] = call(10, 7, 1, 0, 65, NULL, 1000);
    messages[1] = call(9, 8, 0, 1, 0, "phoneCallDiscardReasonMissed", 900);
    messages[2] = call(8, 99, 0, 0, 0, "phoneCallDiscardReasonBusy", 800);       /* the person is not in the answer: skipped */
    messages[3] = call(7, 7, 1, 0, 0, "phoneCallDiscardReasonDisconnect", 700);
    users[0] = user(7, "Ann");
    users[1] = user(8, "Bob");
    answer = obj("messages.messages");
    CHECK_EQ_INT(exteria_tl_set(answer, "messages", vec_of(messages, 4)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "chats", vec_of(NULL, 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "users", vec_of(users, 2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_call_log_parse(answer, rows, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 3);
    CHECK_EQ_INT(rows[0].message_id, 10);
    CHECK_EQ_INT(rows[0].outgoing, 1);
    CHECK_EQ_INT(rows[0].duration, 65);
    CHECK_EQ_INT(rows[0].outcome, EXTERIA_OUTCOME_ENDED);
    CHECK_EQ_INT((int)rows[0].user_id, 7);
    CHECK(strcmp(rows[0].name, "Ann") == 0);
    CHECK_EQ_INT(rows[1].outgoing, 0);
    CHECK_EQ_INT(rows[1].video, 1);
    CHECK_EQ_INT(rows[1].outcome, EXTERIA_OUTCOME_MISSED);
    CHECK_EQ_INT((int)rows[1].user_id, 8);
    CHECK_EQ_INT(rows[2].outcome, EXTERIA_OUTCOME_DISCONNECTED);

    CHECK_EQ_INT(exteria_call_log_parse(answer, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 2);
    CHECK_EQ_INT(exteria_call_log_parse(obj("messages.stickerSet"), rows, 8, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(exteria_call_log_parse(NULL, rows, 8, &count), EXTERIA_E_ARG);
    exteria_arena_free(&arena);
    return test_finish("test_call_log");
}
