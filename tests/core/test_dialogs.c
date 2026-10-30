#include <string.h>
#include "test_util.h"
#include "exteria_dialogs.h"
#include "exteria_messages.h"
#include "exteria_tl_ids.h"

#define SELF 100

static exteria_arena arena;

static void test_noforwards_peer(void) {
    exteria_dialog_row row;
    exteria_tl_value *chat = exteria_tl_new_obj(&arena, "chat");
    exteria_tl_value *list = exteria_tl_new_vec(&arena, 1);
    CHECK(chat && list);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, chat, "id", 42), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, chat, "title", "group"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, chat), EXTERIA_OK);
    memset(&row, 0, sizeof(row));
    row.peer_kind = 2; row.peer_id = 42;
    exteria_dialog_peer_read(&row, NULL, list, SELF);
    CHECK_EQ_INT(row.noforwards, 0);
    CHECK_EQ_INT(exteria_tl_set_flag(chat, "noforwards"), EXTERIA_OK);
    exteria_dialog_peer_read(&row, NULL, list, SELF);
    CHECK_EQ_INT(row.noforwards, 1);
}

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
    CHECK(v != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(v, i, items[i]), EXTERIA_OK);
    return v;
}

static exteria_tl_value *peer(const char *ctor, const char *field, int64_t id) {
    exteria_tl_value *p = obj(ctor);
    set_i64(p, field, id);
    return p;
}

static exteria_tl_value *user(int64_t id, const char *first, const char *last) {
    exteria_tl_value *u = obj("user");
    set_i64(u, "id", id);
    if (first) set_str(u, "first_name", first);
    if (last) set_str(u, "last_name", last);
    return u;
}

static exteria_tl_value *dialog(exteria_tl_value *p, int32_t top, int32_t unread) {
    exteria_tl_value *d = obj("dialog");
    set(d, "peer", p);
    set_i32(d, "top_message", top);
    set_i32(d, "unread_count", unread);
    return d;
}

static exteria_tl_value *message(exteria_tl_value *p, int32_t id, int32_t date, const char *text) {
    exteria_tl_value *m = obj("message");
    set_i32(m, "id", id);
    set(m, "peer_id", p);
    set_i32(m, "date", date);
    set_str(m, "message", text);
    return m;
}

static exteria_tl_value *answer(const char *ctor, exteria_tl_value **dialogs, uint32_t nd, exteria_tl_value **messages,
                                uint32_t nm, exteria_tl_value **chats, uint32_t nc, exteria_tl_value **users, uint32_t nu) {
    exteria_tl_value *a = obj(ctor);
    set(a, "dialogs", vec_of(dialogs, nd));
    set(a, "messages", vec_of(messages, nm));
    set(a, "chats", vec_of(chats, nc));
    set(a, "users", vec_of(users, nu));
    return a;
}

static void test_user_and_saved(void) {
    exteria_dialog_row rows[4];
    size_t count;
    exteria_tl_value *d[2], *m[2], *u[2], *settings, *media, *status;
    d[0] = dialog(peer("peerUser", "user_id", SELF), 7, 0);
    d[1] = dialog(peer("peerUser", "user_id", 5), 9, 3);
    set_flag(d[1], "pinned");
    settings = obj("peerNotifySettings");
    set_i32(settings, "mute_until", 2000);
    set(d[1], "notify_settings", settings);
    set_i32(d[1], "read_outbox_max_id", 9);
    m[0] = message(peer("peerUser", "user_id", SELF), 7, 1000, "");
    media = obj("messageMediaPhoto");
    set(m[0], "media", media);
    m[1] = message(peer("peerUser", "user_id", 5), 9, 1500, "hi\n  there\r\n");
    set_flag(m[1], "out");
    u[0] = user(SELF, "Me", NULL);
    set_flag(u[0], "self");
    u[1] = user(5, "Ann", "Lee");
    set_flag(u[1], "verified");
    set_flag(u[1], "premium");
    status = obj("emojiStatus");
    set_i64(status, "document_id", 4242);
    set_i32(status, "until", 2000000000);
    set(u[1], "emoji_status", status);
    status = obj("userStatusOffline");
    set_i32(status, "was_online", 1234);
    set(u[1], "status", status);
    set_i32(d[1], "read_inbox_max_id", 8);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 2, m, 2, NULL, 0, u, 2), SELF, 1000, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[1].presence, EXTERIA_PRESENCE_OFFLINE);
    CHECK_EQ_INT(rows[1].seen, 1234);
    CHECK_EQ_INT(rows[1].read_inbox_max_id, 8);
    CHECK_EQ_INT(rows[1].read_outbox_max_id, 9);
    CHECK_EQ_INT(rows[0].presence, EXTERIA_PRESENCE_UNKNOWN);
    CHECK_EQ_INT(rows[0].saved, 1);
    CHECK_EQ_INT(rows[0].preview, EXTERIA_PREVIEW_PHOTO);
    CHECK_EQ_INT(rows[0].date, 1000);
    CHECK_EQ_INT(rows[0].pinned, 0);
    CHECK_EQ_INT(rows[1].saved, 0);
    CHECK_EQ_INT(rows[1].contact, 0);
    set_flag(u[1], "contact");
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 2, m, 2, NULL, 0, u, 2), SELF, 1000, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[1].contact, 1);
    CHECK_EQ_INT(rows[1].kind, EXTERIA_DIALOG_USER);
    CHECK(strcmp(rows[1].title, "Ann Lee") == 0);
    CHECK_EQ_INT(rows[1].verified, 1);
    CHECK_EQ_INT(rows[1].premium, 1);
    CHECK_EQ_INT(rows[1].emoji_status, 4242);
    CHECK_EQ_INT(rows[1].emoji_status_until, 2000000000);
    CHECK_EQ_INT(rows[0].premium, 0);
    CHECK_EQ_INT(rows[0].emoji_status, 0);
    CHECK_EQ_INT(rows[1].pinned, 1);
    CHECK_EQ_INT(rows[1].muted, 1);
    CHECK_EQ_INT(rows[1].unread_count, 3);
    CHECK_EQ_INT(rows[1].outgoing, 1);
    CHECK_EQ_INT(rows[1].read, 1);
    CHECK_EQ_INT(rows[1].sender_is_self, 1);
    CHECK_EQ_INT(rows[1].preview, EXTERIA_PREVIEW_TEXT);
    CHECK(strcmp(rows[1].text, "hi there") == 0);
    CHECK(rows[1].sender[0] == 0);
}

static void test_forwarded_last_message(void) {
    exteria_dialog_row rows[2];
    size_t count;
    exteria_tl_value *d[1], *m[1], *u[1], *header;
    d[0] = dialog(peer("peerUser", "user_id", 5), 9, 1);
    m[0] = message(peer("peerUser", "user_id", 5), 9, 1500, "hello");
    u[0] = user(5, "Ann", NULL);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 1, m, 1, NULL, 0, u, 1), SELF, 1000, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].forwarded, 0);
    header = obj("messageFwdHeader");
    set_i32(header, "date", 1400);
    set(m[0], "fwd_from", header);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 1, m, 1, NULL, 0, u, 1), SELF, 1000, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].forwarded, 1);
    CHECK(strcmp(rows[0].text, "hello") == 0);
}

static void test_mute_expired_and_unread(void) {
    exteria_dialog_row rows[2];
    size_t count;
    exteria_tl_value *d[1], *m[1], *u[1], *settings;
    d[0] = dialog(peer("peerUser", "user_id", 5), 9, 0);
    settings = obj("peerNotifySettings");
    set_i32(settings, "mute_until", 999);
    set(d[0], "notify_settings", settings);
    set_flag(d[0], "unread_mark");
    set_i32(d[0], "read_outbox_max_id", 3);
    m[0] = message(peer("peerUser", "user_id", 5), 9, 1500, "x");
    set_flag(m[0], "out");
    u[0] = user(5, NULL, NULL);
    set_str(u[0], "username", "ann");
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogsSlice", d, 1, m, 1, NULL, 0, u, 1), SELF, 1000, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].muted, 0);
    CHECK_EQ_INT(rows[0].unread_mark, 1);
    CHECK_EQ_INT(rows[0].outgoing, 1);
    CHECK_EQ_INT(rows[0].read, 0);
    CHECK(strcmp(rows[0].title, "ann") == 0);
}

