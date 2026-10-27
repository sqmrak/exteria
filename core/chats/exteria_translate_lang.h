#ifndef EXTERIA_TRANSLATE_LANG_H
#define EXTERIA_TRANSLATE_LANG_H

#include <stddef.h>

#include "exteria_status.h"

/* the language codes of the translators */

#define EXTERIA_TR_LANG_MAX 16

typedef enum {
    EXTERIA_TR_GOOGLE = 1,
    EXTERIA_TR_YANDEX = 3,
    EXTERIA_TR_LINGO = 4,
    EXTERIA_TR_BING = 5,
    EXTERIA_TR_DEEPL = 7,
    EXTERIA_TR_TELEGRAM = 8,
    EXTERIA_TR_TRANSMART = 9,
    EXTERIA_TR_LLM = 10
} exteria_tr_provider;

/* which API of Google answers: the new one of translate-pa, the Cloud API when a key is set, or else the one of the Google app */
typedef enum {
    EXTERIA_TR_GOOGLE_NEW,
    EXTERIA_TR_GOOGLE_CLOUD,
    EXTERIA_TR_GOOGLE_APP
} exteria_tr_google_api;

/* the target language as the service wants it, from a code of the form "ru", "pt-BR", "zh_CN" (either separator,
   any case) */
exteria_status exteria_tr_target_for(int provider, int api, const char *code, char *out, size_t cap);

/* the target as the DeepL API names it: "EN-GB", "PT-BR", "ZH-HANS", "ZH-HANT", or the language in capitals */
exteria_status exteria_tr_deepl_target(const char *code, char *out, size_t cap);

#endif
