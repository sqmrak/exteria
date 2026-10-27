#include "test_util.h"
#include "exteria_drafts.h"
#include "exteria_tl_ids.h"
#include "exteria_updates.h"

#include <unistd.h>

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

static exteria_tl_value *draft_update(const char *text) {
    exteria_tl_value *update = obj("updateDraftMessage"), *peer = obj("peerUser"), *draft = obj("draftMessage"), *short_update = obj("updateShort");
    CHECK_EQ_INT(exteria_tl_set_i64(&a, peer, "user_id", 77), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(update, "peer", peer), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&a, draft, "message", text), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, draft, "date", 500), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(update, "draft", draft), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(short_update, "update", update), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, short_update, "date", 500), EXTERIA_OK);
    return short_update;
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
    char path[] = "/tmp/exteria-draft-updates-XXXXXX";
    int fd = mkstemp(path), count = 0;
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    exteria_arena_init(&a, 1u << 20);
    CHECK_EQ_INT(exteria_store_open(&store, path, 123), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_init(&u, store, 123), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_state(&u, state(10, 5, 2)), EXTERIA_OK);

    /* a draft typed on another phone is no part of the sequence: no gap, no difference, and nothing for the journal that nothing reads */
    for (int round = 0; round < 50; ++round) CHECK_EQ_INT(exteria_updates_apply(&u, draft_update("typed elsewhere")), EXTERIA_OK);
    CHECK_EQ_INT(u.needs_difference, 0);
    CHECK_EQ_INT(u.global_gap, 0);
    CHECK_EQ_INT(exteria_store_journal_page(store, 0, 512, count_visit, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_updates_quiet(draft_update("x")), 1);

    /* and what the client hands to the app reads back from the same update */
    {
        const exteria_tl_value *update = exteria_tl_get(draft_update("hello"), "update"), *body = NULL;
        exteria_draft *row = malloc(sizeof(*row));
        int32_t kind = 0, top = 0;
        int64_t peer = 0;
        CHECK(row != NULL);
        CHECK_EQ_INT(exteria_draft_update_read(update, &kind, &peer, &top, &body), EXTERIA_OK);
        CHECK_EQ_INT(exteria_draft_read(body, top, row), EXTERIA_OK);
        CHECK(strcmp(row->text, "hello") == 0);
        CHECK_EQ_INT(row->date, 500);
        free(row);
    }
    exteria_arena_free(&a);
    exteria_store_close(store);
    unlink(path);
    return test_finish("test_draft_updates");
}
