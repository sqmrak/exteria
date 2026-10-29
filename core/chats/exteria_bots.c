#include "exteria_bots.h"

#include <ctype.h>
#include <string.h>

#include "exteria_srp.h"
#include "exteria_store.h"
#include "exteria_tl_ids.h"

#define PLATFORM "ios"
#define PRICES_MAX 16

static int is_vec(const exteria_tl_value *v) {
    return v && v->kind == EXTERIA_TL_V_VEC;
}

/* a string field cut at a character boundary; line breaks stay only where the caller wants them */
static void copy_text(char *dst, size_t cap, const exteria_tl_value *object, const char *field, int keep_lines) {
    const uint8_t *data;
    size_t len, i;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    for (i = 0; i < len; ++i) {
        uint8_t c = data[i];
        dst[i] = (!keep_lines && (c == '\n' || c == '\r' || c == '\t')) ? ' ' : (char)c;
    }
    dst[len] = 0;
}

/* a C string cut at a character boundary; cap includes the terminator */
static void cut_into(char *dst, size_t cap, const char *src) {
    size_t len = strlen(src);
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && ((unsigned char)src[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, src, len);
    dst[len] = 0;
}

/* a string that is useless when cut, an address or a start parameter: false when it does not fit whole */
static int copy_whole(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK) return 0;
    if (len >= cap) return 0;
    memcpy(dst, data, len);
    dst[len] = 0;
    return 1;
}

static exteria_status input_user(exteria_arena *arena, const exteria_peer_ref *bot, exteria_tl_value **out) {
    exteria_tl_value *user;
    exteria_status status;
    *out = NULL;
    if (!bot || bot->kind != 1 || bot->id <= 0 || bot->access_hash == 0) return EXTERIA_E_ARG;
    user = exteria_tl_new_obj(arena, "inputUser");
    if (!user) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, user, "user_id", bot->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, user, "access_hash", bot->access_hash);
    if (status == EXTERIA_OK) *out = user;
    return status;
}

exteria_status exteria_contact_edit_request(exteria_arena *arena, const exteria_peer_ref *user, const char *first, const char *last, const char *phone,
                                            exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    size_t first_len = first ? strlen(first) : 0;
    if (out) *out = NULL;
    if (!arena || !out || !last || !phone || first_len == 0 || first_len >= EXTERIA_CONTACT_NAME_MAX || strlen(last) >= EXTERIA_CONTACT_NAME_MAX ||
        strlen(phone) > 32) return EXTERIA_E_ARG;
    status = input_user(arena, user, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "contacts.addContact");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "id", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "first_name", first);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "last_name", last);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "phone", phone);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static int phone_valid(const char *phone) {
    size_t digits = 0;
    if (!phone) return 0;
    if (*phone == '+') ++phone;
    for (; *phone; ++phone) {
        if (*phone < '0' || *phone > '9') return 0;
        ++digits;
    }
    return digits >= 5 && digits <= 20;
}

exteria_status exteria_contact_import_request(exteria_arena *arena, const char *phone, const char *first, const char *last, exteria_tl_value **out) {
    exteria_tl_value *request, *contact, *list, *items[1];
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !phone_valid(phone) || !first || !last || !first[0] || strlen(first) >= EXTERIA_CONTACT_NAME_MAX || strlen(last) >= EXTERIA_CONTACT_NAME_MAX)
        return EXTERIA_E_ARG;
    contact = exteria_tl_new_obj(arena, "inputPhoneContact");
    request = exteria_tl_new_obj(arena, "contacts.importContacts");
    if (!contact || !request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, contact, "client_id", 1);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, contact, "phone", phone);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, contact, "first_name", first);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, contact, "last_name", last);
    items[0] = contact;
    list = exteria_tl_new_vec(arena, 1);
    if (!list) return EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, 0, items[0]);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "contacts", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_contact_import_parse(const exteria_tl_value *answer, size_t *imported) {
    const exteria_tl_value *list;
    if (imported) *imported = 0;
    if (!imported) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_contacts_importedContacts) || exteria_tl_get_vec(answer, "imported", &list) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    *imported = list->u.vec.count;
    return EXTERIA_OK;
}

/* the characters the server accepts in a start parameter, a slug or a username */
static int word_char(char c, int dash) {
    return isalnum((unsigned char)c) || c == '_' || (dash && c == '-');
}

