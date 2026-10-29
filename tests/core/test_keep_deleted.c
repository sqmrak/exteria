#include "test_util.h"
#include "exteria_updates.h"
#include "exteria_tl_ids.h"

#include <string.h>
#include <unistd.h>

static exteria_arena arena;

static exteria_tl_value *state(int32_t pts) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, "updates.state");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "pts", pts), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "qts", 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "seq", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "date", 100), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "unread_count", 0), EXTERIA_OK);
    return v;
}

static exteria_tl_value *message(int32_t id, int64_t user, const char *text, int32_t edit_date) {
    exteria_tl_value *m = exteria_tl_new_obj(&arena, "message"), *peer = exteria_tl_new_obj(&arena, "peerUser");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, m, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, m, "date", 1000 + id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, peer, "user_id", user), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(m, "peer_id", peer), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, m, "message", text), EXTERIA_OK);
    if (edit_date) CHECK_EQ_INT(exteria_tl_set_i32(&arena, m, "edit_date", edit_date), EXTERIA_OK);
    return m;
}

static exteria_tl_value *deletion(int32_t pts, int32_t id) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, "updateDeleteMessages");
    int32_t ids[1];
    ids[0] = id;
    CHECK_EQ_INT(exteria_tl_set_i32_vec(&arena, v, "messages", ids, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "pts", pts), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "pts_count", 1), EXTERIA_OK);
    {
        exteria_tl_value *wrapper = exteria_tl_new_obj(&arena, "updateShort");
        CHECK_EQ_INT(exteria_tl_set(wrapper, "update", v), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(&arena, wrapper, "date", 200), EXTERIA_OK);
        return wrapper;
    }
}

static const char *text_of(exteria_store *s, exteria_record_kind kind, exteria_peer peer, int64_t id, exteria_arena *read) {
    exteria_tl_value *got = NULL;
    const uint8_t *bytes = NULL;
    size_t len = 0;
    if (exteria_store_get(s, kind, peer, id, read, &got) != EXTERIA_OK) return NULL;
    if (exteria_tl_get_bytes(got, "message", &bytes, &len) != EXTERIA_OK) return NULL;
    return (const char *)bytes;
}

