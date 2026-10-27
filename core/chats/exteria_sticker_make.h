#ifndef EXTERIA_STICKER_MAKE_H
#define EXTERIA_STICKER_MAKE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_tl.h"

/* making a sticker of the account's own: a 512 pixel PNG (the server converts it) is uploaded as a document, then
   put into a new set or into one the account made */

#define EXTERIA_STICKER_TITLE_MAX 64        /* characters */
#define EXTERIA_STICKER_SHORT_NAME_MAX 64   /* bytes; letters, digits and single underscores */
#define EXTERIA_STICKER_EMOJI_MAX 32        /* bytes of the emoji that stand for the sticker */
#define EXTERIA_STICKER_REF_MAX 256

/* the document the server made of the uploaded file, as an input document needs it */
typedef struct exteria_input_document {
    int64_t id;
    int64_t access_hash;
    uint8_t file_reference[EXTERIA_STICKER_REF_MAX];
    size_t file_reference_len;
} exteria_input_document;

/* 1 to EXTERIA_STICKER_TITLE_MAX characters of valid UTF-8 that are not all blanks */
int exteria_sticker_title_valid(const char *title);
/* the public name of a set: starts with a letter, then letters, digits and underscores, no two underscores in a row, none at the end */
int exteria_sticker_short_name_valid(const char *name);
/* one or more emoji and nothing that is a plain letter or digit, at most EXTERIA_STICKER_EMOJI_MAX bytes */
int exteria_sticker_emoji_valid(const char *emoji);

/* messages.uploadMedia of an uploaded file to the account's own chat, as a PNG document with this file name; the answer is read with
   exteria_sticker_upload_parse. file is the inputFile the upload gave */
exteria_status exteria_sticker_upload_request(exteria_arena *arena, exteria_tl_value *file, const char *file_name, exteria_tl_value **out);
/* the messageMediaDocument it answers. out is always initialised; EXTERIA_E_MALFORMED for anything else or a reference too long to keep */
exteria_status exteria_sticker_upload_parse(const exteria_tl_value *answer, exteria_input_document *out);

/* stickers.createStickerSet for the account itself with one sticker; title, name and emoji must pass the checks
   above */
exteria_status exteria_sticker_create_request(exteria_arena *arena, const char *title, const char *short_name, const exteria_input_document *document,
                                              const char *emoji, exteria_tl_value **out);
/* stickers.addStickerToSet for a set found by its public name */
exteria_status exteria_sticker_add_request(exteria_arena *arena, const char *short_name, const exteria_input_document *document, const char *emoji,
                                           exteria_tl_value **out);
/* stickers.checkShortName; the Bool it answers is read with exteria_sticker_check_parse */
exteria_status exteria_sticker_check_request(exteria_arena *arena, const char *short_name, exteria_tl_value **out);
/* EXTERIA_OK when the name is free, EXTERIA_E_STATE when it is taken, EXTERIA_E_MALFORMED for anything else */
exteria_status exteria_sticker_check_parse(const exteria_tl_value *answer);
/* the messages.stickerSet either call answers: the public name of the set in short_name (capacity cap) */
exteria_status exteria_sticker_set_name_parse(const exteria_tl_value *answer, char *short_name, size_t cap);

#endif
