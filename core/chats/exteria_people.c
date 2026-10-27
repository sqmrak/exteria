#include "exteria_people.h"

#include <string.h>

#include "exteria_store.h"
#include "exteria_tl_ids.h"

/* the same text rule as the chat list: UTF-8 cut at a character boundary, no line breaks */
static void copy_text(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len, out = 0;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    for (; out < len; ++out) dst[out] = (data[out] == '\n' || data[out] == '\r' || data[out] == '\t') ? ' ' : (char)data[out];
    dst[out] = 0;
}

static void join_name(char *dst, size_t cap, const exteria_tl_value *user) {
    char first[EXTERIA_PERSON_NAME_MAX], last[EXTERIA_PERSON_NAME_MAX];
    size_t a, b;
    copy_text(first, sizeof(first), user, "first_name");
    copy_text(last, sizeof(last), user, "last_name");
    a = strlen(first);
    b = strlen(last);
    if (a + b + 2 > cap) {
        last[0] = 0;
        b = 0;
    }
    if (a && b) {
        memcpy(dst, first, a);
        dst[a] = ' ';
        memcpy(dst + a + 1, last, b + 1);
    } else if (a || b) {
        memcpy(dst, a ? first : last, (a ? a : b) + 1);
    } else {
        copy_text(dst, cap, user, "username");
    }
}

void exteria_presence_read(const exteria_tl_value *status, exteria_presence *presence, int32_t *seen) {
    int32_t value;
    *presence = EXTERIA_PRESENCE_UNKNOWN;
    *seen = 0;
    if (exteria_tl_is(status, EXTERIA_TL_ID_userStatusOnline)) {
        *presence = EXTERIA_PRESENCE_ONLINE;
    } else if (exteria_tl_is(status, EXTERIA_TL_ID_userStatusOffline)) {
        *presence = EXTERIA_PRESENCE_OFFLINE;
        if (exteria_tl_get_i32(status, "was_online", &value) == EXTERIA_OK) *seen = value;
    } else if (exteria_tl_is(status, EXTERIA_TL_ID_userStatusRecently)) {
        *presence = EXTERIA_PRESENCE_RECENTLY;
    } else if (exteria_tl_is(status, EXTERIA_TL_ID_userStatusLastWeek)) {
        *presence = EXTERIA_PRESENCE_LAST_WEEK;
    } else if (exteria_tl_is(status, EXTERIA_TL_ID_userStatusLastMonth)) {
        *presence = EXTERIA_PRESENCE_LAST_MONTH;
    }
}

void exteria_emoji_status_read(const exteria_tl_value *user, int64_t *document, int32_t *until) {
    const exteria_tl_value *status = exteria_tl_get(user, "emoji_status");
    int64_t id = 0;
    int32_t end = 0;
    if (status && (exteria_tl_is(status, EXTERIA_TL_ID_emojiStatus) || exteria_tl_is(status, EXTERIA_TL_ID_emojiStatusCollectible)) &&
        exteria_tl_get_i64(status, "document_id", &id) == EXTERIA_OK && id > 0) {
        if (exteria_tl_get_i32(status, "until", &end) != EXTERIA_OK || end < 0) end = 0;
    } else {
        id = 0;
    }
    if (document) *document = id;
    if (until) *until = id ? end : 0;
}

exteria_status exteria_person_parse(const exteria_tl_value *user, exteria_person_row *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(user, EXTERIA_TL_ID_user) || exteria_tl_get_i64(user, "id", &out->id) != EXTERIA_OK || out->id <= 0) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    /* a min object comes from a mention and carries no hash that works for this account */
    if (!exteria_tl_has(user, "min")) exteria_tl_get_i64(user, "access_hash", &out->access_hash);
    out->bot = exteria_tl_has(user, "bot") ? 1 : 0;
    if (out->bot) {
        out->bot_inline = exteria_tl_has(user, "bot_inline_placeholder") ? 1 : 0;
        out->bot_inline_geo = exteria_tl_has(user, "bot_inline_geo") ? 1 : 0;
        out->bot_no_chats = exteria_tl_has(user, "bot_nochats") ? 1 : 0;
        out->bot_reads_all = exteria_tl_has(user, "bot_chat_history") ? 1 : 0;
        copy_text(out->bot_placeholder, sizeof(out->bot_placeholder), user, "bot_inline_placeholder");
    }
    out->verified = exteria_tl_has(user, "verified") ? 1 : 0;
    out->contact = exteria_tl_has(user, "contact") ? 1 : 0;
    out->mutual = exteria_tl_has(user, "mutual_contact") ? 1 : 0;
    out->premium = exteria_tl_has(user, "premium") ? 1 : 0;
    exteria_emoji_status_read(user, &out->emoji_status, &out->emoji_status_until);
    out->deleted = exteria_tl_has(user, "deleted") ? 1 : 0;
    {
        /* a collectible color has no id of its own and leaves the name to the default */
        const exteria_tl_value *color = exteria_tl_get(user, "color");
        int32_t id = 0;
        if (exteria_tl_is(color, EXTERIA_TL_ID_peerColor) && exteria_tl_get_i32(color, "color", &id) == EXTERIA_OK && id >= 0) {
            out->has_name_color = 1;
            out->name_color = id;
        }
    }
    join_name(out->name, sizeof(out->name), user);
    copy_text(out->username, sizeof(out->username), user, "username");
    copy_text(out->phone, sizeof(out->phone), user, "phone");
    exteria_photo_ref_read(user, 1, out->id, &out->photo);
    exteria_presence_read(exteria_tl_get(user, "status"), &out->presence, &out->seen);
    if (out->deleted) {
        out->presence = EXTERIA_PRESENCE_DELETED;
        out->seen = 0;
    }
    return EXTERIA_OK;
}

