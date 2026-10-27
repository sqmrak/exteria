#include "exteria_auth.h"

#include <stdio.h>
#include <string.h>

#include "exteria_tl_ids.h"

#define AUTH_ARENA (256u * 1024u)
#define AUTH_TIMEOUT 60000u

static uint64_t now(const exteria_auth *a) {
    return a->clock->monotonic_ms(a->clock->ctx);
}

static void changed(exteria_auth *a, exteria_auth_state state, exteria_status status,
                    const exteria_tl_value *value, const char *error) {
    a->state = state;
    if (a->events.changed) a->events.changed(a->events.ctx, state, status, value, error);
}

static void clear_retry(exteria_auth *a) {
    if (a->retry.data) exteria_wipe(a->retry.data, a->retry.cap);
    exteria_writer_free(&a->retry);
    exteria_writer_init(&a->retry, AUTH_ARENA);
}

static exteria_status text_copy(char *out, size_t cap, const char *in) {
    size_t n;
    if (!in) return EXTERIA_E_ARG;
    n = strlen(in);
    if (n >= cap) return EXTERIA_E_LIMIT;
    memcpy(out, in, n + 1);
    return EXTERIA_OK;
}

static exteria_status send_request(exteria_auth *a, const exteria_tl_value *v, exteria_auth_state resume) {
    exteria_status status;
    uint64_t id;
    if (!a || !v || a->pending || a->state == EXTERIA_AUTH_AUTHORIZED) return EXTERIA_E_STATE;
    clear_retry(a);
    status = exteria_tl_encode(v, &a->retry, NULL);
    if (status != EXTERIA_OK) { clear_retry(a); return status; }
    id = ++a->generation;
    if (!id) id = ++a->generation;
    a->pending = id;
    a->operation = exteria_tl_id(v);
    a->resume_state = resume;
    a->wait_until = now(a) + AUTH_TIMEOUT;
    a->state = EXTERIA_AUTH_WAITING;
    status = a->events.submit(a->events.ctx, id, v);
    if (status != EXTERIA_OK && a->pending == id) {
        a->pending = 0;
        clear_retry(a);
        changed(a, resume, status, NULL, NULL);
    }
    return status;
}

exteria_status exteria_auth_init(exteria_auth *a, int32_t api_id, const char *api_hash,
                                const exteria_clock *clock, const exteria_auth_events *events) {
    if (!a) return EXTERIA_E_ARG;
    memset(a, 0, sizeof(*a));
    if (!events || !events->submit || api_id <= 0 || !api_hash || strlen(api_hash) != 32) return EXTERIA_E_ARG;
    a->events = *events;
    a->clock = clock ? clock : &exteria_system_clock;
    if (!a->clock->monotonic_ms || !a->clock->realtime_ms) return EXTERIA_E_ARG;
    a->api_id = api_id;
    memcpy(a->api_hash, api_hash, 33);
    exteria_writer_init(&a->retry, AUTH_ARENA);
    exteria_arena_init(&a->password_arena, AUTH_ARENA);
    return EXTERIA_OK;
}

void exteria_auth_cancel(exteria_auth *a) {
    uint64_t id;
    if (!a) return;
    id = a->pending;
    a->pending = 0;
    ++a->generation;
    a->state = EXTERIA_AUTH_IDLE;
    if (id && a->events.cancel) a->events.cancel(a->events.ctx, id);
    clear_retry(a);
    exteria_arena_free(&a->password_arena);
    a->password_info = NULL;
    exteria_wipe(a->phone, sizeof(a->phone));
    exteria_wipe(a->code_hash, sizeof(a->code_hash));
    a->qr = 0;
    a->qr_import = 0;
    a->qr_refresh = 0;
    a->migrations = 0;
    a->resend_at = 0;
    changed(a, EXTERIA_AUTH_IDLE, EXTERIA_OK, NULL, NULL);
}

void exteria_auth_free(exteria_auth *a) {
    if (!a) return;
    a->events.changed = NULL;
    exteria_auth_cancel(a);
    exteria_writer_free(&a->retry);
    exteria_wipe(a, sizeof(*a));
}

