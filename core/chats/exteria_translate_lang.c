#include "exteria_translate_lang.h"

#include <stdio.h>
#include <string.h>

/* the target lists of the services, from GoogleTranslator, GoogleAppTranslator, GoogleCloudTranslator,
   MicrosoftTranslator, TranSmartTranslator and LingoTranslator; a string of codes apiece, compared without regard
   to case */
static const char google_new_list[] =
    "aa ab ace ach af ak alz am ar as av awa ay az ba bal ban bbc bci be bem ber ber-Latn bew bg bho bik bm bm-Nkoo bn bo br bs bts btx bua ca ce ceb cgg ch chk chm "
    "ckb cnh co crh crh-Latn crs cs cv cy da de din doi dov dv dyu dz ee el en eo es et eu fa fa-AF ff fi fj fo fon fr fr-CA fur fy ga gaa gd gl gn gom gu gv ha haw "
    "hi hil hmn hr hrx ht hu hy iba id ig ilo is it iu iu-Latn iw ja jam jw ka kac kek kg kha kk kl km kn ko kr kri ktu ku kv ky la lb lg li lij lmo ln lo lt ltg "
    "lua luo lus lv mad mai mak mam mfe mg mh mi min mk ml mn mni-Mtei mr ms ms-Arab mt mwr my ndc-ZW ne new nhe nl no nr nso nus ny oc om or os pa pa-Arab pag pam "
    "pap pl ps pt pt-PT qu rn ro rom ru rw sa sah sat sat-Latn scn sd se sg shn si sk sl sm sn so sq sr ss st su sus sv sw szl ta tcy te tet tg th ti tiv tk tl tn "
    "to tpi tr trp ts tt tum ty tyv udm ug uk ur uz ve vec vi war wo xh yi yo yua yue zap zh zh-CN zh-TW zu";
static const char google_classic_list[] =
    "sq ar am az ga et eu be bg is pl bs fa af da de ru fr tl fi fy km ka gu kk ht ko ha nl ky gl ca cs kn co hr ku la lv lo lt lb ro mg mt mr ml ms mk mi mn bn my "
    "hmn xh zu ne no pa pt ps ny ja sv sm sr st si eo sk sl sw gd ceb so tg te ta th tr cy ur uk uz es iw el haw sd hu sn hy ig it yi hi su id jw en yo vi zh-TW "
    "zh-CN zh";
static const char transmart_list[] = "ar fr fil lo ja it hi id vi de km ms th tr zh ru ko pt es";
static const char lingo_list[] = "zh en es fr ja ru";
static const char bing_list[] =
    "af sq am ar hy az bn bs bg ca zh-Hans zh-Hant hr cs da prs nl en et fil fi fr de el gu ht he hi hu is id iu ga it ja kn kk km ko ku lo lv lt mg ms ml mt mr my mi "
    "ne nb or ps fa pl pt pt-PT pa ro ru sm sr-Cyrl sr-Latn sk sl es sw sv ta te th to tr uk ur vi cy";