exteria_status exteria_channel_person_parse(const exteria_tl_value *channel, exteria_person_row *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if ((!exteria_tl_is(channel, EXTERIA_TL_ID_channel) && !exteria_tl_is(channel, EXTERIA_TL_ID_channelForbidden) &&
         !exteria_tl_is(channel, EXTERIA_TL_ID_community) && !exteria_tl_is(channel, EXTERIA_TL_ID_communityForbidden)) ||
        exteria_tl_get_i64(channel, "id", &out->id) != EXTERIA_OK || out->id <= 0) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    if (!exteria_tl_has(channel, "min")) exteria_tl_get_i64(channel, "access_hash", &out->access_hash);
    out->verified = exteria_tl_has(channel, "verified") ? 1 : 0;
    copy_text(out->name, sizeof(out->name), channel, "title");
    copy_text(out->username, sizeof(out->username), channel, "username");
    exteria_photo_ref_read(channel, 3, out->id, &out->photo);
    return EXTERIA_OK;
}

exteria_status exteria_group_roles_request(exteria_arena *arena, int32_t kind, int64_t id, int64_t hash, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || id <= 0 || (kind != 2 && kind != 3)) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, kind == 2 ? "messages.getFullChat" : "channels.getParticipants");
    if (!request) return EXTERIA_E_NOMEM;
    if (kind == 2) status = exteria_tl_set_i64(arena, request, "chat_id", id);
    else {
        exteria_tl_value *channel = exteria_tl_new_obj(arena, "inputChannel");
        if (!channel) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i64(arena, channel, "channel_id", id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, channel, "access_hash", hash);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "channel", channel);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "filter", exteria_tl_new_obj(arena, "channelParticipantsAdmins"));
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset", 0);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", EXTERIA_GROUP_ROLES_MAX);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    }
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_roles_parse(const exteria_tl_value *answer, int64_t id, exteria_group_role *rows, size_t cap, size_t *count) {
    const exteria_tl_value *participants = NULL;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !rows || !cap || !count || id <= 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_channels_channelParticipants)) {
        int32_t total = 0;
        if (exteria_tl_get_vec(answer, "participants", &participants) != EXTERIA_OK ||
            exteria_tl_get_i32(answer, "count", &total) != EXTERIA_OK || total < 0) return EXTERIA_E_MALFORMED;
        if ((uint32_t)total > participants->u.vec.count) return EXTERIA_E_LIMIT;
    } else if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatFull)) {
        const exteria_tl_value *full = exteria_tl_get(answer, "full_chat");
        const exteria_tl_value *group = exteria_tl_get(full, "participants");
        int64_t full_id = 0, group_id = 0;
        if (!exteria_tl_is(full, EXTERIA_TL_ID_chatFull) || exteria_tl_get_i64(full, "id", &full_id) != EXTERIA_OK || full_id != id ||
            !exteria_tl_is(group, EXTERIA_TL_ID_chatParticipants) || exteria_tl_get_i64(group, "chat_id", &group_id) != EXTERIA_OK || group_id != id ||
            exteria_tl_get_vec(group, "participants", &participants) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    } else return EXTERIA_E_MALFORMED;
    if (participants->u.vec.count > EXTERIA_PEOPLE_MAX) return EXTERIA_E_LIMIT;
    for (uint32_t i = 0; i < participants->u.vec.count; ++i) {
        const exteria_tl_value *p = participants->u.vec.items[i];
        exteria_group_role row;
        memset(&row, 0, sizeof(row));
        row.owner = exteria_tl_is(p, EXTERIA_TL_ID_channelParticipantCreator) || exteria_tl_is(p, EXTERIA_TL_ID_chatParticipantCreator);
        row.admin = row.owner || exteria_tl_is(p, EXTERIA_TL_ID_channelParticipantAdmin) || exteria_tl_is(p, EXTERIA_TL_ID_chatParticipantAdmin);
        if (!row.admin && !exteria_tl_is(p, EXTERIA_TL_ID_channelParticipant) && !exteria_tl_is(p, EXTERIA_TL_ID_channelParticipantSelf) &&
            !exteria_tl_is(p, EXTERIA_TL_ID_chatParticipant)) return EXTERIA_E_MALFORMED;
        if (exteria_tl_get_i64(p, "user_id", &row.user_id) != EXTERIA_OK || row.user_id <= 0) return EXTERIA_E_MALFORMED;
        copy_text(row.rank, sizeof(row.rank), p, "rank");
        if (!row.admin && !row.rank[0]) continue;
        if (n == cap) return EXTERIA_E_LIMIT;
        rows[n++] = row;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_contacts_parse(const exteria_tl_value *answer, exteria_person_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *users;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_contacts_contacts) || exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    for (i = 0; i < users->u.vec.count && n < cap; ++i) {
        /* an empty user in the list is skipped, one bad entry does not hide the rest */
        if (exteria_person_parse(users->u.vec.items[i], &rows[n]) == EXTERIA_OK) ++n;
    }
    *count = n;
    return EXTERIA_OK;
}
