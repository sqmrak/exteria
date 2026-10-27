#include "exteria_tl_ids.h"
#include "exteria_typing.h"
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

static exteria_tl_value *peer_user(int64_t id) {
    exteria_tl_value *p = obj("peerUser");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, p, "user_id", id), EXTERIA_OK);
    return p;
}

static void person_in_a_chat(void) {
    static const struct {
        const char *action;
        exteria_typing_action expected;
    } actions[] = {
        {"sendMessageTypingAction", EXTERIA_TYPING_TEXT},
        {"sendMessageRecordAudioAction", EXTERIA_TYPING_VOICE},
        {"sendMessageRecordRoundAction", EXTERIA_TYPING_VOICE},
        {"sendMessageUploadPhotoAction", EXTERIA_TYPING_PHOTO},
        {"sendMessageRecordVideoAction", EXTERIA_TYPING_VIDEO},
        {"sendMessageUploadDocumentAction", EXTERIA_TYPING_FILE},
        {"sendMessageChooseStickerAction", EXTERIA_TYPING_STICKER},
        {"sendMessageGamePlayAction", EXTERIA_TYPING_OTHER},
        {"sendMessageCancelAction", EXTERIA_TYPING_CANCEL},
    };
    size_t i;
    for (i = 0; i < sizeof(actions) / sizeof(actions[0]); ++i) {
        exteria_tl_value *update = obj("updateUserTyping");
        exteria_typing t;
        CHECK_EQ_INT(exteria_tl_set_i64(&arena, update, "user_id", 777), EXTERIA_OK);
        set(update, "action", obj(actions[i].action));
        CHECK_EQ_INT(exteria_typing_read(update, &t), 1);
        CHECK_EQ_INT(t.peer_kind, 1);
        CHECK_EQ_INT(t.peer_id, 777);
        CHECK_EQ_INT(t.user_id, 777);
        CHECK_EQ_INT(t.top_message, 0);
        CHECK_EQ_INT(t.action, actions[i].expected);
    }
}

static void member_of_a_group(void) {
    exteria_tl_value *update = obj("updateChatUserTyping");
    exteria_typing t;
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, update, "chat_id", 4242), EXTERIA_OK);
    set(update, "from_id", peer_user(555));
    set(update, "action", obj("sendMessageTypingAction"));
    CHECK_EQ_INT(exteria_typing_read(update, &t), 1);
    CHECK_EQ_INT(t.peer_kind, 2);
    CHECK_EQ_INT(t.peer_id, 4242);
    CHECK_EQ_INT(t.user_id, 555);
    CHECK_EQ_INT(t.action, EXTERIA_TYPING_TEXT);

    /* a sender that is not a user (a channel posting as itself) leaves the person unknown, and the action still counts */
    update = obj("updateChatUserTyping");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, update, "chat_id", 4242), EXTERIA_OK);
    {
        exteria_tl_value *channel = obj("peerChannel");
        CHECK_EQ_INT(exteria_tl_set_i64(&arena, channel, "channel_id", 9), EXTERIA_OK);
        set(update, "from_id", channel);
    }
    set(update, "action", obj("sendMessageTypingAction"));
    CHECK_EQ_INT(exteria_typing_read(update, &t), 1);
    CHECK_EQ_INT(t.user_id, 0);
}

static void member_of_a_supergroup_topic(void) {
    exteria_tl_value *update = obj("updateChannelUserTyping");
    exteria_typing t;
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, update, "channel_id", 1234567), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, update, "top_msg_id", 88), EXTERIA_OK);
    set(update, "from_id", peer_user(31));
    set(update, "action", obj("sendMessageRecordAudioAction"));
    CHECK_EQ_INT(exteria_typing_read(update, &t), 1);
    CHECK_EQ_INT(t.peer_kind, 3);
    CHECK_EQ_INT(t.peer_id, 1234567);
    CHECK_EQ_INT(t.user_id, 31);
    CHECK_EQ_INT(t.top_message, 88);
    CHECK_EQ_INT(t.action, EXTERIA_TYPING_VOICE);
}

static void anything_else_is_ignored(void) {
    exteria_typing t;
    exteria_tl_value *update = obj("updateUserTyping");
    memset(&t, 0xaa, sizeof(t));
    CHECK_EQ_INT(exteria_typing_read(NULL, &t), 0);
    CHECK_EQ_INT(t.peer_kind, 0);
    CHECK_EQ_INT(exteria_typing_read(update, NULL), 0);
    /* no action, no user */
    CHECK_EQ_INT(exteria_typing_read(update, &t), 0);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, update, "user_id", 0), EXTERIA_OK);
    set(update, "action", obj("sendMessageTypingAction"));
    CHECK_EQ_INT(exteria_typing_read(update, &t), 0);
    CHECK_EQ_INT(exteria_typing_read(obj("updateUserStatus"), &t), 0);
    CHECK_EQ_INT(exteria_typing_read(obj("boolTrue"), &t), 0);
    /* an action of a layer this app does not know shows nothing, but the update is still a typing one */
    update = obj("updateUserTyping");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, update, "user_id", 5), EXTERIA_OK);
    set(update, "action", obj("sendMessageStopDraftAction"));
    CHECK_EQ_INT(exteria_typing_read(update, &t), 1);
    CHECK_EQ_INT(t.action, EXTERIA_TYPING_CANCEL);
}

int main(void) {
    exteria_arena_init(&arena, 1u << 20);
    person_in_a_chat();
    member_of_a_group();
    member_of_a_supergroup_topic();
    anything_else_is_ignored();
    exteria_arena_free(&arena);
    return test_finish("test_typing");
}
