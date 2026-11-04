#ifndef EXTERIA_CACHE_KIND_H
#define EXTERIA_CACHE_KIND_H

#include <stddef.h>
#include <stdint.h>

/* what a file of the media cache is, for the storage screen; the cache keeps files by key with no extension, so the
   kind comes from the first bytes */
typedef enum exteria_cache_kind {
    EXTERIA_CACHE_VIDEO = 0,
    EXTERIA_CACHE_PHOTO,
    EXTERIA_CACHE_MUSIC,
    EXTERIA_CACHE_STICKER,
    EXTERIA_CACHE_OTHER,
    EXTERIA_CACHE_KIND_COUNT
} exteria_cache_kind;

/* name is the file's name in the cache directory, head the first bytes and len how many of them there are (16 are
   enough); an unknown or empty file is EXTERIA_CACHE_OTHER */
exteria_cache_kind exteria_cache_classify(const char *name, const uint8_t *head, size_t len);

#endif