static void test_group_channel_and_sender(void) {
    exteria_dialog_row rows[4];
    size_t count;
    exteria_tl_value *d[3], *m[3], *c[3], *u[1];
    d[0] = dialog(peer("peerChat", "chat_id", 11), 1, 0);
    d[1] = dialog(peer("peerChannel", "channel_id", 12), 2, 5);
    d[2] = dialog(peer("peerChannel", "channel_id", 13), 3, 0);
    m[0] = message(peer("peerChat", "chat_id", 11), 1, 10, "from bob");
    set(m[0], "from_id", peer("peerUser", "user_id", 6));
    m[1] = message(peer("peerChannel", "channel_id", 12), 2, 20, "news");
    m[2] = message(peer("peerChannel", "channel_id", 13), 3, 30, "mine");
    set(m[2], "from_id", peer("peerUser", "user_id", SELF));
    c[0] = obj("chat");
    set_i64(c[0], "id", 11);
    set_str(c[0], "title", "Friends");
    set_i32(c[0], "participants_count", 23);
    c[1] = obj("channel");
    set_i64(c[1], "id", 12);
    set_str(c[1], "title", "Exteria News");
    set_flag(c[1], "broadcast");
    set_i32(c[1], "participants_count", 154);
    c[2] = obj("channel");
    set_i64(c[2], "id", 13);
    set_str(c[2], "title", "Supergroup");
    set_flag(c[2], "megagroup");
    u[0] = user(6, "Bob", NULL);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 3, m, 3, c, 3, u, 1), SELF, 0, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(rows[0].kind, EXTERIA_DIALOG_GROUP);
    CHECK_EQ_INT(rows[0].participants_count, 23);
    CHECK_EQ_INT(rows[1].participants_count, 154);
    CHECK_EQ_INT(rows[2].participants_count, 0);
    CHECK(strcmp(rows[0].title, "Friends") == 0);
    CHECK(strcmp(rows[0].sender, "Bob") == 0);
    CHECK_EQ_INT(rows[0].sender_is_self, 0);
    CHECK_EQ_INT(rows[1].kind, EXTERIA_DIALOG_CHANNEL);
    CHECK_EQ_INT(rows[1].peer_kind, 3);
    CHECK(rows[1].sender[0] == 0);
    CHECK_EQ_INT(rows[2].kind, EXTERIA_DIALOG_GROUP);
    CHECK_EQ_INT(rows[2].sender_is_self, 1);
    CHECK(rows[2].sender[0] == 0);
    /* nobody posts in a channel by default, and a group is not a channel */
    CHECK_EQ_INT(rows[1].can_post, 0);
    CHECK_EQ_INT(rows[2].can_post, 0);
}

static void test_service_member_preview(void) {
    exteria_dialog_row rows[2];
    size_t count = 0;
    exteria_tl_value *d[] = {dialog(peer("peerChat", "chat_id", 11), 1, 0)};
    exteria_tl_value *m[] = {obj("messageService")};
    exteria_tl_value *c[] = {obj("chat")};
    exteria_tl_value *u[] = {user(6, "Bob", NULL), user(7, "Ann", NULL)};
    exteria_tl_value *action = obj("messageActionChatAddUser");
    exteria_tl_value *users = exteria_tl_new_vec(&arena, 1);
    CHECK(users != NULL);
    CHECK_EQ_INT(exteria_tl_vec_set(users, 0, exteria_tl_new_i64(&arena, 6)), EXTERIA_OK);
    set(action, "users", users);
    set_i32(m[0], "id", 1);
    set_i32(m[0], "date", 10);
    set(m[0], "peer_id", peer("peerChat", "chat_id", 11));
    set(m[0], "from_id", peer("peerUser", "user_id", 6));
    set(m[0], "action", action);
    set_i64(c[0], "id", 11);
    set_str(c[0], "title", "Friends");
    exteria_tl_value *a = answer("messages.dialogs", d, 1, m, 1, c, 1, u, 2);
    CHECK_EQ_INT(exteria_dialogs_parse(a, SELF, 0, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].service_actor_is_target, 1);
    CHECK(strcmp(rows[0].service_target, "Bob") == 0);
    set(m[0], "from_id", peer("peerUser", "user_id", 7));
    CHECK_EQ_INT(exteria_dialogs_parse(a, SELF, 0, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].service_actor_is_target, 0);
    CHECK(strcmp(rows[0].service_target, "Bob") == 0);
}

static void test_channel_posting_rights(void) {
    exteria_dialog_row rows[2];
    size_t count;
    exteria_tl_value *d[2], *m[2], *c[2], *u[1], *rights = obj("chatAdminRights");
    d[0] = dialog(peer("peerChannel", "channel_id", 12), 1, 0);
    d[1] = dialog(peer("peerChannel", "channel_id", 13), 2, 0);
    m[0] = message(peer("peerChannel", "channel_id", 12), 1, 10, "mine");
    m[1] = message(peer("peerChannel", "channel_id", 13), 2, 20, "theirs");
    c[0] = obj("channel");
    set_i64(c[0], "id", 12);
    set_str(c[0], "title", "Owned");
    set_flag(c[0], "broadcast");
    set_flag(c[0], "creator");
    c[1] = obj("channel");
    set_i64(c[1], "id", 13);
    set_str(c[1], "title", "Moderated");
    set_flag(c[1], "broadcast");
    u[0] = user(6, "Bob", NULL);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 2, m, 2, c, 2, u, 1), SELF, 0, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].can_post, 1);
    CHECK_EQ_INT(rows[1].can_post, 0);
    /* an admin may post only with the right to */
    set_flag(rights, "delete_messages");
    set(c[1], "admin_rights", rights);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 2, m, 2, c, 2, u, 1), SELF, 0, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[1].can_post, 0);
    set_flag(rights, "post_messages");
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 2, m, 2, c, 2, u, 1), SELF, 0, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[1].can_post, 1);
}

static exteria_tl_value *document_message(exteria_tl_value *p, int32_t id, exteria_tl_value **attrs, uint32_t n) {
    exteria_tl_value *m = message(p, id, 5, ""), *media = obj("messageMediaDocument"), *doc = obj("document");
    set(doc, "attributes", vec_of(attrs, n));
    set(media, "document", doc);
    set(m, "media", media);
    return m;
}

