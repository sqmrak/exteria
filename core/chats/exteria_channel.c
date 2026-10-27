#include "exteria_channel.h"

#include <string.h>

#include "exteria_store.h"
#include "exteria_tl_ids.h"

exteria_status exteria_channel_from_message_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id,
                                                   int64_t channel_id, exteria_tl_value **out) {
    exteria_tl_value *input, *channel, *list, *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || message_id <= 0 || channel_id <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    channel = exteria_tl_new_obj(arena, "inputChannelFromMessage");
    list = exteria_tl_new_vec(arena, 1);
    request = exteria_tl_new_obj(arena, "channels.getChannels");
    if (!channel || !list || !request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(channel, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, channel, "msg_id", message_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, channel, "channel_id", channel_id);
    if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, 0, channel);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

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

static const exteria_tl_value *find_channel(const exteria_tl_value *chats, int64_t id) {
    uint32_t i;
    for (i = 0; chats && chats->kind == EXTERIA_TL_V_VEC && i < chats->u.vec.count; ++i) {
        int64_t found;
        const exteria_tl_value *chat = chats->u.vec.items[i];
        if (exteria_tl_is(chat, EXTERIA_TL_ID_channel) && exteria_tl_get_i64(chat, "id", &found) == EXTERIA_OK && found == id) return chat;
    }
    return NULL;
}

/* the public name: the username field, or the first active one of the usernames list a channel with several carries */
static void read_username(char *dst, size_t cap, const exteria_tl_value *channel) {
    const exteria_tl_value *names = exteria_tl_get(channel, "usernames");
    uint32_t i;
    copy_text(dst, cap, channel, "username");
    if (dst[0] || !names || names->kind != EXTERIA_TL_V_VEC) return;
    for (i = 0; i < names->u.vec.count; ++i) {
        const exteria_tl_value *name = names->u.vec.items[i];
        if (exteria_tl_has(name, "active")) {
            copy_text(dst, cap, name, "username");
            if (dst[0]) return;
        }
    }
}

static void read_dialog(exteria_dialog_row *row, int64_t id, const exteria_tl_value *chats) {
    memset(row, 0, sizeof(*row));
    row->peer_kind = 3;
    row->peer_id = id;
    exteria_dialog_peer_read(row, NULL, chats, 0);
}

/* a request whose only argument is the channel */
static exteria_status channel_call(exteria_arena *arena, const exteria_peer_ref *channel, const char *method, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !channel || channel->kind != 3 || channel->id <= 0 || channel->access_hash == 0) return EXTERIA_E_ARG;
    input = exteria_tl_new_obj(arena, "inputChannel");
    request = exteria_tl_new_obj(arena, method);
    if (!input || !request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "channel_id", channel->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", channel->access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "channel", input);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_full_channel_request(exteria_arena *arena, const exteria_peer_ref *channel, exteria_tl_value **out) {
    return channel_call(arena, channel, "channels.getFullChannel", out);
}

exteria_status exteria_channel_join_request(exteria_arena *arena, const exteria_peer_ref *channel, exteria_tl_value **out) {
    return channel_call(arena, channel, "channels.joinChannel", out);
}

exteria_status exteria_channel_join_parse(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatInviteJoinResultOk)) return EXTERIA_OK;
    /* the channel wants a bot to verify the newcomer in a web view, which this client does not open */
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatInviteJoinResultWebView)) return EXTERIA_E_UNSUPPORTED;
    return EXTERIA_E_MALFORMED;
}

static const struct {
    uint32_t bit;
    const char *field;
} admin_rights_table[] = {
    {EXTERIA_ADMIN_CHANGE_INFO, "change_info"},
    {EXTERIA_ADMIN_POST_MESSAGES, "post_messages"},
    {EXTERIA_ADMIN_EDIT_MESSAGES, "edit_messages"},
    {EXTERIA_ADMIN_DELETE_MESSAGES, "delete_messages"},
    {EXTERIA_ADMIN_BAN_USERS, "ban_users"},
    {EXTERIA_ADMIN_INVITE_USERS, "invite_users"},
    {EXTERIA_ADMIN_PIN_MESSAGES, "pin_messages"},
    {EXTERIA_ADMIN_ADD_ADMINS, "add_admins"},
    {EXTERIA_ADMIN_MANAGE_CALL, "manage_call"},
    {EXTERIA_ADMIN_ANONYMOUS, "anonymous"},
    {EXTERIA_ADMIN_MANAGE_TOPICS, "manage_topics"},
};

