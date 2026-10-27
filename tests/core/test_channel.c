#include "test_util.h"
#include "exteria_channel.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set_i32(exteria_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, f, x), EXTERIA_OK); }
static void set_i64(exteria_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, f, x), EXTERIA_OK); }
static void set_str(exteria_tl_value *v, const char *f, const char *x) { CHECK_EQ_INT(exteria_tl_set_str(&arena, v, f, x), EXTERIA_OK); }
static void set_flag(exteria_tl_value *v, const char *f) { CHECK_EQ_INT(exteria_tl_set_flag(v, f), EXTERIA_OK); }
static void set(exteria_tl_value *v, const char *f, exteria_tl_value *x) { CHECK_EQ_INT(exteria_tl_set(v, f, x), EXTERIA_OK); }

static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *v = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(v, i, items[i]), EXTERIA_OK);
    return v;
}

static exteria_tl_value *channel(int64_t id, const char *title, int megagroup) {
    exteria_tl_value *c = obj("channel"), *photo = obj("chatPhoto");
    set_i64(c, "id", id);
    set_i64(c, "access_hash", id * 7);
    set_str(c, "title", title);
    set_i64(photo, "photo_id", id + 1000);
    set_i32(photo, "dc_id", 2);
    set(c, "photo", photo);
    if (megagroup) set_flag(c, "megagroup");
    else set_flag(c, "broadcast");
    return c;
}

static exteria_tl_value *answer_for(exteria_tl_value *full, exteria_tl_value **chats, uint32_t n) {
    exteria_tl_value *a = obj("messages.chatFull");
    set(a, "full_chat", full);
    set(a, "chats", vec_of(chats, n));
    set(a, "users", exteria_tl_new_vec(&arena, 0));
    return a;
}

static void test_discussion(void) {
    exteria_peer_ref peer = {3, 500, 3500, 0, 0};
    exteria_dialog_row row;
    exteria_tl_value *request = NULL, *answer = obj("messages.discussionMessage");
    exteria_tl_value *group = channel(600, "discussion", 1), *message = obj("message"), *target = obj("peerChannel");
    exteria_tl_value *messages[1] = {message}, *chats[1] = {group};
    set_i64(target, "channel_id", 600);
    set(message, "peer_id", target);
    set_i32(message, "id", 47);
    set(answer, "messages", vec_of(messages, 1));
    set(answer, "chats", vec_of(chats, 1));
    CHECK_EQ_INT(exteria_discussion_request(&arena, &peer, 12, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getDiscussionMessage);
    CHECK_EQ_INT(exteria_discussion_request(&arena, &peer, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_discussion_parse(answer, 500, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.peer_id, 600);
    CHECK_EQ_INT(row.topic_id, 47);
    CHECK_EQ_INT(row.peer_hash, 4200);
    CHECK_EQ_INT(exteria_discussion_parse(answer, 600, &row), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(row.topic_id, 0);
    CHECK_EQ_INT(exteria_discussion_parse(obj("boolTrue"), 500, &row), EXTERIA_E_MALFORMED);
}

static void test_parse(void) {
    exteria_full_channel full;
    exteria_tl_value *f = obj("channelFull"), *chats[2], *invite = obj("chatInviteExported"), *notify = obj("peerNotifySettings");
    exteria_tl_value *main_channel = channel(500, "samrak", 0), *group = channel(600, "Legacy iOS Community", 1);
    set_i64(f, "id", 500);
    set_str(f, "about", "official channel");
    set_i32(f, "participants_count", 93);
    set_i32(f, "admins_count", 1);
    set_i32(f, "banned_count", 1);
    set_i32(f, "stargifts_count", 4);
    set_i32(f, "pinned_msg_id", 77);
    set_i64(f, "linked_chat_id", 600);
    set_flag(f, "can_view_stats");
    set_flag(f, "stargifts_available");
    set_str(invite, "link", "https://t.me/+abc");
    set(f, "exported_invite", invite);
    set_i32(notify, "mute_until", 5000);
    set(f, "notify_settings", notify);
    set_str(main_channel, "username", "sqmrakdev");
    chats[0] = group;
    chats[1] = main_channel;
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 2), 500, 1000, &full), EXTERIA_OK);
    CHECK(!strcmp(full.dialog.title, "samrak"));
    CHECK_EQ_INT(full.dialog.kind, EXTERIA_DIALOG_CHANNEL);
    CHECK_EQ_INT(full.membership_known, 1);
    CHECK_EQ_INT(full.dialog.peer_hash, 3500);
    CHECK_EQ_INT(full.dialog.photo.photo_id, 1500);
    CHECK_EQ_INT(full.megagroup, 0);
    CHECK(!strcmp(full.username, "sqmrakdev"));
    CHECK(!strcmp(full.about, "official channel"));
    CHECK(!strcmp(full.link, "https://t.me/+abc"));
    CHECK_EQ_INT(full.participants, 93);
    CHECK_EQ_INT(full.admins, 1);
    CHECK_EQ_INT(full.banned, 1);
    CHECK_EQ_INT(full.gifts, 4);
    CHECK_EQ_INT(full.pinned_message, 77);
    CHECK_EQ_INT(full.can_view_stats, 1);
    CHECK_EQ_INT(full.gifts_available, 1);
    CHECK_EQ_INT(full.muted, 1);
    CHECK_EQ_INT(full.has_linked, 1);
    CHECK(!strcmp(full.linked.title, "Legacy iOS Community"));
    CHECK_EQ_INT(full.linked.kind, EXTERIA_DIALOG_GROUP);
    CHECK_EQ_INT(full.linked.peer_id, 600);
    set_flag(main_channel, "min");
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 2), 500, 1000, &full), EXTERIA_OK);
    CHECK_EQ_INT(full.membership_known, 0);
    /* a mute that has run out does not count */
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 2), 500, 6000, &full), EXTERIA_OK);
    CHECK_EQ_INT(full.muted, 0);
    /* a linked chat the answer does not carry is left out */
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats + 1, 1), 500, 1000, &full), EXTERIA_OK);
    CHECK_EQ_INT(full.has_linked, 0);
}

