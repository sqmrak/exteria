#include "test_util.h"
#include "exteria_updates.h"

/* a presence or typing update must not wake the notifier's look at the chat list, and anything else must */

static exteria_tl_value *obj(exteria_arena *a, const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(a, name);
    CHECK(v != NULL);
    return v;
}

static exteria_tl_value *container(exteria_arena *a, const char *name, const char *const *items, uint32_t count) {
    exteria_tl_value *v = obj(a, name), *vec = exteria_tl_new_vec(a, count);
    uint32_t i;
    for (i = 0; i < count; ++i) vec->u.vec.items[i] = obj(a, items[i]);
    CHECK_EQ_INT(exteria_tl_set(v, "updates", vec), EXTERIA_OK);
    return v;
}

int main(void) {
    exteria_arena a;
    exteria_tl_value *v;
    const char *status[] = {"updateUserStatus"};
    const char *typing[] = {"updateUserTyping", "updateChatUserTyping", "updateReadHistoryOutbox"};
    const char *mixed[] = {"updateUserStatus", "updateNewMessage"};
    const char *message[] = {"updateNewChannelMessage"};
    const char *read[] = {"updateReadHistoryInbox"};
    exteria_arena_init(&a, 262144);

    v = obj(&a, "updateShort");
    CHECK_EQ_INT(exteria_tl_set(v, "update", obj(&a, "updateUserStatus")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_quiet(v), 1);
    v = obj(&a, "updateShort");
    CHECK_EQ_INT(exteria_tl_set(v, "update", obj(&a, "updateNewMessage")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_quiet(v), 0);
    v = obj(&a, "updateShort");
    CHECK_EQ_INT(exteria_tl_set(v, "update", obj(&a, "updateReadHistoryInbox")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_quiet(v), 0);

    CHECK_EQ_INT(exteria_updates_quiet(container(&a, "updates", status, 1)), 1);
    CHECK_EQ_INT(exteria_updates_quiet(container(&a, "updatesCombined", typing, 3)), 1);
    CHECK_EQ_INT(exteria_updates_quiet(container(&a, "updates", mixed, 2)), 0);
    CHECK_EQ_INT(exteria_updates_quiet(container(&a, "updates", message, 1)), 0);
    CHECK_EQ_INT(exteria_updates_quiet(container(&a, "updates", read, 1)), 0);
    /* an empty container says nothing, so it is looked at */
    CHECK_EQ_INT(exteria_updates_quiet(container(&a, "updates", status, 0)), 0);

    /* a short message and a gap marker are never quiet */
    CHECK_EQ_INT(exteria_updates_quiet(obj(&a, "updateShortMessage")), 0);
    CHECK_EQ_INT(exteria_updates_quiet(obj(&a, "updatesTooLong")), 0);
    CHECK_EQ_INT(exteria_updates_quiet(NULL), 0);

    exteria_arena_free(&a);
    return test_finish("test_updates_quiet");
}
