#include "exteria_privacy.h"

#include <string.h>

#include "exteria_people.h"
#include "exteria_tl_ids.h"

#define ACCOUNT_TTL_MIN 30
#define ACCOUNT_TTL_MAX 730

static const char *const key_names[EXTERIA_PRIVACY_KEY_COUNT] = {
    "inputPrivacyKeyPhoneNumber", "inputPrivacyKeyStatusTimestamp", "inputPrivacyKeyProfilePhoto", "inputPrivacyKeyForwards",
    "inputPrivacyKeyPhoneCall", "inputPrivacyKeyChatInvite", "inputPrivacyKeyVoiceMessages", "inputPrivacyKeyAbout",
    "inputPrivacyKeyBirthday", "inputPrivacyKeySavedMusic",
};

exteria_status exteria_privacy_get_request(exteria_arena *arena, exteria_privacy_key key, exteria_tl_value **out) {
    exteria_tl_value *request, *name;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || (unsigned)key >= EXTERIA_PRIVACY_KEY_COUNT) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.getPrivacy");
    name = exteria_tl_new_obj(arena, key_names[key]);
    if (!request || !name) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "key", name);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* the text of a title field, cut at a whole character */
static void copy_text(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

/* a name cut at a whole character to the room of the destination */
static void copy_cstr(char *dst, size_t cap, const char *src) {
    size_t len = strlen(src);
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && ((uint8_t)src[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, src, len);
    dst[len] = 0;
}

/* a person by id in a vector of User objects; the name and hash stay zero for one the answer does not carry */
static void find_user(const exteria_tl_value *users, int64_t id, exteria_privacy_user *out) {
    uint32_t i;
    out->id = id;
    out->access_hash = 0;
    out->name[0] = 0;
    if (!users || users->kind != EXTERIA_TL_V_VEC) return;
    for (i = 0; i < users->u.vec.count; ++i) {
        exteria_person_row row;
        if (exteria_person_parse(users->u.vec.items[i], &row) != EXTERIA_OK || row.id != id) continue;
        out->access_hash = row.access_hash;
        out->photo = row.photo;
        copy_cstr(out->name, sizeof(out->name), row.name);
        return;
    }
}

static void find_chat(const exteria_tl_value *chats, int64_t id, exteria_privacy_chat *out) {
    uint32_t i;
    out->id = id;
    out->title[0] = 0;
    if (!chats || chats->kind != EXTERIA_TL_V_VEC) return;
    for (i = 0; i < chats->u.vec.count; ++i) {
        int64_t found;
        const exteria_tl_value *chat = chats->u.vec.items[i];
        if (exteria_tl_get_i64(chat, "id", &found) != EXTERIA_OK || found != id) continue;
        copy_text(out->title, sizeof(out->title), chat, "title");
        exteria_photo_ref_read(chat, exteria_tl_is(chat, EXTERIA_TL_ID_channel) ? 3 : 2, id, &out->photo);
        return;
    }
}

static exteria_status read_users(const exteria_tl_value *rule, const exteria_tl_value *users, exteria_privacy_user *rows, size_t *count) {
    const exteria_tl_value *ids;
    uint32_t i;
    if (exteria_tl_get_vec(rule, "users", &ids) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < ids->u.vec.count; ++i) {
        int64_t id;
        const exteria_tl_value *item = ids->u.vec.items[i];
        if (!item || item->kind != EXTERIA_TL_V_I64) return EXTERIA_E_MALFORMED;
        id = item->u.i64;
        if (*count >= EXTERIA_PRIVACY_EXCEPT_MAX) return EXTERIA_E_LIMIT;
        find_user(users, id, &rows[(*count)++]);
    }
    return EXTERIA_OK;
}

static exteria_status read_chats(const exteria_tl_value *rule, const exteria_tl_value *chats, exteria_privacy_chat *rows, size_t *count) {
    const exteria_tl_value *ids;
    uint32_t i;
    if (exteria_tl_get_vec(rule, "chats", &ids) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < ids->u.vec.count; ++i) {
        const exteria_tl_value *item = ids->u.vec.items[i];
        if (!item || item->kind != EXTERIA_TL_V_I64) return EXTERIA_E_MALFORMED;
        if (*count >= EXTERIA_PRIVACY_EXCEPT_MAX) return EXTERIA_E_LIMIT;
        find_chat(chats, item->u.i64, &rows[(*count)++]);
    }
    return EXTERIA_OK;
}

exteria_status exteria_privacy_parse(const exteria_tl_value *answer, exteria_privacy_rules *out) {
    const exteria_tl_value *rules, *users, *chats;
    uint32_t i;
    exteria_status status = EXTERIA_OK;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_account_privacyRules)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "rules", &rules) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    users = exteria_tl_get(answer, "users");
    chats = exteria_tl_get(answer, "chats");
    for (i = 0; i < rules->u.vec.count && status == EXTERIA_OK; ++i) {
        const exteria_tl_value *rule = rules->u.vec.items[i];
        uint32_t id = exteria_tl_id(rule);
        /* the rules are read in order, and the last of the three bases is the one that stands */
        if (id == EXTERIA_TL_ID_privacyValueAllowAll) out->base = EXTERIA_PRIVACY_EVERYBODY;
        else if (id == EXTERIA_TL_ID_privacyValueAllowContacts) out->base = EXTERIA_PRIVACY_CONTACTS;
        else if (id == EXTERIA_TL_ID_privacyValueDisallowAll) out->base = EXTERIA_PRIVACY_NOBODY;
        else if (id == EXTERIA_TL_ID_privacyValueAllowUsers) status = read_users(rule, users, out->allow_users, &out->allow_users_count);
        else if (id == EXTERIA_TL_ID_privacyValueDisallowUsers) status = read_users(rule, users, out->disallow_users, &out->disallow_users_count);
        else if (id == EXTERIA_TL_ID_privacyValueAllowChatParticipants) status = read_chats(rule, chats, out->allow_chats, &out->allow_chats_count);
        else if (id == EXTERIA_TL_ID_privacyValueDisallowChatParticipants) status = read_chats(rule, chats, out->disallow_chats, &out->disallow_chats_count);
        else if (id == EXTERIA_TL_ID_privacyValueAllowPremium) out->allow_premium = 1;
        else if (id == EXTERIA_TL_ID_privacyValueAllowCloseFriends) out->allow_close_friends = 1;
        else if (id == EXTERIA_TL_ID_privacyValueAllowBots) out->allow_bots = 1;
        else if (id == EXTERIA_TL_ID_privacyValueDisallowBots) out->disallow_bots = 1;
    }
    if (status != EXTERIA_OK) memset(out, 0, sizeof(*out));
    return status;
}