static void test_deleted(void) {
    exteria_store *s = NULL;
    exteria_updates u;
    exteria_arena read;
    exteria_peer peer = {1, 77}, found;
    int64_t count = -1;
    char path[] = "/tmp/exteria-keep-XXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    exteria_arena_init(&read, 4u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_store_open(&s, path, 5), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_init(&u, s, 5), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_state(&u, state(10)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(7, 77, "hello", 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(8, 77, "again", 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_find_common_message(s, 7, &found), EXTERIA_OK);
    CHECK_EQ_INT(found.kind, 1);
    CHECK_EQ_INT((int)found.id, 77);

    /* with nothing asked for, a deleted message is gone */
    CHECK_EQ_INT(exteria_updates_apply(&u, deletion(11, 7)), EXTERIA_OK);
    CHECK(text_of(s, EXTERIA_RECORD_MESSAGE, peer, 7, &read) == NULL);
    CHECK(text_of(s, EXTERIA_RECORD_DELETED_MESSAGE, peer, 7, &read) == NULL);

    /* the private switch alone keeps it, under the kind of the deleted ones, and the chat no longer has it */
    u.keep = EXTERIA_KEEP_DELETED | EXTERIA_KEEP_PRIVATE;
    CHECK_EQ_INT(exteria_updates_apply(&u, deletion(12, 8)), EXTERIA_OK);
    CHECK(text_of(s, EXTERIA_RECORD_MESSAGE, peer, 8, &read) == NULL);
    CHECK(text_of(s, EXTERIA_RECORD_DELETED_MESSAGE, peer, 8, &read) != NULL);
    CHECK(strcmp(text_of(s, EXTERIA_RECORD_DELETED_MESSAGE, peer, 8, &read), "again") == 0);
    CHECK_EQ_INT(exteria_store_count(s, EXTERIA_RECORD_DELETED_MESSAGE, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 1);

    /* a switch for other chats keeps nothing here */
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(9, 77, "third", 0)), EXTERIA_OK);
    u.keep = EXTERIA_KEEP_DELETED | EXTERIA_KEEP_GROUPS;
    CHECK_EQ_INT(exteria_updates_apply(&u, deletion(13, 9)), EXTERIA_OK);
    CHECK(text_of(s, EXTERIA_RECORD_DELETED_MESSAGE, peer, 9, &read) == NULL);

    /* a message the store never held is nothing to keep or remove */
    u.keep = EXTERIA_KEEP_DELETED | EXTERIA_KEEP_PRIVATE;
    CHECK_EQ_INT(exteria_updates_apply(&u, deletion(14, 99)), EXTERIA_OK);

    CHECK_EQ_INT(exteria_store_delete(s, EXTERIA_RECORD_DELETED_MESSAGE, peer, 8), EXTERIA_OK);
    CHECK(text_of(s, EXTERIA_RECORD_DELETED_MESSAGE, peer, 8, &read) == NULL);
    CHECK_EQ_INT(exteria_store_count(s, EXTERIA_RECORD_DELETED_MESSAGE, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(exteria_store_clear(s, EXTERIA_RECORD_DELETED_MESSAGE), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_count(s, EXTERIA_RECORD_DELETED_MESSAGE, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(exteria_store_move(s, EXTERIA_RECORD_MESSAGE, EXTERIA_RECORD_DELETED_MESSAGE, peer, 12345), EXTERIA_E_NOTFOUND);
    exteria_arena_free(&read);
    CHECK_EQ_INT(exteria_store_close(s), EXTERIA_OK);
    unlink(path);
}

static void test_edits(void) {
    exteria_store *s = NULL;
    exteria_updates u;
    exteria_arena read;
    exteria_peer peer = {1, 88};
    int64_t count = -1;
    char path[] = "/tmp/exteria-edit-XXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    exteria_arena_init(&read, 4u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_store_open(&s, path, 6), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_init(&u, s, 6), EXTERIA_OK);
    u.keep = EXTERIA_KEEP_EDITS;
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(3, 88, "one", 0)), EXTERIA_OK);
    /* the same message from a page of history is not an edit */
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(3, 88, "one", 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_count(s, EXTERIA_RECORD_MESSAGE_EDIT, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(3, 88, "two", 2000)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(3, 88, "three", 3000)), EXTERIA_OK);
    /* an edit that changed nothing in the text, and an older copy that arrives late, add no version */
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(3, 88, "three", 3500)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(3, 88, "stale", 2500)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_count(s, EXTERIA_RECORD_MESSAGE_EDIT, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 2);
    CHECK(strcmp(text_of(s, EXTERIA_RECORD_MESSAGE_EDIT, peer, 3 * EXTERIA_EDIT_VERSIONS + 1, &read), "one") == 0);
    CHECK(strcmp(text_of(s, EXTERIA_RECORD_MESSAGE_EDIT, peer, 3 * EXTERIA_EDIT_VERSIONS + 2, &read), "two") == 0);
    /* the neighbour message numbers its versions from one again */
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(4, 88, "a", 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(4, 88, "b", 4000)), EXTERIA_OK);
    CHECK(strcmp(text_of(s, EXTERIA_RECORD_MESSAGE_EDIT, peer, 4 * EXTERIA_EDIT_VERSIONS + 1, &read), "a") == 0);
    /* with the switch off nothing is kept */
    u.keep = 0;
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(5, 88, "x", 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_cache_message(&u, message(5, 88, "y", 5000)), EXTERIA_OK);
    CHECK(text_of(s, EXTERIA_RECORD_MESSAGE_EDIT, peer, 5 * EXTERIA_EDIT_VERSIONS + 1, &read) == NULL);
    exteria_arena_free(&read);
    CHECK_EQ_INT(exteria_store_close(s), EXTERIA_OK);
    unlink(path);
}

int main(void) {
    exteria_arena_init(&arena, 8u * 1024u * 1024u);
    test_deleted();
    test_edits();
    exteria_arena_free(&arena);
    return test_finish("test_keep_deleted");
}
