#include <string.h>

#include "test_util.h"
#include "exteria_people.h"
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

static exteria_tl_value *user(int64_t id, const char *first, const char *last) {
    exteria_tl_value *u = obj("user");
    set_i64(u, "id", id);
    if (first) set_str(u, "first_name", first);
    if (last) set_str(u, "last_name", last);
    return u;
}

static void test_person(void) {
    exteria_person_row row;
    exteria_tl_value *u = user(7, "Ann", "Lee"), *status = obj("userStatusOffline");
    set_str(u, "username", "ann");
    set_str(u, "phone", "79990001122");
    set_flag(u, "verified");
    set_i32(status, "was_online", 1234);
    set(u, "status", status);
    set_i64(u, "access_hash", 4242);
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.id, 7);
    CHECK_EQ_INT(row.access_hash, 4242);
    CHECK(strcmp(row.name, "Ann Lee") == 0);
    CHECK(strcmp(row.username, "ann") == 0);
    CHECK(strcmp(row.phone, "79990001122") == 0);
    CHECK_EQ_INT(row.verified, 1);
    CHECK_EQ_INT(row.premium, 0);
    CHECK_EQ_INT(row.bot, 0);
    CHECK_EQ_INT(row.presence, EXTERIA_PRESENCE_OFFLINE);
    CHECK_EQ_INT(row.seen, 1234);

    {
        exteria_tl_value *service = user(EXTERIA_TELEGRAM_SERVICE_USER_ID, "Telegram", NULL);
        exteria_tl_value *online = obj("userStatusOnline");
        set_i32(online, "expires", 9999);
        set(service, "status", online);
        CHECK_EQ_INT(exteria_person_parse(service, &row), EXTERIA_OK);
        CHECK_EQ_INT(row.presence, EXTERIA_PRESENCE_UNKNOWN);
        CHECK_EQ_INT(row.seen, 0);
        CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
        CHECK_EQ_INT(row.presence, EXTERIA_PRESENCE_OFFLINE);
    }

    set_flag(u, "premium");
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.premium, 1);

    /* a deleted account keeps no last seen time, and is told apart from a user whose status is simply absent */
    set_flag(u, "deleted");
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.deleted, 1);
    CHECK_EQ_INT(row.presence, EXTERIA_PRESENCE_DELETED);
    CHECK_EQ_INT(row.seen, 0);
    u = user(8, "Bob", NULL);
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.deleted, 0);
    CHECK_EQ_INT(row.presence, EXTERIA_PRESENCE_UNKNOWN);

    /* a user seen only through a mention has a hash that is no use for this account */
    set_flag(u, "min");
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.access_hash, 0);

    u = user(8, NULL, NULL);
    set_str(u, "username", "solo");
    set_flag(u, "bot");
    set(u, "status", obj("userStatusOnline"));
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK(strcmp(row.name, "solo") == 0);
    CHECK_EQ_INT(row.bot, 1);
    CHECK_EQ_INT(row.presence, EXTERIA_PRESENCE_ONLINE);

    u = user(9, "Only", NULL);
    set(u, "status", obj("userStatusLastWeek"));
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK(strcmp(row.name, "Only") == 0);
    CHECK_EQ_INT(row.presence, EXTERIA_PRESENCE_LAST_WEEK);
    set(u, "status", obj("userStatusRecently"));
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.presence, EXTERIA_PRESENCE_RECENTLY);
    set(u, "status", obj("userStatusLastMonth"));
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.presence, EXTERIA_PRESENCE_LAST_MONTH);

    CHECK_EQ_INT(exteria_person_parse(obj("userEmpty"), &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(row.id, 0);
    CHECK_EQ_INT(exteria_person_parse(obj("user"), &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_person_parse(NULL, &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_person_parse(u, NULL), EXTERIA_E_ARG);
}

static void test_emoji_status(void) {
    exteria_person_row row;
    exteria_tl_value *u = user(21, "Pro", NULL), *status;
    int64_t doc = 99;
    int32_t until = 99;
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.emoji_status, 0);
    CHECK_EQ_INT(row.emoji_status_until, 0);

    status = obj("emojiStatus");
    set_i64(status, "document_id", 5368324170671202286LL);
    set(u, "emoji_status", status);
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.emoji_status, 5368324170671202286LL);
    CHECK_EQ_INT(row.emoji_status_until, 0);

    status = obj("emojiStatus");
    set_i64(status, "document_id", 77);
    set_i32(status, "until", 1900000000);
    set(u, "emoji_status", status);
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.emoji_status, 77);
    CHECK_EQ_INT(row.emoji_status_until, 1900000000);

    status = obj("emojiStatusCollectible");
    set_i64(status, "document_id", 88);
    set(u, "emoji_status", status);
    exteria_emoji_status_read(u, &doc, &until);
    CHECK_EQ_INT(doc, 88);
    CHECK_EQ_INT(until, 0);

    /* an empty status, a zero document and a user without the field show nothing, and the outputs are defined */
    set(u, "emoji_status", obj("emojiStatusEmpty"));
    exteria_emoji_status_read(u, &doc, &until);
    CHECK_EQ_INT(doc, 0);
    CHECK_EQ_INT(until, 0);
    status = obj("emojiStatus");
    set_i64(status, "document_id", 0);
    set_i32(status, "until", 5);
    set(u, "emoji_status", status);
    exteria_emoji_status_read(u, &doc, &until);
    CHECK_EQ_INT(doc, 0);
    CHECK_EQ_INT(until, 0);
    status = obj("emojiStatus");
    set_i64(status, "document_id", 5);
    set_i32(status, "until", -3);
    set(u, "emoji_status", status);
    exteria_emoji_status_read(u, &doc, &until);
    CHECK_EQ_INT(doc, 5);
    CHECK_EQ_INT(until, 0);
    exteria_emoji_status_read(NULL, &doc, &until);
    CHECK_EQ_INT(doc, 0);
    exteria_emoji_status_read(obj("boolTrue"), NULL, NULL);
}

