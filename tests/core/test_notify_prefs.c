#include "test_util.h"
#include "exteria_notify_prefs.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void set(exteria_tl_value *v, const char *f, exteria_tl_value *x) { CHECK_EQ_INT(exteria_tl_set(v, f, x), EXTERIA_OK); }
static void set_i32(exteria_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, f, x), EXTERIA_OK); }
static void set_i64(exteria_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, f, x), EXTERIA_OK); }
static void set_str(exteria_tl_value *v, const char *f, const char *x) { CHECK_EQ_INT(exteria_tl_set_str(&arena, v, f, x), EXTERIA_OK); }

static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *v = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(v != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(v, i, items[i]), EXTERIA_OK);
    return v;
}

static void read_all_fields(void) {
    exteria_peer_notify n;
    exteria_tl_value *s = obj("peerNotifySettings"), *sound = obj("notificationSoundLocal");
    set(s, "show_previews", obj("boolFalse"));
    set(s, "silent", obj("boolTrue"));
    set_i32(s, "mute_until", 1700003600);
    set_str(sound, "title", "Pop");
    set_str(sound, "data", "sound_in.caf");
    set(s, "ios_sound", sound);
    set(s, "stories_muted", obj("boolTrue"));
    set(s, "stories_hide_sender", obj("boolFalse"));
    set(s, "stories_ios_sound", obj("notificationSoundNone"));
    CHECK_EQ_INT(exteria_peer_notify_read(s, &n), EXTERIA_OK);
    CHECK(n.has_mute && n.mute_until == 1700003600);
    CHECK(n.has_previews && n.previews == 0);
    CHECK(n.has_silent && n.silent == 1);
    CHECK(n.has_sound && n.sound.kind == EXTERIA_SOUND_LOCAL);
    CHECK(!strcmp(n.sound.title, "Pop") && !strcmp(n.sound.data, "sound_in.caf"));
    CHECK(n.has_stories_muted && n.stories_muted == 1);
    CHECK(n.has_stories_hide_sender && n.stories_hide_sender == 0);
    CHECK(n.has_stories_sound && n.stories_sound.kind == EXTERIA_SOUND_NONE);
}

static void read_nothing(void) {
    exteria_peer_notify n;
    memset(&n, 0xff, sizeof(n));
    CHECK_EQ_INT(exteria_peer_notify_read(NULL, &n), EXTERIA_OK);
    CHECK(!n.has_mute && !n.has_previews && !n.has_silent && !n.has_sound && !n.has_stories_muted);
    memset(&n, 0xff, sizeof(n));
    CHECK_EQ_INT(exteria_peer_notify_read(obj("peerNotifySettings"), &n), EXTERIA_OK);
    CHECK(!n.has_mute && !n.has_previews && !n.has_sound);
    CHECK_EQ_INT(exteria_peer_notify_read(NULL, NULL), EXTERIA_E_ARG);
    /* the sound of another system is not ours to show */
    {
        exteria_tl_value *s = obj("peerNotifySettings");
        set(s, "android_sound", obj("notificationSoundNone"));
        CHECK_EQ_INT(exteria_peer_notify_read(s, &n), EXTERIA_OK);
        CHECK(!n.has_sound);
    }
}

