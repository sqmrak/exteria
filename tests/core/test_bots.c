#include "test_util.h"
#include "exteria_bots.h"
#include "exteria_tl_ids.h"
#include "srp_vectors.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set(exteria_tl_value *v, const char *field, exteria_tl_value *x) {
    CHECK_EQ_INT(exteria_tl_set(v, field, x), EXTERIA_OK);
}
static void i32(exteria_tl_value *v, const char *field, int32_t x) {
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, field, x), EXTERIA_OK);
}
static void i64(exteria_tl_value *v, const char *field, int64_t x) {
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, field, x), EXTERIA_OK);
}
static void str(exteria_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, field, x), EXTERIA_OK);
}
static void flag(exteria_tl_value *v, const char *field) {
    CHECK_EQ_INT(exteria_tl_set_flag(v, field), EXTERIA_OK);
}
static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *vec = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(vec, i, items[i]), EXTERIA_OK);
    return vec;
}

/* a request has to encode with the schema's own rules, which catches a misspelled field or a missing flag */
static void roundtrip(exteria_tl_value *request, uint32_t constructor) {
    exteria_writer writer;
    exteria_tl_value *decoded = NULL;
    CHECK(request != NULL);
    exteria_writer_init(&writer, 65536);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, writer.data, writer.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), constructor);
    exteria_writer_free(&writer);
}

static exteria_tl_value *user(int64_t id, const char *name, int bot) {
    exteria_tl_value *v = obj("user");
    i64(v, "id", id);
    i64(v, "access_hash", id * 10);
    str(v, "first_name", name);
    str(v, "username", name);
    if (bot) {
        flag(v, "bot");
        flag(v, "bot_inline_geo");
        str(v, "bot_inline_placeholder", "search cats");
    }
    return v;
}

static exteria_tl_value *peer_user(int64_t id) {
    exteria_tl_value *p = obj("peerUser");
    i64(p, "user_id", id);
    return p;
}

static const exteria_peer_ref bot = {1, 77, 770, 0, 0};
static const exteria_peer_ref chat = {1, 5, 50, 0, 0};
static const exteria_peer_ref group = {2, 9, 0, 0, 0};
static const exteria_peer_ref forum = {3, 12, 120, 0, 44};