static void test_username_list(void) {
    exteria_full_channel full;
    exteria_tl_value *f = obj("channelFull"), *c = channel(700, "multi", 0), *names[2], *a = obj("username"), *b = obj("username");
    exteria_tl_value *chats[1];
    set_i64(f, "id", 700);
    set_str(f, "about", "");
    set_str(a, "username", "dormant");
    set_str(b, "username", "live");
    set_flag(b, "active");
    names[0] = a;
    names[1] = b;
    set(c, "usernames", vec_of(names, 2));
    chats[0] = c;
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 1), 700, 0, &full), EXTERIA_OK);
    CHECK(!strcmp(full.username, "live"));
}

static void test_malformed(void) {
    exteria_full_channel full;
    exteria_tl_value *f = obj("channelFull"), *chats[1];
    set_i64(f, "id", 800);
    chats[0] = channel(801, "other", 0);
    /* the channel the answer is about must be among its chats */
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 1), 800, 0, &full), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(full.participants, 0);
    CHECK_EQ_INT(exteria_full_channel_parse(obj("boolTrue"), 800, 0, &full), EXTERIA_E_MALFORMED);
    /* a basic group's full chat is not a channel's */
    chats[0] = channel(800, "real", 0);
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(obj("chatFull"), chats, 1), 800, 0, &full), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 1), 0, 0, &full), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 1), 800, 0, NULL), EXTERIA_E_ARG);
}

