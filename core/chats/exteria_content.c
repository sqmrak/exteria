#include "exteria_content.h"

#include <string.h>

#include "exteria_tl_ids.h"

exteria_status exteria_content_settings_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.getContentSettings");
    if (!request) return EXTERIA_E_NOMEM;
    *out = request;
    return EXTERIA_OK;
}

exteria_status exteria_content_settings_parse(const exteria_tl_value *answer, exteria_content_settings *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_account_contentSettings)) return EXTERIA_E_MALFORMED;
    out->sensitive_enabled = exteria_tl_has(answer, "sensitive_enabled") ? 1 : 0;
    out->sensitive_can_change = exteria_tl_has(answer, "sensitive_can_change") ? 1 : 0;
    return EXTERIA_OK;
}

exteria_status exteria_content_set_request(exteria_arena *arena, int sensitive_enabled, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status = EXTERIA_OK;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.setContentSettings");
    if (!request) return EXTERIA_E_NOMEM;
    if (sensitive_enabled) status = exteria_tl_set_flag(request, "sensitive_enabled");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_content_set_parse(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolTrue)) return EXTERIA_OK;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolFalse)) return EXTERIA_E_STATE;
    return EXTERIA_E_MALFORMED;
}