static int word_valid(const char *s, size_t min, size_t max, int dash) {
    size_t n = s ? strlen(s) : 0, i;
    if (n < min || n > max) return 0;
    for (i = 0; i < n; ++i) if (!word_char(s[i], dash)) return 0;
    return 1;
}

static int utf8_valid(const char *s) {
    const unsigned char *p = (const unsigned char *)s;
    while (*p) {
        unsigned n, i;
        uint32_t cp;
        if (*p < 0x80u) { ++p; continue; }
        if (*p >= 0xc2u && *p <= 0xdfu) { n = 1; cp = *p & 0x1fu; }
        else if (*p >= 0xe0u && *p <= 0xefu) { n = 2; cp = *p & 0x0fu; }
        else if (*p >= 0xf0u && *p <= 0xf4u) { n = 3; cp = *p & 0x07u; }
        else return 0;
        for (i = 1; i <= n; ++i) {
            if ((p[i] & 0xc0u) != 0x80u) return 0;
            cp = (cp << 6) | (p[i] & 0x3fu);
        }
        if ((n == 2 && cp < 0x800u) || (n == 3 && cp < 0x10000u) || (cp >= 0xd800u && cp <= 0xdfffu) || cp > 0x10ffffu) return 0;
        p += n + 1;
    }
    return 1;
}

/* resolve */

exteria_status exteria_resolve_request(exteria_arena *arena, const char *username, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !word_valid(username, 1, EXTERIA_USERNAME_LOOKUP_MAX, 0)) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "contacts.resolveUsername");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "username", username);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static const exteria_tl_value *find_by_id(const exteria_tl_value *list, int64_t id) {
    uint32_t i;
    for (i = 0; is_vec(list) && i < list->u.vec.count; ++i) {
        int64_t found;
        if (exteria_tl_get_i64(list->u.vec.items[i], "id", &found) == EXTERIA_OK && found == id) return list->u.vec.items[i];
    }
    return NULL;
}

exteria_status exteria_resolve_parse(const exteria_tl_value *answer, int64_t self_id, exteria_resolved *out) {
    exteria_peer peer;
    const exteria_tl_value *users, *chats;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_contacts_resolvedPeer)) return EXTERIA_E_MALFORMED;
    if (exteria_peer_from_tl(exteria_tl_get(answer, "peer"), &peer) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    users = exteria_tl_get(answer, "users");
    chats = exteria_tl_get(answer, "chats");
    out->dialog.peer_kind = peer.kind;
    out->dialog.peer_id = peer.id;
    exteria_dialog_peer_read(&out->dialog, users, chats, self_id);
    if (!out->dialog.title[0] || out->dialog.deleted) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_NOTFOUND;
    }
    if (peer.kind == 1) {
        const exteria_tl_value *user = find_by_id(users, peer.id);
        if (user && exteria_person_parse(user, &out->person) == EXTERIA_OK) out->is_user = 1;
    }
    return EXTERIA_OK;
}

/* invite links */

#define INVITE_HASH_MAX 128

static exteria_status invite_request(exteria_arena *arena, const char *ctor, const char *hash, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !word_valid(hash, 1, INVITE_HASH_MAX, 1)) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, ctor);
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "hash", hash);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_invite_check_request(exteria_arena *arena, const char *hash, exteria_tl_value **out) {
    return invite_request(arena, "messages.checkChatInvite", hash, out);
}

exteria_status exteria_invite_import_request(exteria_arena *arena, const char *hash, exteria_tl_value **out) {
    return invite_request(arena, "messages.importChatInvite", hash, out);
}

