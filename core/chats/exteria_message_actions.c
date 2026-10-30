#include "exteria_message_actions.h"

#include <string.h>

#include "exteria_tl_ids.h"
#include "exteria_app_config.h"

int exteria_read_action_allowed(int ghost, exteria_read_action action) {
    if (action != EXTERIA_READ_AUTOMATIC && action != EXTERIA_READ_EXPLICIT && action != EXTERIA_READ_ONCE) return 0;
    return !ghost || action == EXTERIA_READ_EXPLICIT;
}

int exteria_code_has_hidden_spoiler(size_t offset, size_t length, const exteria_entity *entities, size_t count) {
    if (!length || length > SIZE_MAX - offset || (count && !entities) || count > EXTERIA_MESSAGE_ENTITIES_MAX) return 1;
    for (size_t i = 0; i < count; ++i) {
        if (entities[i].kind != EXTERIA_ENTITY_SPOILER || entities[i].offset < 0 || entities[i].length <= 0) continue;
        size_t start = (size_t)entities[i].offset, span = (size_t)entities[i].length;
        if (span > SIZE_MAX - start) return 1;
        if (start < offset + length && offset < start + span) return 1;
    }
    return 0;
}

exteria_status exteria_sharing_period_parse(const exteria_tl_value *answer, int32_t *seconds) {
    return exteria_app_config_i32(answer, "no_forwards_request_expire_period", seconds);
}

int exteria_sharing_expired(int server_expired, int32_t date, int32_t period, int64_t now) {
    if (server_expired) return 1;
    if (date <= 0 || period < 0 || now <= 0) return 0;
    return now > (int64_t)date + period;
}

exteria_status exteria_sharing_request(exteria_arena *arena, const exteria_peer_ref *peer, int enabled, int32_t request_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *value;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || peer->kind != 1 || peer->self || request_id < 0 || (enabled != 0 && enabled != 1)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.toggleNoForwards");
    value = exteria_tl_new_obj(arena, enabled ? "boolTrue" : "boolFalse");
    if (!request || !value) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "enabled", value);
    if (status == EXTERIA_OK && request_id) status = exteria_tl_set_i32(arena, request, "request_msg_id", request_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

uint32_t exteria_message_actions_for(const exteria_action_context *c) {
    uint32_t mask = 0;
    int sent, words_only, may_write;
    if (!c || c->service) return 0;
    sent = c->message_id > 0;
    if (c->has_text) mask |= EXTERIA_ACTION_COPY;
    if (!sent) return mask;
    words_only = c->media == EXTERIA_PREVIEW_NONE || c->media == EXTERIA_PREVIEW_TEXT;
    /* a broadcast channel is written to by its admins alone, and so replied in, pinned in and cleaned up by them */
    may_write = !c->broadcast || c->can_post;
    mask |= EXTERIA_ACTION_DETAILS | EXTERIA_ACTION_FORWARD;
    if (!c->saved_chat) mask |= EXTERIA_ACTION_SAVE;
    mask |= EXTERIA_ACTION_SELECT;
    mask |= c->bookmarked ? EXTERIA_ACTION_UNBOOKMARK : EXTERIA_ACTION_BOOKMARK;
    if (c->media == EXTERIA_PREVIEW_VOICE) mask |= EXTERIA_ACTION_TRANSCRIBE;
    if (c->has_text && c->translate_wanted) mask |= EXTERIA_ACTION_TRANSLATE;
    if (c->media_fetchable && (c->media == EXTERIA_PREVIEW_PHOTO || c->media == EXTERIA_PREVIEW_VIDEO || c->media == EXTERIA_PREVIEW_GIF ||
                               c->media == EXTERIA_PREVIEW_VIDEO_MESSAGE)) mask |= EXTERIA_ACTION_GALLERY;
    if (c->reactions_possible) mask |= EXTERIA_ACTION_REACT;
    if (may_write) mask |= EXTERIA_ACTION_REPLY;
    /* a public channel links by its name, a private one by a link the server makes */
    if (c->peer_kind == 3) mask |= EXTERIA_ACTION_COPY_LINK;
    if (c->media == EXTERIA_PREVIEW_PHOTO && c->media_fetchable) mask |= EXTERIA_ACTION_COPY_PHOTO;
    mask |= EXTERIA_ACTION_FORWARD_HIDDEN;
    if (!c->outgoing && !c->saved_chat) mask |= EXTERIA_ACTION_REPORT;
    /* a person's messages are searched in a group; a broadcast channel has one voice, and a private chat only two */
    mask |= EXTERIA_ACTION_REMIND;
    if (c->sender_user && !c->outgoing && (c->peer_kind == 2 || (c->peer_kind == 3 && !c->broadcast))) mask |= EXTERIA_ACTION_HISTORY | EXTERIA_ACTION_REPLY_PRIVATE;
    if (c->outgoing && c->has_text && !c->has_entities && words_only) mask |= EXTERIA_ACTION_EDIT | EXTERIA_ACTION_REPEAT;
    /* a picture, a video, an animation, a file or a song carries a caption, which may be written or changed, also when it has none yet; the media itself stays */
    if (c->outgoing && !c->has_entities && (c->media == EXTERIA_PREVIEW_PHOTO || c->media == EXTERIA_PREVIEW_VIDEO || c->media == EXTERIA_PREVIEW_GIF ||
                                            c->media == EXTERIA_PREVIEW_FILE || c->media == EXTERIA_PREVIEW_AUDIO)) mask |= EXTERIA_ACTION_EDIT;
    if (may_write) mask |= c->pinned_now ? EXTERIA_ACTION_UNPIN : EXTERIA_ACTION_PIN;
    if (c->outgoing || c->saved_chat || (c->broadcast && c->can_post)) mask |= EXTERIA_ACTION_DELETE;
    return mask;
}

exteria_status exteria_transcribe_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || message_id <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.transcribeAudio");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", message_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_transcribe_parse(const exteria_tl_value *answer, exteria_transcript *out) {
    const uint8_t *data;
    size_t len;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_transcribedAudio) || exteria_tl_get_i64(answer, "transcription_id", &out->id) != EXTERIA_OK ||
        exteria_tl_get_bytes(answer, "text", &data, &len) != EXTERIA_OK) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    out->pending = exteria_tl_has(answer, "pending") ? 1 : 0;
    if (len >= sizeof(out->text)) {
        len = sizeof(out->text) - 1;
        /* a sequence that did not fit whole goes with its lead byte */
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(out->text, data, len);
    out->text[len] = 0;
    return EXTERIA_OK;
}