static void test_media_kinds(void) {
    exteria_dialog_row rows[8];
    size_t count;
    exteria_tl_value *d[6], *m[6], *u[1], *a[3], *voice_media;
    exteria_tl_value *p = NULL;
    int i;
    u[0] = user(5, "A", NULL);
    for (i = 0; i < 6; ++i) {
        p = peer("peerUser", "user_id", 5 + i);
        d[i] = dialog(p, i + 1, 0);
    }
    /* sticker with an emoji */
    a[0] = obj("documentAttributeSticker");
    set_str(a[0], "alt", "\xF0\x9F\x98\x80");
    m[0] = document_message(peer("peerUser", "user_id", 5), 1, a, 1);
    /* gif is animated */
    a[0] = obj("documentAttributeAnimated");
    m[1] = document_message(peer("peerUser", "user_id", 6), 2, a, 1);
    /* video then a file name */
    a[0] = obj("documentAttributeVideo");
    m[2] = document_message(peer("peerUser", "user_id", 7), 3, a, 1);
    /* a plain file keeps its name */
    a[0] = obj("documentAttributeFilename");
    set_str(a[0], "file_name", "report.pdf");
    m[3] = document_message(peer("peerUser", "user_id", 8), 4, a, 1);
    /* voice note through the media flag */
    voice_media = obj("messageMediaDocument");
    set_flag(voice_media, "voice");
    m[4] = message(peer("peerUser", "user_id", 9), 5, 5, "");
    set(m[4], "media", voice_media);
    /* a service message */
    m[5] = obj("messageService");
    set_i32(m[5], "id", 6);
    set(m[5], "peer_id", peer("peerUser", "user_id", 10));
    set_i32(m[5], "date", 77);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 6, m, 6, NULL, 0, u, 1), SELF, 0, rows, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 6);
    CHECK_EQ_INT(rows[0].preview, EXTERIA_PREVIEW_STICKER);
    CHECK(strcmp(rows[0].text, "\xF0\x9F\x98\x80") == 0);
    CHECK_EQ_INT(rows[1].preview, EXTERIA_PREVIEW_GIF);
    CHECK_EQ_INT(rows[2].preview, EXTERIA_PREVIEW_VIDEO);
    CHECK_EQ_INT(rows[3].preview, EXTERIA_PREVIEW_FILE);
    CHECK(strcmp(rows[3].text, "report.pdf") == 0);
    CHECK_EQ_INT(rows[4].preview, EXTERIA_PREVIEW_VOICE);
    CHECK_EQ_INT(rows[5].preview, EXTERIA_PREVIEW_SERVICE);
    CHECK_EQ_INT(rows[5].date, 77);
}

static exteria_tl_value *thumb_size(const char *type, int32_t w, int32_t h, int32_t bytes) {
    exteria_tl_value *size = obj("photoSize");
    set_str(size, "type", type);
    set_i32(size, "w", w);
    set_i32(size, "h", h);
    set_i32(size, "size", bytes);
    return size;
}

static void fetchable(exteria_tl_value *object, int64_t id) {
    static const uint8_t reference[] = {9, 8, 7};
    set_i64(object, "id", id);
    set_i64(object, "access_hash", id * 3);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, object, "file_reference", reference, sizeof(reference)), EXTERIA_OK);
    set_i32(object, "dc_id", 2);
}

/* a photo carries its own small size, a video the thumbnail beside it; the rest of the kinds have no picture in the list */
static void test_thumbs(void) {
    exteria_dialog_row rows[8];
    size_t count;
    exteria_tl_value *d[7], *m[7], *u[1], *a[2], *sizes[3], *media, *photo, *doc;
    int i;
    u[0] = user(5, "A", NULL);
    for (i = 0; i < 7; ++i) d[i] = dialog(peer("peerUser", "user_id", 5 + i), i + 1, 0);

    /* a photo: its small 90 pixel size, not the larger ones */
    photo = obj("photo");
    fetchable(photo, 11);
    sizes[0] = thumb_size("s", 90, 90, 900);
    sizes[1] = thumb_size("m", 320, 320, 9000);
    sizes[2] = thumb_size("y", 1280, 1280, 90000);
    set(photo, "sizes", vec_of(sizes, 3));
    media = obj("messageMediaPhoto");
    set(media, "photo", photo);
    m[0] = message(peer("peerUser", "user_id", 5), 1, 5, "");
    set(m[0], "media", media);

    /* a video with a thumbnail */
    a[0] = obj("documentAttributeVideo");
    doc = obj("document");
    fetchable(doc, 12);
    set(doc, "attributes", vec_of(a, 1));
    sizes[0] = thumb_size("m", 320, 180, 5000);
    set(doc, "thumbs", vec_of(sizes, 1));
    media = obj("messageMediaDocument");
    set(media, "document", doc);
    m[1] = message(peer("peerUser", "user_id", 6), 2, 5, "");
    set(m[1], "media", media);

    /* a gif and a round video keep theirs too */
    a[0] = obj("documentAttributeAnimated");
    doc = obj("document");
    fetchable(doc, 13);
    set(doc, "attributes", vec_of(a, 1));
    sizes[0] = thumb_size("m", 200, 200, 3000);
    set(doc, "thumbs", vec_of(sizes, 1));
    media = obj("messageMediaDocument");
    set(media, "document", doc);
    m[2] = message(peer("peerUser", "user_id", 7), 3, 5, "");
    set(m[2], "media", media);
    a[0] = obj("documentAttributeVideo");
    set_flag(a[0], "round_message");
    doc = obj("document");
    fetchable(doc, 14);
    set(doc, "attributes", vec_of(a, 1));
    sizes[0] = thumb_size("m", 240, 240, 3000);
    set(doc, "thumbs", vec_of(sizes, 1));
    media = obj("messageMediaDocument");
    set(media, "document", doc);
    m[3] = message(peer("peerUser", "user_id", 8), 4, 5, "");
    set(m[3], "media", media);

    /* a video whose document has no thumbnail, a sticker with one, and plain text */
    a[0] = obj("documentAttributeVideo");
    doc = obj("document");
    fetchable(doc, 15);
    set(doc, "attributes", vec_of(a, 1));
    media = obj("messageMediaDocument");
    set(media, "document", doc);
    m[4] = message(peer("peerUser", "user_id", 9), 5, 5, "");
    set(m[4], "media", media);
    a[0] = obj("documentAttributeSticker");
    set_str(a[0], "alt", "x");
    doc = obj("document");
    fetchable(doc, 16);
    set(doc, "attributes", vec_of(a, 1));
    sizes[0] = thumb_size("m", 128, 128, 3000);
    set(doc, "thumbs", vec_of(sizes, 1));
    media = obj("messageMediaDocument");
    set(media, "document", doc);
    m[5] = message(peer("peerUser", "user_id", 10), 6, 5, "");
    set(m[5], "media", media);
    m[6] = message(peer("peerUser", "user_id", 11), 7, 5, "hello");

    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 7, m, 7, NULL, 0, u, 1), SELF, 0, rows, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 7);
    CHECK_EQ_INT(rows[0].preview, EXTERIA_PREVIEW_PHOTO);
    CHECK_EQ_INT(rows[0].thumb.source, EXTERIA_MEDIA_SOURCE_PHOTO);
    CHECK_EQ_INT(rows[0].thumb.id, 11);
    CHECK(strcmp(rows[0].thumb.thumb, "s") == 0);
    CHECK_EQ_INT(rows[1].preview, EXTERIA_PREVIEW_VIDEO);
    CHECK_EQ_INT(rows[1].thumb.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);
    CHECK_EQ_INT(rows[1].thumb.id, 12);
    CHECK(strcmp(rows[1].thumb.thumb, "m") == 0);
    CHECK_EQ_INT(rows[2].preview, EXTERIA_PREVIEW_GIF);
    CHECK_EQ_INT(rows[2].thumb.id, 13);
    CHECK_EQ_INT(rows[3].preview, EXTERIA_PREVIEW_VIDEO_MESSAGE);
    CHECK_EQ_INT(rows[3].thumb.id, 14);
    CHECK_EQ_INT(rows[4].preview, EXTERIA_PREVIEW_VIDEO);
    CHECK_EQ_INT(rows[4].thumb.source, EXTERIA_MEDIA_SOURCE_NONE);
    CHECK_EQ_INT(rows[5].preview, EXTERIA_PREVIEW_STICKER);
    CHECK_EQ_INT(rows[5].thumb.source, EXTERIA_MEDIA_SOURCE_NONE);
    CHECK_EQ_INT(rows[6].preview, EXTERIA_PREVIEW_TEXT);
    CHECK_EQ_INT(rows[6].thumb.source, EXTERIA_MEDIA_SOURCE_NONE);
    /* the photo that cannot be fetched, as in test_user_and_saved, has no picture either */
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 1, m, 1, NULL, 0, u, 1), SELF, 0, rows, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].thumb.source, EXTERIA_MEDIA_SOURCE_PHOTO);
}