uint32_t exteria_admin_rights_read(const exteria_tl_value *rights) {
    uint32_t bits = 0;
    size_t i;
    if (!exteria_tl_is(rights, EXTERIA_TL_ID_chatAdminRights)) return 0;
    for (i = 0; i < sizeof(admin_rights_table) / sizeof(admin_rights_table[0]); ++i) {
        if (exteria_tl_has(rights, admin_rights_table[i].field)) bits |= admin_rights_table[i].bit;
    }
    return bits;
}

exteria_status exteria_full_channel_parse(const exteria_tl_value *answer, int64_t channel_id, int32_t now, exteria_full_channel *out) {
    const exteria_tl_value *full, *chats, *entity, *invite, *notify;
    int64_t linked = 0;
    int32_t mute_until = 0;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatFull) || channel_id <= 0) return EXTERIA_E_MALFORMED;
    full = exteria_tl_get(answer, "full_chat");
    chats = exteria_tl_get(answer, "chats");
    entity = find_channel(chats, channel_id);
    if (!exteria_tl_is(full, EXTERIA_TL_ID_channelFull) || !entity) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    read_dialog(&out->dialog, channel_id, chats);
    out->megagroup = exteria_tl_has(entity, "megagroup") ? 1 : 0;
    out->creator = exteria_tl_has(entity, "creator") ? 1 : 0;
    out->signatures = exteria_tl_has(entity, "signatures") ? 1 : 0;
    out->admin_rights = out->creator ? EXTERIA_ADMIN_ALL : exteria_admin_rights_read(exteria_tl_get(entity, "admin_rights"));
    out->verified = exteria_tl_has(entity, "verified") ? 1 : 0;
    read_username(out->username, sizeof(out->username), entity);
    copy_text(out->about, sizeof(out->about), full, "about");
    exteria_tl_get_i32(full, "participants_count", &out->participants);
    exteria_tl_get_i32(full, "admins_count", &out->admins);
    exteria_tl_get_i32(full, "banned_count", &out->banned);
    exteria_tl_get_i32(full, "stargifts_count", &out->gifts);
    exteria_tl_get_i32(full, "pinned_msg_id", &out->pinned_message);
    out->can_view_stats = exteria_tl_has(full, "can_view_stats") ? 1 : 0;
    out->gifts_available = exteria_tl_has(full, "stargifts_available") ? 1 : 0;
    invite = exteria_tl_get(full, "exported_invite");
    if (exteria_tl_is(invite, EXTERIA_TL_ID_chatInviteExported)) copy_text(out->link, sizeof(out->link), invite, "link");
    notify = exteria_tl_get(full, "notify_settings");
    if (notify && exteria_tl_get_i32(notify, "mute_until", &mute_until) == EXTERIA_OK && mute_until > now) out->muted = 1;
    {
        exteria_peer chosen;
        if (exteria_peer_from_tl(exteria_tl_get(full, "default_send_as"), &chosen) == EXTERIA_OK && (chosen.kind == 1 || chosen.kind == 3) && chosen.id > 0) {
            out->send_as_kind = chosen.kind;
            out->send_as_id = chosen.id;
        }
    }
    if (exteria_tl_get_i64(full, "linked_chat_id", &linked) == EXTERIA_OK && linked > 0 && find_channel(chats, linked)) {
        read_dialog(&out->linked, linked, chats);
        out->has_linked = out->linked.title[0] != 0;
    }
    return EXTERIA_OK;
}

