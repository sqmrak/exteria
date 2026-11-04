#include "exteria_cache_kind.h"

#include <string.h>

static int has_at(const uint8_t *head, size_t len, size_t offset, const char *magic) {
    size_t n = strlen(magic);
    return head && len >= offset + n && memcmp(head + offset, magic, n) == 0;
}

exteria_cache_kind exteria_cache_classify(const char *name, const uint8_t *head, size_t len) {
    /* the cover of a track is a picture the cache made, and it goes with the music it belongs to */
    if (name && strncmp(name, "cover-", 6) == 0) return EXTERIA_CACHE_MUSIC;
    if (!head || len < 4) return EXTERIA_CACHE_OTHER;
    if (head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) return EXTERIA_CACHE_PHOTO;
    if (head[0] == 0x89 && has_at(head, len, 1, "PNG")) return EXTERIA_CACHE_PHOTO;
    if (has_at(head, len, 0, "GIF8")) return EXTERIA_CACHE_PHOTO;
    /* webp is the format of static stickers, gzip the one of tgs, and webm the one of video stickers */
    if (has_at(head, len, 0, "RIFF") && has_at(head, len, 8, "WEBP")) return EXTERIA_CACHE_STICKER;
    if (head[0] == 0x1F && head[1] == 0x8B) return EXTERIA_CACHE_STICKER;
    if (head[0] == 0x1A && head[1] == 0x45 && head[2] == 0xDF && head[3] == 0xA3) return EXTERIA_CACHE_STICKER;
    if (has_at(head, len, 0, "RIFF") && has_at(head, len, 8, "WAVE")) return EXTERIA_CACHE_MUSIC;
    if (has_at(head, len, 0, "ID3") || has_at(head, len, 0, "OggS") || has_at(head, len, 0, "fLaC")) return EXTERIA_CACHE_MUSIC;
    /* an mpeg audio frame starts with eleven set bits */
    if (head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) return EXTERIA_CACHE_MUSIC;
    if (has_at(head, len, 4, "ftyp")) {
        if (has_at(head, len, 8, "M4A ") || has_at(head, len, 8, "M4B ") || has_at(head, len, 8, "M4P ")) return EXTERIA_CACHE_MUSIC;
        if (has_at(head, len, 8, "heic") || has_at(head, len, 8, "heix") || has_at(head, len, 8, "mif1")) return EXTERIA_CACHE_PHOTO;
        return EXTERIA_CACHE_VIDEO;
    }
    return EXTERIA_CACHE_OTHER;
}