static void test_requests(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref ok = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0}, user = {1, 5, 7, 0, 0};
    CHECK_EQ_INT(exteria_full_channel_request(&arena, &ok, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_getFullChannel);
    CHECK_EQ_INT(exteria_full_channel_request(&arena, &nohash, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_full_channel_request(&arena, &user, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_full_channel_request(&arena, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_full_channel_request(&arena, &ok, NULL), EXTERIA_E_ARG);
}

static void test_join(void) {
    exteria_tl_value *request = NULL, *answer;
    exteria_peer_ref ok = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0}, group = {2, 500, 7, 0, 0};
    exteria_writer wire;
    const exteria_tl_value *input;
    int64_t id = 0, hash = 0;
    CHECK_EQ_INT(exteria_channel_join_request(&arena, &ok, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_joinChannel);
    input = exteria_tl_get(request, "channel");
    CHECK(exteria_tl_is(input, EXTERIA_TL_ID_inputChannel));
    CHECK_EQ_INT(exteria_tl_get_i64(input, "channel_id", &id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i64(input, "access_hash", &hash), EXTERIA_OK);
    CHECK_EQ_INT(id, 500);
    CHECK_EQ_INT(hash, 7);
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    /* a channel needs its access hash, and a basic group is not a channel */
    CHECK_EQ_INT(exteria_channel_join_request(&arena, &nohash, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_channel_join_request(&arena, &group, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_join_request(&arena, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_join_request(&arena, &ok, NULL), EXTERIA_E_ARG);

    answer = obj("messages.chatInviteJoinResultOk");
    CHECK_EQ_INT(exteria_channel_join_parse(answer), EXTERIA_OK);
    CHECK_EQ_INT(exteria_channel_join_parse(obj("messages.chatInviteJoinResultWebView")), EXTERIA_E_UNSUPPORTED);
    /* the old answer of this call was a bare Updates, and anything else is not an answer to it */
    CHECK_EQ_INT(exteria_channel_join_parse(obj("updates")), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_channel_join_parse(obj("boolTrue")), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_channel_join_parse(NULL), EXTERIA_E_MALFORMED);
}

static void test_sender_channel(void) {
    exteria_peer_ref group = {3, INT64_C(4294967300), 77, 0, 0};
    exteria_tl_value *request = NULL;
    exteria_writer wire;
    CHECK_EQ_INT(exteria_channel_from_message_request(&arena, &group, 12, INT64_C(4294967400), &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_channels_getChannels));
    const exteria_tl_value *list = exteria_tl_get(request, "id");
    CHECK(list && list->kind == EXTERIA_TL_V_VEC && list->u.vec.count == 1);
    CHECK(exteria_tl_is(list->u.vec.items[0], EXTERIA_TL_ID_inputChannelFromMessage));
    int64_t id = 0;
    CHECK_EQ_INT(exteria_tl_get_i64(list->u.vec.items[0], "channel_id", &id), EXTERIA_OK);
    CHECK_EQ_INT(id, INT64_C(4294967400));
    exteria_writer_init(&wire, 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_channel_from_message_request(&arena, &group, 0, 8, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_channel_from_message_request(&arena, &group, 12, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_from_message_request(&arena, NULL, 12, 8, &request), EXTERIA_E_ARG);
}


static exteria_tl_value *user_obj(int64_t id, const char *name) {
    exteria_tl_value *u = obj("user");
    set_i64(u, "id", id);
    set_i64(u, "access_hash", id * 3);
    set_str(u, "first_name", name);
    return u;
}

static exteria_tl_value *rights_obj(const char **names, int n) {
    exteria_tl_value *r = obj("chatAdminRights");
    int i;
    for (i = 0; i < n; ++i) set_flag(r, names[i]);
    return r;
}

static exteria_tl_value *peer_user(int64_t id) {
    exteria_tl_value *p = obj("peerUser");
    set_i64(p, "user_id", id);
    return p;
}

static void test_rights_and_creator(void) {
    exteria_full_channel full;
    const char *some[] = {"change_info", "post_messages", "ban_users"};
    exteria_tl_value *f = obj("channelFull"), *c = channel(900, "mine", 0), *chats[1];
    set_i64(f, "id", 900);
    set_str(f, "about", "");
    chats[0] = c;
    /* a plain member holds nothing */
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 1), 900, 0, &full), EXTERIA_OK);
    CHECK_EQ_INT(full.admin_rights, 0);
    CHECK_EQ_INT(full.creator, 0);
    /* an admin holds the rights of its admin_rights object */
    set(c, "admin_rights", rights_obj(some, 3));
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 1), 900, 0, &full), EXTERIA_OK);
    CHECK_EQ_INT(full.admin_rights, EXTERIA_ADMIN_CHANGE_INFO | EXTERIA_ADMIN_POST_MESSAGES | EXTERIA_ADMIN_BAN_USERS);
    /* the creator holds every right, with or without an object, and signatures are read from the channel */
    set_flag(c, "creator");
    set_flag(c, "signatures");
    CHECK_EQ_INT(exteria_full_channel_parse(answer_for(f, chats, 1), 900, 0, &full), EXTERIA_OK);
    CHECK_EQ_INT(full.creator, 1);
    CHECK_EQ_INT(full.signatures, 1);
    CHECK_EQ_INT(full.admin_rights, EXTERIA_ADMIN_ALL);
    CHECK_EQ_INT(exteria_admin_rights_read(NULL), 0);
    CHECK_EQ_INT(exteria_admin_rights_read(obj("chatBannedRights")), 0);
}

static void test_members_parse(void) {
    exteria_channel_member rows[8];
    size_t count = 9;
    int32_t total = -1;
    exteria_tl_value *a = obj("channels.channelParticipants"), *list[7], *users[5];
    const char *some[] = {"post_messages", "add_admins"};
    exteria_tl_value *creator = obj("channelParticipantCreator"), *admin = obj("channelParticipantAdmin"), *plain = obj("channelParticipant");
    exteria_tl_value *banned = obj("channelParticipantBanned"), *left = obj("channelParticipantLeft"), *channel_banned = obj("channelParticipantBanned");
    exteria_tl_value *stranger = obj("channelParticipant");
    set_i64(creator, "user_id", 1);
    set(creator, "admin_rights", rights_obj(some, 0));
    set_str(creator, "rank", "owner");
    set_i64(admin, "user_id", 2);
    set_flag(admin, "can_edit");
    set(admin, "admin_rights", rights_obj(some, 2));
    set_i32(admin, "date", 1700);
    set_i64(plain, "user_id", 3);
    set_i32(plain, "date", 1800);
    set_str(plain, "rank", "member tag");
    set(banned, "peer", peer_user(4));
    set_i32(banned, "date", 1900);
    set(left, "peer", peer_user(5));
    set(channel_banned, "peer", obj("peerChannel"));
    set_i64(stranger, "user_id", 99);
    list[0] = creator; list[1] = admin; list[2] = plain; list[3] = banned; list[4] = left; list[5] = channel_banned; list[6] = stranger;
    users[0] = user_obj(1, "Ann"); users[1] = user_obj(2, "Bob"); users[2] = user_obj(3, "Cid"); users[3] = user_obj(4, "Dee"); users[4] = user_obj(5, "Eve");
    set(a, "participants", vec_of(list, 7));
    set(a, "users", vec_of(users, 5));
    set_i32(a, "count", 321);
    CHECK_EQ_INT(exteria_channel_members_parse(a, rows, 8, &count, &total), EXTERIA_OK);
    /* the one that left, the channel and the user the answer does not describe are not rows */
    CHECK_EQ_INT(count, 4);
    CHECK_EQ_INT(total, 321);
    CHECK_EQ_INT(rows[0].role, EXTERIA_MEMBER_CREATOR);
    CHECK_EQ_INT(rows[0].rights, EXTERIA_ADMIN_ALL);
    CHECK(!strcmp(rows[0].rank, "owner"));
    CHECK(!strcmp(rows[0].person.name, "Ann"));
    CHECK_EQ_INT(rows[1].role, EXTERIA_MEMBER_ADMIN);
    CHECK_EQ_INT(rows[1].can_edit, 1);
    CHECK_EQ_INT(rows[1].rights, EXTERIA_ADMIN_POST_MESSAGES | EXTERIA_ADMIN_ADD_ADMINS);
    CHECK_EQ_INT(rows[1].date, 1700);
    CHECK_EQ_INT(rows[1].person.access_hash, 6);
    CHECK_EQ_INT(rows[2].role, EXTERIA_MEMBER_PLAIN);
    CHECK(!strcmp(rows[2].rank, "member tag"));
    CHECK_EQ_INT(rows[2].can_edit, 0);
    CHECK_EQ_INT(rows[3].role, EXTERIA_MEMBER_BANNED);
    CHECK_EQ_INT(rows[3].person.id, 4);
    CHECK_EQ_INT(rows[3].date, 1900);
    /* more participants than the caller has room for, and an answer of another kind */
    CHECK_EQ_INT(exteria_channel_members_parse(a, rows, 2, &count, &total), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(total, 0);
    CHECK_EQ_INT(exteria_channel_members_parse(obj("boolTrue"), rows, 8, &count, &total), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_channel_members_parse(obj("channels.channelParticipantsNotModified"), rows, 8, &count, &total), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    /* a participant of an unknown kind makes the whole page malformed */
    set(a, "participants", vec_of((exteria_tl_value *[]){obj("channelParticipantsRecent")}, 1));
    CHECK_EQ_INT(exteria_channel_members_parse(a, rows, 8, &count, &total), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_channel_members_parse(NULL, rows, 8, &count, &total), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_members_parse(a, rows, 0, &count, &total), EXTERIA_E_ARG);
}

static void test_members_request(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref ok = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0};
    const exteria_tl_value *filter;
    exteria_writer wire;
    int32_t offset = 0, limit = 0;
    char long_query[EXTERIA_MEMBERS_QUERY_MAX + 8];
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_RECENT, NULL, 50, 25, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_getParticipants);
    filter = exteria_tl_get(request, "filter");
    CHECK(exteria_tl_is(filter, EXTERIA_TL_ID_channelParticipantsRecent));
    CHECK_EQ_INT(exteria_tl_get_i32(request, "offset", &offset), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "limit", &limit), EXTERIA_OK);
    CHECK_EQ_INT(offset, 50);
    CHECK_EQ_INT(limit, 25);
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    /* a query turns the recent list into a search, and empty text does not */
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_RECENT, "ann", 0, 50, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "filter"), EXTERIA_TL_ID_channelParticipantsSearch));
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_RECENT, "", 0, 50, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "filter"), EXTERIA_TL_ID_channelParticipantsRecent));
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_ADMINS, "ignored", 0, 50, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "filter"), EXTERIA_TL_ID_channelParticipantsAdmins));
    /* the blacklist always carries a query, empty for the whole list */
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_KICKED, NULL, 0, 50, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "filter"), EXTERIA_TL_ID_channelParticipantsKicked));
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    /* bounds: offset, limit, query length, channel and list */
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_RECENT, NULL, -1, 50, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_RECENT, NULL, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_RECENT, NULL, 0, EXTERIA_MEMBERS_MAX + 1, &request), EXTERIA_E_ARG);
    memset(long_query, 'a', sizeof(long_query) - 1);
    long_query[sizeof(long_query) - 1] = 0;
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_RECENT, long_query, 0, 50, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &nohash, EXTERIA_MEMBERS_RECENT, NULL, 0, 50, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, (exteria_member_list)9, NULL, 0, 50, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_members_request(&arena, &ok, EXTERIA_MEMBERS_RECENT, NULL, 0, 50, NULL), EXTERIA_E_ARG);
}