static void build_only_what_is_set(void) {
    exteria_peer_notify n;
    exteria_tl_value *out = NULL;
    memset(&n, 0, sizeof(n));
    n.has_mute = 1;
    n.mute_until = EXTERIA_NOTIFY_MUTE_FOREVER;
    n.has_previews = 1;
    n.previews = 1;
    n.has_sound = 1;
    n.sound.kind = EXTERIA_SOUND_RINGTONE;
    n.sound.ringtone_id = 777;
    CHECK_EQ_INT(exteria_peer_notify_build(&arena, &n, &out), EXTERIA_OK);
    CHECK(out != NULL);
    CHECK(exteria_tl_has(out, "mute_until") && exteria_tl_has(out, "show_previews") && exteria_tl_has(out, "sound"));
    CHECK(!exteria_tl_has(out, "silent") && !exteria_tl_has(out, "stories_muted") && !exteria_tl_has(out, "stories_sound"));
    {
        int64_t id = 0;
        int32_t until = 0;
        CHECK_EQ_INT(exteria_tl_get_i32(out, "mute_until", &until), EXTERIA_OK);
        CHECK_EQ_INT(until, EXTERIA_NOTIFY_MUTE_FOREVER);
        CHECK(exteria_tl_is(exteria_tl_get(out, "sound"), EXTERIA_TL_ID_notificationSoundRingtone));
        CHECK_EQ_INT(exteria_tl_get_i64(exteria_tl_get(out, "sound"), "id", &id), EXTERIA_OK);
        CHECK_EQ_INT((int)id, 777);
        CHECK(exteria_tl_is(exteria_tl_get(out, "show_previews"), EXTERIA_TL_ID_boolTrue));
    }
    /* local tones keep their name and file */
    memset(&n, 0, sizeof(n));
    n.has_sound = 1;
    n.sound.kind = EXTERIA_SOUND_LOCAL;
    snprintf(n.sound.title, sizeof(n.sound.title), "Out");
    snprintf(n.sound.data, sizeof(n.sound.data), "sound_out.caf");
    CHECK_EQ_INT(exteria_peer_notify_build(&arena, &n, &out), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(out, "sound"), EXTERIA_TL_ID_notificationSoundLocal));
    CHECK_EQ_INT(exteria_peer_notify_build(NULL, &n, &out), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_peer_notify_build(&arena, NULL, &out), EXTERIA_E_ARG);
    CHECK(out == NULL);
}

static void round_trip(void) {
    exteria_peer_notify a, b;
    exteria_tl_value *built = NULL, *wire;
    memset(&a, 0, sizeof(a));
    a.has_silent = 1;
    a.silent = 1;
    a.has_stories_hide_sender = 1;
    a.stories_hide_sender = 1;
    a.has_stories_sound = 1;
    a.stories_sound.kind = EXTERIA_SOUND_DEFAULT;
    CHECK_EQ_INT(exteria_peer_notify_build(&arena, &a, &built), EXTERIA_OK);
    /* the input settings carry the sound as `sound`; the output ones as `ios_sound`, so the round trip goes through a copy with that name */
    wire = obj("peerNotifySettings");
    set(wire, "silent", (exteria_tl_value *)exteria_tl_get(built, "silent"));
    set(wire, "stories_hide_sender", (exteria_tl_value *)exteria_tl_get(built, "stories_hide_sender"));
    set(wire, "stories_ios_sound", (exteria_tl_value *)exteria_tl_get(built, "stories_sound"));
    CHECK_EQ_INT(exteria_peer_notify_read(wire, &b), EXTERIA_OK);
    CHECK(b.has_silent && b.silent == 1);
    CHECK(b.has_stories_hide_sender && b.stories_hide_sender == 1);
    CHECK(b.has_stories_sound && b.stories_sound.kind == EXTERIA_SOUND_DEFAULT);
    CHECK(!b.has_mute && !b.has_sound);
}

