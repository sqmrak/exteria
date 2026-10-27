#include "exteria_send_as.h"

#include <string.h>

#include "exteria_store.h"
#include "exteria_tl_ids.h"

/* a user is an input peer with its hash, a channel the same, a chat by its id alone; saved messages is the account itself */
static exteria_status identity_peer(exteria_arena *arena, const exteria_peer_ref *who, exteria_tl_value **out) {
    exteria_tl_value *input = NULL;
    exteria_status status;
    *out = NULL;
    if (!who || who->self || who->id <= 0 || who->access_hash == 0 || (who->kind != 1 && who->kind != 3)) return EXTERIA_E_ARG;
    input = exteria_tl_new_obj(arena, who->kind == 1 ? "inputPeerUser" : "inputPeerChannel");
    if (!input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, who->kind == 1 ? "user_id" : "channel_id", who->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", who->access_hash);
    if (status == EXTERIA_OK) *out = input;
    return status;
}

exteria_status exteria_send_as_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || peer->kind == 1 || peer->self) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "channels.getSendAs");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_send_as_parse(const exteria_tl_value *answer, int64_t self_id, exteria_dialog_row *rows, uint8_t *premium_required, size_t cap,
                                     size_t *count) {
    const exteria_tl_value *peers, *chats, *users;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!answer || !rows || !premium_required || !count || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_channels_sendAsPeers)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "peers", &peers) != EXTERIA_OK || exteria_tl_get_vec(answer, "chats", &chats) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < peers->u.vec.count && n < cap && n < EXTERIA_SEND_AS_MAX; ++i) {
        const exteria_tl_value *item = peers->u.vec.items[i];
        exteria_dialog_row *row = &rows[n];
        exteria_peer peer;
        if (!exteria_tl_is(item, EXTERIA_TL_ID_sendAsPeer) || exteria_peer_from_tl(exteria_tl_get(item, "peer"), &peer) != EXTERIA_OK) continue;
        if (peer.kind != 1 && peer.kind != 3) continue;
        memset(row, 0, sizeof(*row));
        row->peer_kind = peer.kind;
        row->peer_id = peer.id;
        exteria_dialog_peer_read(row, users, chats, self_id);
        if (row->deleted || !row->title[0]) continue;
        premium_required[n] = exteria_tl_has(item, "premium_required") ? 1 : 0;
        ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_set_send_as(exteria_arena *arena, exteria_tl_value *request, const exteria_peer_ref *send_as) {
    exteria_tl_value *input;
    exteria_status status;
    if (!arena || !request) return EXTERIA_E_ARG;
    status = identity_peer(arena, send_as, &input);
    if (status != EXTERIA_OK) return status;
    return exteria_tl_set(request, "send_as", input);
}

exteria_status exteria_save_default_send_as_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_peer_ref *send_as,
                                                    exteria_tl_value **out) {
    exteria_tl_value *request, *input, *identity = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !send_as || !out || peer->kind == 1 || peer->self) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    /* the account itself is the choice "as myself", which the server wants as inputPeerSelf */
    if (send_as->self) {
        identity = exteria_tl_new_obj(arena, "inputPeerSelf");
        if (!identity) return EXTERIA_E_NOMEM;
    } else {
        status = identity_peer(arena, send_as, &identity);
        if (status != EXTERIA_OK) return status;
    }
    request = exteria_tl_new_obj(arena, "messages.saveDefaultSendAs");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "send_as", identity);
    if (status == EXTERIA_OK) *out = request;
    return status;
}
