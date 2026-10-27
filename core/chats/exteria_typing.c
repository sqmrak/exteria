#include "exteria_typing.h"

#include "exteria_tl_ids.h"

#include <string.h>

static exteria_typing_action action_of(const exteria_tl_value *action) {
    if (!action || action->kind != EXTERIA_TL_V_OBJ) return EXTERIA_TYPING_CANCEL;
    switch (exteria_tl_id(action)) {
    case EXTERIA_TL_ID_sendMessageTypingAction:
    case EXTERIA_TL_ID_sendMessageTextDraftAction:
    case EXTERIA_TL_ID_sendMessageRichMessageDraftAction:
        return EXTERIA_TYPING_TEXT;
    case EXTERIA_TL_ID_sendMessageRecordAudioAction:
    case EXTERIA_TL_ID_sendMessageRecordRoundAction:
        return EXTERIA_TYPING_VOICE;
    case EXTERIA_TL_ID_sendMessageUploadPhotoAction:
        return EXTERIA_TYPING_PHOTO;
    case EXTERIA_TL_ID_sendMessageRecordVideoAction:
    case EXTERIA_TL_ID_sendMessageUploadVideoAction:
    case EXTERIA_TL_ID_sendMessageUploadRoundAction:
        return EXTERIA_TYPING_VIDEO;
    case EXTERIA_TL_ID_sendMessageUploadAudioAction:
    case EXTERIA_TL_ID_sendMessageUploadDocumentAction:
        return EXTERIA_TYPING_FILE;
    case EXTERIA_TL_ID_sendMessageChooseStickerAction:
        return EXTERIA_TYPING_STICKER;
    case EXTERIA_TL_ID_sendMessageGamePlayAction:
    case EXTERIA_TL_ID_sendMessageGeoLocationAction:
    case EXTERIA_TL_ID_sendMessageChooseContactAction:
    case EXTERIA_TL_ID_sendMessageHistoryImportAction:
        return EXTERIA_TYPING_OTHER;
    default:
        /* a cancel, a stop of a draft, or an action of a newer layer: none of them shows anything */
        return EXTERIA_TYPING_CANCEL;
    }
}

/* the person a Peer names; 0 when it is not a user (a channel posting as itself) */
static int64_t user_of_peer(const exteria_tl_value *peer) {
    int64_t id = 0;
    if (!peer || !exteria_tl_is(peer, EXTERIA_TL_ID_peerUser) || exteria_tl_get_i64(peer, "user_id", &id) != EXTERIA_OK || id <= 0) return 0;
    return id;
}

int exteria_typing_read(const exteria_tl_value *update, exteria_typing *out) {
    int64_t id = 0;
    int32_t top = 0;
    if (out) memset(out, 0, sizeof(*out));
    if (!update || !out) return 0;
    if (exteria_tl_is(update, EXTERIA_TL_ID_updateUserTyping)) {
        if (exteria_tl_get_i64(update, "user_id", &id) != EXTERIA_OK || id <= 0) return 0;
        out->peer_kind = 1;
        out->peer_id = id;
        out->user_id = id;
    } else if (exteria_tl_is(update, EXTERIA_TL_ID_updateChatUserTyping)) {
        if (exteria_tl_get_i64(update, "chat_id", &id) != EXTERIA_OK || id <= 0) return 0;
        out->peer_kind = 2;
        out->peer_id = id;
        out->user_id = user_of_peer(exteria_tl_get(update, "from_id"));
    } else if (exteria_tl_is(update, EXTERIA_TL_ID_updateChannelUserTyping)) {
        if (exteria_tl_get_i64(update, "channel_id", &id) != EXTERIA_OK || id <= 0) return 0;
        out->peer_kind = 3;
        out->peer_id = id;
        out->user_id = user_of_peer(exteria_tl_get(update, "from_id"));
    } else {
        return 0;
    }
    if (exteria_tl_has(update, "top_msg_id") && exteria_tl_get_i32(update, "top_msg_id", &top) == EXTERIA_OK && top > 0) out->top_message = top;
    if (!exteria_tl_get(update, "action")) {
        memset(out, 0, sizeof(*out));
        return 0;
    }
    out->action = action_of(exteria_tl_get(update, "action"));
    return 1;
}
