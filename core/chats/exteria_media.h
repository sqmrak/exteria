#ifndef EXTERIA_MEDIA_H
#define EXTERIA_MEDIA_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_dialogs.h"
#include "exteria_media_ref.h"
#include "exteria_tl.h"
#include "exteria_geo.h"

#define EXTERIA_MEDIA_NAME_MAX 128
#define EXTERIA_MEDIA_ALT_MAX 32
#define EXTERIA_MEDIA_MIME_MAX 48
#define EXTERIA_MEDIA_TAG_MAX 96
/* the packed waveform of a voice note; a longer one than this is dropped, since the picture is only decoration */
#define EXTERIA_MEDIA_WAVEFORM_MAX 256

typedef enum exteria_sticker_format {
    EXTERIA_STICKER_STATIC = 0,     /* webp */
    EXTERIA_STICKER_ANIMATED,       /* gzip lottie, application/x-tgsticker */
    EXTERIA_STICKER_VIDEO           /* webm, only its thumbnail can be shown on old systems */
} exteria_sticker_format;

typedef struct exteria_media_info {
    exteria_preview_kind kind;
    exteria_geo_point location;
    exteria_media_ref ref;          /* the file the bubble shows or the download saves */
    exteria_media_ref full_photo;
    int64_t full_photo_size;
    exteria_media_ref preview;      /* a thumbnail while the file loads, or the only picture of a video sticker */
    exteria_sticker_format sticker;
    int32_t width;
    int32_t height;
    int32_t duration;               /* seconds */
    int64_t size;                   /* bytes of ref */
    char name[EXTERIA_MEDIA_NAME_MAX];
    char alt[EXTERIA_MEDIA_ALT_MAX];    /* the emoji a sticker stands for */
    int64_t sticker_set_id;         /* the set a sticker belongs to, zero when the document names none by id */
    int64_t sticker_set_hash;
    uint8_t spoiler;                /* a photo or a video the sender asked to show blurred until it is tapped */
    char mime[EXTERIA_MEDIA_MIME_MAX];
    char title[EXTERIA_MEDIA_TAG_MAX];      /* the song title of an audio file, empty when the tags have none */
    char performer[EXTERIA_MEDIA_TAG_MAX];
    uint16_t waveform_len;                  /* bytes of waveform in use, zero when the note has none */
    uint8_t waveform[EXTERIA_MEDIA_WAVEFORM_MAX];
} exteria_media_info;

/* playable videos and animations keep their picture area even when telegram supplies no thumbnail */
int exteria_media_uses_picture(exteria_preview_kind kind, int has_file, int has_preview, int has_local_preview);

/* animations play inside the message and stay out of the photo and video gallery */
int exteria_media_opens_viewer(exteria_preview_kind kind);

/* reads the media of a message and says what it is; a media whose file cannot be fetched (no usable reference, an
   unknown constructor) still names its kind with a source of none */
void exteria_media_classify(const exteria_tl_value *media, exteria_media_info *out);

/* the same with the photo size picked nearest to photo_target pixels on the long side; a screen that shows the
   photo full size asks for a larger one than a message bubble does */
void exteria_media_classify_sized(const exteria_tl_value *media, int32_t photo_target, exteria_media_info *out);

/* one Photo object read as a picture, the size picked as exteria_media_classify_sized does; a photo that cannot be
   fetched leaves a media of kind photo with no source. out is always initialised */
void exteria_photo_read(const exteria_tl_value *photo, int32_t target, exteria_media_info *out);

/* one Document read as a file: its dc, size, mime, name, thumbnail and what it is; a sticker attribute makes it a
   sticker; a document that is not a Document object leaves a media with no source. out is always initialised */
void exteria_document_read(const exteria_tl_value *document, exteria_media_info *out);

#endif
