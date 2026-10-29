#include "exteria_group_call.h"

#include <string.h>

#include "exteria_store.h"
#include "exteria_tl_ids.h"

static void copy_text(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data = NULL;
    size_t len = 0;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static int is_vec(const exteria_tl_value *v) {
    return v && v->kind == EXTERIA_TL_V_VEC;
}

static int flag(const exteria_tl_value *object, const char *name) {
    return exteria_tl_has(object, name) ? 1 : 0;
}

exteria_status exteria_group_call_ref_read(const exteria_tl_value *input, exteria_group_call_ref *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(input, EXTERIA_TL_ID_inputGroupCall) || exteria_tl_get_i64(input, "id", &out->id) != EXTERIA_OK ||
        exteria_tl_get_i64(input, "access_hash", &out->access_hash) != EXTERIA_OK || out->id == 0) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    return EXTERIA_OK;
}

exteria_status exteria_group_call_info_read(const exteria_tl_value *call, exteria_group_call_info *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(call, EXTERIA_TL_ID_groupCallDiscarded)) {
        out->discarded = 1;
        if (exteria_tl_get_i64(call, "id", &out->ref.id) != EXTERIA_OK || exteria_tl_get_i64(call, "access_hash", &out->ref.access_hash) != EXTERIA_OK ||
            out->ref.id == 0) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        exteria_tl_get_i32(call, "duration", &out->duration);
        return EXTERIA_OK;
    }
    if (!exteria_tl_is(call, EXTERIA_TL_ID_groupCall) || exteria_tl_get_i64(call, "id", &out->ref.id) != EXTERIA_OK ||
        exteria_tl_get_i64(call, "access_hash", &out->ref.access_hash) != EXTERIA_OK || out->ref.id == 0) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    out->join_muted = (uint8_t)flag(call, "join_muted");
    out->can_change_join_muted = (uint8_t)flag(call, "can_change_join_muted");
    out->creator = (uint8_t)flag(call, "creator");
    out->rtmp_stream = (uint8_t)flag(call, "rtmp_stream");
    out->conference = (uint8_t)flag(call, "conference");
    out->can_start_video = (uint8_t)flag(call, "can_start_video");
    exteria_tl_get_i32(call, "participants_count", &out->participants_count);
    exteria_tl_get_i32(call, "version", &out->version);
    exteria_tl_get_i32(call, "schedule_date", &out->schedule_date);
    copy_text(out->title, sizeof(out->title), call, "title");
    copy_text(out->invite_link, sizeof(out->invite_link), call, "invite_link");
    return EXTERIA_OK;
}

static const exteria_tl_value *find_by_id(const exteria_tl_value *vector, int64_t id) {
    uint32_t i;
    if (!is_vec(vector)) return NULL;
    for (i = 0; i < vector->u.vec.count; ++i) {
        int64_t found = 0;
        const exteria_tl_value *item = vector->u.vec.items[i];
        if (exteria_tl_get_i64(item, "id", &found) == EXTERIA_OK && found == id) return item;
    }
    return NULL;
}

exteria_status exteria_group_participant_read(const exteria_tl_value *participant, const exteria_tl_value *users, const exteria_tl_value *chats,
                                              exteria_group_participant *out) {
    exteria_peer peer;
    int32_t source = 0;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(participant, EXTERIA_TL_ID_groupCallParticipant) || exteria_peer_from_tl(exteria_tl_get(participant, "peer"), &peer) != EXTERIA_OK ||
        peer.id <= 0 || exteria_tl_get_i32(participant, "source", &source) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    out->peer_kind = peer.kind;
    out->peer_id = peer.id;
    out->source = (uint32_t)source;
    exteria_tl_get_i32(participant, "date", &out->date);
    exteria_tl_get_i32(participant, "active_date", &out->active_date);
    exteria_tl_get_i32(participant, "volume", &out->volume);
    out->muted = (uint8_t)flag(participant, "muted");
    out->left = (uint8_t)flag(participant, "left");
    out->can_self_unmute = (uint8_t)flag(participant, "can_self_unmute");
    out->just_joined = (uint8_t)flag(participant, "just_joined");
    out->self = (uint8_t)flag(participant, "self");
    out->muted_by_you = (uint8_t)flag(participant, "muted_by_you");
    out->has_video = (uint8_t)flag(participant, "video");
    out->has_presentation = (uint8_t)flag(participant, "presentation");
    if (peer.kind == 1) {
        const exteria_tl_value *user = find_by_id(users, peer.id);
        exteria_person_row person;
        if (user && exteria_person_parse(user, &person) == EXTERIA_OK) {
            out->access_hash = person.access_hash;
            out->deleted = person.deleted;
            out->photo = person.photo;
            memcpy(out->name, person.name, sizeof(out->name));
        }
    } else {
        const exteria_tl_value *chat = find_by_id(chats, peer.id);
        if (chat) copy_text(out->name, sizeof(out->name), chat, "title");
    }
    return EXTERIA_OK;
}