exteria_status exteria_read_date_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || message_id <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.getOutboxReadDate");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", message_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_read_date_parse(const exteria_tl_value *answer, int32_t *date) {
    if (!date) return EXTERIA_E_ARG;
    *date = 0;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_outboxReadDate) || exteria_tl_get_i32(answer, "date", date) != EXTERIA_OK || *date <= 0) {
        *date = 0;
        return EXTERIA_E_MALFORMED;
    }
    return EXTERIA_OK;
}

exteria_status exteria_group_read_dates_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || message_id <= 0 || (peer->kind != 2 && peer->kind != 3) || peer->self) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.getMessageReadParticipants");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", message_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_group_read_dates_parse(const exteria_tl_value *answer, exteria_group_read_date *rows, size_t capacity, size_t *count) {
    uint32_t i;
    if (count) *count = 0;
    if (!count || (!rows && capacity)) return EXTERIA_E_ARG;
    if (!answer || answer->kind != EXTERIA_TL_V_VEC) return EXTERIA_E_MALFORMED;
    if (answer->u.vec.count > capacity) return EXTERIA_E_LIMIT;
    for (i = 0; i < answer->u.vec.count; ++i) {
        int64_t user = 0;
        int32_t date = 0;
        const exteria_tl_value *row = answer->u.vec.items[i];
        if (!exteria_tl_is(row, EXTERIA_TL_ID_readParticipantDate) || exteria_tl_get_i64(row, "user_id", &user) != EXTERIA_OK || user <= 0 ||
            exteria_tl_get_i32(row, "date", &date) != EXTERIA_OK || date < 0) return EXTERIA_E_MALFORMED;
        rows[i].user_id = user;
        rows[i].date = date;
    }
    *count = answer->u.vec.count;
    return EXTERIA_OK;
}