/* the channel, as the input channel of a request and its peer form; the access hash is required, as an unusable one is rejected by the server */
static exteria_status input_channel(exteria_arena *arena, const exteria_peer_ref *channel, exteria_tl_value **out) {
    exteria_tl_value *input;
    exteria_status status;
    *out = NULL;
    if (!arena || !channel || channel->kind != 3 || channel->id <= 0 || channel->access_hash == 0) return EXTERIA_E_ARG;
    input = exteria_tl_new_obj(arena, "inputChannel");
    if (!input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "channel_id", channel->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", channel->access_hash);
    if (status == EXTERIA_OK) *out = input;
    return status;
}

static exteria_status input_user(exteria_arena *arena, const exteria_peer_ref *user, exteria_tl_value **out) {
    exteria_tl_value *input;
    exteria_status status;
    *out = NULL;
    if (!arena || !user || user->kind != 1 || user->id <= 0 || user->access_hash == 0) return EXTERIA_E_ARG;
    input = exteria_tl_new_obj(arena, "inputUser");
    if (!input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "user_id", user->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", user->access_hash);
    if (status == EXTERIA_OK) *out = input;
    return status;
}

/* a request that starts from the channel: the request object with its channel set, ready for the other arguments */
static exteria_status channel_request(exteria_arena *arena, const exteria_peer_ref *channel, const char *method, exteria_tl_value **request) {
    exteria_tl_value *input;
    exteria_status status = input_channel(arena, channel, &input);
    *request = NULL;
    if (status != EXTERIA_OK) return status;
    *request = exteria_tl_new_obj(arena, method);
    if (!*request) return EXTERIA_E_NOMEM;
    return exteria_tl_set(*request, "channel", input);
}

static size_t text_length(const char *text, size_t max) {
    size_t len = 0;
    if (!text) return 0;
    while (len <= max && text[len]) ++len;
    return len;
}

exteria_status exteria_channel_members_request(exteria_arena *arena, const exteria_peer_ref *channel, exteria_member_list list, const char *query,
                                              int32_t offset, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request = NULL, *filter;
    exteria_status status;
    int has_query = query && query[0];
    if (out) *out = NULL;
    if (!out || offset < 0 || limit < 1 || limit > EXTERIA_MEMBERS_MAX || text_length(query, EXTERIA_MEMBERS_QUERY_MAX) > EXTERIA_MEMBERS_QUERY_MAX) return EXTERIA_E_ARG;
    if (list != EXTERIA_MEMBERS_RECENT && list != EXTERIA_MEMBERS_ADMINS && list != EXTERIA_MEMBERS_KICKED) return EXTERIA_E_ARG;
    status = channel_request(arena, channel, "channels.getParticipants", &request);
    if (status != EXTERIA_OK) return status;
    if (list == EXTERIA_MEMBERS_ADMINS) filter = exteria_tl_new_obj(arena, "channelParticipantsAdmins");
    else if (list == EXTERIA_MEMBERS_KICKED) filter = exteria_tl_new_obj(arena, "channelParticipantsKicked");
    else filter = exteria_tl_new_obj(arena, has_query ? "channelParticipantsSearch" : "channelParticipantsRecent");
    if (!filter) return EXTERIA_E_NOMEM;
    if (list == EXTERIA_MEMBERS_KICKED || (list == EXTERIA_MEMBERS_RECENT && has_query)) {
        status = exteria_tl_set_str(arena, filter, "q", has_query ? query : "");
        if (status != EXTERIA_OK) return status;
    }
    status = exteria_tl_set(request, "filter", filter);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset", offset);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static const exteria_tl_value *find_user(const exteria_tl_value *users, int64_t id) {
    uint32_t i;
    for (i = 0; users && users->kind == EXTERIA_TL_V_VEC && i < users->u.vec.count; ++i) {
        int64_t found;
        const exteria_tl_value *user = users->u.vec.items[i];
        if (exteria_tl_get_i64(user, "id", &found) == EXTERIA_OK && found == id) return user;
    }
    return NULL;
}

/* the user a participant is about: the user_id field, or the peer of a banned one; zero for a participant that is not a user */
static int64_t participant_user(const exteria_tl_value *participant) {
    int64_t id = 0;
    const exteria_tl_value *peer;
    if (exteria_tl_get_i64(participant, "user_id", &id) == EXTERIA_OK) return id;
    peer = exteria_tl_get(participant, "peer");
    if (exteria_tl_is(peer, EXTERIA_TL_ID_peerUser) && exteria_tl_get_i64(peer, "user_id", &id) == EXTERIA_OK) return id;
    return 0;
}

exteria_status exteria_channel_members_parse(const exteria_tl_value *answer, exteria_channel_member *rows, size_t cap, size_t *count, int32_t *total) {
    const exteria_tl_value *participants = NULL, *users;
    int32_t all = 0;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (total) *total = 0;
    if (!answer || !rows || !cap || !count || !total) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_channels_channelParticipantsNotModified)) return EXTERIA_OK;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_channels_channelParticipants) || exteria_tl_get_i32(answer, "count", &all) != EXTERIA_OK || all < 0 ||
        exteria_tl_get_vec(answer, "participants", &participants) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    users = exteria_tl_get(answer, "users");
    if (participants->u.vec.count > cap) return EXTERIA_E_LIMIT;
    for (i = 0; i < participants->u.vec.count; ++i) {
        const exteria_tl_value *p = participants->u.vec.items[i], *user;
        exteria_channel_member *row = &rows[n];
        int64_t id;
        memset(row, 0, sizeof(*row));
        if (exteria_tl_is(p, EXTERIA_TL_ID_channelParticipantCreator)) {
            row->role = EXTERIA_MEMBER_CREATOR;
            row->rights = EXTERIA_ADMIN_ALL;
        } else if (exteria_tl_is(p, EXTERIA_TL_ID_channelParticipantAdmin)) {
            row->role = EXTERIA_MEMBER_ADMIN;
            row->can_edit = exteria_tl_has(p, "can_edit") ? 1 : 0;
            row->rights = exteria_admin_rights_read(exteria_tl_get(p, "admin_rights"));
        } else if (exteria_tl_is(p, EXTERIA_TL_ID_channelParticipantBanned)) {
            row->role = EXTERIA_MEMBER_BANNED;
        } else if (exteria_tl_is(p, EXTERIA_TL_ID_channelParticipant) || exteria_tl_is(p, EXTERIA_TL_ID_channelParticipantSelf)) {
            row->role = EXTERIA_MEMBER_PLAIN;
        } else if (exteria_tl_is(p, EXTERIA_TL_ID_channelParticipantLeft)) {
            continue;
        } else {
            *count = 0;
            return EXTERIA_E_MALFORMED;
        }
        row->self = exteria_tl_is(p, EXTERIA_TL_ID_channelParticipantSelf) || exteria_tl_has(p, "self") ? 1 : 0;
        id = participant_user(p);
        user = id > 0 ? find_user(users, id) : NULL;
        if (!user || exteria_person_parse(user, &row->person) != EXTERIA_OK) continue;
        exteria_tl_get_i32(p, "date", &row->date);
        copy_text(row->rank, sizeof(row->rank), p, "rank");
        ++n;
    }
    *count = n;
    *total = all;
    return EXTERIA_OK;
}

