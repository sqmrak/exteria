#ifndef EXTERIA_LANGPACK_H
#define EXTERIA_LANGPACK_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_tl.h"

/* what a t.me/setlanguage link names: langpack.getLanguage on a pack code, and the langPackLanguage that comes back */

#define EXTERIA_LANGPACK_NAME_MAX 96
#define EXTERIA_LANGPACK_CODE_MAX 33
#define EXTERIA_LANGPACK_URL_MAX 256

typedef struct exteria_langpack_info {
    int official;
    int rtl;
    char name[EXTERIA_LANGPACK_NAME_MAX];           /* in English */
    char native_name[EXTERIA_LANGPACK_NAME_MAX];
    char lang_code[EXTERIA_LANGPACK_CODE_MAX];
    char base_lang_code[EXTERIA_LANGPACK_CODE_MAX]; /* the language the pack builds on, empty without one */
    int32_t strings_count;
    int32_t translated_count;
    char translations_url[EXTERIA_LANGPACK_URL_MAX];
} exteria_langpack_info;

/* langpack.getLanguage for a pack of a platform ("ios": letters, 1 to 16) and a language code (letters, digits, dash and underscore,
   1 to 32); anything else is EXTERIA_E_ARG */
exteria_status exteria_langpack_request(exteria_arena *arena, const char *lang_pack, const char *lang_code, exteria_tl_value **out);

/* a langPackLanguage. a name or a code that does not fit, a missing field and negative counts are EXTERIA_E_MALFORMED, with out zeroed; a
   long url is cut at a character boundary */
exteria_status exteria_langpack_parse(const exteria_tl_value *answer, exteria_langpack_info *out);

/* how much of the pack is translated, as the official clients say it: the share rounded up, 0 when the pack has no strings and 100 at most */
int exteria_langpack_percent(int32_t translated, int32_t strings);

#endif