exteria_status exteria_auth_phone(exteria_auth *a, const char *phone, const exteria_tl_value *settings) {
    exteria_arena arena;
    exteria_tl_value *v, *default_settings;
    exteria_status status;
    size_t i, len;
    if (!a || !phone) return EXTERIA_E_ARG;
    len = strlen(phone);
    if (len < 5 || len > 32) return EXTERIA_E_ARG;
    for (i = phone[0] == '+' ? 1u : 0u; i < len; ++i) if (phone[i] < '0' || phone[i] > '9') return EXTERIA_E_ARG;
    exteria_auth_cancel(a);
    status = text_copy(a->phone, sizeof(a->phone), phone);
    if (status != EXTERIA_OK) return status;
    exteria_arena_init(&arena, AUTH_ARENA);
    v = exteria_tl_new_obj(&arena, "auth.sendCode");
    default_settings = settings ? NULL : exteria_tl_new_obj(&arena, "codeSettings");
    status = v ? exteria_tl_set_str(&arena, v, "phone_number", phone) : EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(&arena, v, "api_id", a->api_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(&arena, v, "api_hash", a->api_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set(v, "settings", (exteria_tl_value *)(settings ? settings : default_settings));
    if (status == EXTERIA_OK) status = send_request(a, v, EXTERIA_AUTH_IDLE);
    exteria_arena_free(&arena);
    return status;
}

static exteria_status phone_fields(exteria_auth *a, exteria_arena *arena, exteria_tl_value *v) {
    exteria_status status = v ? exteria_tl_set_str(arena, v, "phone_number", a->phone) : EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, v, "phone_code_hash", a->code_hash);
    return status;
}

exteria_status exteria_auth_code(exteria_auth *a, const char *code, const exteria_tl_value *email_verification) {
    exteria_arena arena;
    exteria_tl_value *v;
    exteria_status status;
    if (!a || a->state != EXTERIA_AUTH_CODE || (!code && !email_verification) ||
        (code && (!*code || strlen(code) > 128))) return EXTERIA_E_STATE;
    exteria_arena_init(&arena, AUTH_ARENA);
    v = exteria_tl_new_obj(&arena, "auth.signIn");
    status = phone_fields(a, &arena, v);
    if (status == EXTERIA_OK && code) status = exteria_tl_set_str(&arena, v, "phone_code", code);
    if (status == EXTERIA_OK && email_verification) status = exteria_tl_set(v, "email_verification", (exteria_tl_value *)email_verification);
    if (status == EXTERIA_OK) status = send_request(a, v, EXTERIA_AUTH_CODE);
    exteria_arena_free(&arena);
    return status;
}

exteria_status exteria_auth_resend(exteria_auth *a, const char *reason) {
    exteria_arena arena;
    exteria_tl_value *v;
    exteria_status status;
    if (!a || a->state != EXTERIA_AUTH_CODE || now(a) < a->resend_at || (reason && strlen(reason) > 128)) return EXTERIA_E_STATE;
    exteria_arena_init(&arena, AUTH_ARENA);
    v = exteria_tl_new_obj(&arena, "auth.resendCode");
    status = phone_fields(a, &arena, v);
    if (status == EXTERIA_OK && reason) status = exteria_tl_set_str(&arena, v, "reason", reason);
    if (status == EXTERIA_OK) status = send_request(a, v, EXTERIA_AUTH_CODE);
    exteria_arena_free(&arena);
    return status;
}

exteria_status exteria_auth_signup(exteria_auth *a, const char *first_name, const char *last_name) {
    exteria_arena arena;
    exteria_tl_value *v;
    exteria_status status;
    if (!a || a->state != EXTERIA_AUTH_SIGNUP || !first_name || !*first_name || !last_name ||
        strlen(first_name) > 256 || strlen(last_name) > 256) return EXTERIA_E_STATE;
    exteria_arena_init(&arena, AUTH_ARENA);
    v = exteria_tl_new_obj(&arena, "auth.signUp");
    status = phone_fields(a, &arena, v);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(&arena, v, "first_name", first_name);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(&arena, v, "last_name", last_name);
    if (status == EXTERIA_OK) status = send_request(a, v, EXTERIA_AUTH_SIGNUP);
    exteria_arena_free(&arena);
    return status;
}

static exteria_status simple(exteria_auth *a, const char *name, const char *code, exteria_auth_state resume) {
    exteria_arena arena;
    exteria_tl_value *v;
    exteria_status status;
    exteria_arena_init(&arena, AUTH_ARENA);
    v = exteria_tl_new_obj(&arena, name);
    status = v ? EXTERIA_OK : EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK && code) status = exteria_tl_set_str(&arena, v, "code", code);
    if (status == EXTERIA_OK) status = send_request(a, v, resume);
    exteria_arena_free(&arena);
    return status;
}

