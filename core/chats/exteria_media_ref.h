#ifndef EXTERIA_MEDIA_REF_H
#define EXTERIA_MEDIA_REF_H

#include <stdint.h>

/* split from exteria_media.h so the chat list row can hold a thumbnail without a cycle: media.h needs the preview kinds of the row */

#define EXTERIA_MEDIA_REF_MAX 128

typedef enum exteria_media_source {
    EXTERIA_MEDIA_SOURCE_NONE = 0,
    EXTERIA_MEDIA_SOURCE_DOCUMENT,
    EXTERIA_MEDIA_SOURCE_PHOTO
} exteria_media_source;

/* what upload.getFile needs to fetch a document, a photo size or a thumbnail of a document */
typedef struct exteria_media_ref {
    uint8_t source;         /* exteria_media_source; none means the file cannot be fetched */
    uint8_t ref_len;
    int32_t dc;
    int64_t id;
    int64_t access_hash;
    uint8_t file_ref[EXTERIA_MEDIA_REF_MAX];
    /* the photo size type ("m", "x") or the thumbnail type of a document; empty for the document itself */
    char thumb[8];
} exteria_media_ref;

#endif