exteria_status exteria_channel_admin_request(exteria_arena *arena, const exteria_peer_ref *channel, const exteria_peer_ref *user, uint32_t rights,
                                            const char *rank, exteria_tl_value **out) {
    exteria_tl_value *request = NULL, *input = NULL, *bits;
    exteria_status status;
    size_t i;
    if (out) *out = NULL;
    if (!out || (rights & ~EXTERIA_ADMIN_ALL) || text_length(rank, EXTERIA_MEMBER_RANK_MAX) >= EXTERIA_MEMBER_RANK_MAX) return EXTERIA_E_ARG;
    status = input_user(arena, user, &input);
    if (status != EXTERIA_OK) return status;
    status = channel_request(arena, channel, "channels.editAdmin", &request);
    if (status != EXTERIA_OK) return status;
    bits = exteria_tl_new_obj(arena, "chatAdminRights");
    if (!bits) return EXTERIA_E_NOMEM;
    for (i = 0; i < sizeof(admin_rights_table) / sizeof(admin_rights_table[0]) && status == EXTERIA_OK; ++i) {
        if (rights & admin_rights_table[i].bit) status = exteria_tl_set_flag(bits, admin_rights_table[i].field);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "user_id", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "admin_rights", bits);
    if (status == EXTERIA_OK && rank && rank[0]) status = exteria_tl_set_str(arena, request, "rank", rank);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_channel_ban_request(exteria_arena *arena, const exteria_peer_ref *channel, const exteria_peer_ref *user, int banned,
                                          exteria_tl_value **out) {
    exteria_tl_value *request = NULL, *participant = NULL, *rights;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || !user || user->kind != 1 || user->id <= 0 || user->access_hash == 0) return EXTERIA_E_ARG;
    status = channel_request(arena, channel, "channels.editBanned", &request);
    if (status != EXTERIA_OK) return status;
    status = exteria_input_peer(arena, user, &participant);
    if (status != EXTERIA_OK) return status;
    rights = exteria_tl_new_obj(arena, "chatBannedRights");
    if (!rights) return EXTERIA_E_NOMEM;
    /* until_date zero is forever; no flags at all lifts the ban */
    status = exteria_tl_set_i32(arena, rights, "until_date", 0);
    if (status == EXTERIA_OK && banned) status = exteria_tl_set_flag(rights, "view_messages");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "participant", participant);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "banned_rights", rights);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_channel_invite_request(exteria_arena *arena, const exteria_peer_ref *channel, const exteria_peer_ref *users, size_t count,
                                             exteria_tl_value **out) {
    exteria_tl_value *request = NULL, *list;
    exteria_status status;
    size_t i;
    if (out) *out = NULL;
    if (!out || !users || count == 0 || count > EXTERIA_INVITE_MAX || !channel || channel->kind != 3) return EXTERIA_E_ARG;
    status = channel_request(arena, channel, "channels.inviteToChannel", &request);
    if (status != EXTERIA_OK) return status;
    list = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!list) return EXTERIA_E_NOMEM;
    for (i = 0; i < count; ++i) {
        exteria_tl_value *input;
        status = input_user(arena, &users[i], &input);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, (uint32_t)i, input);
        if (status != EXTERIA_OK) return status;
    }
    status = exteria_tl_set(request, "users", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_channel_invite_missing(const exteria_tl_value *answer, size_t *missing) {
    const exteria_tl_value *list = NULL;
    if (missing) *missing = 0;
    if (!answer || !missing || !exteria_tl_is(answer, EXTERIA_TL_ID_messages_invitedUsers)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "missing_invitees", &list) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    *missing = list->u.vec.count;
    return EXTERIA_OK;
}

exteria_status exteria_channel_title_request(exteria_arena *arena, const exteria_peer_ref *channel, const char *title, exteria_tl_value **out) {
    exteria_tl_value *request = NULL;
    exteria_status status;
    if (out) *out = NULL;
    /* the server takes 1 to 128 characters; the byte bound is the same number of ascii characters and four times as many of the widest */
    if (!out || !title || !title[0] || text_length(title, EXTERIA_CHANNEL_TITLE_MAX * 4) > EXTERIA_CHANNEL_TITLE_MAX * 4) return EXTERIA_E_ARG;
    status = channel_request(arena, channel, "channels.editTitle", &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "title", title);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_channel_about_request(exteria_arena *arena, const exteria_peer_ref *channel, const char *about, exteria_tl_value **out) {
    exteria_tl_value *request, *peer = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || !about || !channel || channel->kind != 3 || text_length(about, EXTERIA_ABOUT_MAX) >= EXTERIA_ABOUT_MAX) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, channel, &peer);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.editChatAbout");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", peer);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "about", about);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_channel_username_request(exteria_arena *arena, const exteria_peer_ref *channel, const char *username, int check,
                                               exteria_tl_value **out) {
    exteria_tl_value *request = NULL;
    exteria_status status;
    size_t i;
    if (out) *out = NULL;
    if (!out || !username || text_length(username, EXTERIA_CHANNEL_USERNAME_MAX) >= EXTERIA_CHANNEL_USERNAME_MAX) return EXTERIA_E_ARG;
    /* a public name is letters, digits and underscores; the server's own rules (length, a letter first) are its to apply and report */
    for (i = 0; username[i]; ++i) {
        char c = username[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')) return EXTERIA_E_ARG;
    }
    if (check && !username[0]) return EXTERIA_E_ARG;
    status = channel_request(arena, channel, check ? "channels.checkUsername" : "channels.updateUsername", &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "username", username);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_channel_signatures_request(exteria_arena *arena, const exteria_peer_ref *channel, int enabled, exteria_tl_value **out) {
    exteria_tl_value *request = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!out) return EXTERIA_E_ARG;
    status = channel_request(arena, channel, "channels.toggleSignatures", &request);
    if (status == EXTERIA_OK && enabled) status = exteria_tl_set_flag(request, "signatures_enabled");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_channel_bool_parse(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolTrue)) return EXTERIA_OK;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolFalse)) return EXTERIA_E_STATE;
    return EXTERIA_E_MALFORMED;
}