/* a row for one chat object; the row reader looks the chat up by id in a list, so the chat is put in a list of one */
static exteria_status chat_row(const exteria_tl_value *chat, int64_t self_id, exteria_dialog_row *row) {
    exteria_tl_value *items[1];
    exteria_tl_value list;
    int64_t id;
    memset(row, 0, sizeof(*row));
    if (!chat || exteria_tl_get_i64(chat, "id", &id) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (exteria_tl_is(chat, EXTERIA_TL_ID_channel) || exteria_tl_is(chat, EXTERIA_TL_ID_channelForbidden)) row->peer_kind = 3;
    else if (exteria_tl_is(chat, EXTERIA_TL_ID_chat)) row->peer_kind = 2;
    else return EXTERIA_E_NOTFOUND;
    row->peer_id = id;
    items[0] = (exteria_tl_value *)chat;
    memset(&list, 0, sizeof(list));
    list.kind = EXTERIA_TL_V_VEC;
    list.u.vec.count = 1;
    list.u.vec.items = items;
    exteria_dialog_peer_read(row, NULL, &list, self_id);
    return row->title[0] ? EXTERIA_OK : EXTERIA_E_NOTFOUND;
}

exteria_status exteria_invite_parse(const exteria_tl_value *answer, int64_t self_id, exteria_invite *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(answer, EXTERIA_TL_ID_chatInviteAlready) || exteria_tl_is(answer, EXTERIA_TL_ID_chatInvitePeek)) {
        exteria_status status = chat_row(exteria_tl_get(answer, "chat"), self_id, &out->dialog);
        if (status != EXTERIA_OK) return status;
        out->member = 1;
        cut_into(out->title, sizeof(out->title), out->dialog.title);
        return EXTERIA_OK;
    }
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_chatInvite)) return EXTERIA_E_MALFORMED;
    copy_text(out->title, sizeof(out->title), answer, "title", 0);
    if (!out->title[0]) return EXTERIA_E_MALFORMED;
    copy_text(out->about, sizeof(out->about), answer, "about", 1);
    {
        exteria_media_info photo;
        exteria_photo_read(exteria_tl_get(answer, "photo"), 180, &photo);
        out->photo = photo.ref;
    }
    exteria_tl_get_i32(answer, "participants_count", &out->participants);
    if (out->participants < 0) out->participants = 0;
    out->broadcast = exteria_tl_has(answer, "broadcast") ? 1 : 0;
    out->request_needed = exteria_tl_has(answer, "request_needed") ? 1 : 0;
    out->verified = exteria_tl_has(answer, "verified") ? 1 : 0;
    return EXTERIA_OK;
}

exteria_status exteria_invite_joined_parse(const exteria_tl_value *answer, int64_t self_id, exteria_dialog_row *out) {
    const exteria_tl_value *updates, *chats;
    uint32_t i;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatInviteJoinResultWebView)) return EXTERIA_E_UNSUPPORTED;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatInviteJoinResultOk)) return EXTERIA_E_MALFORMED;
    updates = exteria_tl_get(answer, "updates");
    chats = exteria_tl_get(updates, "chats");
    if (!is_vec(chats)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < chats->u.vec.count; ++i) {
        if (chat_row(chats->u.vec.items[i], self_id, out) == EXTERIA_OK) return EXTERIA_OK;
    }
    memset(out, 0, sizeof(*out));
    return EXTERIA_E_NOTFOUND;
}

/* bot info */

static void read_commands(const exteria_tl_value *list, exteria_bot_info *out) {
    uint32_t i;
    if (!is_vec(list)) return;
    for (i = 0; i < list->u.vec.count && out->command_count < EXTERIA_BOT_COMMANDS_MAX; ++i) {
        const exteria_tl_value *c = list->u.vec.items[i];
        exteria_bot_command *row = &out->commands[out->command_count];
        if (!exteria_tl_is(c, EXTERIA_TL_ID_botCommand) || exteria_tl_has(c, "ephemeral")) continue;
        /* a command that is cut would be sent as another command, so only whole names count */
        if (!copy_whole(row->name, sizeof(row->name), c, "command") || !word_valid(row->name, 1, 32, 0)) continue;
        copy_text(row->text, sizeof(row->text), c, "description", 0);
        ++out->command_count;
    }
}

static void read_menu(const exteria_tl_value *button, exteria_bot_info *out) {
    /* a web app menu button stays the default menu, this client has no way to open the app */
    if (exteria_tl_is(button, EXTERIA_TL_ID_botMenuButtonCommands)) out->menu_kind = EXTERIA_BOT_MENU_COMMANDS;
}

#define BOT_PICTURE_TARGET 480