exteria_status exteria_auth_password(exteria_auth *a, const uint8_t *password, size_t len) {
    exteria_arena arena;
    exteria_tl_value *v, *proof_value;
    exteria_srp_proof proof;
    exteria_status status;
    if (!a || a->state != EXTERIA_AUTH_PASSWORD || !a->password_info) return EXTERIA_E_STATE;
    status = exteria_srp_check(a->password_info, password, len, &proof);
    if (status != EXTERIA_OK) return status;
    exteria_arena_init(&arena, AUTH_ARENA);
    v = exteria_tl_new_obj(&arena, "auth.checkPassword");
    proof_value = exteria_tl_new_obj(&arena, "inputCheckPasswordSRP");
    status = proof_value && v ? exteria_tl_set_i64(&arena, proof_value, "srp_id", proof.id) : EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(&arena, proof_value, "A", proof.A, sizeof(proof.A));
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(&arena, proof_value, "M1", proof.M1, sizeof(proof.M1));
    if (status == EXTERIA_OK) status = exteria_tl_set(v, "password", proof_value);
    if (status == EXTERIA_OK) status = send_request(a, v, EXTERIA_AUTH_PASSWORD);
    exteria_wipe(&proof, sizeof(proof));
    exteria_arena_free(&arena);
    return status;
}

exteria_status exteria_auth_recovery(exteria_auth *a) {
    if (!a || a->state != EXTERIA_AUTH_PASSWORD || !exteria_tl_has(a->password_info, "has_recovery")) return EXTERIA_E_STATE;
    return simple(a, "auth.requestPasswordRecovery", NULL, EXTERIA_AUTH_PASSWORD);
}

exteria_status exteria_auth_recover_code(exteria_auth *a, const char *code) {
    if (!a || a->state != EXTERIA_AUTH_RECOVERY || !code || !*code || strlen(code) > 128) return EXTERIA_E_STATE;
    return simple(a, "auth.recoverPassword", code, EXTERIA_AUTH_RECOVERY);
}

static exteria_status email_request(exteria_auth *a, const char *email, const exteria_tl_value *verification) {
    exteria_arena arena;
    exteria_tl_value *v, *purpose;
    exteria_status status;
    exteria_arena_init(&arena, AUTH_ARENA);
    v = exteria_tl_new_obj(&arena, email ? "account.sendVerifyEmailCode" : "account.verifyEmail");
    purpose = exteria_tl_new_obj(&arena, "emailVerifyPurposeLoginSetup");
    status = phone_fields(a, &arena, purpose);
    if (status == EXTERIA_OK && v) status = exteria_tl_set(v, "purpose", purpose);
    else if (!v) status = EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK && email) status = exteria_tl_set_str(&arena, v, "email", email);
    if (status == EXTERIA_OK && verification) status = exteria_tl_set(v, "verification", (exteria_tl_value *)verification);
    if (status == EXTERIA_OK) status = send_request(a, v, a->state);
    exteria_arena_free(&arena);
    return status;
}

exteria_status exteria_auth_email(exteria_auth *a, const char *email) {
    if (!a || a->state != EXTERIA_AUTH_EMAIL_SETUP || !email || !*email || strlen(email) > 320) return EXTERIA_E_STATE;
    return email_request(a, email, NULL);
}

exteria_status exteria_auth_email_code(exteria_auth *a, const exteria_tl_value *verification) {
    if (!a || a->state != EXTERIA_AUTH_EMAIL_CODE || !verification) return EXTERIA_E_STATE;
    return email_request(a, NULL, verification);
}

