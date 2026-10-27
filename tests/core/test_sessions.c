#include "test_util.h"
#include "exteria_sessions.h"
#include "exteria_tl_ids.h"

#include <string.h>

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void str(exteria_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, field, x), EXTERIA_OK);
}
static void roundtrip(exteria_tl_value *request, uint32_t constructor) {
    exteria_writer writer;
    exteria_tl_value *decoded = NULL;
    exteria_writer_init(&writer, 65536);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, writer.data, writer.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), constructor);
    exteria_writer_free(&writer);
}

static exteria_tl_value *auth(int64_t hash, int current, const char *model, const char *platform, const char *system, const char *app, const char *version) {
    exteria_tl_value *v = obj("authorization");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "hash", hash), EXTERIA_OK);
    if (current) CHECK_EQ_INT(exteria_tl_set_flag(v, "current"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "api_id", 4), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "date_created", 100 + (int32_t)hash), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "date_active", 200 + (int32_t)hash), EXTERIA_OK);
    str(v, "device_model", model);
    str(v, "platform", platform);
    str(v, "system_version", system);
    str(v, "app_name", app);
    str(v, "app_version", version);
    str(v, "ip", "1.2.3.4");
    str(v, "country", "Germany");
    str(v, "region", "");
    return v;
}

static exteria_tl_value *answer(exteria_tl_value **items, uint32_t n, int32_t ttl) {
    exteria_tl_value *a = obj("account.authorizations"), *vec = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(vec, i, items[i]), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, a, "authorization_ttl_days", ttl), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(a, "authorizations", vec), EXTERIA_OK);
    return a;
}