static exteria_status push_rule(exteria_arena *arena, exteria_tl_value *list, uint32_t *at, const char *ctor, exteria_tl_value **made) {
    exteria_tl_value *rule = exteria_tl_new_obj(arena, ctor);
    if (!rule) return EXTERIA_E_NOMEM;
    if (made) *made = rule;
    return exteria_tl_vec_set(list, (*at)++, rule);
}

static exteria_status user_rule(exteria_arena *arena, exteria_tl_value *list, uint32_t *at, const char *ctor, const exteria_privacy_user *users, size_t count) {
    exteria_tl_value *rule, *vec;
    exteria_status status;
    size_t i;
    if (!count) return EXTERIA_OK;
    status = push_rule(arena, list, at, ctor, &rule);
    if (status != EXTERIA_OK) return status;
    vec = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!vec) return EXTERIA_E_NOMEM;
    for (i = 0; i < count; ++i) {
        exteria_tl_value *input = exteria_tl_new_obj(arena, "inputUser");
        if (!input) return EXTERIA_E_NOMEM;
        /* a person the server did not give a hash for cannot be named, and sending a zero hash would be refused as a whole */
        if (users[i].access_hash == 0) return EXTERIA_E_ARG;
        status = exteria_tl_set_i64(arena, input, "user_id", users[i].id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", users[i].access_hash);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(vec, (uint32_t)i, input);
        if (status != EXTERIA_OK) return status;
    }
    return exteria_tl_set(rule, "users", vec);
}

static exteria_status chat_rule(exteria_arena *arena, exteria_tl_value *list, uint32_t *at, const char *ctor, const exteria_privacy_chat *chats, size_t count) {
    exteria_tl_value *rule;
    exteria_status status;
    int64_t ids[EXTERIA_PRIVACY_EXCEPT_MAX];
    size_t i;
    if (!count) return EXTERIA_OK;
    status = push_rule(arena, list, at, ctor, &rule);
    if (status != EXTERIA_OK) return status;
    for (i = 0; i < count; ++i) ids[i] = chats[i].id;
    return exteria_tl_set_i64_vec(arena, rule, "chats", ids, (uint32_t)count);
}

