#ifndef EXTERIA_TRANSLATE_H
#define EXTERIA_TRANSLATE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_tl.h"

/* the translation Telegram does itself, one of the providers of the translator: messages.translateText on a piece
   of text */

#define EXTERIA_TRANSLATE_TEXT_MAX 16384
#define EXTERIA_TRANSLATE_LANG_MAX 16

/* the text, at most EXTERIA_TRANSLATE_TEXT_MAX bytes and not empty, into the language code to_lang ("ru", "pt-br",
   "zh-CN"; letters, digits and dashes, 1 to EXTERIA_TRANSLATE_LANG_MAX - 1 of them); anything else is
   EXTERIA_E_ARG */
exteria_status exteria_translate_request(exteria_arena *arena, const char *text, const char *to_lang, exteria_tl_value **out);
/* a messages.translateResult: the first translated text, cut at a character boundary to cap - 1 bytes;
   EXTERIA_E_MALFORMED for any other answer or one without a text; out is empty then */
exteria_status exteria_translate_parse(const exteria_tl_value *answer, char *out, size_t cap);

#endif