static void test_parse(void) {
    exteria_session_info rows[4];
    exteria_tl_value *items[5];
    size_t count = 99;
    int32_t ttl = -1;
    items[0] = auth(1, 0, "Galaxy", "Android", "14", "Telegram Android", "13.1.0");
    items[1] = auth(2, 1, "iPhone4,1", "iOS", "6.1.6", "exteria", "0.1.0");
    items[2] = auth(0, 0, "no hash", "", "", "", "");
    items[3] = auth(4, 0, "Firefox 154", "Web", "", "Telegram Web", "2.2 K");
    items[4] = obj("boolTrue");
    CHECK_EQ_INT(exteria_sessions_parse(answer(items, 4, 180), rows, 4, &count, &ttl), EXTERIA_OK);
    /* this session leads, a session without a hash is left out, the server's order holds for the rest */
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(ttl, 180);
    CHECK_EQ_INT(rows[0].hash, 2);
    CHECK_EQ_INT(rows[0].current, 1);
    CHECK_EQ_INT(rows[1].hash, 1);
    CHECK_EQ_INT(rows[2].hash, 4);
    CHECK(!strcmp(rows[0].device_model, "iPhone4,1"));
    CHECK(!strcmp(rows[1].app_version, "13.1.0"));
    CHECK_EQ_INT(rows[0].secret_chats_off, 0);
    /* cap cuts the list short and keeps the current one in front */
    CHECK_EQ_INT(exteria_sessions_parse(answer(items, 4, 7), rows, 2, &count, NULL), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(exteria_sessions_parse(answer(items, 4, 7), NULL, 0, &count, NULL), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    /* the current session of the server has the hash zero and must still be listed, first */
    {
        exteria_tl_value *zero[2];
        zero[0] = auth(7, 0, "Pixel", "Android", "14", "Telegram Android", "12.5.1");
        zero[1] = auth(0, 1, "iPhone4,1", "iOS", "6.1.6", "exteria", "0.1.0");
        CHECK_EQ_INT(exteria_sessions_parse(answer(zero, 2, 7), rows, 4, &count, NULL), EXTERIA_OK);
        CHECK_EQ_INT(count, 2);
        CHECK_EQ_INT(rows[0].current, 1);
        CHECK_EQ_INT(rows[0].hash, 0);
        CHECK_EQ_INT(rows[1].hash, 7);
    }
    CHECK_EQ_INT(exteria_sessions_parse(items[4], rows, 4, &count, &ttl), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(ttl, 0);
    CHECK_EQ_INT(exteria_sessions_parse(answer(items, 1, 7), NULL, 4, &count, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sessions_parse(answer(items, 1, 7), rows, 4, NULL, NULL), EXTERIA_E_ARG);
    /* a flag on the session reads as the switch off */
    CHECK_EQ_INT(exteria_tl_set_flag(items[0], "encrypted_requests_disabled"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_flag(items[0], "call_requests_disabled"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_sessions_parse(answer(items, 1, 7), rows, 4, &count, NULL), EXTERIA_OK);
    CHECK_EQ_INT(rows[0].secret_chats_off, 1);
    CHECK_EQ_INT(rows[0].calls_off, 1);
}

static exteria_session_kind kind(const char *model, const char *platform, const char *system, const char *app) {
    exteria_session_info s;
    memset(&s, 0, sizeof(s));
    strcpy(s.device_model, model);
    strcpy(s.platform, platform);
    strcpy(s.system_version, system);
    strcpy(s.app_name, app);
    return exteria_session_kind_of(&s);
}

static void test_kind_and_titles(void) {
    exteria_session_info s;
    char text[64];
    CHECK_EQ_INT(kind("iPhone 4S", "iOS", "", "exteria"), EXTERIA_SESSION_IPHONE);
    CHECK_EQ_INT(kind("iPad Air", "iOS", "", "Telegram"), EXTERIA_SESSION_IPAD);
    CHECK_EQ_INT(kind("MacBook Air M2", "macOS", "", "Telegram macOS"), EXTERIA_SESSION_MAC);
    CHECK_EQ_INT(kind("PC 64bit", "Windows", "", "Telegram Desktop"), EXTERIA_SESSION_WINDOWS);
    CHECK_EQ_INT(kind("Galaxy S25", "Android", "", "Telegram Android"), EXTERIA_SESSION_ANDROID);
    CHECK_EQ_INT(kind("Galaxy Tab S9", "Android", "", "Telegram Android"), EXTERIA_SESSION_ANDROID_TABLET);
    CHECK_EQ_INT(kind("Firefox 154", "Web", "", "Telegram Web"), EXTERIA_SESSION_FIREFOX);
    CHECK_EQ_INT(kind("Chrome 120", "Windows", "", "Telegram Web"), EXTERIA_SESSION_CHROME);
    CHECK_EQ_INT(kind("Safari 17", "macOS", "", "Telegram Web"), EXTERIA_SESSION_SAFARI);
    CHECK_EQ_INT(kind("Vivaldi", "Web", "", "Telegram Web"), EXTERIA_SESSION_WEB);
    CHECK_EQ_INT(kind("PC", "Ubuntu 22.04", "", "Telegram Desktop"), EXTERIA_SESSION_UBUNTU);
    CHECK_EQ_INT(kind("PC", "Linux", "", "Telegram Desktop"), EXTERIA_SESSION_LINUX);
    CHECK_EQ_INT(kind("Box", "", "", "Some Desktop"), EXTERIA_SESSION_DESKTOP);
    CHECK_EQ_INT(kind("", "", "", ""), EXTERIA_SESSION_OTHER);
    /* the platform names the system when it is empty */
    CHECK_EQ_INT(kind("x", "", "iOS 6", "y"), EXTERIA_SESSION_IPHONE);

    memset(&s, 0, sizeof(s));
    strcpy(s.platform, "Android");
    strcpy(s.system_version, "14");
    exteria_session_title(&s, text, sizeof(text));
    CHECK(!strcmp(text, "Android 14"));
    strcpy(s.device_model, "Pixel 9");
    exteria_session_title(&s, text, sizeof(text));
    CHECK(!strcmp(text, "Pixel 9"));
    exteria_session_title(&s, text, 4);
    CHECK(!strcmp(text, "Pix"));
    strcpy(s.app_name, "Telegram Android");
    strcpy(s.app_version, "12.5.1");
    exteria_session_app_line(&s, text, sizeof(text));
    CHECK(!strcmp(text, "Telegram Android 12.5.1"));
    s.app_version[0] = 0;
    exteria_session_app_line(&s, text, sizeof(text));
    CHECK(!strcmp(text, "Telegram Android"));
}

static void test_requests(void) {
    exteria_tl_value *request = NULL;
    const exteria_tl_value *flag;
    CHECK_EQ_INT(exteria_sessions_request(&arena, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_getAuthorizations);
    CHECK_EQ_INT(exteria_session_end_request(&arena, 77, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_resetAuthorization);
    CHECK_EQ_INT(exteria_session_end_request(&arena, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_sessions_end_others_request(&arena, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_auth_resetAuthorizations);

    /* a switch turned off sends the field as true, since the field says what is disabled */
    CHECK_EQ_INT(exteria_session_settings_request(&arena, 9, 0, -1, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_changeAuthorizationSettings);
    flag = exteria_tl_get(request, "encrypted_requests_disabled");
    CHECK(exteria_tl_is(flag, EXTERIA_TL_ID_boolTrue));
    CHECK_EQ_INT(exteria_tl_has(request, "call_requests_disabled"), 0);
    CHECK_EQ_INT(exteria_session_settings_request(&arena, 9, -1, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "encrypted_requests_disabled"), 0);
    CHECK(exteria_tl_is(exteria_tl_get(request, "call_requests_disabled"), EXTERIA_TL_ID_boolFalse));
    CHECK_EQ_INT(exteria_session_settings_request(&arena, 9, -1, -1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_session_settings_request(&arena, 0, 1, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_session_settings_request(&arena, 9, 2, 1, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_sessions_ttl_request(&arena, 180, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_setAuthorizationTTL);
    CHECK_EQ_INT(exteria_sessions_ttl_request(&arena, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sessions_ttl_request(&arena, 366, &request), EXTERIA_E_ARG);
}

static void test_login_token(void) {
    uint8_t token[EXTERIA_LOGIN_TOKEN_MAX];
    size_t len = 99;
    exteria_tl_value *request = NULL;
    /* 24 bytes 0x00..0x17 in url-safe base64 */
    CHECK_EQ_INT(exteria_login_token_from_link("tg://login?token=AAECAwQFBgcICQoLDA0ODxAREhMUFRYX", token, sizeof(token), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 24);
    CHECK_EQ_INT(token[0], 0);
    CHECK_EQ_INT(token[23], 0x17);
    /* the url-safe letters stand for 62 and 63: "--__" is the bytes 0xFB 0xEF 0xFF */
    CHECK_EQ_INT(exteria_login_token_from_link("tg://login?token=--__AAECAwQFBgcICQoLDA0ODxAREg", token, sizeof(token), &len), EXTERIA_OK);
    CHECK_EQ_INT(token[0], 0xFB);
    CHECK_EQ_INT(token[1], 0xEF);
    CHECK_EQ_INT(token[2], 0xFF);
    CHECK_EQ_INT(exteria_login_token_from_link("https://t.me/x", token, sizeof(token), &len), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_login_token_from_link("tg://login?token=AAEC", token, sizeof(token), &len), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_login_token_from_link("tg://login?token=AA!ECAwQFBgcICQoLDA0ODxAREhMUFRYX", token, sizeof(token), &len), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_login_token_from_link("tg://login?token=AAECAwQFBgcICQoLDA0ODxAREhMUFRYX", token, 8, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_login_token_from_link(NULL, token, sizeof(token), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_login_token_accept_request(&arena, token, 24, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_auth_acceptLoginToken);
    CHECK_EQ_INT(exteria_login_token_accept_request(&arena, token, 8, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_parse();
    test_kind_and_titles();
    test_requests();
    test_login_token();
    exteria_arena_free(&arena);
    return test_finish("test_sessions");
}