exteria_status exteria_bot_info_parse(const exteria_tl_value *answer, exteria_bot_info *out) {
    const exteria_tl_value *full, *info;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_users_userFull)) return EXTERIA_E_MALFORMED;
    full = exteria_tl_get(answer, "full_user");
    if (!exteria_tl_is(full, EXTERIA_TL_ID_userFull)) return EXTERIA_E_MALFORMED;
    info = exteria_tl_get(full, "bot_info");
    if (!exteria_tl_is(info, EXTERIA_TL_ID_botInfo)) return EXTERIA_OK;
    out->present = 1;
    copy_text(out->description, sizeof(out->description), info, "description", 1);
    copy_whole(out->privacy_url, sizeof(out->privacy_url), info, "privacy_policy_url");
    read_commands(exteria_tl_get(info, "commands"), out);
    read_menu(exteria_tl_get(info, "menu_button"), out);
    if (exteria_tl_has(info, "description_document")) {
        exteria_document_read(exteria_tl_get(info, "description_document"), &out->picture);
        out->has_picture = out->picture.ref.source != EXTERIA_MEDIA_SOURCE_NONE;
    }
    if (!out->has_picture && exteria_tl_has(info, "description_photo")) {
        exteria_photo_read(exteria_tl_get(info, "description_photo"), BOT_PICTURE_TARGET, &out->picture);
        out->has_picture = out->picture.ref.source != EXTERIA_MEDIA_SOURCE_NONE;
    }
    if (!out->has_picture) memset(&out->picture, 0, sizeof(out->picture));
    return EXTERIA_OK;
}

exteria_status exteria_start_bot_request(exteria_arena *arena, const exteria_peer_ref *bot, const exteria_peer_ref *peer,
                                         int64_t random_id, const char *param, exteria_tl_value **out) {
    exteria_tl_value *request, *user, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !peer || random_id == 0 || !param || (param[0] && !word_valid(param, 1, EXTERIA_START_PARAM_MAX, 1))) return EXTERIA_E_ARG;
    status = input_user(arena, bot, &user);
    if (status == EXTERIA_OK) status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.startBot");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "bot", user);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "start_param", param);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* callbacks */

exteria_status exteria_callback_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, const uint8_t *data,
                                        size_t data_len, int game, exteria_tl_value *password, exteria_tl_value **out) {
    static const uint8_t none[1] = {0};
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || msg_id <= 0 || data_len > EXTERIA_MARKUP_DATA_MAX || (data_len && !data)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.getBotCallbackAnswer");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", msg_id);
    if (status == EXTERIA_OK && game) status = exteria_tl_set_flag(request, "game");
    else if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, request, "data", data_len ? data : none, data_len);
    if (status == EXTERIA_OK && password) status = exteria_tl_set(request, "password", password);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_callback_parse(const exteria_tl_value *answer, exteria_callback_answer *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_botCallbackAnswer)) return EXTERIA_E_MALFORMED;
    out->alert = exteria_tl_has(answer, "alert") ? 1 : 0;
    out->native_ui = exteria_tl_has(answer, "native_ui") ? 1 : 0;
    exteria_tl_get_i32(answer, "cache_time", &out->cache_time);
    copy_text(out->message, sizeof(out->message), answer, "message", 1);
    /* an address that does not fit whole is dropped: opening a cut address would open another page */
    if (exteria_tl_has(answer, "url") && copy_whole(out->url, sizeof(out->url), answer, "url") && out->url[0]) out->has_url = 1;
    else out->url[0] = 0;
    return EXTERIA_OK;
}

exteria_status exteria_password_request(exteria_arena *arena, exteria_tl_value **out) {
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    *out = exteria_tl_new_obj(arena, "account.getPassword");
    return *out ? EXTERIA_OK : EXTERIA_E_NOMEM;
}

exteria_status exteria_password_input(exteria_arena *arena, const exteria_tl_value *account_password, const char *password,
                                      exteria_tl_value **out) {
    exteria_srp_proof proof;
    exteria_tl_value *check;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !password || !password[0] || !exteria_tl_is(account_password, EXTERIA_TL_ID_account_password)) return EXTERIA_E_ARG;
    if (!exteria_tl_has(account_password, "has_password")) return EXTERIA_E_UNSUPPORTED;
    status = exteria_srp_check(account_password, (const uint8_t *)password, strlen(password), &proof);
    if (status != EXTERIA_OK) return status;
    check = exteria_tl_new_obj(arena, "inputCheckPasswordSRP");
    if (!check) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, check, "srp_id", proof.id);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, check, "A", proof.A, sizeof(proof.A));
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, check, "M1", proof.M1, sizeof(proof.M1));
    if (status == EXTERIA_OK) *out = check;
    return status;
}

/* inline mode */