exteria_status exteria_group_participants_read(const exteria_tl_value *vector, const exteria_tl_value *users, const exteria_tl_value *chats,
                                               exteria_group_participant *out, size_t cap, size_t *count) {
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!out || !count || cap == 0) return EXTERIA_E_ARG;
    if (!is_vec(vector)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < vector->u.vec.count && n < cap; ++i) {
        if (exteria_group_participant_read(vector->u.vec.items[i], users, chats, &out[n]) == EXTERIA_OK) ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

static void next_offset_of(const exteria_tl_value *answer, char *out, size_t cap) {
    if (out && cap) copy_text(out, cap, answer, "participants_next_offset");
}

exteria_status exteria_group_call_answer_parse(const exteria_tl_value *answer, exteria_group_call_info *info, exteria_group_participant *participants, size_t cap,
                                               size_t *count, char *next_offset, size_t offset_cap) {
    exteria_status status;
    if (count) *count = 0;
    if (next_offset && offset_cap) next_offset[0] = 0;
    if (!answer || !info || !participants || !count) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_phone_groupCall)) return EXTERIA_E_MALFORMED;
    status = exteria_group_call_info_read(exteria_tl_get(answer, "call"), info);
    if (status != EXTERIA_OK) return status;
    status = exteria_group_participants_read(exteria_tl_get(answer, "participants"), exteria_tl_get(answer, "users"), exteria_tl_get(answer, "chats"), participants,
                                             cap, count);
    if (status != EXTERIA_OK) return status;
    next_offset_of(answer, next_offset, offset_cap);
    return EXTERIA_OK;
}

exteria_status exteria_group_participants_answer_parse(const exteria_tl_value *answer, exteria_group_participant *participants, size_t cap, size_t *count,
                                                       int32_t *version, char *next_offset, size_t offset_cap) {
    exteria_status status;
    if (count) *count = 0;
    if (version) *version = 0;
    if (next_offset && offset_cap) next_offset[0] = 0;
    if (!answer || !participants || !count) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_phone_groupParticipants)) return EXTERIA_E_MALFORMED;
    status = exteria_group_participants_read(exteria_tl_get(answer, "participants"), exteria_tl_get(answer, "users"), exteria_tl_get(answer, "chats"), participants,
                                             cap, count);
    if (status != EXTERIA_OK) return status;
    if (version) exteria_tl_get_i32(answer, "version", version);
    if (next_offset && offset_cap) copy_text(next_offset, offset_cap, answer, "next_offset");
    return EXTERIA_OK;
}

exteria_status exteria_group_update_call(const exteria_tl_value *update, exteria_group_call_info *out) {
    if (out) memset(out, 0, sizeof(*out));
    if (!out) return EXTERIA_E_ARG;
    if (!exteria_tl_is(update, EXTERIA_TL_ID_updateGroupCall)) return EXTERIA_E_MALFORMED;
    return exteria_group_call_info_read(exteria_tl_get(update, "call"), out);
}

exteria_status exteria_group_update_participants(const exteria_tl_value *update, const exteria_tl_value *container, exteria_group_call_ref *call,
                                                 exteria_group_participant *out, size_t cap, size_t *count, int32_t *version) {
    exteria_status status;
    if (count) *count = 0;
    if (version) *version = 0;
    if (!call || !out || !count || cap == 0) return EXTERIA_E_ARG;
    memset(call, 0, sizeof(*call));
    if (!exteria_tl_is(update, EXTERIA_TL_ID_updateGroupCallParticipants)) return EXTERIA_E_MALFORMED;
    status = exteria_group_call_ref_read(exteria_tl_get(update, "call"), call);
    if (status != EXTERIA_OK) return status;
    status = exteria_group_participants_read(exteria_tl_get(update, "participants"), container ? exteria_tl_get(container, "users") : NULL,
                                             container ? exteria_tl_get(container, "chats") : NULL, out, cap, count);
    if (status != EXTERIA_OK) return status;
    if (version) exteria_tl_get_i32(update, "version", version);
    return EXTERIA_OK;
}

