#include "exteria_logins.h"

#include <string.h>

#include "exteria_tl_ids.h"

exteria_status exteria_logins_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.getAuthorizations");
    if (!request) return EXTERIA_E_NOMEM;
    *out = request;
    return EXTERIA_OK;
}

/* copies a text field into dst whole characters at a time; empty when the field is missing */
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

/* "region, country", leaving out what is empty and the region when it only repeats the country */
static void make_place(char *dst, size_t cap, const char *region, const char *country) {
    size_t at = 0, i;
    const char *parts[2] = {region, country};
    dst[0] = 0;
    for (i = 0; i < 2; ++i) {
        size_t len = strlen(parts[i]);
        if (!len || (i == 0 && !strcmp(region, country))) continue;
        if (at) {
            if (at + 2 >= cap) break;
            dst[at++] = ',';
            dst[at++] = ' ';
        }
        if (at + len >= cap) len = cap - 1 - at;
        while (len > 0 && (((unsigned char)parts[i][len]) & 0xC0u) == 0x80u) --len;
        memcpy(dst + at, parts[i], len);
        at += len;
        dst[at] = 0;
    }
}

exteria_status exteria_logins_parse(const exteria_tl_value *answer, exteria_unconfirmed_login *out, size_t cap, size_t *count) {
    const exteria_tl_value *list;
    uint32_t i;
    size_t found = 0, j;
    if (!count) return EXTERIA_E_ARG;
    *count = 0;
    if (!out && cap) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_account_authorizations)) return EXTERIA_E_MALFORMED;
    list = exteria_tl_get(answer, "authorizations");
    if (!list || list->kind != EXTERIA_TL_V_VEC) return EXTERIA_E_MALFORMED;
    for (i = 0; i < list->u.vec.count; ++i) {
        const exteria_tl_value *item = list->u.vec.items[i];
        exteria_unconfirmed_login login;
        char region[EXTERIA_LOGIN_PLACE_MAX], country[EXTERIA_LOGIN_PLACE_MAX];
        size_t at;
        if (!exteria_tl_is(item, EXTERIA_TL_ID_authorization) || !exteria_tl_has(item, "unconfirmed") || exteria_tl_has(item, "current")) continue;
        memset(&login, 0, sizeof(login));
        if (exteria_tl_get_i64(item, "hash", &login.hash) != EXTERIA_OK || login.hash == 0) continue;
        exteria_tl_get_i32(item, "date_created", &login.date);
        copy_field(login.device, sizeof(login.device), item, "device_model");
        if (!login.device[0]) copy_field(login.device, sizeof(login.device), item, "app_name");
        copy_field(region, sizeof(region), item, "region");
        copy_field(country, sizeof(country), item, "country");
        make_place(login.place, sizeof(login.place), region, country);
        /* newest first: the place in the list where this one belongs */
        at = found;
        while (at > 0 && out[at - 1].date < login.date) --at;
        if (found == cap && at == cap) continue;
        if (found < cap) ++found;
        for (j = found - 1; j > at; --j) out[j] = out[j - 1];
        out[at] = login;
    }
    *count = found;
    return EXTERIA_OK;
}

static exteria_status hash_request(exteria_arena *arena, int64_t hash, const char *method, int confirm, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || hash == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, method);
    if (!request) return EXTERIA_E_NOMEM;
    status = confirm ? exteria_tl_set_flag(request, "confirmed") : EXTERIA_OK;
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", hash);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_login_confirm_request(exteria_arena *arena, int64_t hash, exteria_tl_value **out) {
    return hash_request(arena, hash, "account.changeAuthorizationSettings", 1, out);
}

exteria_status exteria_login_reset_request(exteria_arena *arena, int64_t hash, exteria_tl_value **out) {
    return hash_request(arena, hash, "account.resetAuthorization", 0, out);
}
