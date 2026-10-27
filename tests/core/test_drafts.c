#include "exteria_drafts.h"
#include "exteria_tl_ids.h"
#include "test_util.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void set(exteria_tl_value *v, const char *field, exteria_tl_value *x) {
    CHECK_EQ_INT(exteria_tl_set(v, field, x), EXTERIA_OK);
}

static exteria_tl_value *peer_of(const char *ctor, const char *field, int64_t id) {
    exteria_tl_value *p = obj(ctor);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, p, field, id), EXTERIA_OK);
    return p;
}

static exteria_tl_value *entity(const char *ctor, int32_t offset, int32_t length) {
    exteria_tl_value *e = obj(ctor);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, e, "offset", offset), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, e, "length", length), EXTERIA_OK);
    return e;
}

static exteria_tl_value *reply_to(int32_t id, int32_t top) {
    exteria_tl_value *r = obj("inputReplyToMessage");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, r, "reply_to_msg_id", id), EXTERIA_OK);
    if (top) CHECK_EQ_INT(exteria_tl_set_i32(&arena, r, "top_msg_id", top), EXTERIA_OK);
    return r;
}

static exteria_tl_value *draft_of(const char *text, int32_t date, exteria_tl_value *reply, exteria_tl_value *entities) {
    exteria_tl_value *d = obj("draftMessage");
    CHECK_EQ_INT(exteria_tl_set_str(&arena, d, "message", text), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, d, "date", date), EXTERIA_OK);
    if (reply) set(d, "reply_to", reply);
    if (entities) set(d, "entities", entities);
    return d;
}

static exteria_draft *fresh(void) {
    exteria_draft *d = malloc(sizeof(*d));
    CHECK(d != NULL);
    return d;
}

static void reads_text_reply_and_entities(void) {
    exteria_draft *out = fresh();
    exteria_tl_value *list = exteria_tl_new_vec(&arena, 2), *d;
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, entity("messageEntityBold", 0, 5)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 1, entity("messageEntityItalic", 6, 3)), EXTERIA_OK);
    d = draft_of("hello you", 1700000000, reply_to(42, 0), list);
    CHECK_EQ_INT(exteria_tl_set_flag(d, "no_webpage"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_draft_read(d, 0, out), EXTERIA_OK);
    CHECK_EQ_INT(out->present, 1);
    CHECK_EQ_INT(out->no_webpage, 1);
    CHECK_EQ_INT(out->date, 1700000000);
    CHECK_EQ_INT(out->reply_to, 42);
    CHECK(strcmp(out->text, "hello you") == 0);
    CHECK_EQ_INT(out->entity_count, 2);
    CHECK_EQ_INT(out->entities[0].kind, EXTERIA_ENTITY_BOLD);
    CHECK_EQ_INT(out->entities[1].offset, 6);
    free(out);
}

static void empty_draft_is_not_present(void) {
    exteria_draft *out = fresh();
    exteria_tl_value *e = obj("draftMessageEmpty");
    CHECK_EQ_INT(exteria_draft_read(e, 0, out), EXTERIA_OK);
    CHECK_EQ_INT(out->present, 0);
    CHECK_EQ_INT(out->date, 0);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, e, "date", 77), EXTERIA_OK);
    CHECK_EQ_INT(exteria_draft_read(e, 0, out), EXTERIA_OK);
    CHECK_EQ_INT(out->date, 77);
    /* no text and no answer keeps nothing, even as a draftMessage */
    CHECK_EQ_INT(exteria_draft_read(draft_of("", 5, NULL, NULL), 0, out), EXTERIA_OK);
    CHECK_EQ_INT(out->present, 0);
    /* a bare reply is kept: the person pressed reply and has not typed yet */
    CHECK_EQ_INT(exteria_draft_read(draft_of("", 5, reply_to(9, 0), NULL), 0, out), EXTERIA_OK);
    CHECK_EQ_INT(out->present, 1);
    CHECK_EQ_INT(out->reply_to, 9);
    free(out);
}

static void topic_root_is_not_an_answer(void) {
    exteria_draft *out = fresh();
    exteria_tl_value *d = draft_of("in a topic", 5, reply_to(300, 300), NULL);
    CHECK_EQ_INT(exteria_draft_read(d, 300, out), EXTERIA_OK);
    CHECK_EQ_INT(out->reply_to, 0);
    CHECK_EQ_INT(out->present, 1);
    d = draft_of("in a topic", 5, reply_to(310, 300), NULL);
    CHECK_EQ_INT(exteria_draft_read(d, 300, out), EXTERIA_OK);
    CHECK_EQ_INT(out->reply_to, 310);
    free(out);
}