exteria_status exteria_auth_qr(exteria_auth *a, const int64_t *except_ids, uint32_t count) {
    exteria_arena arena;
    exteria_tl_value *v;
    exteria_status status;
    if (!a || count > 1024 || (count && !except_ids)) return EXTERIA_E_ARG;
    if (a->state != EXTERIA_AUTH_QR && a->state != EXTERIA_AUTH_IDLE) return EXTERIA_E_STATE;
    exteria_arena_init(&arena, AUTH_ARENA);
    v = exteria_tl_new_obj(&arena, "auth.exportLoginToken");
    status = v ? exteria_tl_set_i32(&arena, v, "api_id", a->api_id) : EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = exteria_tl_set_str(&arena, v, "api_hash", a->api_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64_vec(&arena, v, "except_ids", except_ids, count);
    a->qr = 1;
    a->qr_refresh = 0;
    if (status == EXTERIA_OK) status = send_request(a, v, EXTERIA_AUTH_QR);
    exteria_arena_free(&arena);
    return status;
}

exteria_status exteria_auth_qr_refresh(exteria_auth *a) {
    if (!a || !a->qr) return EXTERIA_E_STATE;
    if (a->pending) { a->qr_refresh = 1; return EXTERIA_OK; }
    if (a->state != EXTERIA_AUTH_QR) return EXTERIA_E_STATE;
    return exteria_auth_qr(a, NULL, 0);
}

static exteria_status sent_code(exteria_auth *a, const exteria_tl_value *v) {
    const uint8_t *hash;
    size_t len;
    int32_t timeout = 0;
    const exteria_tl_value *type;
    if (exteria_tl_get_bytes(v, "phone_code_hash", &hash, &len) != EXTERIA_OK || len == 0 ||
        len >= sizeof(a->code_hash) || memchr(hash, 0, len)) return EXTERIA_E_MALFORMED;
    memcpy(a->code_hash, hash, len); a->code_hash[len] = 0;
    if (exteria_tl_has(v, "timeout") && exteria_tl_get_i32(v, "timeout", &timeout) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (timeout < 0) return EXTERIA_E_MALFORMED;
    a->resend_at = exteria_tl_has(v, "next_type") ? now(a) + (uint64_t)timeout * 1000u : UINT64_MAX;
    type = exteria_tl_get(v, "type");
    changed(a, exteria_tl_is(type, EXTERIA_TL_ID_auth_sentCodeTypeSetUpEmailRequired) ?
            EXTERIA_AUTH_EMAIL_SETUP : EXTERIA_AUTH_CODE, EXTERIA_OK, v, NULL);
    return EXTERIA_OK;
}

exteria_status exteria_auth_resume(exteria_auth *a) {
    exteria_arena arena;
    exteria_tl_value *v;
    exteria_status status;
    uint64_t id;
    if (!a || (a->state != EXTERIA_AUTH_MIGRATE && a->state != EXTERIA_AUTH_FLOOD_WAIT) || a->pending)
        return EXTERIA_E_STATE;
    if (a->state == EXTERIA_AUTH_FLOOD_WAIT && now(a) < a->wait_until) return EXTERIA_E_RETRY;
    if (a->qr_import) {
        a->qr_import = 0;
        a->state = EXTERIA_AUTH_QR;
    }
    exteria_arena_init(&arena, AUTH_ARENA);
    status = exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, a->retry.data, a->retry.len, &v);
    if (status == EXTERIA_OK) {
        id = ++a->generation;
        a->pending = id;
        a->state = EXTERIA_AUTH_WAITING;
        a->wait_until = now(a) + AUTH_TIMEOUT;
        status = a->events.submit(a->events.ctx, id, v);
        if (status != EXTERIA_OK && a->pending == id) { a->pending = 0; changed(a, a->resume_state, status, NULL, NULL); }
    }
    exteria_arena_free(&arena);
    return status;
}

exteria_status exteria_auth_result(exteria_auth *a, uint64_t id, const exteria_mt_rpc_result *r) {
    exteria_status status = EXTERIA_OK;
    const exteria_tl_value *v;
    uint32_t operation;
    if (!a || !r) return EXTERIA_E_ARG;
    if (!id || id != a->pending) return EXTERIA_E_NOTFOUND;
    a->pending = 0;
    operation = a->operation;
    if (r->status != EXTERIA_OK) {
        char name[128];
        int32_t number;
        exteria_mt_rpc_error_split(r->error_text, name, sizeof(name), &number);
        if (r->status == EXTERIA_E_RPC && !strcmp(name, "SESSION_PASSWORD_NEEDED")) {
            clear_retry(a);
            a->state = EXTERIA_AUTH_PASSWORD;
            return simple(a, "account.getPassword", NULL, EXTERIA_AUTH_PASSWORD);
        }
        if (r->status == EXTERIA_E_RPC && !strcmp(name, "SRP_ID_INVALID")) {
            clear_retry(a);
            a->state = EXTERIA_AUTH_PASSWORD;
            return simple(a, "account.getPassword", NULL, EXTERIA_AUTH_PASSWORD);
        }
        if (r->status == EXTERIA_E_RPC && number > 0 &&
            (!strcmp(name, "PHONE_MIGRATE") || !strcmp(name, "NETWORK_MIGRATE") || !strcmp(name, "USER_MIGRATE"))) {
            if (++a->migrations > 3 || number > 1000) status = EXTERIA_E_LIMIT;
            else { a->migrate_dc = number; changed(a, EXTERIA_AUTH_MIGRATE, r->status, NULL, r->error_text); return EXTERIA_OK; }
        } else if (r->status == EXTERIA_E_RPC && number > 0 &&
                   (!strcmp(name, "FLOOD_WAIT") || !strcmp(name, "FLOOD_PREMIUM_WAIT"))) {
            a->wait_until = now(a) + (uint64_t)number * 1000u;
            changed(a, EXTERIA_AUTH_FLOOD_WAIT, r->status, NULL, r->error_text);
            return EXTERIA_OK;
        } else status = r->status;
        clear_retry(a);
        changed(a, a->resume_state, status, NULL, r->error_text);
        return status;
    }
    v = r->value;
    if (!v) status = EXTERIA_E_MALFORMED;
    else if (exteria_tl_is(v, EXTERIA_TL_ID_auth_sentCode)) {
        clear_retry(a);
        return sent_code(a, v);
    } else if (exteria_tl_is(v, EXTERIA_TL_ID_auth_sentCodeSuccess) || exteria_tl_is(v, EXTERIA_TL_ID_auth_loginTokenSuccess)) {
        v = exteria_tl_get(v, "authorization");
        if (!v) status = EXTERIA_E_MALFORMED;
    }
    if (status == EXTERIA_OK && exteria_tl_is(v, EXTERIA_TL_ID_auth_authorization)) {
        clear_retry(a);
        exteria_arena_free(&a->password_arena);
        a->password_info = NULL;
        changed(a, EXTERIA_AUTH_AUTHORIZED, EXTERIA_OK, v, NULL);
        return EXTERIA_OK;
    }
    if (status == EXTERIA_OK && exteria_tl_is(v, EXTERIA_TL_ID_auth_authorizationSignUpRequired)) {
        clear_retry(a);
        changed(a, EXTERIA_AUTH_SIGNUP, EXTERIA_OK, v, NULL);
        return EXTERIA_OK;
    }
    if (status == EXTERIA_OK && operation == EXTERIA_TL_ID_account_getPassword && exteria_tl_is(v, EXTERIA_TL_ID_account_password)) {
        exteria_writer w;
        exteria_writer_init(&w, AUTH_ARENA);
        exteria_arena_free(&a->password_arena);
        a->password_info = NULL;
        status = exteria_tl_encode(v, &w, NULL);
        if (status == EXTERIA_OK) status = exteria_tl_decode_all(&a->password_arena, NULL, EXTERIA_TL_REF_ANY,
                                                               w.data, w.len, &a->password_info);
        exteria_writer_free(&w);
        clear_retry(a);
        changed(a, EXTERIA_AUTH_PASSWORD, status, v, NULL);
        return status;
    }
    if (status == EXTERIA_OK && exteria_tl_is(v, EXTERIA_TL_ID_auth_passwordRecovery)) {
        clear_retry(a);
        changed(a, EXTERIA_AUTH_RECOVERY, EXTERIA_OK, v, NULL);
        return EXTERIA_OK;
    }
    if (status == EXTERIA_OK && exteria_tl_is(v, EXTERIA_TL_ID_account_sentEmailCode)) {
        clear_retry(a);
        changed(a, EXTERIA_AUTH_EMAIL_CODE, EXTERIA_OK, v, NULL);
        return EXTERIA_OK;
    }
    if (status == EXTERIA_OK && exteria_tl_is(v, EXTERIA_TL_ID_account_emailVerifiedLogin)) {
        clear_retry(a);
        return sent_code(a, exteria_tl_get(v, "sent_code"));
    }
    if (status == EXTERIA_OK && exteria_tl_is(v, EXTERIA_TL_ID_auth_loginToken)) {
        int32_t expires;
        if (exteria_tl_get_i32(v, "expires", &expires) != EXTERIA_OK || expires < 0) status = EXTERIA_E_MALFORMED;
        else {
            int64_t server_now = (int64_t)a->clock->realtime_ms(a->clock->ctx) + a->server_time_offset_ms;
            int64_t remaining = (int64_t)expires * 1000 - server_now;
            /* an already expired server token waits one second instead of spinning the worker and blinking the code */
            a->qr_expires = now(a) + (uint64_t)(remaining > 1000 ? remaining : 1000);
            clear_retry(a);
            changed(a, EXTERIA_AUTH_QR, EXTERIA_OK, v, NULL);
            if (a->qr_refresh) return exteria_auth_qr_refresh(a);
            return EXTERIA_OK;
        }
    }
    if (status == EXTERIA_OK && exteria_tl_is(v, EXTERIA_TL_ID_auth_loginTokenMigrateTo)) {
        exteria_arena arena;
        exteria_tl_value *request;
        const uint8_t *token;
        size_t len;
        if (exteria_tl_get_i32(v, "dc_id", &a->migrate_dc) != EXTERIA_OK || a->migrate_dc <= 0 ||
            exteria_tl_get_bytes(v, "token", &token, &len) != EXTERIA_OK || !len || len > 4096 || ++a->migrations > 3)
            status = EXTERIA_E_MALFORMED;
        else {
            exteria_arena_init(&arena, AUTH_ARENA);
            request = exteria_tl_new_obj(&arena, "auth.importLoginToken");
            status = request ? exteria_tl_set_bytes(&arena, request, "token", token, len) : EXTERIA_E_NOMEM;
            clear_retry(a);
            if (status == EXTERIA_OK) status = exteria_tl_encode(request, &a->retry, NULL);
            exteria_arena_free(&arena);
            if (status == EXTERIA_OK) {
                a->operation = EXTERIA_TL_ID_auth_importLoginToken;
                a->qr_import = 1;
                a->resume_state = EXTERIA_AUTH_QR;
                changed(a, EXTERIA_AUTH_MIGRATE, EXTERIA_OK, v, NULL);
                return EXTERIA_OK;
            }
        }
    }
    if (status == EXTERIA_OK) status = EXTERIA_E_UNSUPPORTED;
    clear_retry(a);
    changed(a, a->resume_state, status, v, NULL);
    return status;
}

exteria_status exteria_auth_tick(exteria_auth *a) {
    if (!a) return EXTERIA_E_ARG;
    if (a->pending && now(a) >= a->wait_until) {
        uint64_t id = a->pending;
        a->pending = 0;
        if (a->events.cancel) a->events.cancel(a->events.ctx, id);
        clear_retry(a);
        changed(a, a->resume_state, EXTERIA_E_TIMEOUT, NULL, NULL);
        return EXTERIA_E_TIMEOUT;
    }
    if (!a->pending && a->state == EXTERIA_AUTH_QR && now(a) >= a->qr_expires)
        return exteria_auth_qr_refresh(a);
    return EXTERIA_OK;
}

uint32_t exteria_auth_next_ms(const exteria_auth *a) {
    uint64_t next = UINT64_MAX;
    if (!a) return UINT32_MAX;
    if (a->pending) {
        uint64_t at = now(a);
        next = a->wait_until > at ? a->wait_until - at : 0;
    }
    if (!a->pending && a->state == EXTERIA_AUTH_QR) {
        uint64_t at = now(a), left = a->qr_expires > at ? a->qr_expires - at : 0;
        if (left < next) next = left;
    }
    return next > 0xfffffffeu ? UINT32_MAX : (uint32_t)next;
}

exteria_status exteria_auth_qr_url(const exteria_tl_value *v, char *out, size_t cap) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const uint8_t *token;
    size_t len, i, pos = 0;
    uint32_t bits = 0;
    unsigned count = 0;
    const char prefix[] = "tg://login?token=";
    if (!out || !cap) return EXTERIA_E_ARG;
    out[0] = 0;
    if (exteria_tl_get_bytes(v, "token", &token, &len) != EXTERIA_OK || !len || len > 4096) return EXTERIA_E_ARG;
    if (sizeof(prefix) + (len * 8 + 5) / 6 > cap) return EXTERIA_E_LIMIT;
    memcpy(out, prefix, sizeof(prefix) - 1); pos = sizeof(prefix) - 1;
    for (i = 0; i < len; ++i) {
        bits = (bits << 8) | token[i]; count += 8;
        while (count >= 6) { count -= 6; out[pos++] = alphabet[(bits >> count) & 63u]; }
    }
    if (count) out[pos++] = alphabet[(bits << (6 - count)) & 63u];
    out[pos] = 0;
    return EXTERIA_OK;
}