static void test_caption_wins_and_cut(void) {
    exteria_dialog_row rows[2];
    size_t count;
    exteria_tl_value *d[2], *m[2], *u[1], *a[1];
    char long_text[400];
    size_t i;
    d[0] = dialog(peer("peerUser", "user_id", 5), 1, 0);
    d[1] = dialog(peer("peerUser", "user_id", 6), 2, 0);
    a[0] = obj("documentAttributeFilename");
    set_str(a[0], "file_name", "name.bin");
    m[0] = document_message(peer("peerUser", "user_id", 5), 1, a, 1);
    set_str(m[0], "message", "caption");
    /* two byte letters up to the cut: the buffer must end on a whole letter */
    for (i = 0; i + 2 < sizeof(long_text); i += 2) { long_text[i] = (char)0xC3; long_text[i + 1] = (char)0xA9; }
    long_text[i] = 0;
    m[1] = message(peer("peerUser", "user_id", 6), 2, 5, long_text);
    u[0] = user(5, "A", NULL);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 2, m, 2, NULL, 0, u, 1), SELF, 0, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].preview, EXTERIA_PREVIEW_FILE);
    CHECK(strcmp(rows[0].text, "caption") == 0);
    CHECK(strlen(rows[1].text) < EXTERIA_DIALOG_TEXT_MAX);
    CHECK_EQ_INT(strlen(rows[1].text) % 2, 0);
    for (i = 0; i < strlen(rows[1].text); i += 2) CHECK((uint8_t)rows[1].text[i] == 0xC3 && (uint8_t)rows[1].text[i + 1] == 0xA9);
}

static void test_limits_and_errors(void) {
    exteria_dialog_row rows[2];
    size_t count = 99;
    exteria_tl_value *d[3], *u[1], *notmodified;
    d[0] = dialog(peer("peerUser", "user_id", 5), 0, 0);
    d[1] = obj("dialogFolder");
    d[2] = dialog(peer("peerUser", "user_id", 6), 0, 0);
    u[0] = user(5, "A", NULL);
    /* a folder is skipped, the cap holds, and a dialog without a message still yields a row */
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 3, NULL, 0, NULL, 0, u, 1), SELF, 0, rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].preview, EXTERIA_PREVIEW_NONE);
    CHECK_EQ_INT(rows[0].date, 0);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 3, NULL, 0, NULL, 0, u, 1), SELF, 0, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    /* a user missing from the answer is shown as deleted rather than dropped */
    CHECK_EQ_INT(rows[1].deleted, 1);
    CHECK_EQ_INT(rows[1].presence, EXTERIA_PRESENCE_DELETED);
    /* a user the answer marks deleted loses the time it was last seen */
    u[0] = user(6, "Gone", NULL);
    set_flag(u[0], "deleted");
    {
        exteria_tl_value *gone = obj("userStatusOffline");
        set_i32(gone, "was_online", 1234);
        set(u[0], "status", gone);
    }
    d[0] = d[2];
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 1, NULL, 0, NULL, 0, u, 1), SELF, 0, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].deleted, 1);
    CHECK_EQ_INT(rows[0].presence, EXTERIA_PRESENCE_DELETED);
    CHECK_EQ_INT(rows[0].seen, 0);

    notmodified = obj("messages.dialogsNotModified");
    CHECK_EQ_INT(exteria_dialogs_parse(notmodified, SELF, 0, rows, 2, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    notmodified = obj("messages.dialogs");
    CHECK_EQ_INT(exteria_dialogs_parse(notmodified, SELF, 0, rows, 2, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_dialogs_parse(NULL, SELF, 0, rows, 2, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 1, NULL, 0, NULL, 0, u, 1), SELF, 0, rows, 0, &count), EXTERIA_E_ARG);
}

static void test_folder_and_hash(void) {
    exteria_dialog_row rows[3];
    size_t count;
    exteria_tl_value *d[3], *m[1], *u[2], *c[1], *folder, *info;
    folder = obj("dialogFolder");
    info = obj("folder");
    set_i32(info, "id", 1);
    set_str(info, "title", "Archive");
    set(folder, "folder", info);
    set(folder, "peer", peer("peerUser", "user_id", 6));
    set_i32(folder, "top_message", 3);
    set_i32(folder, "unread_unmuted_messages_count", 0);
    set_i32(folder, "unread_muted_messages_count", 70);
    set_i32(folder, "unread_muted_peers_count", 7);
    set_flag(folder, "pinned");
    /* the server sends the archive between two chats, the list wants it first */
    d[0] = dialog(peer("peerUser", "user_id", 5), 9, 0);
    d[1] = folder;
    d[2] = dialog(peer("peerChannel", "channel_id", 12), 4, 0);
    m[0] = message(peer("peerUser", "user_id", 6), 3, 50, "old news");
    u[0] = user(5, "Ann", NULL);
    set_i64(u[0], "access_hash", 777);
    u[1] = user(6, "Bob", NULL);
    set_i64(u[1], "access_hash", 888);
    c[0] = obj("channel");
    set_i64(c[0], "id", 12);
    set_str(c[0], "title", "News");
    set_i64(c[0], "access_hash", 4242);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 3, m, 1, c, 1, u, 2), SELF, 0, rows, 3, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(rows[0].folder, 1);
    CHECK_EQ_INT(rows[0].folder_id, 1);
    CHECK(strcmp(rows[0].title, "Archive") == 0);
    CHECK_EQ_INT(rows[0].unread_count, 7);
    CHECK_EQ_INT(rows[0].muted, 1);
    CHECK_EQ_INT(rows[0].peer_hash, 0);
    CHECK_EQ_INT(rows[0].text[0], 0);
    CHECK_EQ_INT(rows[0].pinned, 0);
    CHECK_EQ_INT(rows[0].peer_id, 0);
    CHECK_EQ_INT(rows[0].date, 0);
    CHECK_EQ_INT(rows[0].top_message, 0);
    CHECK_EQ_INT(rows[1].folder, 0);
    CHECK_EQ_INT(rows[1].peer_hash, 777);
    CHECK_EQ_INT(rows[2].peer_hash, 4242);
    /* a mention-only user has no usable hash */
    set_flag(u[0], "min");
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 3, m, 1, c, 1, u, 2), SELF, 0, rows, 3, &count), EXTERIA_OK);
    CHECK_EQ_INT(rows[1].peer_hash, 0);
}

