#include "exteria_drafts.h"

#include "exteria_store.h"
#include "exteria_tl_ids.h"

#include <string.h>

static int is_vec(const exteria_tl_value *v) {
    return v && v->kind == EXTERIA_TL_V_VEC;
}

exteria_status exteria_draft_read(const exteria_tl_value *draft, int32_t topic_id, exteria_draft *out) {
    const uint8_t *text;
    size_t len;
    const exteria_tl_value *reply;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!draft) return EXTERIA_E_ARG;
    if (exteria_tl_is(draft, EXTERIA_TL_ID_draftMessageEmpty)) {
        /* the date is optional there and only says when the draft was cleared */
        if (exteria_tl_get_i32(draft, "date", &out->date) != EXTERIA_OK) out->date = 0;
        return EXTERIA_OK;
    }
    if (!exteria_tl_is(draft, EXTERIA_TL_ID_draftMessage)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_bytes(draft, "message", &text, &len) != EXTERIA_OK || len >= sizeof(out->text)) return EXTERIA_E_MALFORMED;
    memcpy(out->text, text, len);
    out->text[len] = 0;
    if (exteria_tl_get_i32(draft, "date", &out->date) != EXTERIA_OK) out->date = 0;
    out->no_webpage = exteria_tl_has(draft, "no_webpage") ? 1 : 0;
    reply = exteria_tl_get(draft, "reply_to");
    if (reply && exteria_tl_is(reply, EXTERIA_TL_ID_inputReplyToMessage)) {
        int32_t id = 0;
        if (exteria_tl_get_i32(reply, "reply_to_msg_id", &id) == EXTERIA_OK && id > 0 && id != topic_id) out->reply_to = id;
    }
    exteria_entities_read(draft, out->entities, EXTERIA_MESSAGE_ENTITIES_MAX, out->urls, sizeof(out->urls), &out->entity_count);
    out->present = out->text[0] || out->reply_to ? 1 : 0;
    return EXTERIA_OK;
}

exteria_status exteria_draft_save_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *text, const exteria_send_entity *entities,
                                          size_t entity_count, int32_t reply_to, int no_webpage, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *list = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !text || !out || reply_to < 0 || strlen(text) >= EXTERIA_DRAFT_TEXT_MAX) return EXTERIA_E_ARG;
    status = exteria_send_entities_build(arena, text, entities, entity_count, &list);
    if (status != EXTERIA_OK) return status;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.saveDraft");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    /* a topic draft names the topic root, the way a message sent there does */
    if (status == EXTERIA_OK) status = exteria_set_reply(arena, request, peer, reply_to);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", text);
    if (status == EXTERIA_OK && list) status = exteria_tl_set(request, "entities", list);
    if (status == EXTERIA_OK && no_webpage) status = exteria_tl_set_flag(request, "no_webpage");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_draft_update_read(const exteria_tl_value *update, int32_t *peer_kind, int64_t *peer_id, int32_t *topic_id,
                                         const exteria_tl_value **draft) {
    exteria_peer peer;
    const exteria_tl_value *body;
    int32_t top = 0;
    if (!peer_kind || !peer_id || !topic_id || !draft) return EXTERIA_E_ARG;
    *peer_kind = 0;
    *peer_id = 0;
    *topic_id = 0;
    *draft = NULL;
    if (!exteria_tl_is(update, EXTERIA_TL_ID_updateDraftMessage)) return EXTERIA_E_UNSUPPORTED;
    if (exteria_tl_has(update, "saved_peer_id")) return EXTERIA_E_UNSUPPORTED;
    if (exteria_peer_from_tl(exteria_tl_get(update, "peer"), &peer) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    body = exteria_tl_get(update, "draft");
    if (!body) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_i32(update, "top_msg_id", &top) != EXTERIA_OK) top = 0;
    /* the General topic is the chat itself for everything the app does with threads */
    if (top < 0) return EXTERIA_E_MALFORMED;
    *peer_kind = peer.kind;
    *peer_id = peer.id;
    *topic_id = top > 1 ? top : 0;
    *draft = body;
    return EXTERIA_OK;
}

exteria_status exteria_draft_dialogs_visit(const exteria_tl_value *answer, exteria_draft_visit visit, void *ctx) {
    const exteria_tl_value *dialogs;
    uint32_t i;
    if (!answer || !visit) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_dialogsNotModified)) return EXTERIA_OK;
    dialogs = exteria_tl_get(answer, "dialogs");
    if (!is_vec(dialogs)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < dialogs->u.vec.count; ++i) {
        const exteria_tl_value *dialog = dialogs->u.vec.items[i];
        exteria_peer peer;
        exteria_status status;
        if (!exteria_tl_is(dialog, EXTERIA_TL_ID_dialog)) continue;
        if (exteria_peer_from_tl(exteria_tl_get(dialog, "peer"), &peer) != EXTERIA_OK) continue;
        status = visit(ctx, peer.kind, peer.id, 0, exteria_tl_get(dialog, "draft"));
        if (status != EXTERIA_OK) return status;
    }
    return EXTERIA_OK;
}

exteria_status exteria_draft_topics_visit(const exteria_tl_value *answer, int32_t peer_kind, int64_t peer_id, exteria_draft_visit visit, void *ctx) {
    const exteria_tl_value *topics;
    uint32_t i;
    if (!answer || !visit || peer_kind != 3 || peer_id <= 0) return EXTERIA_E_ARG;
    topics = exteria_tl_get(answer, "topics");
    if (!is_vec(topics)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < topics->u.vec.count; ++i) {
        const exteria_tl_value *topic = topics->u.vec.items[i];
        int32_t id = 0;
        exteria_status status;
        if (!exteria_tl_is(topic, EXTERIA_TL_ID_forumTopic) || exteria_tl_get_i32(topic, "id", &id) != EXTERIA_OK || id <= 0) continue;
        status = visit(ctx, peer_kind, peer_id, id > 1 ? id : 0, exteria_tl_get(topic, "draft"));
        if (status != EXTERIA_OK) return status;
    }
    return EXTERIA_OK;
}
