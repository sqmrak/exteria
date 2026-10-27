#ifndef EXTERIA_PHOTOS_H
#define EXTERIA_PHOTOS_H

#include <stdint.h>

#include "exteria_tl.h"

/* what it takes to fetch a profile photo: where the file lives and who it belongs to */
typedef struct exteria_photo_ref {
    int64_t photo_id;       /* zero when the peer has no usable photo */
    int32_t dc;
    int32_t peer_kind;      /* 1 user, 2 chat, 3 channel, as exteria_peer */
    int64_t peer_id;
    int64_t access_hash;    /* zero for a basic group, which needs none */
} exteria_photo_ref;

/* reads the photo of a user, chat or channel object; a missing, empty or malformed photo, or a user or channel
   seen only in part (min) whose access hash cannot be used, leaves a zeroed ref and returns 0 */
int exteria_photo_ref_read(const exteria_tl_value *entity, int32_t peer_kind, int64_t peer_id, exteria_photo_ref *out);

/* an inputPeerPhotoFileLocation for the small (160 pixel) variant, built in arena */
exteria_status exteria_photo_location(exteria_arena *arena, const exteria_photo_ref *ref, exteria_tl_value **out);

#endif
