#include "exteria_call_log.h"

#include <stdlib.h>
#include <string.h>

#include "exteria_store.h"
#include "exteria_tl_ids.h"

exteria_status exteria_call_log_request(exteria_arena *arena, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request, *filter, *empty;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || limit < 1 || limit > EXTERIA_CALL_LOG_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.search");
    filter = exteria_tl_new_obj(arena, "inputMessagesFilterPhoneCalls");
    empty = exteria_tl_new_obj(arena, "inputPeerEmpty");
    if (!request || !filter || !empty) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "q", "");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "filter", filter);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "min_date", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "max_date", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", empty);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "add_offset", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "max_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "min_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static const exteria_tl_value *find_user(const exteria_tl_value *users, int64_t id) {
    uint32_t i;
    for (i = 0; i < users->u.vec.count; ++i) {
        int64_t found;
        const exteria_tl_value *user = users->u.vec.items[i];
        if (exteria_tl_get_i64(user, "id", &found) == EXTERIA_OK && found == id) return user;
    }
    return NULL;
}

exteria_status exteria_call_log_parse(const exteria_tl_value *answer, exteria_call_log_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *messages, *users;
    exteria_message_row *message;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_messages) && !exteria_tl_is(answer, EXTERIA_TL_ID_messages_messagesSlice) &&
        !exteria_tl_is(answer, EXTERIA_TL_ID_messages_channelMessages)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "messages", &messages) != EXTERIA_OK || exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    /* a message row is large, so it is made once on the heap for all of them */
    message = malloc(sizeof(*message));
    if (!message) return EXTERIA_E_NOMEM;
    for (i = 0; i < messages->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *m = messages->u.vec.items[i], *user;
        exteria_peer peer;
        exteria_person_row person;
        exteria_call_log_row *row = &rows[n];
        if (exteria_peer_from_tl(exteria_tl_get(m, "peer_id"), &peer) != EXTERIA_OK || peer.kind != 1) continue;
        memset(message, 0, sizeof(*message));
        if (exteria_message_read(m, message) != EXTERIA_OK || message->service != EXTERIA_SERVICE_CALL + 1) continue;
        user = find_user(users, peer.id);
        if (!user || exteria_person_parse(user, &person) != EXTERIA_OK) continue;
        memset(row, 0, sizeof(*row));
        row->message_id = message->id;
        row->date = message->date;
        row->duration = message->service_value;
        row->outgoing = message->out;
        row->video = message->call_video;
        row->outcome = message->call_reason;
        row->user_id = person.id;
        row->access_hash = person.access_hash;
        row->deleted = person.deleted;
        row->photo = person.photo;
        memcpy(row->name, person.name, sizeof(row->name));
        ++n;
    }
    free(message);
    *count = n;
    return EXTERIA_OK;
}