static void test_backdrop(void) {
    exteria_person_row row;
    exteria_tl_value *u = user(31, "Gift", NULL), *status, *color, *items[3];
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.has_backdrop, 0);
    /* a collectible status gives the colors, the tiles and the name with the number from the slug */
    status = obj("emojiStatusCollectible");
    set_i64(status, "collectible_id", 5);
    set_i64(status, "document_id", 88);
    set_str(status, "title", "Cookie Heart");
    set_str(status, "slug", "CookieHeart-5916");
    set_i64(status, "pattern_document_id", 4242);
    set_i32(status, "center_color", 0xD79A3C);
    set_i32(status, "edge_color", 0xB5602F);
    set_i32(status, "pattern_color", 0xFFE0A0);
    set_i32(status, "text_color", 0xFFFFFF);
    set(u, "emoji_status", status);
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.has_backdrop, 1);
    CHECK_EQ_INT(row.backdrop_center, 0xD79A3Cu);
    CHECK_EQ_INT(row.backdrop_edge, 0xB5602Fu);
    CHECK_EQ_INT(row.backdrop_pattern, 0xFFE0A0u);
    CHECK_EQ_INT(row.backdrop_text, 0xFFFFFFu);
    CHECK_EQ_INT(row.backdrop_pattern_document, 4242);
    CHECK(!strcmp(row.backdrop_title, "Cookie Heart #5916"));
    /* a slug with no number after its dash leaves the title as it is */
    set_str(status, "slug", "CookieHeart-x");
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK(!strcmp(row.backdrop_title, "Cookie Heart"));
    /* a collectible profile color wins over the status, and takes its colors from the list */
    color = obj("peerColorCollectible");
    set_i64(color, "collectible_id", 6);
    set_i64(color, "gift_emoji_id", 7);
    set_i64(color, "background_emoji_id", 9001);
    set_i32(color, "accent_color", 0x112233);
    items[0] = exteria_tl_new_i32(&arena, 0x445566);
    items[1] = exteria_tl_new_i32(&arena, 0x778899);
    set(color, "colors", vec_of(items, 2));
    set(u, "profile_color", color);
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.has_backdrop, 1);
    CHECK_EQ_INT(row.backdrop_center, 0x445566u);
    CHECK_EQ_INT(row.backdrop_edge, 0x778899u);
    CHECK_EQ_INT(row.backdrop_pattern, 0x112233u);
    CHECK_EQ_INT(row.backdrop_pattern_document, 9001);
    CHECK_EQ_INT(row.backdrop_title[0], 0);
    /* one color is both ends, and a list with none is no backdrop; a plain status and a plain color index give none either */
    set(color, "colors", vec_of(items, 1));
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.backdrop_edge, 0x445566u);
    set(color, "colors", vec_of(items, 0));
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.has_backdrop, 0);
    set(u, "profile_color", obj("peerColor"));
    set(u, "emoji_status", obj("emojiStatusEmpty"));
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.has_backdrop, 0);
}

