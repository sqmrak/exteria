#include "test_util.h"
#include "exteria_updates.h"
#include "exteria_tl_ids.h"
#include "exteria_people.h"

#include <limits.h>
#include <string.h>
#include <unistd.h>

static exteria_tl_value *state(exteria_arena *a, int32_t pts, int32_t qts, int32_t seq) {
    exteria_tl_value *v = exteria_tl_new_obj(a, "updates.state");
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "pts", pts), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "qts", qts), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "seq", seq), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "date", 100), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "unread_count", 0), EXTERIA_OK);
    return v;
}

static exteria_tl_value *short_update(exteria_arena *a, int32_t pts, int32_t count, int32_t id) {
    exteria_tl_value *v = exteria_tl_new_obj(a, "updateShortMessage");
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(a, v, "user_id", INT64_C(4294967399)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(a, v, "message", "hello"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "pts", pts), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "pts_count", count), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, v, "date", 101), EXTERIA_OK);
    return v;
}

static exteria_status count_visit(void *ctx, int64_t id, const exteria_tl_value *v) {
    int *count = ctx;
    CHECK(id > 0);
    CHECK(v != NULL);
    ++*count;
    return EXTERIA_OK;
}

static void test_atomic(void) {
    exteria_store *s = NULL, *other = NULL;
    exteria_arena a, read;
    exteria_updates u;
    exteria_tl_value *v, *got, *request;
    exteria_cursor cursor;
    exteria_peer peer = {1, INT64_C(4294967399)};
    exteria_peer zero = {0, 0};
    exteria_outbox_item item;
    char path[] = "/tmp/exteria-store-XXXXXX";
    int fd = mkstemp(path), count = 0;
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    exteria_arena_init(&a, 8u * 1024u * 1024u);
    exteria_arena_init(&read, 8u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_store_open(&s, path, 123), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_init(&u, s, 123), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_request(&u, 0, NULL, &a, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_updates_getState));
    CHECK_EQ_INT(exteria_updates_state(&u, state(&a, 10, 5, 2)), EXTERIA_OK);
    v = short_update(&a, 11, 1, 7);
    CHECK_EQ_INT(exteria_updates_apply(&u, v), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_get(s, EXTERIA_RECORD_MESSAGE, peer, 7, &read, &got), EXTERIA_OK);
    CHECK(exteria_tl_is(got, EXTERIA_TL_ID_message));
    CHECK_EQ_INT(exteria_updates_apply(&u, v), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_journal_page(s, 0, 512, count_visit, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_updates_apply(&u, short_update(&a, 13, 1, 9)), EXTERIA_E_RETRY);
    CHECK_EQ_INT(exteria_store_cursor_get(s, 0, &cursor), EXTERIA_OK);
    CHECK_EQ_INT(cursor.pts, 11);
    CHECK_EQ_INT(exteria_store_get(s, EXTERIA_RECORD_MESSAGE, peer, 9, &read, &got), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_updates_apply(&u, short_update(&a, 12, 1, 8)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_apply(&u, short_update(&a, 13, 1, 9)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_begin(s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_put(s, EXTERIA_RECORD_USER, zero, INT64_MAX - 1, exteria_tl_new_obj(&a, "boolTrue")), EXTERIA_OK);
    cursor.pts = 999;
    CHECK_EQ_INT(exteria_store_cursor_put(s, 0, &cursor), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_rollback(s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_cursor_get(s, 0, &cursor), EXTERIA_OK);
    CHECK_EQ_INT(cursor.pts, 13);
    CHECK_EQ_INT(exteria_store_get(s, EXTERIA_RECORD_USER, zero, INT64_MAX - 1, &read, &got), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_store_open(&other, path, 124), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_get(other, EXTERIA_RECORD_MESSAGE, peer, 7, &read, &got), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_store_begin(s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_begin(other), EXTERIA_E_RETRY);
    CHECK_EQ_INT(exteria_store_rollback(s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_close(other), EXTERIA_OK);
    request = exteria_tl_new_obj(&a, "messages.sendMessage");
    v = exteria_tl_new_obj(&a, "inputPeerUser");
    CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "user_id", peer.id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "access_hash", INT64_MIN + 17), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(request, "peer", v), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&a, request, "message", "durable"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&a, request, "random_id", INT64_MIN + 19), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_outbox_add(s, peer, request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_outbox_add(s, peer, request), EXTERIA_E_STORAGE);
    CHECK_EQ_INT(exteria_store_outbox_next(s, &read, &item), EXTERIA_OK);
    CHECK_EQ_INT(item.random_id, INT64_MIN + 19);
    CHECK_EQ_INT(exteria_store_outbox_set(s, item.random_id, EXTERIA_OUTBOX_SENDING, 0, 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_close(s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_open(&s, path, 123), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_outbox_recover(s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_outbox_next(s, &read, &item), EXTERIA_OK);
    CHECK_EQ_INT(item.random_id, INT64_MIN + 19);
    CHECK_EQ_INT(exteria_store_outbox_set(s, item.random_id, EXTERIA_OUTBOX_SENT, 42, 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_outbox_set(s, item.random_id, EXTERIA_OUTBOX_PENDING, 0, 0), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_store_outbox_next(s, &read, &item), EXTERIA_E_NOTFOUND);
    count = 0;
    CHECK_EQ_INT(exteria_store_page(s, EXTERIA_RECORD_MESSAGE, peer, INT64_MAX, 2, count_visit, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(exteria_store_page(s, EXTERIA_RECORD_MESSAGE, peer, INT64_MAX, 513, count_visit, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_store_begin(s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_journal_ack(s, INT64_MAX), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_commit(s), EXTERIA_OK);
    count = 0;
    CHECK_EQ_INT(exteria_store_journal_page(s, 0, 512, count_visit, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_store_close(s), EXTERIA_OK);
    unlink(path);
    exteria_arena_free(&a);
    exteria_arena_free(&read);
}

static void test_difference(void) {
    exteria_store *s = NULL;
    exteria_updates u;
    exteria_cursor c, next;
    exteria_arena a;
    exteria_tl_value *v, *vec, *request;
    exteria_arena_init(&a, 2u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_store_open(&s, ":memory:", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_init(&u, s, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_state(&u, state(&a, 10, 4, 1)), EXTERIA_OK);
    v = exteria_tl_new_obj(&a, "updates.differenceSlice");
    vec = exteria_tl_new_vec(&a, 0);
    CHECK_EQ_INT(exteria_tl_set(v, "new_messages", vec), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(v, "new_encrypted_messages", vec), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(v, "other_updates", vec), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(v, "users", vec), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(v, "chats", vec), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(v, "intermediate_state", state(&a, 15, 4, 2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_difference(&u, 0, v), EXTERIA_OK);
    CHECK(u.more_difference);
    CHECK_EQ_INT(exteria_updates_request(&u, 0, NULL, &a, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_updates_getDifference));
    CHECK_EQ_INT(exteria_tl_get_i32(request, "pts", &c.pts), EXTERIA_OK);
    CHECK_EQ_INT(c.pts, 15);
    CHECK_EQ_INT(exteria_tl_set(v, "intermediate_state", state(&a, 14, 4, 2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_difference(&u, 0, v), EXTERIA_E_MALFORMED);
    /* a state that carries an earlier date than the cursor holds is a good answer, and the cursor keeps its date */
    CHECK_EQ_INT(exteria_store_cursor_get(s, 0, &c), EXTERIA_OK);
    {
        exteria_tl_value *later = state(&a, 16, 4, 2);
        CHECK_EQ_INT(exteria_tl_set_i32(&a, later, "date", c.date - 1), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(v, "intermediate_state", later), EXTERIA_OK);
        CHECK_EQ_INT(exteria_updates_difference(&u, 0, v), EXTERIA_OK);
        CHECK_EQ_INT(exteria_store_cursor_get(s, 0, &next), EXTERIA_OK);
        CHECK_EQ_INT(next.pts, 16);
        CHECK_EQ_INT(next.date, c.date);
    }
    v = exteria_tl_new_obj(&a, "updates.channelDifferenceEmpty");
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "pts", 123), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_flag(v, "final"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_difference(&u, INT64_C(4294967299), v), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_cursor_get(s, INT64_C(4294967299), &c), EXTERIA_OK);
    CHECK_EQ_INT(c.pts, 123);
    CHECK_EQ_INT(exteria_store_close(s), EXTERIA_OK);
    exteria_arena_free(&a);
}

static void test_cached_senders(void) {
    static const char *const kinds[] = {"channel", "channelForbidden", "community", "communityForbidden", "chat"};
    exteria_store *s = NULL;
    exteria_updates u;
    exteria_arena a, read;
    exteria_tl_value *answer, *chats, *empty, *got;
    size_t i;
    exteria_arena_init(&a, 2u * 1024u * 1024u);
    exteria_arena_init(&read, 2u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_store_open(&s, ":memory:", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_init(&u, s, 1), EXTERIA_OK);
    answer = exteria_tl_new_obj(&a, "messages.messages");
    chats = exteria_tl_new_vec(&a, 5);
    empty = exteria_tl_new_vec(&a, 0);
    for (i = 0; i < 5; ++i) {
        exteria_tl_value *sender = exteria_tl_new_obj(&a, kinds[i]);
        int64_t id = INT64_C(4294967399) + (int64_t)(i % 4);
        CHECK_EQ_INT(exteria_tl_set_i64(&a, sender, "id", id), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_str(&a, sender, "title", kinds[i]), EXTERIA_OK);
        if (i != 4) CHECK_EQ_INT(exteria_tl_set_i64(&a, sender, "access_hash", 77), EXTERIA_OK);
        if (i == 0 || i == 2 || i == 4) {
            exteria_tl_value *photo = exteria_tl_new_obj(&a, "chatPhoto");
            CHECK_EQ_INT(exteria_tl_set_i64(&a, photo, "photo_id", 900), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set_i32(&a, photo, "dc_id", 4), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set(sender, "photo", photo), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set_i32(&a, sender, "date", 100), EXTERIA_OK);
        }
        if (i == 4) {
            CHECK_EQ_INT(exteria_tl_set_i32(&a, sender, "participants_count", 2), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tl_set_i32(&a, sender, "version", 1), EXTERIA_OK);
        }
        CHECK_EQ_INT(exteria_tl_vec_set(chats, (uint32_t)i, sender), EXTERIA_OK);
    }
    CHECK_EQ_INT(exteria_tl_set(answer, "chats", chats), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "users", empty), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "messages", empty), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_cache(&u, answer), EXTERIA_OK);
    for (i = 0; i < 5; ++i) {
        exteria_peer peer = {i == 4 ? 2 : 3, INT64_C(4294967399) + (int64_t)(i % 4)};
        CHECK_EQ_INT(exteria_store_get(s, EXTERIA_RECORD_CHAT, peer, peer.id, &read, &got), EXTERIA_OK);
        CHECK(exteria_tl_is(got, chats->u.vec.items[i]->u.obj.ctor->id));
        if (i != 4) {
            exteria_person_row row;
            CHECK_EQ_INT(exteria_channel_person_parse(got, &row), EXTERIA_OK);
            CHECK_EQ_INT(row.id, peer.id);
            CHECK(!strcmp(row.name, kinds[i]));
            CHECK_EQ_INT(row.photo.photo_id, i == 0 || i == 2 ? 900 : 0);
        }
        if (i > 0 && i < 4) {
            peer.kind = 2;
            CHECK_EQ_INT(exteria_store_get(s, EXTERIA_RECORD_CHAT, peer, peer.id, &read, &got), EXTERIA_E_NOTFOUND);
        }
    }
    {
        exteria_peer peer = {3, INT64_C(4294967401)};
        exteria_person_row row;
        exteria_tl_value *update = exteria_tl_new_obj(&a, "updates");
        CHECK_EQ_INT(exteria_updates_state(&u, state(&a, 10, 0, 1)), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_str(&a, chats->u.vec.items[2], "title", "Renamed community"), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(update, "chats", chats), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(update, "users", empty), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(update, "updates", empty), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(&a, update, "date", 101), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(&a, update, "seq", 2), EXTERIA_OK);
        CHECK_EQ_INT(exteria_updates_apply(&u, update), EXTERIA_OK);
        CHECK_EQ_INT(exteria_store_get(s, EXTERIA_RECORD_CHAT, peer, peer.id, &read, &got), EXTERIA_OK);
        CHECK_EQ_INT(exteria_channel_person_parse(got, &row), EXTERIA_OK);
        CHECK(!strcmp(row.name, "Renamed community"));
    }
    CHECK_EQ_INT(exteria_store_close(s), EXTERIA_OK);
    exteria_arena_free(&a);
    exteria_arena_free(&read);
}

/* a channel seen in part (min) must not replace the whole one the store holds: its photo and its hash are what the avatar is fetched with */
static exteria_tl_value *channel_object(exteria_arena *a, int64_t id, const char *title, int with_hash, int min) {
    exteria_tl_value *channel = exteria_tl_new_obj(a, "channel"), *photo = exteria_tl_new_obj(a, "chatPhoto");
    CHECK_EQ_INT(exteria_tl_set_i64(a, channel, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(a, channel, "title", title), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(a, channel, "date", 100), EXTERIA_OK);
    if (with_hash) CHECK_EQ_INT(exteria_tl_set_i64(a, channel, "access_hash", 77), EXTERIA_OK);
    if (min) CHECK_EQ_INT(exteria_tl_set_flag(channel, "min"), EXTERIA_OK);
    if (with_hash) {
        CHECK_EQ_INT(exteria_tl_set_i64(a, photo, "photo_id", 900), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(a, photo, "dc_id", 4), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(channel, "photo", photo), EXTERIA_OK);
    } else {
        /* the photo field of a channel is not optional, and an empty one is what a stub without a photo carries */
        CHECK_EQ_INT(exteria_tl_set(channel, "photo", exteria_tl_new_obj(a, "chatPhotoEmpty")), EXTERIA_OK);
    }
    return channel;
}

static void cache_chat(exteria_updates *u, exteria_arena *a, exteria_tl_value *channel) {
    exteria_tl_value *answer = exteria_tl_new_obj(a, "messages.messages"), *chats = exteria_tl_new_vec(a, 1), *empty = exteria_tl_new_vec(a, 0);
    CHECK_EQ_INT(exteria_tl_vec_set(chats, 0, channel), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "chats", chats), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "users", empty), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "messages", empty), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_cache(u, answer), EXTERIA_OK);
}

static void test_min_keeps_whole(void) {
    exteria_store *s = NULL;
    exteria_updates u;
    exteria_arena a, read;
    exteria_tl_value *got;
    exteria_person_row row;
    exteria_peer whole = {3, INT64_C(4294967500)}, stub = {3, INT64_C(4294967501)};
    exteria_arena_init(&a, 2u * 1024u * 1024u);
    exteria_arena_init(&read, 2u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_store_open(&s, ":memory:", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_init(&u, s, 1), EXTERIA_OK);
    cache_chat(&u, &a, channel_object(&a, whole.id, "Whole", 1, 0));
    /* the stub of the same channel comes later in a group's messages: the whole one stays, photo and hash with it */
    cache_chat(&u, &a, channel_object(&a, whole.id, "Stub", 0, 1));
    CHECK_EQ_INT(exteria_store_get(s, EXTERIA_RECORD_CHAT, whole, whole.id, &read, &got), EXTERIA_OK);
    CHECK_EQ_INT(exteria_channel_person_parse(got, &row), EXTERIA_OK);
    CHECK(!strcmp(row.name, "Whole"));
    CHECK_EQ_INT(row.access_hash, 77);
    CHECK_EQ_INT(row.photo.photo_id, 900);
    /* a stub of a channel the store has never held is kept, since it is all there is */
    cache_chat(&u, &a, channel_object(&a, stub.id, "Only a stub", 0, 1));
    CHECK_EQ_INT(exteria_store_get(s, EXTERIA_RECORD_CHAT, stub, stub.id, &read, &got), EXTERIA_OK);
    CHECK_EQ_INT(exteria_channel_person_parse(got, &row), EXTERIA_OK);
    CHECK(!strcmp(row.name, "Only a stub"));
    CHECK_EQ_INT(row.photo.photo_id, 0);
    /* and a whole object does replace a stub, and another whole one */
    cache_chat(&u, &a, channel_object(&a, stub.id, "Now whole", 1, 0));
    CHECK_EQ_INT(exteria_store_get(s, EXTERIA_RECORD_CHAT, stub, stub.id, &read, &got), EXTERIA_OK);
    CHECK_EQ_INT(exteria_channel_person_parse(got, &row), EXTERIA_OK);
    CHECK(!strcmp(row.name, "Now whole"));
    CHECK_EQ_INT(row.photo.photo_id, 900);
    CHECK_EQ_INT(exteria_store_close(s), EXTERIA_OK);
    exteria_arena_free(&a);
    exteria_arena_free(&read);
}

int main(void) {
    test_min_keeps_whole();
    test_atomic();
    test_difference();
    test_cached_senders();
    return test_finish("test_store_updates");
}