exteria_status exteria_group_update_connection(const exteria_tl_value *update, const char **json, size_t *len, int *presentation) {
    const exteria_tl_value *params;
    const uint8_t *data = NULL;
    size_t n = 0;
    if (json) *json = NULL;
    if (len) *len = 0;
    if (presentation) *presentation = 0;
    if (!json || !len) return EXTERIA_E_ARG;
    if (!exteria_tl_is(update, EXTERIA_TL_ID_updateGroupCallConnection)) return EXTERIA_E_MALFORMED;
    params = exteria_tl_get(update, "params");
    if (!exteria_tl_is(params, EXTERIA_TL_ID_dataJSON) || exteria_tl_get_bytes(params, "data", &data, &n) != EXTERIA_OK || !data || n == 0) return EXTERIA_E_MALFORMED;
    *json = (const char *)data;
    *len = n;
    if (presentation) *presentation = flag(update, "presentation");
    return EXTERIA_OK;
}

static exteria_status input_call(exteria_arena *arena, const exteria_group_call_ref *call, exteria_tl_value **out) {
    exteria_tl_value *input;
    exteria_status status;
    *out = NULL;
    if (!arena || !call || call->id == 0) return EXTERIA_E_ARG;
    input = exteria_tl_new_obj(arena, "inputGroupCall");
    if (!input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "id", call->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", call->access_hash);
    if (status == EXTERIA_OK) *out = input;
    return status;
}

/* a request object of this method with its call set */
static exteria_status call_request(exteria_arena *arena, const exteria_group_call_ref *call, const char *method, exteria_tl_value **request) {
    exteria_tl_value *input = NULL;
    exteria_status status = input_call(arena, call, &input);
    *request = NULL;
    if (status != EXTERIA_OK) return status;
    *request = exteria_tl_new_obj(arena, method);
    if (!*request) return EXTERIA_E_NOMEM;
    return exteria_tl_set(*request, "call", input);
}

exteria_status exteria_group_call_get_request(exteria_arena *arena, const exteria_group_call_ref *call, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || limit < 0 || limit > EXTERIA_GROUP_PARTICIPANTS_MAX) return EXTERIA_E_ARG;
    status = call_request(arena, call, "phone.getGroupCall", &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_participants_get_request(exteria_arena *arena, const exteria_group_call_ref *call, const char *offset, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || limit <= 0 || limit > EXTERIA_GROUP_PARTICIPANTS_MAX || (offset && strlen(offset) >= EXTERIA_GROUP_OFFSET_MAX)) return EXTERIA_E_ARG;
    status = call_request(arena, call, "phone.getGroupParticipants", &request);
    if (status == EXTERIA_OK) {
        exteria_tl_value *ids = exteria_tl_new_vec(arena, 0), *sources = exteria_tl_new_vec(arena, 0);
        if (!ids || !sources) return EXTERIA_E_NOMEM;
        status = exteria_tl_set(request, "ids", ids);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "sources", sources);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "offset", offset ? offset : "");
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_join_request(exteria_arena *arena, const exteria_group_call_ref *call, int muted, const char *params, size_t params_len,
                                          const char *invite_hash, exteria_tl_value **out) {
    exteria_tl_value *request, *join_as, *data;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || !params || params_len == 0 || params_len > EXTERIA_GROUP_JOIN_PARAMS_MAX || memchr(params, 0, params_len) ||
        (invite_hash && (!invite_hash[0] || strlen(invite_hash) >= EXTERIA_GROUP_INVITE_HASH_MAX))) return EXTERIA_E_ARG;
    status = call_request(arena, call, "phone.joinGroupCall", &request);
    if (status != EXTERIA_OK) return status;
    join_as = exteria_tl_new_obj(arena, "inputPeerSelf");
    data = exteria_tl_new_obj(arena, "dataJSON");
    if (!join_as || !data) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "join_as", join_as);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, data, "data", params, params_len);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "params", data);
    if (status == EXTERIA_OK && muted) status = exteria_tl_set_flag(request, "muted");
    if (status == EXTERIA_OK && invite_hash) status = exteria_tl_set_str(arena, request, "invite_hash", invite_hash);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_leave_request(exteria_arena *arena, const exteria_group_call_ref *call, uint32_t source, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!out) return EXTERIA_E_ARG;
    status = call_request(arena, call, "phone.leaveGroupCall", &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "source", (int32_t)source);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_create_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t random_id, const char *title, exteria_tl_value **out) {
    exteria_tl_value *request, *input = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || peer->self || peer->kind < 2 || peer->kind > 3 || (title && strlen(title) >= EXTERIA_GROUP_TITLE_MAX)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "phone.createGroupCall");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK && title && title[0]) status = exteria_tl_set_str(arena, request, "title", title);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_discard_request(exteria_arena *arena, const exteria_group_call_ref *call, exteria_tl_value **out) {
    if (out) *out = NULL;
    if (!out) return EXTERIA_E_ARG;
    return call_request(arena, call, "phone.discardGroupCall", out);
}