exteria_status exteria_inline_query_request(exteria_arena *arena, const exteria_peer_ref *bot, const exteria_peer_ref *peer,
                                            const char *query, const char *offset, exteria_tl_value **out) {
    exteria_tl_value *request, *user, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !query || !offset || strlen(query) > EXTERIA_INLINE_QUERY_MAX || strlen(offset) >= EXTERIA_INLINE_OFFSET_MAX ||
        !utf8_valid(query)) return EXTERIA_E_ARG;
    status = input_user(arena, bot, &user);
    if (status == EXTERIA_OK) status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.getInlineBotResults");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "bot", user);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "query", query);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "offset", offset);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static void read_web_ref(const exteria_tl_value *document, exteria_web_ref *out, int32_t *width, int32_t *height, int32_t *duration) {
    const exteria_tl_value *attributes;
    uint32_t i;
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(document, EXTERIA_TL_ID_webDocument)) {
        out->proxied = 1;
        if (exteria_tl_get_i64(document, "access_hash", &out->access_hash) != EXTERIA_OK) return;
    } else if (!exteria_tl_is(document, EXTERIA_TL_ID_webDocumentNoProxy)) {
        return;
    }
    if (!copy_whole(out->url, sizeof(out->url), document, "url") || !out->url[0]) {
        memset(out, 0, sizeof(*out));
        return;
    }
    exteria_tl_get_i32(document, "size", &out->size);
    copy_text(out->mime, sizeof(out->mime), document, "mime_type", 0);
    out->present = 1;
    attributes = exteria_tl_get(document, "attributes");
    for (i = 0; is_vec(attributes) && i < attributes->u.vec.count; ++i) {
        const exteria_tl_value *a = attributes->u.vec.items[i];
        double seconds = 0;
        if (exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeImageSize)) {
            exteria_tl_get_i32(a, "w", width);
            exteria_tl_get_i32(a, "h", height);
        } else if (exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeVideo)) {
            exteria_tl_get_i32(a, "w", width);
            exteria_tl_get_i32(a, "h", height);
            if (exteria_tl_get_f64(a, "duration", &seconds) == EXTERIA_OK && seconds > 0 && seconds < 2147483647.0) *duration = (int32_t)seconds;
        } else if (exteria_tl_is(a, EXTERIA_TL_ID_documentAttributeAudio)) {
            exteria_tl_get_i32(a, "duration", duration);
        }
    }
}

static exteria_inline_kind inline_kind(const exteria_tl_value *result) {
    const uint8_t *type;
    size_t len;
    static const struct { const char *name; exteria_inline_kind kind; } table[] = {
        {"article", EXTERIA_INLINE_ARTICLE}, {"photo", EXTERIA_INLINE_PHOTO}, {"gif", EXTERIA_INLINE_GIF}, {"mpeg4_gif", EXTERIA_INLINE_GIF},
        {"video", EXTERIA_INLINE_VIDEO}, {"audio", EXTERIA_INLINE_AUDIO}, {"voice", EXTERIA_INLINE_VOICE},
        {"document", EXTERIA_INLINE_FILE}, {"sticker", EXTERIA_INLINE_STICKER}, {"geo", EXTERIA_INLINE_LOCATION},
        {"venue", EXTERIA_INLINE_LOCATION}, {"contact", EXTERIA_INLINE_CONTACT}, {"game", EXTERIA_INLINE_GAME}
    };
    size_t i;
    if (exteria_tl_get_bytes(result, "type", &type, &len) != EXTERIA_OK) return EXTERIA_INLINE_OTHER;
    for (i = 0; i < sizeof(table) / sizeof(table[0]); ++i) {
        if (strlen(table[i].name) == len && memcmp(table[i].name, type, len) == 0) return table[i].kind;
    }
    return EXTERIA_INLINE_OTHER;
}

/* what an article says when the bot gave it no description: the first words of the message it will send */
static void message_preview(const exteria_tl_value *result, char *dst, size_t cap) {
    const exteria_tl_value *message = exteria_tl_get(result, "send_message");
    dst[0] = 0;
    if (exteria_tl_is(message, EXTERIA_TL_ID_botInlineMessageText) || exteria_tl_is(message, EXTERIA_TL_ID_botInlineMessageMediaAuto))
        copy_text(dst, cap, message, "message", 0);
}

