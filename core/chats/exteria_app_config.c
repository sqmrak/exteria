#include "exteria_app_config.h"

#include <math.h>
#include <string.h>

#include "exteria_tl_ids.h"

exteria_status exteria_app_config_i32(const exteria_tl_value *answer, const char *key, int32_t *out) {
    const exteria_tl_value *config, *entries;
    size_t key_len;
    if (out) *out = 0;
    if (!out || !key || !key[0] || !exteria_tl_is(answer, EXTERIA_TL_ID_help_appConfig)) return EXTERIA_E_MALFORMED;
    key_len = strlen(key);
    config = exteria_tl_get(answer, "config");
    if (!exteria_tl_is(config, EXTERIA_TL_ID_jsonObject) || exteria_tl_get_vec(config, "value", &entries) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (uint32_t i = 0; i < entries->u.vec.count; ++i) {
        const exteria_tl_value *entry = entries->u.vec.items[i], *value;
        const uint8_t *name;
        size_t len;
        double number;
        if (!exteria_tl_is(entry, EXTERIA_TL_ID_jsonObjectValue) || exteria_tl_get_bytes(entry, "key", &name, &len) != EXTERIA_OK ||
            !name || len != key_len || memcmp(name, key, len)) continue;
        value = exteria_tl_get(entry, "value");
        if (!exteria_tl_is(value, EXTERIA_TL_ID_jsonNumber) || exteria_tl_get_f64(value, "value", &number) != EXTERIA_OK ||
            !isfinite(number) || number < 0 || number > INT32_MAX || floor(number) != number) return EXTERIA_E_MALFORMED;
        *out = (int32_t)number;
        return EXTERIA_OK;
    }
    return EXTERIA_E_NOTFOUND;
}