static exteria_tl_value *colors_of(uint32_t first, uint32_t second, int two) {
    exteria_tl_value *items[2], *colors = obj("help.peerColorProfileSet");
    items[0] = exteria_tl_new_i32(&arena, (int32_t)first);
    items[1] = exteria_tl_new_i32(&arena, (int32_t)second);
    set(colors, "palette_colors", vec_of(items, 1));
    set(colors, "bg_colors", vec_of(items, two ? 2 : 1));
    set(colors, "story_colors", vec_of(items, 1));
    return colors;
}

static exteria_tl_value *option(int32_t id, exteria_tl_value *light, exteria_tl_value *dark) {
    exteria_tl_value *o = obj("help.peerColorOption");
    set_i32(o, "color_id", id);
    if (light) set(o, "colors", light);
    if (dark) set(o, "dark_colors", dark);
    return o;
}

static void test_profile_colors(void) {
    exteria_person_row row;
    exteria_profile_color rows[8];
    exteria_tl_value *u = user(41, "Tint", NULL), *color, *request = NULL, *answer, *items[4];
    size_t count = 0;
    int32_t hash = -1;
    /* a plain color index and its emoji on the user */
    color = obj("peerColor");
    set_i32(color, "color", 12);
    set_i64(color, "background_emoji_id", 555);
    set(u, "profile_color", color);
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.has_profile_color, 1);
    CHECK_EQ_INT(row.profile_color_id, 12);
    CHECK_EQ_INT(row.profile_color_emoji, 555);
    CHECK_EQ_INT(row.has_backdrop, 0);
    set(u, "profile_color", obj("peerColor"));
    CHECK_EQ_INT(exteria_person_parse(u, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.has_profile_color, 0);
    /* the request and the list: dark colors when the server sends them, one color for both ends, and no row for an option without colors */
    CHECK_EQ_INT(exteria_profile_colors_request(&arena, 77, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_help_getPeerProfileColors);
    CHECK_EQ_INT(exteria_profile_colors_request(NULL, 0, &request), EXTERIA_E_ARG);
    items[0] = option(3, colors_of(0xAA0000, 0xBB1111, 1), colors_of(0x220000, 0x331111, 1));
    items[1] = option(4, colors_of(0x00AA00, 0, 0), NULL);
    items[2] = option(5, NULL, NULL);
    answer = obj("help.peerColors");
    set_i32(answer, "hash", 4242);
    set(answer, "colors", vec_of(items, 3));
    CHECK_EQ_INT(exteria_profile_colors_parse(answer, rows, 8, &count, &hash), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(hash, 4242);
    CHECK_EQ_INT(rows[0].id, 3);
    CHECK_EQ_INT(rows[0].bg[0], 0xAA0000u);
    CHECK_EQ_INT(rows[0].bg[1], 0xBB1111u);
    CHECK_EQ_INT(rows[0].has_dark, 1);
    CHECK_EQ_INT(rows[0].dark_bg[0], 0x220000u);
    CHECK_EQ_INT(rows[1].id, 4);
    CHECK_EQ_INT(rows[1].bg[0], 0x00AA00u);
    CHECK_EQ_INT(rows[1].bg[1], 0x00AA00u);
    CHECK_EQ_INT(rows[1].has_dark, 0);
    CHECK_EQ_INT(exteria_profile_colors_parse(answer, rows, 1, &count, NULL), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_profile_colors_parse(obj("help.peerColorsNotModified"), rows, 8, &count, &hash), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_profile_colors_parse(obj("boolTrue"), rows, 8, &count, &hash), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_profile_colors_parse(NULL, rows, 8, &count, &hash), EXTERIA_E_ARG);
}

static void test_contacts(void) {
    exteria_person_row rows[3];
    size_t count;
    exteria_tl_value *users[3], *a = obj("contacts.contacts");
    users[0] = user(1, "A", NULL);
    set_flag(users[0], "contact");
    set_flag(users[0], "mutual_contact");
    users[1] = obj("userEmpty");
    users[2] = user(3, "C", NULL);
    set(a, "users", vec_of(users, 3));
    CHECK_EQ_INT(exteria_contacts_parse(a, rows, 3, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[1].id, 3);
    /* a contact who has the account in the contacts too is marked, one who has not is not */
    CHECK_EQ_INT(rows[0].mutual, 1);
    CHECK_EQ_INT(rows[0].contact, 1);
    CHECK_EQ_INT(rows[1].mutual, 0);
    CHECK_EQ_INT(exteria_contacts_parse(a, rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_contacts_parse(obj("contacts.contactsNotModified"), rows, 3, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_contacts_parse(obj("contacts.contacts"), rows, 3, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_contacts_parse(a, rows, 0, &count), EXTERIA_E_ARG);
}

static void test_channel_person(void) {
    exteria_person_row row;
    exteria_tl_value *c = obj("channel"), *photo = obj("chatPhoto");
    set_i64(c, "id", 1234);
    set_i64(c, "access_hash", 77);
    set_str(c, "title", "News");
    set_str(c, "username", "news");
    set_flag(c, "verified");
    set_i64(photo, "photo_id", 900);
    set_i32(photo, "dc_id", 4);
    set(c, "photo", photo);
    CHECK_EQ_INT(exteria_channel_person_parse(c, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.id, 1234);
    CHECK_EQ_INT(row.access_hash, 77);
    CHECK(!strcmp(row.name, "News"));
    CHECK_EQ_INT(row.verified, 1);
    CHECK_EQ_INT(row.photo.photo_id, 900);
    CHECK_EQ_INT(row.photo.peer_kind, 3);
    CHECK_EQ_INT(row.photo.peer_id, 1234);
    /* a channel seen only in part has no hash that works for this account, so it has no photo location either */
    set_flag(c, "min");
    CHECK_EQ_INT(exteria_channel_person_parse(c, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.access_hash, 0);
    CHECK_EQ_INT(row.photo.photo_id, 0);
    CHECK_EQ_INT(exteria_channel_person_parse(user(5, "A", NULL), &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(row.id, 0);
    CHECK_EQ_INT(exteria_channel_person_parse(NULL, &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_channel_person_parse(c, NULL), EXTERIA_E_ARG);
}

static void test_sender_kinds(void) {
    static const char *const kinds[] = {"channel", "community", "channelForbidden", "communityForbidden"};
    exteria_person_row row;
    size_t i;
    for (i = 0; i < sizeof(kinds) / sizeof(kinds[0]); ++i) {
        exteria_tl_value *sender = obj(kinds[i]);
        int64_t id = INT64_C(4294967399) + (int64_t)i;
        set_i64(sender, "id", id);
        set_i64(sender, "access_hash", 77);
        set_str(sender, "title", "Community\nname");
        if (i < 2) {
            exteria_tl_value *photo = obj("chatPhoto");
            set_i64(photo, "photo_id", 900);
            set_i32(photo, "dc_id", 4);
            set(sender, "photo", photo);
        }
        CHECK_EQ_INT(exteria_channel_person_parse(sender, &row), EXTERIA_OK);
        CHECK_EQ_INT(row.id, id);
        CHECK_EQ_INT(row.access_hash, 77);
        CHECK(!strcmp(row.name, "Community name"));
        CHECK_EQ_INT(row.photo.photo_id, i < 2 ? 900 : 0);
        if (i < 2) {
            CHECK_EQ_INT(row.photo.peer_kind, 3);
            CHECK_EQ_INT(row.photo.peer_id, id);
            set_flag(sender, "min");
            CHECK_EQ_INT(exteria_channel_person_parse(sender, &row), EXTERIA_OK);
            CHECK(!strcmp(row.name, "Community name"));
            CHECK_EQ_INT(row.access_hash, 0);
            CHECK_EQ_INT(row.photo.photo_id, 0);
        }
        set_i64(sender, "id", 0);
        CHECK_EQ_INT(exteria_channel_person_parse(sender, &row), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(row.id, 0);
        CHECK(!row.name[0]);
        set_i64(sender, "id", -1);
        CHECK_EQ_INT(exteria_channel_person_parse(sender, &row), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(row.id, 0);
    }
    {
        exteria_tl_value *sender = obj("communityForbidden");
        set_i64(sender, "id", 3);
        set_str(sender, "title", "Title only");
        CHECK_EQ_INT(exteria_channel_person_parse(sender, &row), EXTERIA_OK);
        CHECK(!strcmp(row.name, "Title only"));
        CHECK_EQ_INT(row.access_hash, 0);
        CHECK_EQ_INT(row.photo.photo_id, 0);
    }
    CHECK_EQ_INT(exteria_channel_person_parse(obj("chat"), &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(row.id, 0);
}

static void test_group_roles(void) {
    static const char *const names[] = {"channelParticipantCreator", "channelParticipantAdmin", "channelParticipant", "chatParticipantCreator", "chatParticipantAdmin", "chatParticipant"};
    exteria_group_role rows[4];
    exteria_tl_value *answer = obj("channels.channelParticipants"), *parts[3], *request;
    size_t count = 99;
    exteria_writer encoded;
    int64_t id = INT64_C(4294967400);
    for (int kind = 2; kind <= 3; ++kind) {
        CHECK_EQ_INT(exteria_group_roles_request(&arena, kind, id, 77, &request), EXTERIA_OK);
        CHECK(exteria_tl_is(request, kind == 2 ? EXTERIA_TL_ID_messages_getFullChat : EXTERIA_TL_ID_channels_getParticipants));
        exteria_writer_init(&encoded, 1024);
        CHECK_EQ_INT(exteria_tl_encode(request, &encoded, NULL), EXTERIA_OK);
        exteria_writer_free(&encoded);
    }
    CHECK_EQ_INT(exteria_group_roles_request(&arena, 1, id, 77, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_group_roles_request(&arena, 3, 0, 77, &request), EXTERIA_E_ARG);
    for (int basic = 0; basic < 2; ++basic) {
        for (int i = 0; i < 3; ++i) {
            parts[i] = obj(names[basic * 3 + i]);
            set_i64(parts[i], "user_id", id + i);
        }
        set_str(parts[0], "rank", "custom\nowner");
        set_str(parts[2], "rank", "member tag");
        if (!basic) {
            set_i32(answer, "count", 3);
            set(answer, "participants", vec_of(parts, 3));
        } else {
            exteria_tl_value *full = obj("chatFull"), *group = obj("chatParticipants");
            answer = obj("messages.chatFull");
            set_i64(full, "id", id);
            set_i64(group, "chat_id", id);
            set(group, "participants", vec_of(parts, 3));
            set(full, "participants", group);
            set(answer, "full_chat", full);
            CHECK_EQ_INT(exteria_group_roles_parse(answer, id + 1, rows, 4, &count), EXTERIA_E_MALFORMED);
            CHECK_EQ_INT(count, 0);
        }
        CHECK_EQ_INT(exteria_group_roles_parse(answer, id, rows, 4, &count), EXTERIA_OK);
        CHECK_EQ_INT(count, 3);
        CHECK_EQ_INT(rows[0].user_id, id);
        CHECK(rows[0].owner && rows[0].admin);
        CHECK(!strcmp(rows[0].rank, "custom owner"));
        CHECK(!rows[1].owner && rows[1].admin);
        CHECK(!rows[1].rank[0]);
        CHECK(!rows[2].owner && !rows[2].admin);
        CHECK(!strcmp(rows[2].rank, "member tag"));
        CHECK_EQ_INT(exteria_group_roles_parse(answer, id, rows, 2, &count), EXTERIA_E_LIMIT);
        CHECK_EQ_INT(count, 0);
        set_i64(parts[1], "user_id", 0);
        CHECK_EQ_INT(exteria_group_roles_parse(answer, id, rows, 4, &count), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(count, 0);
    }
    answer = obj("channels.channelParticipants");
    set_i32(answer, "count", 1);
    set(answer, "participants", vec_of(NULL, 0));
    CHECK_EQ_INT(exteria_group_roles_parse(answer, id, rows, 4, &count), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count, 0);
    set_i32(answer, "count", 0);
    CHECK_EQ_INT(exteria_group_roles_parse(answer, id, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_group_roles_parse(obj("boolTrue"), id, rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_group_roles_parse(NULL, id, rows, 4, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_group_roles_parse(answer, id, rows, 0, &count), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_person();
    test_emoji_status();
    test_backdrop();
    test_profile_colors();
    test_contacts();
    test_channel_person();
    test_sender_kinds();
    test_group_roles();
    exteria_arena_free(&arena);
    return test_finish("test_people");
}