uint32_t exteria_selection_actions(const uint32_t *masks, size_t count) {
    uint32_t together = EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_DELETE, result = EXTERIA_ACTION_SELECT;
    size_t i;
    if (!masks || count == 0) return 0;
    for (i = 0; i < count; ++i) {
        together &= masks[i];
        if (masks[i] & EXTERIA_ACTION_COPY) result |= EXTERIA_ACTION_COPY;
    }
    if (count <= EXTERIA_MESSAGES_MAX) result |= together;
    return result;
}

static int ids_valid(const int32_t *ids, size_t count) {
    size_t i;
    if (!ids || count == 0 || count > EXTERIA_MESSAGES_MAX) return 0;
    for (i = 0; i < count; ++i) if (ids[i] <= 0) return 0;
    return 1;
}

exteria_status exteria_delete_messages_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                               int revoke, exteria_tl_value **out) {
    exteria_tl_value *request, *channel;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || !ids_valid(ids, count)) return EXTERIA_E_ARG;
    if (peer->kind == 3 && !peer->self) {
        if (peer->id <= 0 || peer->access_hash == 0) return EXTERIA_E_ARG;
        request = exteria_tl_new_obj(arena, "channels.deleteMessages");
        channel = exteria_tl_new_obj(arena, "inputChannel");
        if (!request || !channel) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i64(arena, channel, "channel_id", peer->id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, channel, "access_hash", peer->access_hash);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "channel", channel);
    } else if (peer->kind == 1 || peer->kind == 2) {
        request = exteria_tl_new_obj(arena, "messages.deleteMessages");
        if (!request) return EXTERIA_E_NOMEM;
        status = revoke ? exteria_tl_set_flag(request, "revoke") : EXTERIA_OK;
    } else {
        return EXTERIA_E_ARG;
    }
    if (status == EXTERIA_OK) status = exteria_tl_set_i32_vec(arena, request, "id", ids, (uint32_t)count);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_delete_messages_parse(const exteria_tl_value *answer) {
    return exteria_tl_is(answer, EXTERIA_TL_ID_messages_affectedMessages) ? EXTERIA_OK : EXTERIA_E_MALFORMED;
}

exteria_status exteria_pin_message_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, int unpin, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || id <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.updatePinnedMessage");
    if (!request) return EXTERIA_E_NOMEM;
    if (unpin) status = exteria_tl_set_flag(request, "unpin");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "id", id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static exteria_status edit_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, const char *text, int allow_empty,
                                   exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    size_t len;
    if (out) *out = NULL;
    if (!arena || !peer || !out || !text || id <= 0) return EXTERIA_E_ARG;
    len = strlen(text);
    if (len == 0 && !allow_empty) return EXTERIA_E_ARG;
    if (len >= EXTERIA_MESSAGE_TEXT_MAX) return EXTERIA_E_LIMIT;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.editMessage");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "id", id);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", text);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_edit_message_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, const char *text,
                                            exteria_tl_value **out) {
    return edit_request(arena, peer, id, text, 0, out);
}

exteria_status exteria_edit_caption_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, const char *text,
                                            exteria_tl_value **out) {
    return edit_request(arena, peer, id, text, 1, out);
}

exteria_status exteria_forward_messages_request(exteria_arena *arena, const exteria_peer_ref *from, const exteria_peer_ref *to,
                                                const int32_t *ids, const int64_t *random_ids, size_t count, int drop_author,
                                                exteria_tl_value **out) {
    exteria_tl_value *request, *source, *target;
    exteria_status status;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !from || !to || !out || !random_ids || !ids_valid(ids, count)) return EXTERIA_E_ARG;
    for (i = 0; i < count; ++i) if (random_ids[i] == 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, from, &source);
    if (status == EXTERIA_OK) status = exteria_input_peer(arena, to, &target);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.forwardMessages");
    if (!request) return EXTERIA_E_NOMEM;
    status = drop_author ? exteria_tl_set_flag(request, "drop_author") : EXTERIA_OK;
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "from_peer", source);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32_vec(arena, request, "id", ids, (uint32_t)count);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64_vec(arena, request, "random_id", random_ids, (uint32_t)count);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "to_peer", target);
    if (status == EXTERIA_OK) *out = request;
    return status;
}