static void test_admin_and_ban(void) {
    exteria_tl_value *request = NULL;
    const exteria_tl_value *rights, *participant;
    exteria_peer_ref ok = {3, 500, 7, 0, 0}, user = {1, 42, 9, 0, 0}, nohash_user = {1, 42, 0, 0, 0}, channel_peer = {3, 42, 9, 0, 0};
    const uint8_t *bytes;
    size_t len = 0;
    exteria_writer wire;
    CHECK_EQ_INT(exteria_channel_admin_request(&arena, &ok, &user, EXTERIA_ADMIN_CHANGE_INFO | EXTERIA_ADMIN_BAN_USERS, "editor", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_editAdmin);
    CHECK(exteria_tl_is(exteria_tl_get(request, "user_id"), EXTERIA_TL_ID_inputUser));
    rights = exteria_tl_get(request, "admin_rights");
    CHECK(exteria_tl_has(rights, "change_info"));
    CHECK(exteria_tl_has(rights, "ban_users"));
    CHECK(!exteria_tl_has(rights, "post_messages"));
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "rank", &bytes, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 6);
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    /* no rights at all dismisses the admin, and no rank leaves the field out */
    CHECK_EQ_INT(exteria_channel_admin_request(&arena, &ok, &user, 0, NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_admin_rights_read(exteria_tl_get(request, "admin_rights")), 0);
    CHECK(!exteria_tl_has(request, "rank"));
    CHECK_EQ_INT(exteria_channel_admin_request(&arena, &ok, &user, 0x8000u, NULL, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_channel_admin_request(&arena, &ok, &nohash_user, 1, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_admin_request(&arena, &ok, &channel_peer, 1, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_admin_request(&arena, &ok, NULL, 1, NULL, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_channel_ban_request(&arena, &ok, &user, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_editBanned);
    participant = exteria_tl_get(request, "participant");
    CHECK(exteria_tl_is(participant, EXTERIA_TL_ID_inputPeerUser));
    rights = exteria_tl_get(request, "banned_rights");
    CHECK(exteria_tl_has(rights, "view_messages"));
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_channel_ban_request(&arena, &ok, &user, 0, &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(exteria_tl_get(request, "banned_rights"), "view_messages"));
    CHECK_EQ_INT(exteria_channel_ban_request(&arena, &ok, &nohash_user, 1, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_channel_ban_request(&arena, &ok, &channel_peer, 1, &request), EXTERIA_E_ARG);
}

static void test_invite(void) {
    exteria_tl_value *request = NULL, *answer, *missing;
    exteria_peer_ref ok = {3, 500, 7, 0, 0}, users[2] = {{1, 11, 21, 0, 0}, {1, 12, 22, 0, 0}}, nohash = {1, 13, 0, 0, 0}, group = {2, 500, 7, 0, 0};
    exteria_writer wire;
    size_t count = 9;
    CHECK_EQ_INT(exteria_channel_invite_request(&arena, &ok, users, 2, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_inviteToChannel);
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_channel_invite_request(&arena, &ok, users, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_channel_invite_request(&arena, &ok, users, EXTERIA_INVITE_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_invite_request(&arena, &ok, &nohash, 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_invite_request(&arena, &group, users, 1, &request), EXTERIA_E_ARG);
    answer = obj("messages.invitedUsers");
    missing = exteria_tl_new_vec(&arena, 1);
    CHECK(answer && missing);
    CHECK_EQ_INT(exteria_tl_vec_set(missing, 0, obj("missingInvitee")), EXTERIA_OK);
    set(answer, "missing_invitees", missing);
    CHECK_EQ_INT(exteria_channel_invite_missing(answer, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 1);
    CHECK_EQ_INT(exteria_channel_invite_missing(obj("inputPeerEmpty"), &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT((int)count, 0);
}

static void test_settings_requests(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref ok = {3, 500, 7, 0, 0}, group = {2, 500, 7, 0, 0};
    exteria_writer wire;
    char huge[EXTERIA_ABOUT_MAX + 4];
    CHECK_EQ_INT(exteria_channel_title_request(&arena, &ok, "New name", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_editTitle);
    CHECK_EQ_INT(exteria_channel_title_request(&arena, &ok, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_channel_title_request(&arena, &ok, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_about_request(&arena, &ok, "about text", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_editChatAbout);
    CHECK(exteria_tl_is(exteria_tl_get(request, "peer"), EXTERIA_TL_ID_inputPeerChannel));
    exteria_writer_init(&wire, 512);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    /* an empty description is how it is cleared */
    CHECK_EQ_INT(exteria_channel_about_request(&arena, &ok, "", &request), EXTERIA_OK);
    memset(huge, 'x', sizeof(huge) - 1);
    huge[sizeof(huge) - 1] = 0;
    CHECK_EQ_INT(exteria_channel_about_request(&arena, &ok, huge, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_about_request(&arena, &group, "x", &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_channel_username_request(&arena, &ok, "my_channel1", 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_updateUsername);
    CHECK_EQ_INT(exteria_channel_username_request(&arena, &ok, "my_channel1", 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_checkUsername);
    CHECK_EQ_INT(exteria_channel_username_request(&arena, &ok, "", 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_channel_username_request(&arena, &ok, "", 1, &request), EXTERIA_E_ARG);
    /* a name with a space, a dot, a slash or a shell character is not sent */
    CHECK_EQ_INT(exteria_channel_username_request(&arena, &ok, "my channel", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_username_request(&arena, &ok, "a.b", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_username_request(&arena, &ok, "../x", 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);

    CHECK_EQ_INT(exteria_channel_signatures_request(&arena, &ok, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_toggleSignatures);
    CHECK(exteria_tl_has(request, "signatures_enabled"));
    CHECK_EQ_INT(exteria_channel_signatures_request(&arena, &ok, 0, &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(request, "signatures_enabled"));
    CHECK_EQ_INT(exteria_channel_signatures_request(&arena, &group, 1, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_channel_bool_parse(obj("boolTrue")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_channel_bool_parse(obj("boolFalse")), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_channel_bool_parse(obj("updates")), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_channel_bool_parse(NULL), EXTERIA_E_MALFORMED);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_parse();
    test_discussion();
    test_username_list();
    test_malformed();
    test_requests();
    test_join();
    test_sender_channel();
    test_rights_and_creator();
    test_members_parse();
    test_members_request();
    test_admin_and_ban();
    test_invite();
    test_settings_requests();
    exteria_arena_free(&arena);
    return test_finish("test_channel");
}