static void test_resolve(void) {
    exteria_tl_value *request = NULL, *answer, *users[1];
    exteria_resolved resolved;
    CHECK_EQ_INT(exteria_resolve_request(&arena, "durov_bot", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_contacts_resolveUsername);
    CHECK_EQ_INT(exteria_resolve_request(&arena, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_resolve_request(&arena, "a b", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_resolve_request(&arena, "a/b", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_resolve_request(&arena, "@bot", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_resolve_request(&arena, "012345678901234567890123456789012", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_resolve_request(&arena, NULL, &request), EXTERIA_E_ARG);

    answer = obj("contacts.resolvedPeer");
    set(answer, "peer", peer_user(77));
    users[0] = user(77, "helper_bot", 1);
    set(answer, "users", vec_of(users, 1));
    set(answer, "chats", vec_of(NULL, 0));
    CHECK_EQ_INT(exteria_resolve_parse(answer, 1, &resolved), EXTERIA_OK);
    CHECK_EQ_INT(resolved.is_user, 1);
    CHECK_EQ_INT(resolved.dialog.peer_kind, 1);
    CHECK_EQ_INT(resolved.dialog.peer_id, 77);
    CHECK_EQ_INT(resolved.dialog.peer_hash, 770);
    CHECK_EQ_INT(resolved.dialog.kind, EXTERIA_DIALOG_BOT);
    CHECK_EQ_INT(resolved.person.bot, 1);
    CHECK_EQ_INT(resolved.person.bot_inline, 1);
    CHECK_EQ_INT(resolved.person.bot_inline_geo, 1);
    CHECK_EQ_INT(resolved.person.bot_no_chats, 0);
    CHECK(!strcmp(resolved.person.bot_placeholder, "search cats"));

    /* a person has none of the bot flags even when the answer carried the fields */
    users[0] = user(78, "friend", 0);
    set(answer, "peer", peer_user(78));
    set(answer, "users", vec_of(users, 1));
    CHECK_EQ_INT(exteria_resolve_parse(answer, 1, &resolved), EXTERIA_OK);
    CHECK_EQ_INT(resolved.person.bot, 0);
    CHECK_EQ_INT(resolved.person.bot_inline, 0);
    CHECK_EQ_INT(resolved.dialog.kind, EXTERIA_DIALOG_USER);

    /* the peer is not among the users */
    set(answer, "peer", peer_user(99));
    CHECK_EQ_INT(exteria_resolve_parse(answer, 1, &resolved), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(resolved.dialog.peer_id, 0);
    CHECK_EQ_INT(exteria_resolve_parse(obj("boolTrue"), 1, &resolved), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_resolve_parse(answer, 1, NULL), EXTERIA_E_ARG);
}

static exteria_tl_value *channel_obj(int64_t id, const char *title) {
    exteria_tl_value *c = obj("channel");
    i64(c, "id", id);
    str(c, "title", title);
    flag(c, "broadcast");
    i64(c, "access_hash", id * 10);
    return c;
}

static void test_invite(void) {
    exteria_tl_value *request = NULL, *answer, *items[2], *updates, *joined;
    exteria_invite invite;
    exteria_dialog_row row;
    CHECK_EQ_INT(exteria_invite_check_request(&arena, "AbC-d_1", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_checkChatInvite);
    CHECK_EQ_INT(exteria_invite_import_request(&arena, "AbC-d_1", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_importChatInvite);
    CHECK_EQ_INT(exteria_invite_check_request(&arena, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_invite_import_request(&arena, "a b", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_invite_check_request(&arena, NULL, &request), EXTERIA_E_ARG);

    answer = obj("chatInvite");
    flag(answer, "channel");
    flag(answer, "broadcast");
    flag(answer, "request_needed");
    str(answer, "title", "Secret\nclub");
    str(answer, "about", "line one\nline two");
    i32(answer, "participants_count", 4200);
    CHECK_EQ_INT(exteria_invite_parse(answer, 1, &invite), EXTERIA_OK);
    CHECK_EQ_INT(invite.member, 0);
    CHECK_EQ_INT(invite.broadcast, 1);
    CHECK_EQ_INT(invite.request_needed, 1);
    CHECK_EQ_INT(invite.participants, 4200);
    CHECK(!strcmp(invite.title, "Secret club"));
    CHECK(!strcmp(invite.about, "line one\nline two"));

    answer = obj("chatInvite");
    str(answer, "title", "");
    CHECK_EQ_INT(exteria_invite_parse(answer, 1, &invite), EXTERIA_E_MALFORMED);

    answer = obj("chatInviteAlready");
    set(answer, "chat", channel_obj(500, "Known"));
    CHECK_EQ_INT(exteria_invite_parse(answer, 1, &invite), EXTERIA_OK);
    CHECK_EQ_INT(invite.member, 1);
    CHECK_EQ_INT(invite.dialog.peer_kind, 3);
    CHECK_EQ_INT(invite.dialog.peer_id, 500);
    CHECK_EQ_INT(invite.dialog.peer_hash, 5000);
    CHECK(!strcmp(invite.title, "Known"));
    CHECK_EQ_INT(exteria_invite_parse(obj("boolTrue"), 1, &invite), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_invite_parse(answer, 1, NULL), EXTERIA_E_ARG);

    joined = obj("messages.chatInviteJoinResultOk");
    updates = obj("updates");
    items[0] = channel_obj(600, "Joined");
    set(updates, "chats", vec_of(items, 1));
    set(updates, "users", vec_of(NULL, 0));
    set(updates, "updates", vec_of(NULL, 0));
    i32(updates, "date", 1);
    i32(updates, "seq", 1);
    set(joined, "updates", updates);
    CHECK_EQ_INT(exteria_invite_joined_parse(joined, 1, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.peer_kind, 3);
    CHECK_EQ_INT(row.peer_id, 600);
    CHECK(!strcmp(row.title, "Joined"));

    set(updates, "chats", vec_of(NULL, 0));
    CHECK_EQ_INT(exteria_invite_joined_parse(joined, 1, &row), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_invite_joined_parse(obj("messages.chatInviteJoinResultWebView"), 1, &row), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_invite_joined_parse(obj("boolTrue"), 1, &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_invite_joined_parse(joined, 1, NULL), EXTERIA_E_ARG);
}

static exteria_tl_value *command(const char *name, const char *text) {
    exteria_tl_value *c = obj("botCommand");
    str(c, "command", name);
    str(c, "description", text);
    return c;
}

static exteria_tl_value *full_user(exteria_tl_value *bot_info) {
    exteria_tl_value *full = obj("userFull"), *answer = obj("users.userFull");
    i64(full, "id", 77);
    str(full, "about", "about me");
    if (bot_info) set(full, "bot_info", bot_info);
    set(answer, "full_user", full);
    set(answer, "users", vec_of(NULL, 0));
    set(answer, "chats", vec_of(NULL, 0));
    return answer;
}

static void test_bot_info(void) {
    static exteria_bot_info info;
    exteria_tl_value *b = obj("botInfo"), *commands[5], *menu = obj("botMenuButton"), *answer;
    exteria_tl_value *ephemeral = command("hidden", "temporary");
    flag(ephemeral, "ephemeral");
    str(b, "description", "I search cats.\nSend a name.");
    str(b, "privacy_policy_url", "https://example.org/privacy");
    commands[0] = command("start", "Begin");
    commands[1] = command("help", "What I can do");
    commands[2] = ephemeral;
    commands[3] = command("bad name", "has a space");
    commands[4] = command("long_command_", "x");
    set(b, "commands", vec_of(commands, 5));
    str(menu, "text", "Open");
    str(menu, "url", "https://app.example.org/");
    set(b, "menu_button", menu);
    answer = full_user(b);
    CHECK_EQ_INT(exteria_bot_info_parse(answer, &info), EXTERIA_OK);
    CHECK_EQ_INT(info.present, 1);
    CHECK(!strcmp(info.description, "I search cats.\nSend a name."));
    CHECK(!strcmp(info.privacy_url, "https://example.org/privacy"));
    /* a web app menu button is not opened here, so the bot keeps the default menu */
    CHECK_EQ_INT(info.menu_kind, EXTERIA_BOT_MENU_DEFAULT);
    CHECK_EQ_INT(info.has_picture, 0);
    /* the temporary command and the one with a space in its name are not offered */
    CHECK_EQ_INT(info.command_count, 3);
    CHECK(!strcmp(info.commands[0].name, "start"));
    CHECK(!strcmp(info.commands[1].text, "What I can do"));
    CHECK(!strcmp(info.commands[2].name, "long_command_"));

    b = obj("botInfo");
    set(b, "menu_button", obj("botMenuButtonCommands"));
    CHECK_EQ_INT(exteria_bot_info_parse(full_user(b), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.menu_kind, EXTERIA_BOT_MENU_COMMANDS);
    CHECK_EQ_INT(info.command_count, 0);
    b = obj("botInfo");
    set(b, "menu_button", obj("botMenuButtonDefault"));
    CHECK_EQ_INT(exteria_bot_info_parse(full_user(b), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.menu_kind, EXTERIA_BOT_MENU_DEFAULT);

    CHECK_EQ_INT(exteria_bot_info_parse(full_user(NULL), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.present, 0);
    CHECK_EQ_INT(exteria_bot_info_parse(obj("boolTrue"), &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bot_info_parse(answer, NULL), EXTERIA_E_ARG);
}

static void test_start(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref no_hash = {1, 77, 0, 0, 0};
    CHECK_EQ_INT(exteria_start_bot_request(&arena, &bot, &chat, 5, "", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_startBot);
    CHECK_EQ_INT(exteria_start_bot_request(&arena, &bot, &group, 5, "ref_1-a", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_startBot);
    CHECK_EQ_INT(exteria_start_bot_request(&arena, &bot, &chat, 0, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_start_bot_request(&arena, &bot, &chat, 5, "a b", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_start_bot_request(&arena, &bot, &chat, 5, "x/y", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_start_bot_request(&arena, &bot, &chat, 5, "0123456789012345678901234567890123456789012345678901234567890123x", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_start_bot_request(&arena, &no_hash, &chat, 5, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_start_bot_request(&arena, &group, &chat, 5, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_start_bot_request(&arena, &bot, &chat, 5, NULL, &request), EXTERIA_E_ARG);
}

/* the number a contact is added by, and what the server says of it */
static void test_contact_import(void) {
    exteria_tl_value *request = NULL, *answer, *none;
    size_t count = 9;
    CHECK_EQ_INT(exteria_contact_import_request(&arena, "+79001112233", "Ann", "", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_contacts_importContacts);
    CHECK_EQ_INT(exteria_contact_import_request(&arena, "79001112233", "Ann", "Lee", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_contact_import_request(&arena, "7900", "Ann", "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_contact_import_request(&arena, "+7 900 111", "Ann", "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_contact_import_request(&arena, "+790011122334455667788", "Ann", "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_contact_import_request(&arena, NULL, "Ann", "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_contact_import_request(&arena, "79001112233", "", "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_contact_import_request(&arena, "79001112233", "Ann", NULL, &request), EXTERIA_E_ARG);
    answer = obj("contacts.importedContacts");
    none = exteria_tl_new_vec(&arena, 0);
    CHECK_EQ_INT(exteria_tl_set(answer, "imported", none), EXTERIA_OK);
    CHECK_EQ_INT(exteria_contact_import_parse(answer, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 0);
    CHECK_EQ_INT(exteria_contact_import_parse(obj("boolTrue"), &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_contact_import_parse(answer, NULL), EXTERIA_E_ARG);
}

/* the name the person gives a contact */
static void test_contact_edit(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref no_hash = {1, 77, 0, 0, 0};
    char big[EXTERIA_CONTACT_NAME_MAX + 1];
    CHECK_EQ_INT(exteria_contact_edit_request(&arena, &bot, "Ann", "Lee", "79001112233", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_contacts_addContact);
    CHECK_EQ_INT(exteria_contact_edit_request(&arena, &bot, "Ann", "", "", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_contact_edit_request(&arena, &bot, "", "Lee", "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_contact_edit_request(&arena, &bot, NULL, "Lee", "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_contact_edit_request(&arena, &bot, "Ann", NULL, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_contact_edit_request(&arena, &no_hash, "Ann", "", "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_contact_edit_request(&arena, &group, "Ann", "", "", &request), EXTERIA_E_ARG);
    memset(big, 'a', sizeof(big));
    big[EXTERIA_CONTACT_NAME_MAX] = 0;
    CHECK_EQ_INT(exteria_contact_edit_request(&arena, &bot, big, "", "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_contact_edit_request(&arena, &bot, "Ann", big, "", &request), EXTERIA_E_ARG);
}

static exteria_tl_value *account_password(void) {
    exteria_tl_value *algo = obj("passwordKdfAlgoSHA256SHA256PBKDF2HMACSHA512iter100000SHA256ModPow"), *info = obj("account.password");
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, algo, "salt1", srp_salt1, sizeof(srp_salt1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, algo, "salt2", srp_salt2, sizeof(srp_salt2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, algo, "p", srp_prime, sizeof(srp_prime)), EXTERIA_OK);
    i32(algo, "g", 3);
    flag(info, "has_password");
    set(info, "current_algo", algo);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, info, "srp_B", srp_B, sizeof(srp_B)), EXTERIA_OK);
    i64(info, "srp_id", 35);
    return info;
}

static void test_callback(void) {
    exteria_tl_value *request = NULL, *answer, *check = NULL;
    static const uint8_t data[] = {'a', 0, 'b'};
    static exteria_callback_answer reply;
    uint8_t big[EXTERIA_MARKUP_DATA_MAX + 1];
    memset(big, 'x', sizeof(big));
    CHECK_EQ_INT(exteria_callback_request(&arena, &chat, 12, data, sizeof(data), 0, NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "data"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "game"), 0);
    roundtrip(request, EXTERIA_TL_ID_messages_getBotCallbackAnswer);
    /* a press with an empty payload still carries the field, otherwise the server takes it for another button */
    CHECK_EQ_INT(exteria_callback_request(&arena, &chat, 12, NULL, 0, 0, NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "data"), 1);
    roundtrip(request, EXTERIA_TL_ID_messages_getBotCallbackAnswer);
    CHECK_EQ_INT(exteria_callback_request(&arena, &group, 12, NULL, 0, 1, NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "data"), 0);
    CHECK_EQ_INT(exteria_tl_has(request, "game"), 1);
    roundtrip(request, EXTERIA_TL_ID_messages_getBotCallbackAnswer);
    CHECK_EQ_INT(exteria_callback_request(&arena, &chat, 0, data, sizeof(data), 0, NULL, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_callback_request(&arena, &chat, 12, big, sizeof(big), 0, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_callback_request(&arena, &chat, 12, NULL, 3, 0, NULL, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_password_input(&arena, account_password(), "hunter2", &check), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(check), EXTERIA_TL_ID_inputCheckPasswordSRP);
    CHECK_EQ_INT(exteria_callback_request(&arena, &chat, 12, data, sizeof(data), 0, check, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "password"), 1);
    roundtrip(request, EXTERIA_TL_ID_messages_getBotCallbackAnswer);
    {
        exteria_tl_value *none = obj("account.password");
        CHECK_EQ_INT(exteria_password_input(&arena, none, "x", &check), EXTERIA_E_UNSUPPORTED);
        CHECK(check == NULL);
    }
    CHECK_EQ_INT(exteria_password_input(&arena, account_password(), "", &check), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_password_input(&arena, obj("boolTrue"), "x", &check), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_password_request(&arena, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_getPassword);

    answer = obj("messages.botCallbackAnswer");
    flag(answer, "alert");
    str(answer, "message", "Done\nfor now");
    i32(answer, "cache_time", 30);
    CHECK_EQ_INT(exteria_callback_parse(answer, &reply), EXTERIA_OK);
    CHECK_EQ_INT(reply.alert, 1);
    CHECK_EQ_INT(reply.has_url, 0);
    CHECK_EQ_INT(reply.cache_time, 30);
    CHECK(!strcmp(reply.message, "Done\nfor now"));

    answer = obj("messages.botCallbackAnswer");
    flag(answer, "has_url");
    str(answer, "url", "https://t.me/game?x=1");
    i32(answer, "cache_time", 0);
    CHECK_EQ_INT(exteria_callback_parse(answer, &reply), EXTERIA_OK);
    CHECK_EQ_INT(reply.has_url, 1);
    CHECK_EQ_INT(reply.message[0], 0);
    CHECK(!strcmp(reply.url, "https://t.me/game?x=1"));

    {
        char long_url[EXTERIA_CALLBACK_URL_MAX + 40];
        memset(long_url, 'a', sizeof(long_url));
        long_url[sizeof(long_url) - 1] = 0;
        answer = obj("messages.botCallbackAnswer");
        str(answer, "url", long_url);
        i32(answer, "cache_time", 0);
        CHECK_EQ_INT(exteria_callback_parse(answer, &reply), EXTERIA_OK);
        /* an address that does not fit is not opened at all */
        CHECK_EQ_INT(reply.has_url, 0);
        CHECK_EQ_INT(reply.url[0], 0);
    }
    CHECK_EQ_INT(exteria_callback_parse(obj("boolTrue"), &reply), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_callback_parse(answer, NULL), EXTERIA_E_ARG);
}

static exteria_tl_value *web_document(const char *url, int proxied, const char *mime, int w, int h) {
    exteria_tl_value *d = obj(proxied ? "webDocument" : "webDocumentNoProxy"), *a = obj("documentAttributeImageSize"), *attrs[1];
    str(d, "url", url);
    if (proxied) i64(d, "access_hash", 4444);
    i32(d, "size", 1000);
    str(d, "mime_type", mime);
    i32(a, "w", w);
    i32(a, "h", h);
    attrs[0] = a;
    set(d, "attributes", vec_of(attrs, 1));
    return d;
}

static exteria_tl_value *text_message(const char *text) {
    exteria_tl_value *m = obj("botInlineMessageText");
    str(m, "message", text);
    return m;
}

static void test_inline(void) {
    static exteria_inline_result rows[8];
    static exteria_inline_page page;
    exteria_tl_value *request = NULL, *answer, *results[6], *article = obj("botInlineResult"), *photo = obj("botInlineResult");
    exteria_tl_value *gif = obj("botInlineResult"), *media = obj("botInlineMediaResult"), *broken = obj("botInlineResult"), *pm = obj("inlineBotSwitchPM");
    exteria_tl_value *web = obj("inlineBotWebView"), *sticker = obj("document");
    size_t count = 0;
    char query[EXTERIA_INLINE_QUERY_MAX + 2];

    CHECK_EQ_INT(exteria_inline_query_request(&arena, &bot, &chat, "cats", "", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_getInlineBotResults);
    CHECK_EQ_INT(exteria_inline_query_request(&arena, &bot, &forum, "", "next:2", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_getInlineBotResults);
    memset(query, 'q', sizeof(query));
    query[EXTERIA_INLINE_QUERY_MAX + 1] = 0;
    CHECK_EQ_INT(exteria_inline_query_request(&arena, &bot, &chat, query, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_inline_query_request(&arena, &bot, &chat, "\xff", "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_inline_query_request(&arena, &bot, &chat, "q", NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_inline_query_request(&arena, &group, &chat, "q", "", &request), EXTERIA_E_ARG);

    str(article, "id", "a1");
    str(article, "type", "article");
    str(article, "title", "Cat facts");
    set(article, "send_message", text_message("Cats sleep 16 hours a day."));
    str(photo, "id", "p1");
    str(photo, "type", "photo");
    set(photo, "content", web_document("https://img.example.org/cat.jpg", 0, "image/jpeg", 800, 600));
    set(photo, "send_message", obj("botInlineMessageMediaAuto"));
    str(gif, "id", "g1");
    str(gif, "type", "mpeg4_gif");
    set(gif, "thumb", web_document("https://img.example.org/t.jpg", 1, "image/jpeg", 90, 60));
    set(gif, "content", web_document("https://img.example.org/c.mp4", 0, "video/mp4", 480, 320));
    set(gif, "send_message", obj("botInlineMessageMediaAuto"));
    str(media, "id", "m1");
    str(media, "type", "sticker");
    sticker = obj("document");
    i64(sticker, "id", 31);
    i64(sticker, "access_hash", 32);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, sticker, "file_reference", "ref", 3), EXTERIA_OK);
    i32(sticker, "dc_id", 2);
    set(media, "document", sticker);
    set(media, "send_message", obj("botInlineMessageMediaAuto"));
    str(broken, "type", "article");
    results[0] = article;
    results[1] = photo;
    results[2] = gif;
    results[3] = media;
    results[4] = broken;
    results[5] = obj("boolTrue");
    answer = obj("messages.botResults");
    flag(answer, "gallery");
    i64(answer, "query_id", 987654321);
    str(answer, "next_offset", "page2");
    str(pm, "text", "Connect");
    str(pm, "start_param", "login_1");
    set(answer, "switch_pm", pm);
    /* the web app button of the page is not read: there is no way to open it */
    str(web, "text", "Open app");
    str(web, "url", "https://app.example.org/inline");
    set(answer, "switch_webview", web);
    set(answer, "results", vec_of(results, 6));
    i32(answer, "cache_time", 300);
    set(answer, "users", vec_of(NULL, 0));
    CHECK_EQ_INT(exteria_inline_results_parse(answer, &page, rows, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT(page.query_id, 987654321);
    CHECK_EQ_INT(page.gallery, 1);
    CHECK_EQ_INT(page.cache_time, 300);
    CHECK(!strcmp(page.next_offset, "page2"));
    CHECK(!strcmp(page.switch_text, "Connect"));
    CHECK(!strcmp(page.switch_param, "login_1"));
    /* the result without an id and the stray object are skipped */
    CHECK_EQ_INT(count, 4);
    CHECK_EQ_INT(rows[0].kind, EXTERIA_INLINE_ARTICLE);
    CHECK(!strcmp(rows[0].id, "a1"));
    CHECK(!strcmp(rows[0].title, "Cat facts"));
    CHECK(!strcmp(rows[0].description, "Cats sleep 16 hours a day."));
    CHECK_EQ_INT(rows[0].thumb.present, 0);
    CHECK_EQ_INT(rows[1].kind, EXTERIA_INLINE_PHOTO);
    /* a photo the bot hosts without a thumbnail uses itself */
    CHECK_EQ_INT(rows[1].thumb.present, 1);
    CHECK_EQ_INT(rows[1].thumb.proxied, 0);
    CHECK(!strcmp(rows[1].thumb.url, "https://img.example.org/cat.jpg"));
    CHECK_EQ_INT(rows[1].width, 800);
    CHECK_EQ_INT(rows[1].height, 600);
    CHECK_EQ_INT(rows[2].kind, EXTERIA_INLINE_GIF);
    CHECK_EQ_INT(rows[2].thumb.proxied, 1);
    CHECK_EQ_INT(rows[2].thumb.access_hash, 4444);
    CHECK(!strcmp(rows[2].thumb.url, "https://img.example.org/t.jpg"));
    CHECK_EQ_INT(rows[2].width, 480);
    CHECK_EQ_INT(rows[3].kind, EXTERIA_INLINE_STICKER);
    CHECK_EQ_INT(rows[3].media.ref.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);

    /* a bad start parameter takes the connect button away rather than sending the person to a wrong deep link */
    str(pm, "start_param", "bad param!");
    set(answer, "switch_pm", pm);
    CHECK_EQ_INT(exteria_inline_results_parse(answer, &page, rows, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT(page.switch_text[0], 0);
    CHECK_EQ_INT(exteria_inline_results_parse(answer, &page, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(exteria_inline_results_parse(obj("boolTrue"), &page, rows, 8, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_inline_results_parse(answer, &page, NULL, 8, &count), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_inline_send_request(&arena, &chat, 9, 987654321, "a1", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_sendInlineBotResult);
    CHECK_EQ_INT(exteria_inline_send_request(&arena, &forum, 9, 987654321, "a1", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "reply_to"), 1);
    roundtrip(request, EXTERIA_TL_ID_messages_sendInlineBotResult);
    CHECK_EQ_INT(exteria_inline_send_request(&arena, &chat, 0, 1, "a1", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_inline_send_request(&arena, &chat, 9, 1, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_inline_send_request(&arena, &chat, 9, 1, NULL, &request), EXTERIA_E_ARG);
}

static void test_url_auth(void) {
    static exteria_url_auth auth;
    exteria_tl_value *request = NULL, *answer, *codes[3];
    CHECK_EQ_INT(exteria_url_auth_request(&arena, &chat, 12, 3, NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "peer"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "url"), 0);
    roundtrip(request, EXTERIA_TL_ID_messages_requestUrlAuth);
    CHECK_EQ_INT(exteria_url_auth_request(&arena, NULL, 0, 0, "https://site.example.org/login", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "peer"), 0);
    CHECK_EQ_INT(exteria_tl_has(request, "url"), 1);
    roundtrip(request, EXTERIA_TL_ID_messages_requestUrlAuth);
    CHECK_EQ_INT(exteria_url_auth_request(&arena, NULL, 0, 0, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_url_auth_request(&arena, NULL, 0, 0, "", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_url_auth_request(&arena, &chat, 0, 3, NULL, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_url_auth_accept_request(&arena, &chat, 12, 3, NULL, 1, 0, NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "write_allowed"), 1);
    roundtrip(request, EXTERIA_TL_ID_messages_acceptUrlAuth);
    CHECK_EQ_INT(exteria_url_auth_accept_request(&arena, NULL, 0, 0, "https://site.example.org/login", 0, 1, "42", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "share_phone_number"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "match_code"), 1);
    roundtrip(request, EXTERIA_TL_ID_messages_acceptUrlAuth);
    CHECK_EQ_INT(exteria_url_auth_accept_request(&arena, &chat, 12, 3, NULL, 0, 0, "", &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_url_auth_parse(obj("urlAuthResultDefault"), &auth), EXTERIA_OK);
    CHECK_EQ_INT(auth.kind, EXTERIA_URL_AUTH_OPEN);
    answer = obj("urlAuthResultAccepted");
    str(answer, "url", "https://site.example.org/in?token=1");
    CHECK_EQ_INT(exteria_url_auth_parse(answer, &auth), EXTERIA_OK);
    CHECK_EQ_INT(auth.kind, EXTERIA_URL_AUTH_DONE);
    CHECK(!strcmp(auth.url, "https://site.example.org/in?token=1"));
    CHECK_EQ_INT(exteria_url_auth_parse(obj("urlAuthResultAccepted"), &auth), EXTERIA_OK);
    CHECK_EQ_INT(auth.url[0], 0);

    answer = obj("urlAuthResultRequest");
    flag(answer, "request_write_access");
    set(answer, "bot", user(77, "login_bot", 1));
    str(answer, "domain", "site.example.org");
    codes[0] = exteria_tl_new_str(&arena, "17");
    codes[1] = exteria_tl_new_str(&arena, "");
    codes[2] = exteria_tl_new_str(&arena, "93");
    set(answer, "match_codes", vec_of(codes, 3));
    flag(answer, "match_codes_first");
    CHECK_EQ_INT(exteria_url_auth_parse(answer, &auth), EXTERIA_OK);
    CHECK_EQ_INT(auth.kind, EXTERIA_URL_AUTH_ASK);
    CHECK_EQ_INT(auth.request_write, 1);
    CHECK_EQ_INT(auth.request_phone, 0);
    CHECK(!strcmp(auth.domain, "site.example.org"));
    CHECK(!strcmp(auth.bot, "login_bot"));
    CHECK_EQ_INT(auth.code_count, 2);
    CHECK(!strcmp(auth.codes[0], "17"));
    CHECK(!strcmp(auth.codes[1], "93"));
    answer = obj("urlAuthResultRequest");
    set(answer, "bot", user(77, "login_bot", 1));
    CHECK_EQ_INT(exteria_url_auth_parse(answer, &auth), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_url_auth_parse(obj("boolTrue"), &auth), EXTERIA_E_MALFORMED);
}

static exteria_tl_value *price(const char *label, int64_t amount) {
    exteria_tl_value *p = obj("labeledPrice");
    str(p, "label", label);
    i64(p, "amount", amount);
    return p;
}

static exteria_tl_value *stars_form(const char *currency, int64_t a, int64_t b) {
    exteria_tl_value *form = obj("payments.paymentFormStars"), *invoice = obj("invoice"), *prices[2];
    i64(form, "form_id", 600);
    i64(form, "bot_id", 77);
    str(form, "title", "Sticker pack");
    str(form, "description", "Ten stickers\nand a pin");
    str(invoice, "currency", currency);
    prices[0] = price("pack", a);
    prices[1] = price("tax", b);
    set(invoice, "prices", vec_of(prices, 2));
    set(form, "invoice", invoice);
    set(form, "users", vec_of(NULL, 0));
    return form;
}

static void test_invoice(void) {
    static exteria_stars_form form;
    exteria_tl_value *input = NULL;
    CHECK_EQ_INT(exteria_invoice_message_input(&arena, &chat, 12, &input), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(input), EXTERIA_TL_ID_inputInvoiceMessage);
    CHECK_EQ_INT(exteria_invoice_slug_input(&arena, "abc_DEF-123", &input), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(input), EXTERIA_TL_ID_inputInvoiceSlug);
    CHECK_EQ_INT(exteria_invoice_slug_input(&arena, "a b", &input), EXTERIA_E_ARG);
    CHECK(input == NULL);
    CHECK_EQ_INT(exteria_invoice_slug_input(&arena, "", &input), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_invoice_message_input(&arena, &chat, 0, &input), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_stars_form_parse(stars_form("XTR", 90, 10), &form), EXTERIA_OK);
    CHECK_EQ_INT(form.form_id, 600);
    CHECK_EQ_INT(form.bot_id, 77);
    CHECK_EQ_INT(form.stars, 100);
    CHECK(!strcmp(form.title, "Sticker pack"));
    CHECK(!strcmp(form.description, "Ten stickers\nand a pin"));
    CHECK_EQ_INT(exteria_stars_form_parse(stars_form("USD", 90, 10), &form), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(form.form_id, 0);
    CHECK_EQ_INT(exteria_stars_form_parse(stars_form("XTR", -1, 10), &form), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_stars_form_parse(stars_form("XTR", INT64_MAX, 1), &form), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_stars_form_parse(obj("payments.paymentForm"), &form), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_stars_form_parse(obj("boolTrue"), &form), EXTERIA_E_MALFORMED);
}

static void test_user_from_message(void) {
    exteria_tl_value *request = NULL, *list[2];
    exteria_person_row row;
    CHECK_EQ_INT(exteria_user_from_message_request(&arena, &chat, 12, 4242, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_users_getUsers);
    CHECK_EQ_INT(exteria_user_from_message_request(&arena, &group, 12, 4242, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_user_from_message_request(&arena, &chat, 0, 4242, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_user_from_message_request(&arena, &chat, 12, 0, &request), EXTERIA_E_ARG);
    list[0] = user(3, "other", 0);
    list[1] = user(4242, "wanted", 0);
    CHECK_EQ_INT(exteria_user_from_message_parse(vec_of(list, 2), 4242, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.id, 4242);
    CHECK_EQ_INT(row.access_hash, 42420);
    CHECK_EQ_INT(exteria_user_from_message_parse(vec_of(list, 2), 9, &row), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(row.id, 0);
    CHECK_EQ_INT(exteria_user_from_message_parse(obj("boolTrue"), 9, &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_user_from_message_parse(vec_of(NULL, 0), 9, &row), EXTERIA_E_NOTFOUND);
}

static void test_answers(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref picked[2] = {{1, 5, 50, 0, 0}, {3, 12, 120, 0, 0}};
    CHECK_EQ_INT(exteria_send_contact_request(&arena, &chat, "+15550100", "Ann", "Lee", 4, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_sendMedia);
    CHECK_EQ_INT(exteria_send_contact_request(&arena, &forum, "+15550100", "Ann", "", 4, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "reply_to"), 1);
    CHECK_EQ_INT(exteria_send_contact_request(&arena, &chat, "", "Ann", "", 4, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_send_contact_request(&arena, &chat, "+1", "Ann", "", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_send_contact_request(&arena, &chat, "+1", "\xff", "", 4, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_requested_peers_request(&arena, &chat, 12, 3, picked, 2, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_sendBotRequestedPeer);
    CHECK_EQ_INT(exteria_requested_peers_request(&arena, &chat, 12, 3, picked, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_requested_peers_request(&arena, &chat, 12, 3, picked, 11, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_requested_peers_request(&arena, &chat, 0, 3, picked, 2, &request), EXTERIA_E_ARG);
    picked[1].access_hash = 0;
    CHECK_EQ_INT(exteria_requested_peers_request(&arena, &chat, 12, 3, picked, 2, &request), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 64u * 1024u * 1024u);
    test_resolve();
    test_invite();
    test_bot_info();
    test_start();
    test_contact_edit();
    test_contact_import();
    test_callback();
    test_inline();
    test_url_auth();
    test_invoice();
    test_user_from_message();
    test_answers();
    exteria_arena_free(&arena);
    return test_finish("test_bots");
}
