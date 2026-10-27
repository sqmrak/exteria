#include "exteria_report.h"

#include <string.h>

#include "exteria_tl_ids.h"

static const char *const reason_names[EXTERIA_REPORT_REASON_COUNT] = {
    "inputReportReasonSpam",
    "inputReportReasonViolence",
    "inputReportReasonPornography",
    "inputReportReasonChildAbuse",
    "inputReportReasonCopyright",
    "inputReportReasonIllegalDrugs",
    "inputReportReasonPersonalDetails",
    "inputReportReasonOther",
};

exteria_status exteria_report_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_report_reason reason, const char *message,
                                      exteria_tl_value **out) {
    exteria_tl_value *request, *input, *why;
    exteria_status status;
    size_t len;
    if (out) *out = NULL;
    if (!arena || !out || (unsigned)reason >= EXTERIA_REPORT_REASON_COUNT) return EXTERIA_E_ARG;
    if (!message) message = "";
    len = strlen(message);
    if (len > EXTERIA_REPORT_MESSAGE_MAX) return EXTERIA_E_LIMIT;
    if (reason == EXTERIA_REPORT_OTHER && !len) return EXTERIA_E_ARG;
    /* the saved messages are the account itself, which nobody reports */
    if (peer && peer->self) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "account.reportPeer");
    why = exteria_tl_new_obj(arena, reason_names[reason]);
    if (!request || !why) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "reason", why);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", message);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_report_parse(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolTrue)) return EXTERIA_OK;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolFalse)) return EXTERIA_E_STATE;
    return EXTERIA_E_MALFORMED;
}

exteria_status exteria_message_report_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                              const uint8_t *token, size_t token_len, const char *comment, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !peer || !out || !ids || count == 0 || count > EXTERIA_REPORT_IDS_MAX || peer->self) return EXTERIA_E_ARG;
    if (!token && token_len) return EXTERIA_E_ARG;
    if (token_len > EXTERIA_REPORT_TOKEN_MAX) return EXTERIA_E_LIMIT;
    if (!comment) comment = "";
    if (strlen(comment) > EXTERIA_REPORT_MESSAGE_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < count; ++i) if (ids[i] <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.report");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32_vec(arena, request, "id", ids, (uint32_t)count);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, request, "option", token ? token : (const uint8_t *)"", token_len);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", comment);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* text is cut at a character boundary when it does not fit */
static void copy_text(char *dst, size_t cap, const uint8_t *data, size_t len) {
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static exteria_status read_token(const exteria_tl_value *obj, uint8_t *token, size_t *token_len) {
    const uint8_t *data;
    size_t len;
    if (exteria_tl_get_bytes(obj, "option", &data, &len) != EXTERIA_OK || len > EXTERIA_REPORT_TOKEN_MAX) return EXTERIA_E_MALFORMED;
    if (len) memcpy(token, data, len);
    *token_len = len;
    return EXTERIA_OK;
}

exteria_status exteria_message_report_parse(const exteria_tl_value *answer, exteria_message_report_answer *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(answer, EXTERIA_TL_ID_reportResultReported)) {
        out->step = EXTERIA_REPORT_STEP_DONE;
        return EXTERIA_OK;
    }
    if (exteria_tl_is(answer, EXTERIA_TL_ID_reportResultAddComment)) {
        if (read_token(answer, out->token, &out->token_len) != EXTERIA_OK) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        out->step = EXTERIA_REPORT_STEP_COMMENT;
        out->comment_optional = exteria_tl_has(answer, "optional") ? 1 : 0;
        return EXTERIA_OK;
    }
    if (exteria_tl_is(answer, EXTERIA_TL_ID_reportResultChooseOption)) {
        const exteria_tl_value *list;
        const uint8_t *data;
        size_t len, i;
        uint32_t n;
        if (exteria_tl_get_vec(answer, "options", &list) != EXTERIA_OK || exteria_tl_get_bytes(answer, "title", &data, &len) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        copy_text(out->title, sizeof(out->title), data, len);
        n = list->u.vec.count;
        for (i = 0; i < n && out->option_count < EXTERIA_REPORT_OPTIONS_MAX; ++i) {
            const exteria_tl_value *item = list->u.vec.items[i];
            exteria_report_option *option = &out->options[out->option_count];
            if (!item || exteria_tl_get_bytes(item, "text", &data, &len) != EXTERIA_OK || !len) continue;
            if (read_token(item, option->token, &option->token_len) != EXTERIA_OK) continue;
            copy_text(option->text, sizeof(option->text), data, len);
            ++out->option_count;
        }
        if (!out->option_count) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        out->step = EXTERIA_REPORT_STEP_CHOOSE;
        return EXTERIA_OK;
    }
    return EXTERIA_E_MALFORMED;
}