exteria_status exteria_group_edit_request(exteria_arena *arena, const exteria_group_call_ref *call, const exteria_peer_ref *peer, int set_muted, int muted,
                                          int32_t volume, exteria_tl_value **out) {
    exteria_tl_value *request, *input = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || !peer || (!set_muted && volume == 0) || volume < 0 || volume > EXTERIA_GROUP_VOLUME_MAX) return EXTERIA_E_ARG;
    status = call_request(arena, call, "phone.editGroupCallParticipant", &request);
    if (status == EXTERIA_OK) status = exteria_input_peer(arena, peer, &input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "participant", input);
    if (status == EXTERIA_OK && set_muted) {
        exteria_tl_value *value = exteria_tl_new_obj(arena, muted ? "boolTrue" : "boolFalse");
        status = value ? exteria_tl_set(request, "muted", value) : EXTERIA_E_NOMEM;
    }
    if (status == EXTERIA_OK && volume) status = exteria_tl_set_i32(arena, request, "volume", volume);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_invite_link_request(exteria_arena *arena, const exteria_group_call_ref *call, int can_self_unmute, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!out) return EXTERIA_E_ARG;
    status = call_request(arena, call, "phone.exportGroupCallInvite", &request);
    if (status == EXTERIA_OK && can_self_unmute) status = exteria_tl_set_flag(request, "can_self_unmute");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_invite_link_parse(const exteria_tl_value *answer, char *link, size_t cap) {
    if (link && cap) link[0] = 0;
    if (!link || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_phone_exportedGroupCallInvite)) return EXTERIA_E_MALFORMED;
    copy_text(link, cap, answer, "link");
    return link[0] ? EXTERIA_OK : EXTERIA_E_MALFORMED;
}

exteria_status exteria_group_check_request(exteria_arena *arena, const exteria_group_call_ref *call, const int32_t *sources, uint32_t count, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || !sources || count == 0 || count > EXTERIA_GROUP_PARTICIPANTS_MAX) return EXTERIA_E_ARG;
    status = call_request(arena, call, "phone.checkGroupCall", &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32_vec(arena, request, "sources", sources, count);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_check_parse(const exteria_tl_value *answer, int32_t source, int *present) {
    uint32_t i;
    if (present) *present = 0;
    if (!present) return EXTERIA_E_ARG;
    if (!is_vec(answer)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < answer->u.vec.count; ++i) {
        const exteria_tl_value *item = answer->u.vec.items[i];
        if (item && item->kind == EXTERIA_TL_V_I32 && item->u.i32 == source) *present = 1;
    }
    return EXTERIA_OK;
}

exteria_status exteria_group_full_chat_request(exteria_arena *arena, const exteria_peer_ref *chat, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !chat || !out || chat->self || chat->id <= 0 || (chat->kind != 2 && chat->kind != 3) || (chat->kind == 3 && chat->access_hash == 0)) return EXTERIA_E_ARG;
    if (chat->kind == 2) {
        request = exteria_tl_new_obj(arena, "messages.getFullChat");
        if (!request) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i64(arena, request, "chat_id", chat->id);
    } else {
        request = exteria_tl_new_obj(arena, "channels.getFullChannel");
        input = exteria_tl_new_obj(arena, "inputChannel");
        if (!request || !input) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i64(arena, input, "channel_id", chat->id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", chat->access_hash);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "channel", input);
    }
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_full_chat_call(const exteria_tl_value *answer, exteria_group_call_ref *out) {
    const exteria_tl_value *full;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatFull)) return EXTERIA_E_MALFORMED;
    full = exteria_tl_get(answer, "full_chat");
    if (!exteria_tl_is(full, EXTERIA_TL_ID_chatFull) && !exteria_tl_is(full, EXTERIA_TL_ID_channelFull)) return EXTERIA_E_MALFORMED;
    if (!exteria_tl_has(full, "call")) return EXTERIA_E_NOTFOUND;
    return exteria_group_call_ref_read(exteria_tl_get(full, "call"), out);
}

exteria_status exteria_group_updates_find_call(const exteria_tl_value *updates, exteria_group_call_info *out) {
    const exteria_tl_value *one, *list;
    uint32_t i;
    if (out) memset(out, 0, sizeof(*out));
    if (!out) return EXTERIA_E_ARG;
    one = exteria_tl_get(updates, "update");
    if (exteria_tl_is(one, EXTERIA_TL_ID_updateGroupCall)) return exteria_group_update_call(one, out);
    list = exteria_tl_get(updates, "updates");
    for (i = 0; is_vec(list) && i < list->u.vec.count; ++i) {
        if (exteria_tl_is(list->u.vec.items[i], EXTERIA_TL_ID_updateGroupCall)) return exteria_group_update_call(list->u.vec.items[i], out);
    }
    return EXTERIA_E_NOTFOUND;
}