static void test_search_parse(void) {
    exteria_dialog_row rows[4];
    size_t count;
    int32_t next = -1;
    exteria_tl_value *m[3], *chats[1], *u[1], *answer_value, *channel;
    m[0] = message(peer("peerUser", "user_id", 5), 40, 2000, "found in a chat");
    m[1] = message(peer("peerChannel", "channel_id", 77), 41, 2100, "post text");
    m[2] = message(peer("peerUser", "user_id", 99), 42, 2200, "from someone the answer does not carry");
    channel = obj("channel");
    set_i64(channel, "id", 77);
    set_i64(channel, "access_hash", 5555);
    set_str(channel, "title", "News");
    chats[0] = channel;
    u[0] = user(5, "Ann", "Lee");
    answer_value = obj("messages.messagesSlice");
    set(answer_value, "messages", vec_of(m, 3));
    set(answer_value, "topics", vec_of(NULL, 0));
    set(answer_value, "chats", vec_of(chats, 1));
    set(answer_value, "users", vec_of(u, 1));
    set_i32(answer_value, "count", 3);
    set_i32(answer_value, "next_rate", 1234);
    CHECK_EQ_INT(exteria_search_parse(answer_value, SELF, rows, 4, &count, &next), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(next, 1234);
    CHECK_EQ_INT(rows[0].peer_kind, 1);
    CHECK(strcmp(rows[0].title, "Ann Lee") == 0);
    CHECK_EQ_INT(rows[0].top_message, 40);
    CHECK(strcmp(rows[0].text, "found in a chat") == 0);
    CHECK_EQ_INT(rows[0].date, 2000);
    CHECK_EQ_INT(rows[1].peer_kind, 3);
    CHECK_EQ_INT(rows[1].kind, EXTERIA_DIALOG_CHANNEL);
    CHECK_EQ_INT(rows[1].peer_hash, 5555);
    CHECK(strcmp(rows[1].title, "News") == 0);
    CHECK_EQ_INT(exteria_search_parse(answer_value, SELF, rows, 1, &count, NULL), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_search_parse(obj("contacts.contacts"), SELF, rows, 4, &count, &next), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_search_parse(NULL, SELF, rows, 4, &count, &next), EXTERIA_E_ARG);
}

static void test_found_parse(void) {
    exteria_dialog_row rows[6];
    size_t count;
    exteria_tl_value *mine[2], *found[3], *chats[1], *u[2], *answer_value, *channel, *request;
    mine[0] = peer("peerUser", "user_id", 5);
    mine[1] = peer("peerChannel", "channel_id", 77);
    found[0] = peer("peerUser", "user_id", 5);
    found[1] = peer("peerChannel", "channel_id", 88);
    found[2] = peer("peerUser", "user_id", 99);
    channel = obj("channel");
    set_i64(channel, "id", 77);
    set_i64(channel, "access_hash", 5555);
    set_str(channel, "title", "News");
    set_str(channel, "username", "daily_news");
    chats[0] = channel;
    u[0] = user(5, "Ann", "Lee");
    set_i64(u[0], "access_hash", 321);
    set_str(u[0], "username", "ann");
    answer_value = obj("contacts.found");
    set(answer_value, "my_results", vec_of(mine, 2));
    set(answer_value, "results", vec_of(found, 3));
    set(answer_value, "chats", vec_of(chats, 1));
    set(answer_value, "users", vec_of(u, 1));
    CHECK_EQ_INT(exteria_found_parse(answer_value, SELF, rows, 6, &count), EXTERIA_OK);
    /* the user is listed once, the channel the answer does not carry and the missing user are skipped */
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].peer_kind, 1);
    CHECK(strcmp(rows[0].title, "Ann Lee") == 0);
    CHECK_EQ_INT(rows[0].peer_hash, 321);
    CHECK(strcmp(rows[0].text, "@ann") == 0);
    CHECK_EQ_INT(rows[1].kind, EXTERIA_DIALOG_CHANNEL);
    CHECK_EQ_INT(rows[1].peer_hash, 5555);
    CHECK(strcmp(rows[1].text, "@daily_news") == 0);
    CHECK_EQ_INT(exteria_found_parse(answer_value, SELF, rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_found_parse(obj("contacts.contacts"), SELF, rows, 6, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_found_parse(NULL, SELF, rows, 6, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_found_request(&arena, "ann", 20, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_contacts_search);
    CHECK_EQ_INT(exteria_found_request(&arena, "ann", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_found_request(&arena, NULL, 20, &request), EXTERIA_E_ARG);
}

static exteria_tl_value *topic(int32_t id, const char *title, int32_t top, int32_t unread) {
    exteria_tl_value *t = obj("forumTopic");
    set_i32(t, "id", id);
    set_str(t, "title", title);
    set_i32(t, "top_message", top);
    set_i32(t, "unread_count", unread);
    return t;
}

static void test_forum_topics(void) {
    exteria_dialog_row forum, rows[4];
    size_t count;
    exteria_tl_value *chat, *t[4], *m[2], *u[1], *settings, *a;
    exteria_tl_value *d[1];
    chat = obj("channel");
    set_i64(chat, "id", 9);
    set_i64(chat, "access_hash", 55);
    set_str(chat, "title", "9-2");
    set_flag(chat, "megagroup");
    set_flag(chat, "forum");
    d[0] = dialog(peer("peerChannel", "channel_id", 9), 3, 0);
    {
        exteria_tl_value *c[1], *msgs[1];
        c[0] = chat;
        msgs[0] = message(peer("peerChannel", "channel_id", 9), 3, 1000, "x");
        CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 1, msgs, 1, c, 1, NULL, 0), SELF, 1000, rows, 4, &count), EXTERIA_OK);
        CHECK_EQ_INT(count, 1);
        CHECK_EQ_INT(rows[0].forum, 1);
        forum = rows[0];
        forum.photo.photo_id = 5;
    }
    t[0] = topic(1, "General", 30, 0);
    set_flag(t[0], "pinned");
    t[1] = topic(5, "flood", 40, 5);
    set_i32(t[1], "icon_color", 0x6FB9F0);
    set_i64(t[1], "icon_emoji_id", 777);
    set_i32(t[1], "unread_mentions_count", 2);
    set_i32(t[1], "unread_reactions_count", 3);
    set_i32(t[1], "read_inbox_max_id", 35);
    settings = obj("peerNotifySettings");
    set_i32(settings, "mute_until", 5000);
    set(t[1], "notify_settings", settings);
    t[2] = obj("forumTopicDeleted");
    set_i32(t[2], "id", 6);
    t[3] = topic(8, "empty", 0, 0);
    set_flag(t[3], "closed");
    m[0] = message(peer("peerChannel", "channel_id", 9), 30, 1500, "welcome");
    m[1] = message(peer("peerChannel", "channel_id", 9), 40, 1900, "pic");
    set(m[1], "from_id", peer("peerUser", "user_id", 5));
    u[0] = user(5, "Ann", "Lee");
    a = obj("messages.forumTopics");
    set(a, "topics", vec_of(t, 4));
    set(a, "messages", vec_of(m, 2));
    set(a, "chats", vec_of(NULL, 0));
    set(a, "users", vec_of(u, 1));
    CHECK_EQ_INT(exteria_topics_parse(a, &forum, SELF, 1000, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(rows[0].topic_id, 1);
    CHECK_EQ_INT(rows[0].pinned, 1);
    CHECK_EQ_INT(rows[0].forum, 0);
    CHECK_EQ_INT(rows[0].peer_kind, 3);
    CHECK_EQ_INT(rows[0].peer_id, 9);
    CHECK_EQ_INT(rows[0].peer_hash, 55);
    CHECK(strcmp(rows[0].title, "General") == 0);
    CHECK(strcmp(rows[0].text, "welcome") == 0);
    CHECK_EQ_INT(rows[0].date, 1500);
    CHECK_EQ_INT(rows[1].topic_id, 5);
    CHECK_EQ_INT(rows[1].pinned, 0);
    CHECK_EQ_INT(rows[1].muted, 1);
    CHECK_EQ_INT(rows[1].unread_count, 5);
    CHECK_EQ_INT(rows[1].mentions, 2);
    CHECK_EQ_INT(rows[1].reactions, 3);
    CHECK_EQ_INT(rows[0].reactions, 0);
    CHECK_EQ_INT(rows[1].read_inbox_max_id, 35);
    CHECK_EQ_INT(rows[1].topic_icon_color, 0x6FB9F0);
    CHECK(rows[1].topic_icon_emoji == 777);
    CHECK(strcmp(rows[1].sender, "Ann Lee") == 0);
    /* the group's photo stays for the bar of the topic's chat; the list draws the icon instead */
    CHECK(rows[1].photo.photo_id == 5);
    /* a topic without a message still lists, closed */
    CHECK_EQ_INT(rows[2].topic_id, 8);
    CHECK_EQ_INT(rows[2].topic_closed, 1);
    CHECK_EQ_INT(rows[2].preview, EXTERIA_PREVIEW_NONE);
    CHECK_EQ_INT(rows[2].date, 0);
    /* the rows stop at the capacity */
    CHECK_EQ_INT(exteria_topics_parse(a, &forum, SELF, 1000, rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_topics_parse(obj("messages.dialogs"), &forum, SELF, 1000, rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_topics_parse(a, NULL, SELF, 1000, rows, 4, &count), EXTERIA_E_ARG);
}

static void test_forum_topic_request(void) {
    exteria_tl_value *request = NULL;
    exteria_writer w;
    exteria_tl_error error;
    CHECK_EQ_INT(exteria_topics_request(&arena, 3, 9, 55, 0, 0, 0, 50, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getForumTopics);
    exteria_writer_init(&w, 4096);
    CHECK_EQ_INT(exteria_tl_encode(request, &w, &error), EXTERIA_OK);
    exteria_writer_free(&w);
    CHECK_EQ_INT(exteria_topics_request(&arena, 1, 9, 55, 0, 0, 0, 50, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_topics_request(&arena, 3, 9, 0, 0, 0, 0, 50, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_topics_request(&arena, 3, 9, 55, 0, 0, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_topics_request(&arena, 3, 9, 55, 0, 0, 0, EXTERIA_DIALOGS_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

static exteria_tl_value *community_chat(int64_t id, const char *title, int collapsed) {
    exteria_tl_value *c = obj("community");
    set_i64(c, "id", id);
    set_i64(c, "access_hash", 900 + id);
    set_str(c, "title", title);
    if (collapsed) set_flag(c, "collapsed_in_dialogs");
    return c;
}

static exteria_tl_value *linked(int64_t channel, int visible_false) {
    exteria_tl_value *l = obj("communityPeer");
    set(l, "peer", peer("peerChannel", "channel_id", channel));
    if (visible_false) set(l, "visible", obj("boolFalse"));
    return l;
}

static void test_community_row(void) {
    exteria_dialog_row rows[3];
    size_t count;
    exteria_tl_value *d[2], *c[1];
    d[0] = obj("dialogCommunity");
    set_i64(d[0], "community_id", 40);
    set_flag(d[0], "pinned");
    d[1] = obj("dialogCommunity");
    set_i64(d[1], "community_id", 41);
    c[0] = community_chat(40, "Legacy iOS", 1);
    /* 41 is not in the chats of the answer and is skipped */
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 2, NULL, 0, c, 1, NULL, 0), SELF, 1000, rows, 3, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].community, 1);
    CHECK_EQ_INT(rows[0].community_collapsed, 1);
    CHECK_EQ_INT(rows[0].peer_kind, 3);
    CHECK_EQ_INT(rows[0].peer_id, 40);
    CHECK_EQ_INT(rows[0].peer_hash, 940);
    CHECK_EQ_INT(rows[0].pinned, 1);
    CHECK(strcmp(rows[0].title, "Legacy iOS") == 0);
    CHECK_EQ_INT(rows[0].preview, EXTERIA_PREVIEW_NONE);
}

static void test_linked_community(void) {
    exteria_dialog_row rows[4];
    size_t count;
    exteria_tl_value *d[3], *c[2], *u[1], *chan;
    /* a chat and a user that were added to a community say which, and the community of the answer gives its hash and name */
    d[0] = dialog(peer("peerChannel", "channel_id", 70), 0, 0);
    d[1] = dialog(peer("peerUser", "user_id", 5), 0, 0);
    d[2] = dialog(peer("peerChannel", "channel_id", 71), 0, 0);
    chan = obj("channel");
    set_i64(chan, "id", 70);
    set_i64(chan, "access_hash", 7);
    set_str(chan, "title", "News");
    set_i64(chan, "linked_community_id", 40);
    c[0] = chan;
    c[1] = community_chat(40, "Legacy iOS", 0);
    u[0] = user(5, "Bot", NULL);
    set_i64(u[0], "linked_community_id", 41);
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", d, 2, NULL, 0, c, 2, u, 1), SELF, 1000, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].linked_community_id, 40);
    CHECK_EQ_INT(rows[0].linked_community_hash, 940);
    CHECK(strcmp(rows[0].linked_community_title, "Legacy iOS") == 0);
    /* the community of the bot is not among the chats: its id is kept, with nothing to open it by */
    CHECK_EQ_INT(rows[1].linked_community_id, 41);
    CHECK_EQ_INT(rows[1].linked_community_hash, 0);
    CHECK_EQ_INT(rows[1].linked_community_title[0], 0);
    /* a channel with no link has none */
    set_i64(chan, "id", 71);
    c[0] = obj("channel");
    set_i64(c[0], "id", 71);
    set_str(c[0], "title", "Plain");
    CHECK_EQ_INT(exteria_dialogs_parse(answer("messages.dialogs", &d[2], 1, NULL, 0, c, 1, NULL, 0), SELF, 1000, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].linked_community_id, 0);
}

static void test_community_chats(void) {
    exteria_community_info info;
    exteria_dialog_row rows[4];
    size_t count;
    exteria_tl_value *full, *links[5], *chats[4], *a, *joined, *viewed, *group;
    full = obj("communityFull");
    set_i64(full, "id", 40);
    set_str(full, "about", "old\nphones");
    joined = obj("channel");
    set_i64(joined, "id", 7);
    set_i64(joined, "access_hash", 70);
    set_str(joined, "title", "Survival");
    set_flag(joined, "megagroup");
    viewed = obj("channel");
    set_i64(viewed, "id", 8);
    set_i64(viewed, "access_hash", 80);
    set_str(viewed, "title", "News");
    set_flag(viewed, "left");
    group = obj("chat");
    set_i64(group, "id", 9);
    set_str(group, "title", "Basic");
    chats[0] = community_chat(40, "Legacy iOS", 0);
    chats[1] = joined;
    chats[2] = viewed;
    chats[3] = group;
    links[0] = linked(7, 0);
    links[1] = linked(8, 0);
    links[2] = linked(7, 0);
    links[3] = obj("communityPeer");
    set(links[3], "peer", peer("peerChat", "chat_id", 9));
    set(links[3], "visible", obj("boolFalse"));
    links[4] = linked(99, 0);
    set(full, "linked_peers", vec_of(links, 5));
    a = obj("messages.chatFull");
    set(a, "full_chat", full);
    set(a, "chats", vec_of(chats, 4));
    set(a, "users", vec_of(NULL, 0));
    CHECK_EQ_INT(exteria_community_parse(a, &info, rows, 4, &count), EXTERIA_OK);
    CHECK(strcmp(info.title, "Legacy iOS") == 0);
    CHECK(strcmp(info.about, "old phones") == 0);
    CHECK_EQ_INT(info.collapsed, 0);
    /* a repeated link, a hidden one and a chat the answer lacks are left out */
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].peer_id, 7);
    CHECK_EQ_INT(rows[0].kind, EXTERIA_DIALOG_GROUP);
    CHECK_EQ_INT(rows[0].left, 0);
    CHECK_EQ_INT(rows[0].peer_hash, 70);
    CHECK_EQ_INT(rows[1].peer_id, 8);
    CHECK_EQ_INT(rows[1].kind, EXTERIA_DIALOG_CHANNEL);
    CHECK_EQ_INT(rows[1].left, 1);
    CHECK_EQ_INT(exteria_community_parse(a, &info, rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_community_parse(obj("messages.dialogs"), &info, rows, 4, &count), EXTERIA_E_MALFORMED);
    set(a, "full_chat", obj("channelFull"));
    CHECK_EQ_INT(exteria_community_parse(a, &info, rows, 4, &count), EXTERIA_E_MALFORMED);
}

static void test_community_previews(void) {
    exteria_dialog_row rows[3], before;
    exteria_tl_value *d[3], *m[3], *a;
    memset(rows, 0, sizeof(rows));
    for (size_t i = 0; i < 3; ++i) {
        rows[i].peer_kind = 3;
        rows[i].peer_id = 7 + (int64_t)i;
        rows[i].peer_hash = 70 + (int64_t)i;
        rows[i].kind = i == 0 ? EXTERIA_DIALOG_GROUP : EXTERIA_DIALOG_CHANNEL;
    }
    strcpy(rows[0].title, "Joined group");
    strcpy(rows[1].title, "Viewable channel");
    rows[1].left = 1;
    rows[1].verified = 1;
    before = rows[2];
    /* message ids repeat across channels and the peer-dialog order can differ from the community */
    d[0] = dialog(peer("peerChannel", "channel_id", 8), 10, 3);
    d[1] = dialog(peer("peerChannel", "channel_id", 7), 10, 2);
    d[2] = dialog(peer("peerChannel", "channel_id", 99), 10, 9);
    m[0] = message(peer("peerChannel", "channel_id", 7), 10, 100, "group message");
    m[1] = message(peer("peerChannel", "channel_id", 8), 10, 200, "channel message");
    m[2] = message(peer("peerChannel", "channel_id", 99), 10, 300, "unrelated");
    a = answer("messages.peerDialogs", d, 3, m, 3, NULL, 0, NULL, 0);
    CHECK_EQ_INT(exteria_community_previews_apply(a, SELF, 1000, rows, 3), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].peer_id, 7);
    CHECK_EQ_INT(rows[0].kind, EXTERIA_DIALOG_GROUP);
    CHECK_EQ_INT(rows[0].date, 100);
    CHECK_EQ_INT(rows[0].unread_count, 2);
    CHECK(strcmp(rows[0].title, "Joined group") == 0);
    CHECK(strcmp(rows[0].text, "group message") == 0);
    CHECK_EQ_INT(rows[1].peer_id, 8);
    CHECK_EQ_INT(rows[1].left, 1);
    CHECK_EQ_INT(rows[1].verified, 1);
    CHECK_EQ_INT(rows[1].peer_hash, 71);
    CHECK_EQ_INT(rows[1].date, 200);
    CHECK_EQ_INT(rows[1].preview, EXTERIA_PREVIEW_TEXT);
    CHECK_EQ_INT(rows[1].unread_count, 3);
    CHECK(strcmp(rows[1].text, "channel message") == 0);
    CHECK(memcmp(&rows[2], &before, sizeof(before)) == 0);
    before = rows[0];
    CHECK_EQ_INT(exteria_community_previews_apply(obj("messages.peerDialogs"), SELF, 1000, rows, 3), EXTERIA_E_MALFORMED);
    CHECK(memcmp(&rows[0], &before, sizeof(before)) == 0);
    a = answer("messages.peerDialogs", NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    CHECK_EQ_INT(exteria_community_previews_apply(a, SELF, 1000, rows, 3), EXTERIA_OK);
    CHECK(memcmp(&rows[0], &before, sizeof(before)) == 0);
    CHECK_EQ_INT(exteria_community_previews_apply(a, SELF, 1000, rows, 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_community_previews_apply(a, SELF, 1000, rows, EXTERIA_DIALOGS_MAX + 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_community_previews_apply(a, SELF, 1000, NULL, 0), EXTERIA_E_ARG);
}

static void test_peer_dialogs_request(void) {
    exteria_peer_ref peers[101];
    exteria_tl_value *request = NULL;
    const exteria_tl_value *list;
    exteria_writer writer;
    memset(peers, 0, sizeof(peers));
    for (size_t i = 0; i < 101; ++i) {
        peers[i].kind = i % 2 ? 3 : 2;
        peers[i].id = (int64_t)i + 1;
        peers[i].access_hash = i % 2 ? 500 : 0;
    }
    CHECK_EQ_INT(exteria_peer_dialogs_request(&arena, peers, 100, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_messages_getPeerDialogs));
    CHECK_EQ_INT(exteria_tl_get_vec(request, "peers", &list), EXTERIA_OK);
    CHECK_EQ_INT(list->u.vec.count, 100);
    CHECK(exteria_tl_is(exteria_tl_get(list->u.vec.items[0], "peer"), EXTERIA_TL_ID_inputPeerChat));
    CHECK(exteria_tl_is(exteria_tl_get(list->u.vec.items[1], "peer"), EXTERIA_TL_ID_inputPeerChannel));
    exteria_writer_init(&writer, 64 * 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    exteria_writer_free(&writer);
    CHECK_EQ_INT(exteria_peer_dialogs_request(&arena, peers, 101, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_peer_dialogs_request(&arena, peers, 0, &request), EXTERIA_E_ARG);
    peers[1].access_hash = 0;
    CHECK_EQ_INT(exteria_peer_dialogs_request(&arena, peers, 2, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_peer_dialogs_request(&arena, NULL, 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_peer_dialogs_request(NULL, peers, 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_peer_dialogs_request(&arena, peers, 1, NULL), EXTERIA_E_ARG);
}

static void test_community_collapse_request(void) {
    exteria_tl_value *request = NULL;
    exteria_writer w;
    exteria_tl_error error;
    CHECK_EQ_INT(exteria_community_collapse_request(&arena, 40, 940, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_communities_toggleCommunityCollapsedInDialogs);
    CHECK(exteria_tl_has(request, "collapsed"));
    exteria_writer_init(&w, 4096);
    CHECK_EQ_INT(exteria_tl_encode(request, &w, &error), EXTERIA_OK);
    exteria_writer_free(&w);
    CHECK_EQ_INT(exteria_community_collapse_request(&arena, 40, 940, 0, &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(request, "collapsed"));
    CHECK_EQ_INT(exteria_community_collapse_request(&arena, 40, 0, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

static void test_archive_shortcut(void) {
    exteria_dialog_row rows[3];
    memset(rows, 0, sizeof(rows));
    size_t count = 0;
    CHECK_EQ_INT(exteria_dialogs_ensure_archive(rows, 3, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].folder_id, 1);
    CHECK(rows[0].folder);
    rows[0].unread_count = 7;
    CHECK_EQ_INT(exteria_dialogs_ensure_archive(rows, 3, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].unread_count, 7);
    memset(rows, 0, sizeof(rows));
    rows[0].peer_id = 12;
    rows[1].peer_id = 13;
    count = 2;
    CHECK_EQ_INT(exteria_dialogs_ensure_archive(rows, 2, &count), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].peer_id, 12);
    CHECK_EQ_INT(exteria_dialogs_ensure_archive(rows, 3, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(rows[1].peer_id, 12);
    CHECK_EQ_INT(rows[2].peer_id, 13);
    CHECK_EQ_INT(exteria_dialogs_ensure_archive(NULL, 3, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dialogs_ensure_archive(rows, 3, NULL), EXTERIA_E_ARG);
}

static void test_archive_summary(void) {
    exteria_dialog_row summary;
    exteria_tl_value *f = obj("dialogFolder"), *folder = obj("folder");
    set_i32(folder, "id", 1);
    set(f, "folder", folder);
    set_flag(f, "pinned");
    set(f, "peer", peer("peerUser", "user_id", 5));
    set_i32(f, "top_message", 42);
    set_i32(f, "unread_unmuted_peers_count", 3);
    set_i32(f, "unread_muted_peers_count", 5);
    set_i32(f, "unread_muted_messages_count", 500);
    exteria_tl_value *info = answer("messages.peerDialogs", &f, 1, NULL, 0, NULL, 0, NULL, 0);
    exteria_tl_value *d[3] = {dialog(peer("peerUser", "user_id", 5), 42, 7),
        dialog(peer("peerUser", "user_id", 6), 9, 2), dialog(peer("peerUser", "user_id", 7), 4, 0)};
    set_flag(d[0], "pinned");
    set_i32(d[1], "folder_id", 1);
    set_i32(d[2], "folder_id", 1);
    exteria_tl_value *u[3] = {user(5, "Main pin", NULL), user(6, "Archive one", NULL), user(7, "Archive two", NULL)};
    exteria_tl_value *m = message(peer("peerUser", "user_id", 5), 42, 123, "wrong pinned message");
    exteria_tl_value *contents = answer("messages.dialogsSlice", d, 3, &m, 1, NULL, 0, u, 3);
    CHECK_EQ_INT(exteria_archive_summary_parse(info, contents, SELF, 0, &summary), EXTERIA_OK);
    CHECK(strcmp(summary.text, "Archive one, Archive two") == 0);
    CHECK_EQ_INT(summary.unread_count, 8);
    CHECK_EQ_INT(summary.muted, 0);
    CHECK_EQ_INT(summary.folder, 1);
    CHECK_EQ_INT(summary.preview, EXTERIA_PREVIEW_TEXT);
    CHECK_EQ_INT(summary.pinned, 0);
    CHECK_EQ_INT(summary.date, 0);
    CHECK_EQ_INT(summary.top_message, 0);
    CHECK_EQ_INT(summary.peer_id, 0);
    CHECK_EQ_INT(summary.sender[0], 0);
    CHECK_EQ_INT(summary.outgoing, 0);
    set_i32(f, "unread_unmuted_peers_count", 0);
    CHECK_EQ_INT(exteria_archive_summary_parse(info, contents, SELF, 0, &summary), EXTERIA_OK);
    CHECK_EQ_INT(summary.muted, 1);
    set_i32(f, "unread_unmuted_peers_count", INT32_MAX);
    CHECK_EQ_INT(exteria_archive_summary_parse(info, contents, SELF, 0, &summary), EXTERIA_OK);
    CHECK_EQ_INT(summary.unread_count, INT32_MAX);
    set_i32(f, "unread_unmuted_peers_count", -10);
    set_i32(f, "unread_muted_peers_count", -20);
    CHECK_EQ_INT(exteria_archive_summary_parse(info, contents, SELF, 0, &summary), EXTERIA_OK);
    CHECK_EQ_INT(summary.unread_count, 0);
    char name[125];
    memset(name, 'a', sizeof(name) - 1); name[sizeof(name) - 1] = 0;
    set_str(u[1], "first_name", name);
    set_str(u[2], "first_name", "😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀");
    CHECK_EQ_INT(exteria_archive_summary_parse(info, contents, SELF, 0, &summary), EXTERIA_OK);
    CHECK_EQ_INT(strlen(summary.text), 158);
    CHECK_EQ_INT((unsigned char)summary.text[157], 0x80);
    exteria_tl_value *empty = answer("messages.dialogs", NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    CHECK_EQ_INT(exteria_archive_summary_parse(info, empty, SELF, 0, &summary), EXTERIA_OK);
    CHECK_EQ_INT(summary.preview, EXTERIA_PREVIEW_NONE);
    CHECK_EQ_INT(summary.text[0], 0);
    CHECK_EQ_INT(exteria_archive_summary_parse(empty, contents, SELF, 0, &summary), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(summary.folder, 0);
    CHECK_EQ_INT(exteria_archive_summary_parse(empty, empty, SELF, 0, &summary), EXTERIA_OK);
    CHECK_EQ_INT(summary.folder, 1);
    CHECK_EQ_INT(summary.unread_count, 0);
    CHECK_EQ_INT(exteria_archive_summary_parse(NULL, empty, SELF, 0, &summary), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_archive_summary_parse(info, obj("messages.messages"), SELF, 0, &summary), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_archive_summary_parse(info, empty, SELF, 0, NULL), EXTERIA_E_ARG);
    set_i32(folder, "id", 2);
    CHECK_EQ_INT(exteria_archive_summary_parse(info, empty, SELF, 0, &summary), EXTERIA_E_MALFORMED);
}

static void test_saved_dialogs(void) {
    exteria_dialog_row rows[4];
    size_t count;
    exteria_tl_value *d[3], *m[3], *u[2], *request = NULL, *list;
    int32_t value = 0;
    exteria_tl_value *mine, *theirs;
    /* the dialogs of the favorites are keyed by the chat a message came from, which the message names in saved_peer_id and not in peer_id */
    d[0] = obj("savedDialog");
    set(d[0], "peer", peer("peerUser", "user_id", SELF));
    set_i32(d[0], "top_message", 7);
    d[1] = obj("savedDialog");
    set(d[1], "peer", peer("peerUser", "user_id", 5));
    set_i32(d[1], "top_message", 9);
    set_flag(d[1], "pinned");
    mine = message(peer("peerUser", "user_id", SELF), 7, 1000, "note");
    set(mine, "saved_peer_id", peer("peerUser", "user_id", SELF));
    theirs = message(peer("peerUser", "user_id", SELF), 9, 1100, "forwarded");
    set(theirs, "saved_peer_id", peer("peerUser", "user_id", 5));
    m[0] = mine;
    m[1] = theirs;
    u[0] = user(SELF, "Me", NULL);
    set_flag(u[0], "self");
    u[1] = user(5, "Ann", "Lee");
    list = answer("messages.savedDialogs", d, 2, m, 2, NULL, 0, u, 2);
    CHECK_EQ_INT(exteria_dialogs_parse(list, SELF, 0, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].saved, 1);
    CHECK_EQ_INT(rows[0].top_message, 7);
    CHECK(strcmp(rows[0].text, "note") == 0);
    CHECK_EQ_INT(rows[1].peer_id, 5);
    CHECK_EQ_INT(rows[1].pinned, 1);
    CHECK_EQ_INT(rows[1].date, 1100);
    CHECK(strcmp(rows[1].text, "forwarded") == 0);
    CHECK(strcmp(rows[1].title, "Ann Lee") == 0);
    list = answer("messages.savedDialogsSlice", d, 2, m, 2, NULL, 0, u, 2);
    set_i32(list, "count", 2);
    CHECK_EQ_INT(exteria_dialogs_parse(list, SELF, 0, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    /* an ordinary dialog in a saved answer, and a saved dialog in an ordinary one, are skipped */
    d[2] = dialog(peer("peerUser", "user_id", 5), 9, 0);
    list = answer("messages.savedDialogs", &d[2], 1, m, 2, NULL, 0, u, 2);
    CHECK_EQ_INT(exteria_dialogs_parse(list, SELF, 0, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    list = answer("messages.dialogs", d, 1, m, 2, NULL, 0, u, 2);
    CHECK_EQ_INT(exteria_dialogs_parse(list, SELF, 0, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    /* a message that came from elsewhere does not stand in for the preview */
    d[0] = obj("savedDialog");
    set(d[0], "peer", peer("peerUser", "user_id", 5));
    set_i32(d[0], "top_message", 7);
    list = answer("messages.savedDialogs", d, 1, m, 2, NULL, 0, u, 2);
    CHECK_EQ_INT(exteria_dialogs_parse(list, SELF, 0, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK(strcmp(rows[0].text, "") == 0);
    /* the request */
    CHECK_EQ_INT(exteria_saved_dialogs_request(&arena, 0, 0, 0, 0, 0, 50, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "limit", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 50);
    CHECK(exteria_tl_is(exteria_tl_get(request, "offset_peer"), EXTERIA_TL_ID_inputPeerEmpty));
    CHECK_EQ_INT(exteria_saved_dialogs_request(&arena, 1000, 9, 1, 5, 99, 50, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "offset_peer"), EXTERIA_TL_ID_inputPeerUser));
    CHECK_EQ_INT(exteria_saved_dialogs_request(&arena, 0, 0, 0, 0, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_dialogs_request(&arena, 0, 0, 0, 0, 0, EXTERIA_DIALOGS_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_dialogs_request(&arena, -1, 0, 0, 0, 0, 10, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_dialogs_request(&arena, 0, 0, 0, 0, 0, 10, NULL), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_noforwards_peer();
    test_archive_shortcut();
    test_archive_summary();
    test_user_and_saved();
    test_forwarded_last_message();
    test_mute_expired_and_unread();
    test_search_parse();
    test_found_parse();
    test_group_channel_and_sender();
    test_service_member_preview();
    test_channel_posting_rights();
    test_media_kinds();
    test_thumbs();
    test_caption_wins_and_cut();
    test_limits_and_errors();
    test_folder_and_hash();
    test_forum_topics();
    test_forum_topic_request();
    test_community_row();
    test_community_chats();
    test_community_collapse_request();
    test_community_previews();
    test_peer_dialogs_request();
    test_saved_dialogs();
    test_linked_community();
    exteria_arena_free(&arena);
    return test_finish("test_dialogs");
}
