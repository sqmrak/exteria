#include "test_util.h"
#include "exteria_notify_prefs.h"
#include "exteria_tl_ids.h"
#include "exteria_updates.h"

#include <string.h>
#include <unistd.h>

#define EXCEPTIONS 300

static exteria_arena a;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&a, name);
    CHECK(v != NULL);
    return v;
}

static exteria_tl_value *state(int32_t pts, int32_t qts, int32_t seq) {
    exteria_tl_value *v = obj("updates.state");
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "pts", pts), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "qts", qts), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "seq", seq), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "date", 100), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "unread_count", 0), EXTERIA_OK);
    return v;
}

/* the answer of account.getNotifyExceptions: an Updates whose entries are settings of chats, with the channels and users they name */
static exteria_tl_value *exceptions_answer(int with_chats) {
    exteria_tl_value *answer = obj("updates"), *list = exteria_tl_new_vec(&a, EXCEPTIONS), *chats = exteria_tl_new_vec(&a, EXCEPTIONS);
    for (uint32_t i = 0; i < EXCEPTIONS; ++i) {
        exteria_tl_value *update = obj("updateNotifySettings"), *notify = obj("notifyPeer"), *peer = obj("peerChannel"), *settings = obj("peerNotifySettings");
        exteria_tl_value *channel = obj("channelForbidden");
        CHECK_EQ_INT(exteria_tl_set_i64(&a, peer, "channel_id", 1000 + i), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(notify, "peer", peer), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(&a, settings, "mute_until", 2147483647), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(update, "peer", notify), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set(update, "notify_settings", settings), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_vec_set(list, i, update), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i64(&a, channel, "id", 1000 + i), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i64(&a, channel, "access_hash", 7), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_str(&a, channel, "title", "c"), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_vec_set(chats, i, channel), EXTERIA_OK);
    }
    CHECK_EQ_INT(exteria_tl_set(answer, "updates", list), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "users", exteria_tl_new_vec(&a, 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer, "chats", with_chats ? chats : exteria_tl_new_vec(&a, 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, answer, "date", 1000), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, answer, "seq", 0), EXTERIA_OK);
    return answer;
}

static exteria_status count_visit(void *ctx, int64_t id, const exteria_tl_value *v) {
    (void)id;
    (void)v;
    ++*(int *)ctx;
    return EXTERIA_OK;
}

int main(void) {
    exteria_store *store = NULL;
    exteria_updates u;
    char path[] = "/tmp/exteria-notify-updates-XXXXXX";
    int fd = mkstemp(path);
    exteria_status status;
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    exteria_arena_init(&a, 16u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_store_open(&store, path, 123), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_init(&u, store, 123), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_state(&u, state(10, 5, 2)), EXTERIA_OK);
    status = exteria_updates_apply(&u, exceptions_answer(0));
    fprintf(stderr, "without chats: %d\n", (int)status);
    status = exteria_updates_apply(&u, exceptions_answer(1));
    fprintf(stderr, "apply status %d, needs_difference %d, global_gap %d, channels %u\n", (int)status, u.needs_difference, u.global_gap, (unsigned)u.channel_count);
    /* a list of settings is no part of the sequence of updates: it must not open a gap or fail */
    CHECK_EQ_INT(status, EXTERIA_OK);
    CHECK_EQ_INT(u.needs_difference, 0);
    CHECK_EQ_INT((int)u.channel_count, 0);
    /* the list is asked for again and again, and none of it is kept in the journal that nothing reads */
    for (int round = 0; round < 40; ++round) CHECK_EQ_INT(exteria_updates_apply(&u, exceptions_answer(1)), EXTERIA_OK);
    {
        /* a full journal makes room instead of refusing the next update */
        int count = 0;
        CHECK_EQ_INT(exteria_store_begin(store), EXTERIA_OK);
        for (int i = 0; i < 8400; ++i) CHECK_EQ_INT(exteria_store_journal_add(store, obj("boolTrue")), EXTERIA_OK);
        CHECK_EQ_INT(exteria_store_commit(store), EXTERIA_OK);
        CHECK_EQ_INT(exteria_store_journal_page(store, 0, 512, count_visit, &count), EXTERIA_OK);
        CHECK_EQ_INT(exteria_store_begin(store), EXTERIA_OK);
        CHECK_EQ_INT(exteria_store_journal_add(store, obj("boolTrue")), EXTERIA_OK);
        CHECK_EQ_INT(exteria_store_commit(store), EXTERIA_OK);
        CHECK(count > 0);
    }
    exteria_arena_free(&a);
    exteria_store_close(store);
    unlink(path);
    return test_finish("test_notify_updates");
}
