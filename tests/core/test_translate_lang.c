#include "test_util.h"
#include "exteria_translate_lang.h"

#include <string.h>

static void target(int provider, int api, const char *code, exteria_status expected, const char *expected_code) {
    char out[EXTERIA_TR_LANG_MAX];
    exteria_status status = exteria_tr_target_for(provider, api, code, out, sizeof(out));
    CHECK_EQ_INT(status, expected);
    if (expected == EXTERIA_OK) CHECK(!strcmp(out, expected_code));
    else CHECK_EQ_INT(out[0], 0);
}

static void test_google(void) {
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_NEW, "ru", EXTERIA_OK, "ru");
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_NEW, "RU", EXTERIA_OK, "ru");
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_NEW, "zh_CN", EXTERIA_OK, "zh-CN");
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_NEW, "zh-hk", EXTERIA_OK, "zh-TW");
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_NEW, "zh", EXTERIA_OK, "zh");
    /* the country is dropped from every other language, so "pt-BR" asks for "pt" */
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_NEW, "pt-BR", EXTERIA_OK, "pt");
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_APP, "in", EXTERIA_OK, "id");
    /* the languages of the new API that the old ones lack */
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_NEW, "yue", EXTERIA_OK, "yue");
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_APP, "yue", EXTERIA_E_UNSUPPORTED, NULL);
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_CLOUD, "yue", EXTERIA_E_UNSUPPORTED, NULL);
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_CLOUD, "ceb", EXTERIA_OK, "ceb");
    target(EXTERIA_TR_GOOGLE, EXTERIA_TR_GOOGLE_NEW, "xx", EXTERIA_E_UNSUPPORTED, NULL);
}

static void test_other_services(void) {
    target(EXTERIA_TR_DEEPL, 0, "en-GB", EXTERIA_OK, "en-GB");
    target(EXTERIA_TR_DEEPL, 0, "en_us", EXTERIA_OK, "en-US");
    target(EXTERIA_TR_DEEPL, 0, "en-AU", EXTERIA_OK, "en");
    target(EXTERIA_TR_DEEPL, 0, "pt-br", EXTERIA_OK, "pt-BR");
    target(EXTERIA_TR_DEEPL, 0, "pt", EXTERIA_OK, "pt");
    target(EXTERIA_TR_DEEPL, 0, "zh", EXTERIA_OK, "zh");
    target(EXTERIA_TR_DEEPL, 0, "zh-CN", EXTERIA_OK, "zh-CN");
    target(EXTERIA_TR_DEEPL, 0, "zh-HK", EXTERIA_OK, "zh-TW");
    target(EXTERIA_TR_YANDEX, 0, "pt-BR", EXTERIA_OK, "pt-BR");
    target(EXTERIA_TR_YANDEX, 0, "pt-PT", EXTERIA_OK, "pt");
    target(EXTERIA_TR_YANDEX, 0, "de-AT", EXTERIA_OK, "de");
    target(EXTERIA_TR_TELEGRAM, 0, "zh-TW", EXTERIA_OK, "zh-TW");
    target(EXTERIA_TR_TELEGRAM, 0, "zh_CN", EXTERIA_OK, "zh-CN");
    target(EXTERIA_TR_TELEGRAM, 0, "zh-HK", EXTERIA_OK, "zh");
    target(EXTERIA_TR_TELEGRAM, 0, "pt-BR", EXTERIA_OK, "pt");
    target(EXTERIA_TR_TELEGRAM, 0, "ru", EXTERIA_OK, "ru");
    target(EXTERIA_TR_LINGO, 0, "ru", EXTERIA_OK, "ru");
    target(EXTERIA_TR_LINGO, 0, "de", EXTERIA_E_UNSUPPORTED, NULL);
    target(EXTERIA_TR_BING, 0, "ru", EXTERIA_OK, "ru");
    target(EXTERIA_TR_BING, 0, "zh", EXTERIA_OK, "zh-Hans");
    target(EXTERIA_TR_BING, 0, "zh-CN", EXTERIA_OK, "zh-Hans");
    target(EXTERIA_TR_BING, 0, "zh_TW", EXTERIA_OK, "zh-Hant");
    target(EXTERIA_TR_BING, 0, "zh-HK", EXTERIA_OK, "zh-Hant");
    target(EXTERIA_TR_BING, 0, "pt-PT", EXTERIA_OK, "pt-PT");
    target(EXTERIA_TR_BING, 0, "pt-BR", EXTERIA_OK, "pt");
    target(EXTERIA_TR_BING, 0, "no", EXTERIA_E_UNSUPPORTED, NULL);
    target(EXTERIA_TR_BING, 0, "sr", EXTERIA_E_UNSUPPORTED, NULL);
    target(EXTERIA_TR_TRANSMART, 0, "fil", EXTERIA_OK, "fil");
    target(EXTERIA_TR_TRANSMART, 0, "uk", EXTERIA_E_UNSUPPORTED, NULL);
    target(EXTERIA_TR_LLM, 0, "pt-BR", EXTERIA_OK, "pt");
    target(EXTERIA_TR_LLM, 0, "xx", EXTERIA_OK, "xx");
}