exteria_status exteria_privacy_set_request(exteria_arena *arena, exteria_privacy_key key, const exteria_privacy_rules *rules, exteria_tl_value **out) {
    exteria_tl_value *request, *name, *list;
    exteria_status status;
    uint32_t at = 0;
    const char *base;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !rules || (unsigned)key >= EXTERIA_PRIVACY_KEY_COUNT) return EXTERIA_E_ARG;
    if (rules->allow_users_count > EXTERIA_PRIVACY_EXCEPT_MAX || rules->disallow_users_count > EXTERIA_PRIVACY_EXCEPT_MAX ||
        rules->allow_chats_count > EXTERIA_PRIVACY_EXCEPT_MAX || rules->disallow_chats_count > EXTERIA_PRIVACY_EXCEPT_MAX) return EXTERIA_E_ARG;
    switch (rules->base) {
    case EXTERIA_PRIVACY_EVERYBODY: base = "inputPrivacyValueAllowAll"; break;
    case EXTERIA_PRIVACY_CONTACTS: base = "inputPrivacyValueAllowContacts"; break;
    case EXTERIA_PRIVACY_NOBODY: base = "inputPrivacyValueDisallowAll"; break;
    default: return EXTERIA_E_ARG;
    }
    request = exteria_tl_new_obj(arena, "account.setPrivacy");
    name = exteria_tl_new_obj(arena, key_names[key]);
    /* at most the four exception rules, four extras and the base */
    list = exteria_tl_new_vec(arena, 9);
    if (!request || !name || !list) return EXTERIA_E_NOMEM;
    status = user_rule(arena, list, &at, "inputPrivacyValueAllowUsers", rules->allow_users, rules->allow_users_count);
    if (status == EXTERIA_OK) status = user_rule(arena, list, &at, "inputPrivacyValueDisallowUsers", rules->disallow_users, rules->disallow_users_count);
    if (status == EXTERIA_OK) status = chat_rule(arena, list, &at, "inputPrivacyValueAllowChatParticipants", rules->allow_chats, rules->allow_chats_count);
    if (status == EXTERIA_OK) status = chat_rule(arena, list, &at, "inputPrivacyValueDisallowChatParticipants", rules->disallow_chats, rules->disallow_chats_count);
    if (status == EXTERIA_OK && rules->allow_premium) status = push_rule(arena, list, &at, "inputPrivacyValueAllowPremium", NULL);
    if (status == EXTERIA_OK && rules->allow_close_friends) status = push_rule(arena, list, &at, "inputPrivacyValueAllowCloseFriends", NULL);
    if (status == EXTERIA_OK && rules->allow_bots) status = push_rule(arena, list, &at, "inputPrivacyValueAllowBots", NULL);
    if (status == EXTERIA_OK && rules->disallow_bots) status = push_rule(arena, list, &at, "inputPrivacyValueDisallowBots", NULL);
    if (status == EXTERIA_OK) status = push_rule(arena, list, &at, base, NULL);
    if (status != EXTERIA_OK) return status;
    /* the vector was made for nine and holds what was pushed */
    list->u.vec.count = at;
    status = exteria_tl_set(request, "key", name);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "rules", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_blocked_request(exteria_arena *arena, int32_t offset, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || offset < 0 || limit < 1 || limit > EXTERIA_BLOCKED_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "contacts.getBlocked");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, request, "offset", offset);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static const exteria_tl_value *find_object(const exteria_tl_value *vec, int64_t id) {
    uint32_t i;
    if (!vec || vec->kind != EXTERIA_TL_V_VEC) return NULL;
    for (i = 0; i < vec->u.vec.count; ++i) {
        int64_t found;
        if (exteria_tl_get_i64(vec->u.vec.items[i], "id", &found) == EXTERIA_OK && found == id) return vec->u.vec.items[i];
    }
    return NULL;
}

static int read_blocked(const exteria_tl_value *item, const exteria_tl_value *users, const exteria_tl_value *chats, exteria_blocked_row *out) {
    const exteria_tl_value *peer = NULL, *object;
    const char *field = NULL;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(item, EXTERIA_TL_ID_peerBlocked) || exteria_tl_get_obj(item, "peer_id", &peer) != EXTERIA_OK) return 0;
    if (exteria_tl_is(peer, EXTERIA_TL_ID_peerUser)) { out->kind = 1; field = "user_id"; }
    else if (exteria_tl_is(peer, EXTERIA_TL_ID_peerChat)) { out->kind = 2; field = "chat_id"; }
    else if (exteria_tl_is(peer, EXTERIA_TL_ID_peerChannel)) { out->kind = 3; field = "channel_id"; }
    else return 0;
    if (exteria_tl_get_i64(peer, field, &out->id) != EXTERIA_OK) return 0;
    exteria_tl_get_i32(item, "date", &out->date);
    if (out->kind == 1) {
        exteria_person_row row;
        object = find_object(users, out->id);
        if (object && exteria_person_parse(object, &row) == EXTERIA_OK) {
            out->access_hash = row.access_hash;
            out->photo = row.photo;
            copy_cstr(out->name, sizeof(out->name), row.name);
        }
    } else {
        object = find_object(chats, out->id);
        if (object) {
            copy_text(out->name, sizeof(out->name), object, "title");
            exteria_tl_get_i64(object, "access_hash", &out->access_hash);
            exteria_photo_ref_read(object, out->kind, out->id, &out->photo);
        }
    }
    return 1;
}