static int lower(int c) {
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static int upper(int c) {
    return c >= 'a' && c <= 'z' ? c - 32 : c;
}

static int in_list(const char *list, const char *code) {
    size_t length = strlen(code);
    const char *at = list;
    while (*at) {
        size_t n = 0;
        size_t i;
        int same;
        while (at[n] && at[n] != ' ') ++n;
        same = n == length;
        for (i = 0; same && i < n; ++i) same = lower(at[i]) == lower(code[i]);
        if (same) return 1;
        at += n;
        while (*at == ' ') ++at;
    }
    return 0;
}

static int is_letter(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

/* "pt-BR" into lowercase language and uppercase country; the country is empty when the code has none */
static exteria_status split_code(const char *code, char *lang, size_t lang_cap, char *country, size_t country_cap) {
    size_t i = 0, n = 0;
    lang[0] = 0;
    country[0] = 0;
    if (!code) return EXTERIA_E_ARG;
    while (is_letter(code[i])) {
        if (n + 1 >= lang_cap) return EXTERIA_E_ARG;
        lang[n++] = (char)lower(code[i++]);
    }
    lang[n] = 0;
    if (n < 2 || n > 3) return EXTERIA_E_ARG;
    if (!code[i]) return EXTERIA_OK;
    if (code[i] != '-' && code[i] != '_') return EXTERIA_E_ARG;
    ++i;
    n = 0;
    while (code[i]) {
        if (!is_letter(code[i]) && !(code[i] >= '0' && code[i] <= '9')) return EXTERIA_E_ARG;
        if (n + 1 >= country_cap) return EXTERIA_E_ARG;
        country[n++] = (char)upper(code[i++]);
    }
    country[n] = 0;
    return n >= 2 ? EXTERIA_OK : EXTERIA_E_ARG;
}

static exteria_status put(char *out, size_t cap, const char *text) {
    size_t length = strlen(text);
    if (!out || length + 1 > cap) return EXTERIA_E_ARG;
    memcpy(out, text, length + 1);
    return EXTERIA_OK;
}

static exteria_status join(char *out, size_t cap, const char *lang, const char *country) {
    int written = snprintf(out, cap, country[0] ? "%s-%s" : "%s", lang, country);
    return written > 0 && (size_t)written < cap ? EXTERIA_OK : EXTERIA_E_ARG;
}

static int country_is(const char *country, const char *a, const char *b) {
    return !strcmp(country, a) || (b && !strcmp(country, b));
}

exteria_status exteria_tr_target_for(int provider, int api, const char *code, char *out, size_t cap) {
    char lang[8], country[8], result[24];
    exteria_status status;
    if (out && cap) out[0] = 0;
    if (!out || !cap) return EXTERIA_E_ARG;
    status = split_code(code, lang, sizeof(lang), country, sizeof(country));
    if (status != EXTERIA_OK) return status;
    /* the old code of Indonesian, which the Java locale still reports */
    if (!strcmp(lang, "in")) strcpy(lang, "id");
    switch (provider) {
    case EXTERIA_TR_DEEPL:
        if (!strcmp(lang, "en") && country_is(country, "GB", "US")) status = join(result, sizeof(result), lang, country);
        else if (!strcmp(lang, "pt") && country_is(country, "BR", "PT")) status = join(result, sizeof(result), lang, country);
        else if (!strcmp(lang, "zh") && country_is(country, "CN", NULL)) status = put(result, sizeof(result), "zh-CN");
        else if (!strcmp(lang, "zh") && country_is(country, "TW", "HK")) status = put(result, sizeof(result), "zh-TW");
        else status = put(result, sizeof(result), lang);
        break;
    case EXTERIA_TR_YANDEX:
        status = !strcmp(lang, "pt") && country_is(country, "BR", NULL) ? put(result, sizeof(result), "pt-BR") : put(result, sizeof(result), lang);
        break;
    case EXTERIA_TR_GOOGLE:
        if (!strcmp(lang, "zh") && country_is(country, "CN", NULL)) status = put(result, sizeof(result), "zh-CN");
        else if (!strcmp(lang, "zh") && country_is(country, "TW", "HK")) status = put(result, sizeof(result), "zh-TW");
        else status = put(result, sizeof(result), lang);
        if (status == EXTERIA_OK) {
            const char *list = api == EXTERIA_TR_GOOGLE_NEW ? google_new_list : google_classic_list;
            if (!in_list(list, result)) return EXTERIA_E_UNSUPPORTED;
        }
        break;
    case EXTERIA_TR_TELEGRAM: {
        char joined[24];
        status = join(joined, sizeof(joined), lang, country);
        if (status != EXTERIA_OK) break;
        /* the list of Telegram holds a few codes with a country, and any other country is dropped */
        if (country[0] && (!strcmp(joined, "zh-TW") || !strcmp(joined, "zh-CN"))) status = put(result, sizeof(result), joined);
        else if (!strcmp(lang, "zh") && !strcmp(country, "DG")) status = put(result, sizeof(result), "zh-CN");
        else status = put(result, sizeof(result), lang);
        break;
    }
    case EXTERIA_TR_LINGO:
        status = put(result, sizeof(result), lang);
        if (status == EXTERIA_OK && !in_list(lingo_list, result)) return EXTERIA_E_UNSUPPORTED;
        break;
    case EXTERIA_TR_BING:
        /* bing names the two Chinese scripts, and Chinese with no country is the simplified one */
        if (!strcmp(lang, "zh") && country_is(country, "TW", "HK")) status = put(result, sizeof(result), "zh-Hant");
        else if (!strcmp(lang, "zh")) status = put(result, sizeof(result), "zh-Hans");
        else if (!strcmp(lang, "pt") && country_is(country, "PT", NULL)) status = put(result, sizeof(result), "pt-PT");
        else status = put(result, sizeof(result), lang);
        if (status == EXTERIA_OK && !in_list(bing_list, result)) return EXTERIA_E_UNSUPPORTED;
        break;
    case EXTERIA_TR_TRANSMART:
        status = put(result, sizeof(result), lang);
        if (status == EXTERIA_OK && !in_list(transmart_list, result)) return EXTERIA_E_UNSUPPORTED;
        break;
    case EXTERIA_TR_LLM:
        status = put(result, sizeof(result), lang);
        break;
    default:
        return EXTERIA_E_ARG;
    }
    if (status != EXTERIA_OK) return status;
    return put(out, cap, result);
}

exteria_status exteria_tr_deepl_target(const char *code, char *out, size_t cap) {
    char lower_code[24];
    size_t i, n;
    if (out && cap) out[0] = 0;
    if (!code || !out || !cap) return EXTERIA_E_ARG;
    n = strlen(code);
    if (!n || n >= sizeof(lower_code)) return EXTERIA_E_ARG;
    for (i = 0; i < n; ++i) lower_code[i] = (char)lower(code[i] == '_' ? '-' : code[i]);
    lower_code[n] = 0;
    if (!strcmp(lower_code, "zh-cn") || !strcmp(lower_code, "zh-hans")) return put(out, cap, "ZH-HANS");
    if (!strcmp(lower_code, "zh-tw") || !strcmp(lower_code, "zh-hk") || !strcmp(lower_code, "zh-hant")) return put(out, cap, "ZH-HANT");
    for (i = 0; i < n; ++i) lower_code[i] = (char)upper(lower_code[i]);
    return put(out, cap, lower_code);
}