static int read_inline_result(const exteria_tl_value *r, exteria_inline_result *out) {
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(r, EXTERIA_TL_ID_botInlineResult)) {
        const exteria_tl_value *thumb = exteria_tl_get(r, "thumb"), *content = exteria_tl_get(r, "content");
        int32_t w = 0, h = 0, d = 0;
        if (!copy_whole(out->id, sizeof(out->id), r, "id") || !out->id[0]) return 0;
        out->kind = (uint8_t)inline_kind(r);
        copy_text(out->title, sizeof(out->title), r, "title", 0);
        copy_text(out->description, sizeof(out->description), r, "description", 0);
        exteria_web_ref whole;
        read_web_ref(thumb, &out->thumb, &w, &h, &d);
        read_web_ref(content, &whole, &out->width, &out->height, &out->duration);
        /* a picture or an animation that has no thumbnail is its own thumbnail */
        if (!out->thumb.present && (out->kind == EXTERIA_INLINE_PHOTO || out->kind == EXTERIA_INLINE_GIF) && whole.present &&
            !strncmp(whole.mime, "image/", 6)) out->thumb = whole;
        if (!out->width) out->width = w;
        if (!out->height) out->height = h;
        if (!out->duration) out->duration = d;
    } else if (exteria_tl_is(r, EXTERIA_TL_ID_botInlineMediaResult)) {
        if (!copy_whole(out->id, sizeof(out->id), r, "id") || !out->id[0]) return 0;
        out->kind = (uint8_t)inline_kind(r);
        copy_text(out->title, sizeof(out->title), r, "title", 0);
        copy_text(out->description, sizeof(out->description), r, "description", 0);
        if (exteria_tl_has(r, "document")) exteria_document_read(exteria_tl_get(r, "document"), &out->media);
        else if (exteria_tl_has(r, "photo")) exteria_photo_read(exteria_tl_get(r, "photo"), 320, &out->media);
        if (out->media.ref.source == EXTERIA_MEDIA_SOURCE_NONE && out->media.preview.source == EXTERIA_MEDIA_SOURCE_NONE)
            memset(&out->media, 0, sizeof(out->media));
        out->width = out->media.width;
        out->height = out->media.height;
        out->duration = out->media.duration;
    } else {
        return 0;
    }
    if (out->kind == EXTERIA_INLINE_LOCATION) {
        const exteria_tl_value *message = exteria_tl_get(r, "send_message");
        if (exteria_geo_read(exteria_tl_get(message, "geo"),
            exteria_tl_is(message, EXTERIA_TL_ID_botInlineMessageMediaVenue) ? message : NULL, &out->media.location) != EXTERIA_OK) return 0;
        out->media.kind = EXTERIA_PREVIEW_LOCATION;
        out->media.width = 320;
        out->media.height = 180;
    }
    if (!out->description[0]) message_preview(r, out->description, sizeof(out->description));
    return 1;
}

exteria_status exteria_inline_results_parse(const exteria_tl_value *answer, exteria_inline_page *page, exteria_inline_result *rows,
                                            size_t cap, size_t *count) {
    const exteria_tl_value *results, *pm;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!page) return EXTERIA_E_ARG;
    memset(page, 0, sizeof(*page));
    if (!rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_botResults) || exteria_tl_get_vec(answer, "results", &results) != EXTERIA_OK ||
        exteria_tl_get_i64(answer, "query_id", &page->query_id) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    page->gallery = exteria_tl_has(answer, "gallery") ? 1 : 0;
    exteria_tl_get_i32(answer, "cache_time", &page->cache_time);
    /* a cut offset would fetch another page, so a long one ends the paging instead */
    if (!copy_whole(page->next_offset, sizeof(page->next_offset), answer, "next_offset")) page->next_offset[0] = 0;
    pm = exteria_tl_get(answer, "switch_pm");
    if (exteria_tl_is(pm, EXTERIA_TL_ID_inlineBotSwitchPM)) {
        copy_text(page->switch_text, sizeof(page->switch_text), pm, "text", 0);
        if (!copy_whole(page->switch_param, sizeof(page->switch_param), pm, "start_param") ||
            (page->switch_param[0] && !word_valid(page->switch_param, 1, EXTERIA_START_PARAM_MAX, 1))) {
            page->switch_text[0] = 0;
            page->switch_param[0] = 0;
        }
    }
    for (i = 0; i < results->u.vec.count && n < cap; ++i) {
        if (read_inline_result(results->u.vec.items[i], &rows[n])) ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_inline_send_request(exteria_arena *arena, const exteria_peer_ref *peer, int64_t random_id, int64_t query_id,
                                           const char *result_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !peer || random_id == 0 || !result_id || !result_id[0] || strlen(result_id) >= EXTERIA_INLINE_ID_MAX) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.sendInlineBotResult");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_set_topic_reply(arena, request, peer);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "query_id", query_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "id", result_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_user_from_message_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, int64_t user_id, exteria_tl_value **out) {
    exteria_tl_value *request, *list, *user, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || msg_id <= 0 || user_id <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "users.getUsers");
    list = exteria_tl_new_vec(arena, 1);
    user = exteria_tl_new_obj(arena, "inputUserFromMessage");
    if (!request || !list || !user) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(user, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, user, "msg_id", msg_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, user, "user_id", user_id);
    if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, 0, user);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_user_from_message_parse(const exteria_tl_value *answer, int64_t user_id, exteria_person_row *out) {
    uint32_t i;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!is_vec(answer)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < answer->u.vec.count; ++i) {
        exteria_person_row row;
        if (exteria_person_parse(answer->u.vec.items[i], &row) == EXTERIA_OK && row.id == user_id) {
            *out = row;
            return EXTERIA_OK;
        }
    }
    return EXTERIA_E_NOTFOUND;
}

