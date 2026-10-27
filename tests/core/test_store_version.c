#include "test_util.h"
#include "exteria_store.h"

/* a watcher skips its read while the version of its chat stands; a write to the chat, to a user or chat record, or a sweep must move it */

static exteria_tl_value *record(exteria_arena *a, int32_t id) {
    exteria_tl_value *v = exteria_tl_new_obj(a, "updates.state");
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "pts", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "qts", 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "seq", 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "date", 100), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "unread_count", 0), EXTERIA_OK);
    return v;
}

int main(void) {
    exteria_store *s = NULL;
    exteria_arena a;
    exteria_tl_value *v;
    exteria_peer chat = {2, 1001}, other = {2, 1002}, user = {1, 77};
    uint64_t before, after;
    exteria_arena_init(&a, 65536);
    v = record(&a, 5);
    CHECK_EQ_INT(exteria_store_open(&s, ":memory:", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_peer_version(NULL, chat), 0);

    before = exteria_store_peer_version(s, chat);
    CHECK_EQ_INT(exteria_store_put(s, EXTERIA_RECORD_MESSAGE, chat, 10, v), EXTERIA_OK);
    after = exteria_store_peer_version(s, chat);
    CHECK(after > before);

    /* a read changes nothing */
    CHECK_EQ_INT(exteria_store_peer_version(s, chat), after);

    /* another chat in another bucket leaves this one alone */
    before = after;
    CHECK_EQ_INT(exteria_store_put(s, EXTERIA_RECORD_MESSAGE, other, 11, v), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_peer_version(s, chat), before);

    /* a user record changes names in every chat */
    CHECK_EQ_INT(exteria_store_put(s, EXTERIA_RECORD_USER, user, 77, v), EXTERIA_OK);
    after = exteria_store_peer_version(s, chat);
    CHECK(after > before);

    before = after;
    CHECK_EQ_INT(exteria_store_delete(s, EXTERIA_RECORD_MESSAGE, chat, 10), EXTERIA_OK);
    after = exteria_store_peer_version(s, chat);
    CHECK(after > before);

    /* a failed write keeps the number */
    before = after;
    CHECK_EQ_INT(exteria_store_put(s, EXTERIA_RECORD_MESSAGE, chat, 12, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_store_peer_version(s, chat), before);

    /* the sweep over every chat moves them all */
    CHECK_EQ_INT(exteria_store_delete_common_message(s, 11), EXTERIA_OK);
    after = exteria_store_peer_version(s, chat);
    CHECK(after > before);
    CHECK(exteria_store_peer_version(s, other) > 0);

    CHECK_EQ_INT(exteria_store_close(s), EXTERIA_OK);
    exteria_arena_free(&a);
    return test_finish("test_store_version");
}