exteria_status exteria_blocked_parse(const exteria_tl_value *answer, exteria_blocked_row *rows, size_t cap, size_t *count, int32_t *total) {
    const exteria_tl_value *list;
    uint32_t i;
    size_t found = 0;
    if (!count) return EXTERIA_E_ARG;
    *count = 0;
    if (total) *total = 0;
    if (!rows && cap) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_contacts_blocked) && !exteria_tl_is(answer, EXTERIA_TL_ID_contacts_blockedSlice)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "blocked", &list) != EXTERIA_OK || list->u.vec.count > EXTERIA_BLOCKED_MAX * 5u) return EXTERIA_E_MALFORMED;
    for (i = 0; i < list->u.vec.count && found < cap; ++i) {
        if (read_blocked(list->u.vec.items[i], exteria_tl_get(answer, "users"), exteria_tl_get(answer, "chats"), &rows[found])) ++found;
    }
    *count = found;
    if (total) {
        int32_t all = 0;
        if (!exteria_tl_has(answer, "count") || exteria_tl_get_i32(answer, "count", &all) != EXTERIA_OK) all = (int32_t)list->u.vec.count;
        *total = all;
    }
    return EXTERIA_OK;
}

exteria_status exteria_block_request(exteria_arena *arena, const exteria_peer_ref *peer, int block, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !peer) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, block ? "contacts.block" : "contacts.unblock");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_input_peer(arena, peer, &input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", input);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static exteria_status plain_request(exteria_arena *arena, const char *method, exteria_tl_value **out) {
    exteria_tl_value *request;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, method);
    if (!request) return EXTERIA_E_NOMEM;
    *out = request;
    return EXTERIA_OK;
}

exteria_status exteria_account_ttl_request(exteria_arena *arena, exteria_tl_value **out) {
    return plain_request(arena, "account.getAccountTTL", out);
}

exteria_status exteria_account_ttl_parse(const exteria_tl_value *answer, int32_t *days) {
    if (!days) return EXTERIA_E_ARG;
    *days = 0;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_accountDaysTTL)) return EXTERIA_E_MALFORMED;
    return exteria_tl_get_i32(answer, "days", days) == EXTERIA_OK ? EXTERIA_OK : EXTERIA_E_MALFORMED;
}

exteria_status exteria_account_ttl_set_request(exteria_arena *arena, int32_t days, exteria_tl_value **out) {
    exteria_tl_value *request, *ttl;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || days < ACCOUNT_TTL_MIN || days > ACCOUNT_TTL_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.setAccountTTL");
    ttl = exteria_tl_new_obj(arena, "accountDaysTTL");
    if (!request || !ttl) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, ttl, "days", days);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "ttl", ttl);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_history_ttl_request(exteria_arena *arena, exteria_tl_value **out) {
    return plain_request(arena, "messages.getDefaultHistoryTTL", out);
}

exteria_status exteria_history_ttl_parse(const exteria_tl_value *answer, int32_t *seconds) {
    if (!seconds) return EXTERIA_E_ARG;
    *seconds = 0;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_defaultHistoryTTL)) return EXTERIA_E_MALFORMED;
    return exteria_tl_get_i32(answer, "period", seconds) == EXTERIA_OK ? EXTERIA_OK : EXTERIA_E_MALFORMED;
}

exteria_status exteria_history_ttl_set_request(exteria_arena *arena, int32_t seconds, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || seconds < 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.setDefaultHistoryTTL");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, request, "period", seconds);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_clear_payments_request(exteria_arena *arena, int credentials, int info, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status = EXTERIA_OK;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || (!credentials && !info)) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "payments.clearSavedInfo");
    if (!request) return EXTERIA_E_NOMEM;
    if (credentials) status = exteria_tl_set_flag(request, "credentials");
    if (status == EXTERIA_OK && info) status = exteria_tl_set_flag(request, "info");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_reset_saved_contacts_request(exteria_arena *arena, exteria_tl_value **out) {
    return plain_request(arena, "contacts.resetSaved", out);
}
