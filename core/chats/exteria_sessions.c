#include "exteria_sessions.h"

#include <string.h>

#include "exteria_tl_ids.h"

exteria_status exteria_sessions_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.getAuthorizations");
    if (!request) return EXTERIA_E_NOMEM;
    *out = request;
    return EXTERIA_OK;
}

/* copies a text field whole characters at a time; empty when the field is missing */
static void copy_field(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static int read_session(const exteria_tl_value *item, exteria_session_info *out) {
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(item, EXTERIA_TL_ID_authorization) || exteria_tl_get_i64(item, "hash", &out->hash) != EXTERIA_OK) return 0;
    out->current = exteria_tl_has(item, "current") ? 1 : 0;
    out->official_app = exteria_tl_has(item, "official_app") ? 1 : 0;
    out->password_pending = exteria_tl_has(item, "password_pending") ? 1 : 0;
    out->secret_chats_off = exteria_tl_has(item, "encrypted_requests_disabled") ? 1 : 0;
    out->calls_off = exteria_tl_has(item, "call_requests_disabled") ? 1 : 0;
    out->unconfirmed = exteria_tl_has(item, "unconfirmed") ? 1 : 0;
    exteria_tl_get_i32(item, "api_id", &out->api_id);
    exteria_tl_get_i32(item, "date_created", &out->date_created);
    exteria_tl_get_i32(item, "date_active", &out->date_active);
    copy_field(out->device_model, sizeof(out->device_model), item, "device_model");
    copy_field(out->platform, sizeof(out->platform), item, "platform");
    copy_field(out->system_version, sizeof(out->system_version), item, "system_version");
    copy_field(out->app_name, sizeof(out->app_name), item, "app_name");
    copy_field(out->app_version, sizeof(out->app_version), item, "app_version");
    copy_field(out->ip, sizeof(out->ip), item, "ip");
    copy_field(out->country, sizeof(out->country), item, "country");
    copy_field(out->region, sizeof(out->region), item, "region");
    return 1;
}

exteria_status exteria_sessions_parse(const exteria_tl_value *answer, exteria_session_info *out, size_t cap, size_t *count, int32_t *ttl_days) {
    const exteria_tl_value *list;
    uint32_t i;
    size_t found = 0;
    if (!count) return EXTERIA_E_ARG;
    *count = 0;
    if (ttl_days) *ttl_days = 0;
    if (!out && cap) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_account_authorizations)) return EXTERIA_E_MALFORMED;
    list = exteria_tl_get(answer, "authorizations");
    if (!list || list->kind != EXTERIA_TL_V_VEC || list->u.vec.count > EXTERIA_SESSIONS_MAX * 4u) return EXTERIA_E_MALFORMED;
    if (ttl_days && exteria_tl_has(answer, "authorization_ttl_days") && exteria_tl_get_i32(answer, "authorization_ttl_days", ttl_days) != EXTERIA_OK) *ttl_days = 0;
    for (i = 0; i < list->u.vec.count && found < cap; ++i) {
        exteria_session_info row;
        size_t j;
        /* the session of this app has the hash zero on the server, and is the only one that may */
        if (!read_session(list->u.vec.items[i], &row) || (row.hash == 0 && !row.current)) continue;
        /* the current session leads whatever place the server gave it */
        if (row.current) {
            for (j = found; j > 0; --j) out[j] = out[j - 1];
            out[0] = row;
        } else {
            out[found] = row;
        }
        ++found;
    }
    *count = found;
    return EXTERIA_OK;
}

static int contains(const char *text, const char *needle) {
    return strstr(text, needle) != NULL;
}

/* the text lowercased into a buffer, so the comparisons below read plainly */
static void lower(const char *text, char *out, size_t cap) {
    size_t i;
    for (i = 0; text[i] && i + 1 < cap; ++i) out[i] = (char)((text[i] >= 'A' && text[i] <= 'Z') ? text[i] + 32 : text[i]);
    out[i] = 0;
}

exteria_session_kind exteria_session_kind_of(const exteria_session_info *session) {
    char platform[EXTERIA_SESSION_SHORT_MAX], model[EXTERIA_SESSION_TEXT_MAX], app[EXTERIA_SESSION_SHORT_MAX];
    lower(session->platform[0] ? session->platform : session->system_version, platform, sizeof(platform));
    lower(session->device_model, model, sizeof(model));
    lower(session->app_name, app, sizeof(app));
    if (contains(model, "safari")) return EXTERIA_SESSION_SAFARI;
    if (contains(model, "edge")) return EXTERIA_SESSION_EDGE;
    if (contains(model, "chrome")) return EXTERIA_SESSION_CHROME;
    if (contains(model, "opera")) return EXTERIA_SESSION_OPERA;
    if (contains(model, "firefox")) return EXTERIA_SESSION_FIREFOX;
    if (contains(model, "vivaldi")) return EXTERIA_SESSION_WEB;
    if (contains(platform, "ubuntu")) return EXTERIA_SESSION_UBUNTU;
    if (contains(platform, "linux")) return EXTERIA_SESSION_LINUX;
    if (contains(platform, "ios")) return contains(model, "ipad") ? EXTERIA_SESSION_IPAD : EXTERIA_SESSION_IPHONE;
    if (contains(platform, "windows")) return EXTERIA_SESSION_WINDOWS;
    if (contains(platform, "macos")) return EXTERIA_SESSION_MAC;
    if (contains(platform, "android")) return contains(model, "tab") ? EXTERIA_SESSION_ANDROID_TABLET : EXTERIA_SESSION_ANDROID;
    if (contains(app, "desktop")) return EXTERIA_SESSION_DESKTOP;
    return EXTERIA_SESSION_OTHER;
}