static void test_bad_codes(void) {
    char out[EXTERIA_TR_LANG_MAX];
    target(EXTERIA_TR_GOOGLE, 0, "", EXTERIA_E_ARG, NULL);
    target(EXTERIA_TR_GOOGLE, 0, "r", EXTERIA_E_ARG, NULL);
    target(EXTERIA_TR_GOOGLE, 0, "russian", EXTERIA_E_ARG, NULL);
    target(EXTERIA_TR_GOOGLE, 0, "ru;drop", EXTERIA_E_ARG, NULL);
    target(EXTERIA_TR_GOOGLE, 0, "ru-", EXTERIA_E_ARG, NULL);
    target(EXTERIA_TR_GOOGLE, 0, "ru-R", EXTERIA_E_ARG, NULL);
    target(EXTERIA_TR_GOOGLE, 0, "ru-RU-x", EXTERIA_E_ARG, NULL);
    target(EXTERIA_TR_GOOGLE, 0, "r1", EXTERIA_E_ARG, NULL);
    target(77, 0, "ru", EXTERIA_E_ARG, NULL);
    CHECK_EQ_INT(exteria_tr_target_for(EXTERIA_TR_GOOGLE, 0, NULL, out, sizeof(out)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tr_target_for(EXTERIA_TR_GOOGLE, 0, "ru", NULL, 8), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tr_target_for(EXTERIA_TR_GOOGLE, 0, "ru", out, 0), EXTERIA_E_ARG);
    /* a buffer that cannot hold the answer is refused, never cut */
    CHECK_EQ_INT(exteria_tr_target_for(EXTERIA_TR_DEEPL, 0, "pt-BR", out, 4), EXTERIA_E_ARG);
}

static void deepl(const char *code, exteria_status expected, const char *expected_code) {
    char out[EXTERIA_TR_LANG_MAX];
    CHECK_EQ_INT(exteria_tr_deepl_target(code, out, sizeof(out)), expected);
    if (expected == EXTERIA_OK) CHECK(!strcmp(out, expected_code));
}

static void test_deepl_target(void) {
    deepl("ru", EXTERIA_OK, "RU");
    deepl("en-GB", EXTERIA_OK, "EN-GB");
    deepl("pt_br", EXTERIA_OK, "PT-BR");
    deepl("zh-CN", EXTERIA_OK, "ZH-HANS");
    deepl("zh-hans", EXTERIA_OK, "ZH-HANS");
    deepl("zh-TW", EXTERIA_OK, "ZH-HANT");
    deepl("zh-HK", EXTERIA_OK, "ZH-HANT");
    deepl("zh", EXTERIA_OK, "ZH");
    deepl("", EXTERIA_E_ARG, NULL);
    deepl(NULL, EXTERIA_E_ARG, NULL);
    deepl("averyveryverylongcodethatdoesnotfit", EXTERIA_E_ARG, NULL);
}

int main(void) {
    test_google();
    test_other_services();
    test_bad_codes();
    test_deepl_target();
    return test_finish("test_translate_lang");
}