static void requests(void) {
    exteria_tl_value *r = NULL;
    exteria_peer_notify n;
    exteria_peer_ref peer;
    memset(&n, 0, sizeof(n));
    n.has_mute = 1;
    CHECK_EQ_INT(exteria_notify_scope_request(&arena, EXTERIA_SCOPE_CHATS, &r), EXTERIA_OK);
    CHECK(exteria_tl_is(r, EXTERIA_TL_ID_account_getNotifySettings));
    CHECK(exteria_tl_is(exteria_tl_get(r, "peer"), EXTERIA_TL_ID_inputNotifyChats));
    CHECK_EQ_INT(exteria_notify_scope_request(&arena, EXTERIA_SCOPE_COUNT, &r), EXTERIA_E_ARG);
    CHECK(r == NULL);

    CHECK_EQ_INT(exteria_notify_update_request(&arena, 1, EXTERIA_SCOPE_BROADCASTS, NULL, &n, &r), EXTERIA_OK);
    CHECK(exteria_tl_is(r, EXTERIA_TL_ID_account_updateNotifySettings));
    CHECK(exteria_tl_is(exteria_tl_get(r, "peer"), EXTERIA_TL_ID_inputNotifyBroadcasts));
    memset(&peer, 0, sizeof(peer));
    peer.kind = 1;
    peer.id = 55;
    peer.access_hash = 99;
    CHECK_EQ_INT(exteria_notify_update_request(&arena, 0, EXTERIA_SCOPE_USERS, &peer, &n, &r), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(r, "peer"), EXTERIA_TL_ID_inputNotifyPeer));
    peer.kind = 3;
    peer.id = 66;
    peer.topic_id = 4;
    CHECK_EQ_INT(exteria_notify_update_request(&arena, 0, EXTERIA_SCOPE_USERS, &peer, &n, &r), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(r, "peer"), EXTERIA_TL_ID_inputNotifyForumTopic));
    CHECK_EQ_INT(exteria_notify_update_request(&arena, 0, EXTERIA_SCOPE_USERS, NULL, &n, &r), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_notify_update_request(&arena, 1, EXTERIA_SCOPE_USERS, NULL, NULL, &r), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_notify_peer_request(&arena, &peer, &r), EXTERIA_OK);
    CHECK(exteria_tl_is(r, EXTERIA_TL_ID_account_getNotifySettings));
    CHECK(exteria_tl_is(exteria_tl_get(r, "peer"), EXTERIA_TL_ID_inputNotifyForumTopic));
    CHECK_EQ_INT(exteria_notify_peer_request(&arena, NULL, &r), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_notify_exceptions_request(&arena, 1, 0, &r), EXTERIA_OK);
    CHECK(exteria_tl_has(r, "compare_sound") && !exteria_tl_has(r, "compare_stories"));
    CHECK_EQ_INT(exteria_notify_reset_request(&arena, &r), EXTERIA_OK);
    CHECK(exteria_tl_is(r, EXTERIA_TL_ID_account_resetNotifySettings));
    CHECK_EQ_INT(exteria_notify_signup_request(&arena, 1, &r), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(r, "silent"), EXTERIA_TL_ID_boolTrue));

    CHECK_EQ_INT(exteria_notify_bool_result(obj("boolTrue")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_notify_bool_result(obj("boolFalse")), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_notify_bool_result(obj("user")), EXTERIA_E_MALFORMED);
}

static exteria_tl_value *update(exteria_tl_value *notify, int32_t mute) {
    exteria_tl_value *u = obj("updateNotifySettings"), *s = obj("peerNotifySettings");
    set_i32(s, "mute_until", mute);
    set(u, "peer", notify);
    set(u, "notify_settings", s);
    return u;
}