static void put(char *out, size_t cap, size_t *at, const char *text) {
    size_t len = strlen(text);
    if (*at + len >= cap) len = cap - 1 - *at;
    memcpy(out + *at, text, len);
    *at += len;
    out[*at] = 0;
}

void exteria_session_title(const exteria_session_info *session, char *out, size_t cap) {
    size_t at = 0;
    if (!out || !cap) return;
    out[0] = 0;
    if (session->device_model[0]) {
        put(out, cap, &at, session->device_model);
        return;
    }
    put(out, cap, &at, session->platform);
    if (session->platform[0] && session->system_version[0]) put(out, cap, &at, " ");
    put(out, cap, &at, session->system_version);
}

void exteria_session_app_line(const exteria_session_info *session, char *out, size_t cap) {
    size_t at = 0;
    if (!out || !cap) return;
    out[0] = 0;
    put(out, cap, &at, session->app_name);
    if (session->app_name[0] && session->app_version[0]) put(out, cap, &at, " ");
    put(out, cap, &at, session->app_version);
}

static exteria_status hash_request(exteria_arena *arena, const char *method, int64_t hash, int allow_zero, exteria_tl_value **request) {
    exteria_status status;
    *request = NULL;
    if (!arena || (hash == 0 && !allow_zero)) return EXTERIA_E_ARG;
    *request = exteria_tl_new_obj(arena, method);
    if (!*request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, *request, "hash", hash);
    if (status != EXTERIA_OK) *request = NULL;
    return status;
}

exteria_status exteria_session_end_request(exteria_arena *arena, int64_t hash, exteria_tl_value **out) {
    if (!out) return EXTERIA_E_ARG;
    return hash_request(arena, "account.resetAuthorization", hash, 0, out);
}

exteria_status exteria_sessions_end_others_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "auth.resetAuthorizations");
    if (!request) return EXTERIA_E_NOMEM;
    *out = request;
    return EXTERIA_OK;
}

static exteria_status set_bool(exteria_arena *arena, exteria_tl_value *request, const char *field, int value) {
    exteria_tl_value *flag = exteria_tl_new_obj(arena, value ? "boolTrue" : "boolFalse");
    if (!flag) return EXTERIA_E_NOMEM;
    return exteria_tl_set(request, field, flag);
}

exteria_status exteria_session_settings_request(exteria_arena *arena, int64_t hash, int secret_chats, int calls, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (secret_chats < -1 || secret_chats > 1 || calls < -1 || calls > 1 || (secret_chats < 0 && calls < 0)) return EXTERIA_E_ARG;
    /* the hash of the current session is zero, and this call is the one that is made on it */
    status = hash_request(arena, "account.changeAuthorizationSettings", hash, 1, &request);
    if (status != EXTERIA_OK) return status;
    /* the call names what is disabled, so "takes secret chats" is the opposite of the field */
    if (secret_chats >= 0) status = set_bool(arena, request, "encrypted_requests_disabled", !secret_chats);
    if (status == EXTERIA_OK && calls >= 0) status = set_bool(arena, request, "call_requests_disabled", !calls);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_sessions_ttl_request(exteria_arena *arena, int32_t days, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || days < 1 || days > 365) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.setAuthorizationTTL");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, request, "authorization_ttl_days", days);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static int base64url_value(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '-' || c == '+') return 62;
    if (c == '_' || c == '/') return 63;
    return -1;
}

exteria_status exteria_login_token_from_link(const char *link, uint8_t *token, size_t cap, size_t *len) {
    static const char prefix[] = "tg://login?token=";
    const char *text;
    uint32_t bits = 0;
    int have = 0;
    size_t n = 0, i;
    if (len) *len = 0;
    if (!link || !token || !len) return EXTERIA_E_ARG;
    if (strncmp(link, prefix, sizeof(prefix) - 1) != 0) return EXTERIA_E_MALFORMED;
    text = link + sizeof(prefix) - 1;
    for (i = 0; text[i] && text[i] != '&' && text[i] != '=' && text[i] != '#'; ++i) {
        int value = base64url_value(text[i]);
        if (value < 0) return EXTERIA_E_MALFORMED;
        bits = (bits << 6) | (uint32_t)value;
        have += 6;
        if (have >= 8) {
            have -= 8;
            if (n >= cap || n >= EXTERIA_LOGIN_TOKEN_MAX) return EXTERIA_E_LIMIT;
            token[n++] = (uint8_t)((bits >> have) & 0xFFu);
        }
    }
    /* a token is 32 bytes; anything shorter is not one a device shows */
    if (n < 16) return EXTERIA_E_MALFORMED;
    *len = n;
    return EXTERIA_OK;
}

exteria_status exteria_login_token_accept_request(exteria_arena *arena, const uint8_t *token, size_t len, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !token || len < 16 || len > EXTERIA_LOGIN_TOKEN_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "auth.acceptLoginToken");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_bytes(arena, request, "token", token, len);
    if (status == EXTERIA_OK) *out = request;
    return status;
}