/* signing in on a site */

static exteria_status set_button_target(exteria_arena *arena, exteria_tl_value *request, const exteria_peer_ref *peer, int32_t msg_id,
                                        int32_t button_id, const char *url) {
    exteria_tl_value *input;
    exteria_status status = EXTERIA_OK;
    if (peer) {
        status = exteria_input_peer(arena, peer, &input);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", msg_id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "button_id", button_id);
    }
    if (status == EXTERIA_OK && url) status = exteria_tl_set_str(arena, request, "url", url);
    return status;
}

static int url_auth_target_valid(const exteria_peer_ref *peer, int32_t msg_id, const char *url) {
    if (peer) return msg_id > 0;
    return url && url[0] && strlen(url) < EXTERIA_BOT_URL_MAX && utf8_valid(url);
}

exteria_status exteria_url_auth_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, int32_t button_id,
                                        const char *url, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !url_auth_target_valid(peer, msg_id, url)) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.requestUrlAuth");
    if (!request) return EXTERIA_E_NOMEM;
    status = set_button_target(arena, request, peer, msg_id, button_id, peer ? NULL : url);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_url_auth_accept_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, int32_t button_id,
                                               const char *url, int write_allowed, int share_phone, const char *code, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !url_auth_target_valid(peer, msg_id, url) || (code && (!code[0] || strlen(code) >= 16))) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.acceptUrlAuth");
    if (!request) return EXTERIA_E_NOMEM;
    status = EXTERIA_OK;
    if (write_allowed) status = exteria_tl_set_flag(request, "write_allowed");
    if (status == EXTERIA_OK && share_phone) status = exteria_tl_set_flag(request, "share_phone_number");
    if (status == EXTERIA_OK) status = set_button_target(arena, request, peer, msg_id, button_id, peer ? NULL : url);
    if (status == EXTERIA_OK && code) status = exteria_tl_set_str(arena, request, "match_code", code);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_url_auth_parse(const exteria_tl_value *answer, exteria_url_auth *out) {
    const exteria_tl_value *bot, *codes;
    uint32_t i;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(answer, EXTERIA_TL_ID_urlAuthResultDefault)) {
        out->kind = EXTERIA_URL_AUTH_OPEN;
        return EXTERIA_OK;
    }
    if (exteria_tl_is(answer, EXTERIA_TL_ID_urlAuthResultAccepted)) {
        out->kind = EXTERIA_URL_AUTH_DONE;
        /* an accepted login without an address leaves the person on the page they were on */
        if (exteria_tl_has(answer, "url") && !copy_whole(out->url, sizeof(out->url), answer, "url")) out->url[0] = 0;
        return EXTERIA_OK;
    }
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_urlAuthResultRequest)) return EXTERIA_E_MALFORMED;
    out->kind = EXTERIA_URL_AUTH_ASK;
    out->request_write = exteria_tl_has(answer, "request_write_access") ? 1 : 0;
    out->request_phone = exteria_tl_has(answer, "request_phone_number") ? 1 : 0;
    if (!copy_whole(out->domain, sizeof(out->domain), answer, "domain") || !out->domain[0]) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    bot = exteria_tl_get(answer, "bot");
    if (exteria_tl_is(bot, EXTERIA_TL_ID_user)) {
        exteria_person_row person;
        if (exteria_person_parse(bot, &person) == EXTERIA_OK) cut_into(out->bot, sizeof(out->bot), person.name);
    }
    codes = exteria_tl_get(answer, "match_codes");
    for (i = 0; is_vec(codes) && i < codes->u.vec.count && out->code_count < EXTERIA_URL_AUTH_CODES_MAX; ++i) {
        const uint8_t *data;
        size_t len;
        if (codes->u.vec.items[i]->kind != EXTERIA_TL_V_BYTES) continue;
        data = codes->u.vec.items[i]->u.bytes.data;
        len = codes->u.vec.items[i]->u.bytes.len;
        if (!len || len >= sizeof(out->codes[0])) continue;
        memcpy(out->codes[out->code_count], data, len);
        out->codes[out->code_count][len] = 0;
        ++out->code_count;
    }
    return EXTERIA_OK;
}