static void exceptions(void) {
    exteria_tl_value *p1 = obj("peerUser"), *p2 = obj("peerChannel"), *p3 = obj("peerUser"), *topic = obj("notifyForumTopic"), *peer4 = obj("peerChannel");
    exteria_tl_value *n1 = obj("notifyPeer"), *n2 = obj("notifyPeer"), *n3 = obj("notifyPeer"), *kind = obj("notifyUsers");
    exteria_tl_value *items[5], *users[1], *chats[1], *answer = obj("updates"), *u = obj("user"), *c = obj("channel");
    exteria_notify_exception list[8];
    size_t count = 99;
    set_i64(p1, "user_id", 7);
    set_i64(p2, "channel_id", 9);
    set_i64(p3, "user_id", 8);
    set_i64(peer4, "channel_id", 9);
    set(n1, "peer", p1);
    set(n2, "peer", p2);
    set(n3, "peer", p3);
    set(topic, "peer", peer4);
    set_i32(topic, "top_msg_id", 3);
    set_i64(u, "id", 7);
    set_str(u, "first_name", "Ann");
    set_i64(u, "access_hash", 70);
    set_i64(c, "id", 9);
    set_str(c, "title", "News");
    set_i64(c, "access_hash", 90);
    items[0] = update(n1, 0);
    items[1] = update(kind, 5);        /* a kind, not a chat: left out */
    items[2] = update(n2, EXTERIA_NOTIFY_MUTE_FOREVER);
    items[3] = update(topic, 5);
    items[4] = update(n3, 0);          /* a user the answer does not carry */
    users[0] = u;
    chats[0] = c;
    set(answer, "updates", vec_of(items, 5));
    set(answer, "users", vec_of(users, 1));
    set(answer, "chats", vec_of(chats, 1));
    CHECK_EQ_INT(exteria_notify_exceptions_parse(answer, 1, list, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 4);
    CHECK_EQ_INT(list[0].peer_kind, 1);
    CHECK_EQ_INT((int)list[0].peer_id, 7);
    CHECK(!strcmp(list[0].title, "Ann"));
    CHECK_EQ_INT((int)list[0].peer_hash, 70);
    CHECK(list[0].settings.has_mute && list[0].settings.mute_until == 0);
    CHECK_EQ_INT(list[1].peer_kind, 3);
    CHECK(!strcmp(list[1].title, "News"));
    CHECK(!list[0].broadcast && list[1].broadcast);
    CHECK_EQ_INT(list[1].settings.mute_until, EXTERIA_NOTIFY_MUTE_FOREVER);
    CHECK(list[2].forum_topic);
    CHECK(list[3].deleted && list[3].title[0] == 0);
    /* a cap cuts the list */
    CHECK_EQ_INT(exteria_notify_exceptions_parse(answer, 1, list, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 2);
    CHECK_EQ_INT(exteria_notify_exceptions_parse(obj("user"), 1, list, 8, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(exteria_notify_exceptions_parse(obj("updatesTooLong"), 1, list, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(exteria_notify_exceptions_parse(answer, 1, NULL, 8, &count), EXTERIA_E_ARG);
}

static void reactions(void) {
    exteria_reaction_notify r, back;
    exteria_tl_value *built = NULL, *body = obj("reactionsNotifySettings");
    memset(&r, 0, sizeof(r));
    r.messages_from = EXTERIA_REACTION_FROM_CONTACTS;
    r.stories_from = EXTERIA_REACTION_FROM_NOBODY;
    r.previews = 0;
    r.sound.kind = EXTERIA_SOUND_NONE;
    CHECK_EQ_INT(exteria_reaction_notify_set_request(&arena, &r, &built), EXTERIA_OK);
    CHECK(exteria_tl_is(built, EXTERIA_TL_ID_account_setReactionsNotifySettings));
    {
        const exteria_tl_value *s = exteria_tl_get(built, "settings");
        CHECK(exteria_tl_is(exteria_tl_get(s, "messages_notify_from"), EXTERIA_TL_ID_reactionNotificationsFromContacts));
        CHECK(!exteria_tl_has(s, "stories_notify_from"));
        CHECK(exteria_tl_is(exteria_tl_get(s, "show_previews"), EXTERIA_TL_ID_boolFalse));
        CHECK(exteria_tl_is(exteria_tl_get(s, "sound"), EXTERIA_TL_ID_notificationSoundNone));
        /* the answer has the same shape as what was sent */
        set(body, "messages_notify_from", (exteria_tl_value *)exteria_tl_get(s, "messages_notify_from"));
        set(body, "show_previews", (exteria_tl_value *)exteria_tl_get(s, "show_previews"));
        set(body, "sound", (exteria_tl_value *)exteria_tl_get(s, "sound"));
    }
    CHECK_EQ_INT(exteria_reaction_notify_read(body, &back), EXTERIA_OK);
    CHECK_EQ_INT(back.messages_from, EXTERIA_REACTION_FROM_CONTACTS);
    CHECK_EQ_INT(back.stories_from, EXTERIA_REACTION_FROM_NOBODY);
    CHECK_EQ_INT(back.previews, 0);
    CHECK_EQ_INT(back.sound.kind, EXTERIA_SOUND_NONE);
    CHECK_EQ_INT(exteria_reaction_notify_read(obj("user"), &back), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_reaction_notify_set_request(&arena, NULL, &built), EXTERIA_E_ARG);
}

static void ringtones(void) {
    exteria_tl_value *d1 = obj("document"), *d2 = obj("documentEmpty"), *a1 = obj("documentAttributeAudio"), *a2 = obj("documentAttributeFilename");
    exteria_tl_value *attrs[2], *docs[2], *answer = obj("account.savedRingtones"), *req = NULL;
    static const uint8_t ref[3] = {1, 2, 3};
    exteria_ringtone_row rows[4];
    size_t count = 99;
    set_i64(d1, "id", 42);
    set_i64(d1, "access_hash", 4242);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, d1, "file_reference", ref, sizeof(ref)), EXTERIA_OK);
    set_i64(d1, "size", 1234);
    set_i32(d1, "dc_id", 2);
    set_str(d1, "mime_type", "audio/mpeg");
    set_i32(a1, "duration", 4);
    set_str(a1, "title", "Chime");
    set_str(a2, "file_name", "chime.mp3");
    attrs[0] = a1;
    attrs[1] = a2;
    set(d1, "attributes", vec_of(attrs, 2));
    docs[0] = d1;
    docs[1] = d2;
    set(answer, "ringtones", vec_of(docs, 2));
    CHECK_EQ_INT(exteria_ringtones_parse(answer, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 1);
    CHECK_EQ_INT((int)rows[0].id, 42);
    CHECK(!strcmp(rows[0].title, "Chime") && !strcmp(rows[0].file_name, "chime.mp3") && !strcmp(rows[0].mime, "audio/mpeg"));
    CHECK_EQ_INT(rows[0].duration, 4);
    CHECK_EQ_INT(rows[0].dc, 2);
    CHECK_EQ_INT(rows[0].file_reference_len, 3);
    CHECK_EQ_INT(exteria_ringtones_parse(obj("account.savedRingtonesNotModified"), rows, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_ringtones_parse(obj("user"), rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_ringtone_unsave_request(&arena, &rows[0], &req), EXTERIA_OK);
    CHECK(exteria_tl_is(req, EXTERIA_TL_ID_account_saveRingtone));
    CHECK(exteria_tl_is(exteria_tl_get(req, "unsave"), EXTERIA_TL_ID_boolTrue));
    rows[0].id = 0;
    CHECK_EQ_INT(exteria_ringtone_unsave_request(&arena, &rows[0], &req), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_ringtones_request(&arena, &req), EXTERIA_OK);
    CHECK(exteria_tl_is(req, EXTERIA_TL_ID_account_getSavedRingtones));
}

static void decisions(void) {
    exteria_notify_rules rules;
    exteria_peer_notify chat;
    exteria_notify_decision d;
    exteria_notify_rules_init(&rules);
    memset(&chat, 0, sizeof(chat));
    exteria_notify_decide(&rules, EXTERIA_SCOPE_USERS, &chat, 100, &d);
    CHECK(d.notify && d.previews && d.sound.kind == EXTERIA_SOUND_DEFAULT);
    exteria_notify_decide(&rules, EXTERIA_SCOPE_USERS, NULL, 100, &d);
    CHECK(d.notify);
    /* a kind muted for an hour, then an hour later */
    rules.scope[EXTERIA_SCOPE_CHATS].has_mute = 1;
    rules.scope[EXTERIA_SCOPE_CHATS].mute_until = 200;
    exteria_notify_decide(&rules, EXTERIA_SCOPE_CHATS, &chat, 100, &d);
    CHECK(!d.notify);
    exteria_notify_decide(&rules, EXTERIA_SCOPE_CHATS, &chat, 200, &d);
    CHECK(d.notify);
    exteria_notify_decide(&rules, EXTERIA_SCOPE_COUNT, &chat, 100, &d);
    CHECK(!d.notify);
    exteria_notify_decide(NULL, EXTERIA_SCOPE_USERS, &chat, 100, &d);
    CHECK(!d.notify);

    CHECK_EQ_INT(exteria_notify_scope_of(1, 0), EXTERIA_SCOPE_USERS);
    CHECK_EQ_INT(exteria_notify_scope_of(2, 0), EXTERIA_SCOPE_CHATS);
    CHECK_EQ_INT(exteria_notify_scope_of(3, 0), EXTERIA_SCOPE_CHATS);
    CHECK_EQ_INT(exteria_notify_scope_of(3, 1), EXTERIA_SCOPE_BROADCASTS);

    CHECK_EQ_INT(exteria_notify_mute_state(0, 1000), 0);
    CHECK_EQ_INT(exteria_notify_mute_state(1000, 1000), 0);
    CHECK_EQ_INT(exteria_notify_mute_state(1000 + 3600, 1000), 2);
    CHECK_EQ_INT(exteria_notify_mute_state(1000 + 365 * 24 * 3600, 1000), 1);
    CHECK_EQ_INT(exteria_notify_mute_state(EXTERIA_NOTIFY_MUTE_FOREVER, 1000), 1);
}

int main(void) {
    exteria_arena_init(&arena, 1 << 20);
    read_all_fields();
    read_nothing();
    build_only_what_is_set();
    round_trip();
    requests();
    exceptions();
    reactions();
    ringtones();
    decisions();
    exteria_arena_free(&arena);
    return test_finish("test_notify_prefs");
}
