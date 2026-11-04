#include "exteria_cache_kind.h"
#include "test_util.h"

static exteria_cache_kind kind(const char *name, const void *bytes, size_t len) {
    return exteria_cache_classify(name, (const uint8_t *)bytes, len);
}

int main(void) {
    CHECK_EQ_INT(kind("d1_2", "\xFF\xD8\xFF\xE0\0\0\0\0", 8), EXTERIA_CACHE_PHOTO);
    CHECK_EQ_INT(kind("p1_2", "\x89PNG\r\n\x1A\n", 8), EXTERIA_CACHE_PHOTO);
    CHECK_EQ_INT(kind("d1", "GIF89a\0\0", 8), EXTERIA_CACHE_PHOTO);
    CHECK_EQ_INT(kind("d1", "\0\0\0\x18" "ftypmp42", 12), EXTERIA_CACHE_VIDEO);
    CHECK_EQ_INT(kind("d1", "\0\0\0\x14" "ftypqt  ", 12), EXTERIA_CACHE_VIDEO);
    CHECK_EQ_INT(kind("d1", "\0\0\0\x20" "ftypM4A ", 12), EXTERIA_CACHE_MUSIC);
    CHECK_EQ_INT(kind("d1", "\0\0\0\x18" "ftypheic", 12), EXTERIA_CACHE_PHOTO);
    CHECK_EQ_INT(kind("d1", "ID3\x04\0\0\0\0\0\0\0", 12), EXTERIA_CACHE_MUSIC);
    CHECK_EQ_INT(kind("d1", "\xFF\xFB\x90\x44", 4), EXTERIA_CACHE_MUSIC);
    CHECK_EQ_INT(kind("d1", "OggS\0\x02\0\0", 8), EXTERIA_CACHE_MUSIC);
    CHECK_EQ_INT(kind("d1", "fLaC\0\0\0\x22", 8), EXTERIA_CACHE_MUSIC);
    CHECK_EQ_INT(kind("d1", "RIFF\x24\0\0\0" "WAVEfmt ", 12), EXTERIA_CACHE_MUSIC);
    CHECK_EQ_INT(kind("d1", "RIFF\x24\0\0\0" "WEBPVP8 ", 12), EXTERIA_CACHE_STICKER);
    CHECK_EQ_INT(kind("d1", "\x1F\x8B\x08\0\0\0\0\0", 8), EXTERIA_CACHE_STICKER);
    CHECK_EQ_INT(kind("d1", "\x1A\x45\xDF\xA3\x01\0\0\0", 8), EXTERIA_CACHE_STICKER);
    /* a cover is a jpeg by its bytes and music by its name */
    CHECK_EQ_INT(kind("cover-v2-d1", "\xFF\xD8\xFF\xE0", 4), EXTERIA_CACHE_MUSIC);
    CHECK_EQ_INT(kind("cover-v2-d1", NULL, 0), EXTERIA_CACHE_MUSIC);
    /* unknown, short, empty and missing heads */
    CHECK_EQ_INT(kind("d1", "%PDF-1.4", 8), EXTERIA_CACHE_OTHER);
    CHECK_EQ_INT(kind("d1", "\xFF\xD8\xFF", 3), EXTERIA_CACHE_OTHER);
    CHECK_EQ_INT(kind("d1", "RIFF\0\0\0\0", 8), EXTERIA_CACHE_OTHER);
    /* a head cut before the brand is still an mp4 container, and the video is the common one */
    CHECK_EQ_INT(kind("d1", "\0\0\0\x18" "ftyp", 8), EXTERIA_CACHE_VIDEO);
    CHECK_EQ_INT(kind("d1", "", 0), EXTERIA_CACHE_OTHER);
    CHECK_EQ_INT(kind(NULL, NULL, 0), EXTERIA_CACHE_OTHER);
    return test_finish("test_cache_kind");
}