/* invoices */

exteria_status exteria_invoice_message_input(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, exteria_tl_value **out) {
    exteria_tl_value *invoice, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || msg_id <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    invoice = exteria_tl_new_obj(arena, "inputInvoiceMessage");
    if (!invoice) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(invoice, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, invoice, "msg_id", msg_id);
    if (status == EXTERIA_OK) *out = invoice;
    return status;
}

exteria_status exteria_invoice_slug_input(exteria_arena *arena, const char *slug, exteria_tl_value **out) {
    exteria_tl_value *invoice;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !word_valid(slug, 1, 128, 1)) return EXTERIA_E_ARG;
    invoice = exteria_tl_new_obj(arena, "inputInvoiceSlug");
    if (!invoice) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, invoice, "slug", slug);
    if (status == EXTERIA_OK) *out = invoice;
    return status;
}

exteria_status exteria_stars_form_parse(const exteria_tl_value *answer, exteria_stars_form *out) {
    const exteria_tl_value *invoice, *prices;
    const uint8_t *currency;
    size_t currency_len, i;
    int64_t total = 0;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(answer, EXTERIA_TL_ID_payments_paymentForm)) return EXTERIA_E_UNSUPPORTED;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_payments_paymentFormStars)) return EXTERIA_E_MALFORMED;
    invoice = exteria_tl_get(answer, "invoice");
    if (exteria_tl_get_i64(answer, "form_id", &out->form_id) != EXTERIA_OK || !exteria_tl_is(invoice, EXTERIA_TL_ID_invoice) ||
        exteria_tl_get_bytes(invoice, "currency", &currency, &currency_len) != EXTERIA_OK ||
        exteria_tl_get_vec(invoice, "prices", &prices) != EXTERIA_OK || prices->u.vec.count == 0 || prices->u.vec.count > PRICES_MAX) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    if (currency_len != 3 || memcmp(currency, "XTR", 3) != 0) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_UNSUPPORTED;
    }
    for (i = 0; i < prices->u.vec.count; ++i) {
        int64_t amount;
        if (exteria_tl_get_i64(prices->u.vec.items[i], "amount", &amount) != EXTERIA_OK || amount < 0 || amount > INT64_MAX - total) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        total += amount;
    }
    out->stars = total;
    exteria_tl_get_i64(answer, "bot_id", &out->bot_id);
    copy_text(out->title, sizeof(out->title), answer, "title", 0);
    copy_text(out->description, sizeof(out->description), answer, "description", 1);
    return EXTERIA_OK;
}

/* answers to a keyboard */

exteria_status exteria_send_contact_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *phone, const char *first_name,
                                            const char *last_name, int64_t random_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *media;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || random_id == 0 || !phone || !phone[0] || !first_name || !last_name || strlen(phone) > 32 || strlen(first_name) > 128 ||
        strlen(last_name) > 128 || !utf8_valid(first_name) || !utf8_valid(last_name)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.sendMedia");
    media = exteria_tl_new_obj(arena, "inputMediaContact");
    if (!request || !media) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, media, "phone_number", phone);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "first_name", first_name);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "last_name", last_name);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, media, "vcard", "");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_set_topic_reply(arena, request, peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "media", media);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", "");
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_requested_peers_request(exteria_arena *arena, const exteria_peer_ref *bot_chat, int32_t msg_id, int32_t button_id,
                                               const exteria_peer_ref *peers, size_t count, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *list;
    exteria_status status;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !out || !peers || count == 0 || count > 10 || msg_id <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, bot_chat, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.sendBotRequestedPeer");
    list = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!request || !list) return EXTERIA_E_NOMEM;
    for (i = 0; i < count && status == EXTERIA_OK; ++i) {
        exteria_tl_value *picked;
        status = exteria_input_peer(arena, &peers[i], &picked);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, (uint32_t)i, picked);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", msg_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "button_id", button_id);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "requested_peers", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}
