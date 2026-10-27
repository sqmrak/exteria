#include "exteria_avatars.h"

#include <string.h>

#include "exteria_tl_ids.h"

exteria_status exteria_user_photos_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request, *user;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !peer || limit < 1 || limit > EXTERIA_AVATARS_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "photos.getUserPhotos");
    if (!request) return EXTERIA_E_NOMEM;
    if (peer->self) {
        user = exteria_tl_new_obj(arena, "inputUserSelf");
        if (!user) return EXTERIA_E_NOMEM;
        status = EXTERIA_OK;
    } else {
        if (peer->kind != 1 || peer->id <= 0 || peer->access_hash == 0) return EXTERIA_E_ARG;
        user = exteria_tl_new_obj(arena, "inputUser");
        if (!user) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i64(arena, user, "user_id", peer->id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, user, "access_hash", peer->access_hash);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "user_id", user);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "max_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* a photo the viewer can fetch has a file; photoEmpty and photos without a usable size read as no source */
static int keep_photo(const exteria_tl_value *photo, exteria_media_info *out) {
    exteria_photo_read(photo, EXTERIA_AVATAR_TARGET, out);
    return out->ref.source != EXTERIA_MEDIA_SOURCE_NONE;
}

exteria_status exteria_user_avatars_parse(const exteria_tl_value *answer, exteria_media_info *photos, size_t cap, size_t *count, int32_t *total) {
    const exteria_tl_value *list;
    uint32_t i;
    if (!photos || !count || !total) return EXTERIA_E_ARG;
    *count = 0;
    *total = 0;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_photos_photos) && !exteria_tl_is(answer, EXTERIA_TL_ID_photos_photosSlice)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "photos", &list) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_photos_photosSlice)) {
        if (exteria_tl_get_i32(answer, "count", total) != EXTERIA_OK || *total < 0) {
            *total = 0;
            return EXTERIA_E_MALFORMED;
        }
    } else {
        *total = (int32_t)list->u.vec.count;
    }
    for (i = 0; i < list->u.vec.count && *count < cap; ++i) {
        if (keep_photo(list->u.vec.items[i], &photos[*count])) ++*count;
    }
    return EXTERIA_OK;
}

exteria_status exteria_chat_avatars_parse(const exteria_tl_value *answer, exteria_media_info *photos, size_t cap, size_t *count) {
    const exteria_tl_value *list;
    uint32_t i;
    if (!photos || !count) return EXTERIA_E_ARG;
    *count = 0;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_messages) && !exteria_tl_is(answer, EXTERIA_TL_ID_messages_messagesSlice) &&
        !exteria_tl_is(answer, EXTERIA_TL_ID_messages_channelMessages)) {
        return EXTERIA_E_MALFORMED;
    }
    if (exteria_tl_get_vec(answer, "messages", &list) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < list->u.vec.count && *count < cap; ++i) {
        const exteria_tl_value *message = list->u.vec.items[i], *action;
        if (!exteria_tl_is(message, EXTERIA_TL_ID_messageService)) continue;
        action = exteria_tl_get(message, "action");
        if (!exteria_tl_is(action, EXTERIA_TL_ID_messageActionChatEditPhoto)) continue;
        if (keep_photo(exteria_tl_get(action, "photo"), &photos[*count])) ++*count;
    }
    return EXTERIA_OK;
}
