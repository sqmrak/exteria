#ifndef EXTERIA_AVATARS_H
#define EXTERIA_AVATARS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_media.h"
#include "exteria_messages.h"
#include "exteria_tl.h"

/* the profile photos one screen asks for; a person with more shows the newest ones */
#define EXTERIA_AVATARS_MAX 40
/* the long side of the photo size picked for the full screen viewer */
#define EXTERIA_AVATAR_TARGET 1280

/* photos.getUserPhotos of the user a peer names (kind 1 with an access hash, or oneself), the newest first. limit is 1 to EXTERIA_AVATARS_MAX; any other
   peer or limit is EXTERIA_E_ARG */
exteria_status exteria_user_photos_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t limit, exteria_tl_value **out);
/* a photos.photos or photos.photosSlice: every photo that can be fetched is put in photos (at most cap) as
   exteria_photo_read reads it at EXTERIA_AVATAR_TARGET, count says how many */
exteria_status exteria_user_avatars_parse(const exteria_tl_value *answer, exteria_media_info *photos, size_t cap, size_t *count, int32_t *total);
/* a messages answer to exteria_chat_photos_request: the photo of each service message that changed the photo of
   the chat, in server order; other messages and photos that cannot be fetched are skipped */
exteria_status exteria_chat_avatars_parse(const exteria_tl_value *answer, exteria_media_info *photos, size_t cap, size_t *count);

#endif