static void rejects_what_is_not_a_draft(void) {
    exteria_draft *out = fresh();
    CHECK_EQ_INT(exteria_draft_read(NULL, 0, out), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_draft_read(obj("boolTrue"), 0, out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_draft_read(obj("draftMessage"), 0, out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(out->present, 0);
    CHECK_EQ_INT(exteria_draft_read(obj("draftMessageEmpty"), 0, NULL), EXTERIA_E_ARG);
    free(out);
}

static void save_request_carries_everything(void) {
    exteria_peer_ref chat = {3, 500, 7, 0, 0}, topic = {3, 500, 7, 0, 300};
    exteria_send_entity bold = {EXTERIA_ENTITY_BOLD, 0, 0, 5, 0, 0, 0, NULL};
    exteria_tl_value *request = NULL;
    const exteria_tl_value *list, *reply;
    int32_t id = 0;
    CHECK_EQ_INT(exteria_draft_save_request(&arena, &chat, "hello you", &bold, 1, 42, 1, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_messages_saveDraft));
    CHECK(exteria_tl_has(request, "no_webpage"));
    CHECK(exteria_tl_has(request, "peer"));
    list = exteria_tl_get(request, "entities");
    CHECK(list && list->kind == EXTERIA_TL_V_VEC && list->u.vec.count == 1);
    reply = exteria_tl_get(request, "reply_to");
    CHECK(reply != NULL);
    CHECK_EQ_INT(exteria_tl_get_i32(reply, "reply_to_msg_id", &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 42);
    CHECK(!exteria_tl_has(reply, "top_msg_id"));

    /* a draft in a topic names the root when it answers nothing, and the root as the thread when it answers a message */
    CHECK_EQ_INT(exteria_draft_save_request(&arena, &topic, "t", NULL, 0, 0, 0, &request), EXTERIA_OK);
    reply = exteria_tl_get(request, "reply_to");
    CHECK(reply != NULL);
    CHECK_EQ_INT(exteria_tl_get_i32(reply, "reply_to_msg_id", &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 300);
    CHECK(!exteria_tl_has(request, "no_webpage"));
    CHECK(!exteria_tl_has(request, "entities"));
    CHECK_EQ_INT(exteria_draft_save_request(&arena, &topic, "t", NULL, 0, 310, 0, &request), EXTERIA_OK);
    reply = exteria_tl_get(request, "reply_to");
    CHECK_EQ_INT(exteria_tl_get_i32(reply, "reply_to_msg_id", &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 310);
    CHECK_EQ_INT(exteria_tl_get_i32(reply, "top_msg_id", &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 300);

    /* the way a draft is cleared: no text, no answer */
    CHECK_EQ_INT(exteria_draft_save_request(&arena, &chat, "", NULL, 0, 0, 0, &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(request, "reply_to"));
    CHECK(!exteria_tl_has(request, "entities"));
}

static void save_request_refuses_bad_input(void) {
    exteria_peer_ref chat = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0};
    exteria_send_entity past = {EXTERIA_ENTITY_BOLD, 0, 0, 50, 0, 0, 0, NULL};
    exteria_tl_value *request = (exteria_tl_value *)1;
    CHECK_EQ_INT(exteria_draft_save_request(&arena, &chat, "short", &past, 1, 0, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_draft_save_request(&arena, &chat, "x", NULL, 0, -1, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_draft_save_request(&arena, &nohash, "x", NULL, 0, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_draft_save_request(&arena, &chat, NULL, NULL, 0, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_draft_save_request(&arena, NULL, "x", NULL, 0, 0, 0, &request), EXTERIA_E_ARG);
}

static void update_names_chat_and_topic(void) {
    int32_t kind = -1, topic = -1;
    int64_t id = -1;
    const exteria_tl_value *draft = NULL;
    exteria_tl_value *update = obj("updateDraftMessage"), *body = draft_of("x", 9, NULL, NULL);
    set(update, "peer", peer_of("peerUser", "user_id", 77));
    set(update, "draft", body);
    CHECK_EQ_INT(exteria_draft_update_read(update, &kind, &id, &topic, &draft), EXTERIA_OK);
    CHECK_EQ_INT(kind, 1);
    CHECK_EQ_INT(id, 77);
    CHECK_EQ_INT(topic, 0);
    CHECK(draft == body);

    update = obj("updateDraftMessage");
    set(update, "peer", peer_of("peerChannel", "channel_id", 500));
    set(update, "draft", body);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, update, "top_msg_id", 300), EXTERIA_OK);
    CHECK_EQ_INT(exteria_draft_update_read(update, &kind, &id, &topic, &draft), EXTERIA_OK);
    CHECK_EQ_INT(kind, 3);
    CHECK_EQ_INT(topic, 300);

    /* the draft of a saved chat of a monoforum is not a draft of this chat */
    CHECK_EQ_INT(exteria_tl_set(update, "saved_peer_id", peer_of("peerUser", "user_id", 5)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_draft_update_read(update, &kind, &id, &topic, &draft), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(kind, 0);
    CHECK(draft == NULL);

    CHECK_EQ_INT(exteria_draft_update_read(obj("updateUserStatus"), &kind, &id, &topic, &draft), EXTERIA_E_UNSUPPORTED);
    update = obj("updateDraftMessage");
    set(update, "draft", body);
    CHECK_EQ_INT(exteria_draft_update_read(update, &kind, &id, &topic, &draft), EXTERIA_E_MALFORMED);
}

typedef struct seen {
    int count;
    int32_t kind[8];
    int64_t id[8];
    int32_t topic[8];
    const exteria_tl_value *draft[8];
} seen;

static exteria_status collect(void *ctx, int32_t kind, int64_t id, int32_t topic, const exteria_tl_value *draft) {
    seen *s = ctx;
    if (s->count >= 8) return EXTERIA_E_LIMIT;
    s->kind[s->count] = kind;
    s->id[s->count] = id;
    s->topic[s->count] = topic;
    s->draft[s->count] = draft;
    ++s->count;
    return EXTERIA_OK;
}

static exteria_status stop(void *ctx, int32_t kind, int64_t id, int32_t topic, const exteria_tl_value *draft) {
    (void)kind; (void)id; (void)topic; (void)draft;
    ++*(int *)ctx;
    return EXTERIA_E_STATE;
}

static void walks_dialogs(void) {
    exteria_tl_value *answer = obj("messages.dialogs"), *list = exteria_tl_new_vec(&arena, 3), *a = obj("dialog"), *b = obj("dialog"), *folder = obj("dialogFolder");
    exteria_tl_value *body = draft_of("kept", 5, NULL, NULL);
    seen s;
    int calls = 0;
    memset(&s, 0, sizeof(s));
    set(a, "peer", peer_of("peerUser", "user_id", 1));
    set(a, "draft", body);
    set(b, "peer", peer_of("peerChat", "chat_id", 2));
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, a), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 1, folder), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 2, b), EXTERIA_OK);
    set(answer, "dialogs", list);
    CHECK_EQ_INT(exteria_draft_dialogs_visit(answer, collect, &s), EXTERIA_OK);
    CHECK_EQ_INT(s.count, 2);
    CHECK_EQ_INT(s.kind[0], 1);
    CHECK(s.draft[0] == body);
    CHECK_EQ_INT(s.kind[1], 2);
    CHECK_EQ_INT(s.id[1], 2);
    CHECK(s.draft[1] == NULL);
    CHECK_EQ_INT(exteria_draft_dialogs_visit(answer, stop, &calls), EXTERIA_E_STATE);
    CHECK_EQ_INT(calls, 1);
    CHECK_EQ_INT(exteria_draft_dialogs_visit(obj("messages.dialogsNotModified"), collect, &s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_draft_dialogs_visit(obj("boolTrue"), collect, &s), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_draft_dialogs_visit(NULL, collect, &s), EXTERIA_E_ARG);
}

static void walks_topics(void) {
    exteria_tl_value *answer = obj("messages.forumTopics"), *list = exteria_tl_new_vec(&arena, 3), *general = obj("forumTopic"), *topic = obj("forumTopic"), *gone = obj("forumTopicDeleted");
    exteria_tl_value *body = draft_of("kept", 5, NULL, NULL);
    seen s;
    memset(&s, 0, sizeof(s));
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, general, "id", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, topic, "id", 300), EXTERIA_OK);
    set(topic, "draft", body);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, general), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 1, topic), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 2, gone), EXTERIA_OK);
    set(answer, "topics", list);
    CHECK_EQ_INT(exteria_draft_topics_visit(answer, 3, 500, collect, &s), EXTERIA_OK);
    CHECK_EQ_INT(s.count, 2);
    CHECK_EQ_INT(s.topic[0], 0);
    CHECK(s.draft[0] == NULL);
    CHECK_EQ_INT(s.topic[1], 300);
    CHECK_EQ_INT(s.id[1], 500);
    CHECK(s.draft[1] == body);
    CHECK_EQ_INT(exteria_draft_topics_visit(answer, 1, 500, collect, &s), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 1u << 22);
    reads_text_reply_and_entities();
    empty_draft_is_not_present();
    topic_root_is_not_an_answer();
    rejects_what_is_not_a_draft();
    save_request_carries_everything();
    save_request_refuses_bad_input();
    update_names_chat_and_topic();
    walks_dialogs();
    walks_topics();
    exteria_arena_free(&arena);
    return test_finish("test_drafts");
}
