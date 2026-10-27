#ifndef EXTERIA_AUTH_H
#define EXTERIA_AUTH_H

#include "exteria_mt_client.h"
#include "exteria_srp.h"

typedef enum exteria_auth_state {
    EXTERIA_AUTH_IDLE = 0,
    EXTERIA_AUTH_WAITING,
    EXTERIA_AUTH_CODE,
    EXTERIA_AUTH_EMAIL_SETUP,
    EXTERIA_AUTH_EMAIL_CODE,
    EXTERIA_AUTH_PASSWORD,
    EXTERIA_AUTH_SIGNUP,
    EXTERIA_AUTH_RECOVERY,
    EXTERIA_AUTH_QR,
    EXTERIA_AUTH_MIGRATE,
    EXTERIA_AUTH_FLOOD_WAIT,
    EXTERIA_AUTH_AUTHORIZED
} exteria_auth_state;

typedef struct exteria_auth_events {
    void *ctx;
    exteria_status (*submit)(void *ctx, uint64_t id, const exteria_tl_value *request);
    void (*cancel)(void *ctx, uint64_t id);
    void (*changed)(void *ctx, exteria_auth_state state, exteria_status status,
                    const exteria_tl_value *value, const char *error);
} exteria_auth_events;

typedef struct exteria_auth {
    exteria_auth_events events;
    const exteria_clock *clock;
    int32_t api_id;
    char api_hash[129];
    char phone[65];
    char code_hash[257];
    exteria_auth_state state;
    exteria_auth_state resume_state;
    uint64_t generation;
    uint64_t pending;
    uint64_t resend_at;
    uint64_t wait_until;
    int32_t migrate_dc;
    uint32_t migrations;
    uint32_t operation;
    int qr;
    int qr_import;
    int qr_refresh;
    int64_t server_time_offset_ms;
    /* monotonic deadline, so changing the wall clock cannot repeatedly replace a login code */
    uint64_t qr_expires;
    exteria_writer retry;
    exteria_arena password_arena;
    exteria_tl_value *password_info;
} exteria_auth;

exteria_status exteria_auth_init(exteria_auth *a, int32_t api_id, const char *api_hash,
                                const exteria_clock *clock, const exteria_auth_events *events);
void exteria_auth_cancel(exteria_auth *a);
void exteria_auth_free(exteria_auth *a);
exteria_status exteria_auth_phone(exteria_auth *a, const char *phone, const exteria_tl_value *settings);
exteria_status exteria_auth_code(exteria_auth *a, const char *code, const exteria_tl_value *email_verification);
exteria_status exteria_auth_resend(exteria_auth *a, const char *reason);
exteria_status exteria_auth_signup(exteria_auth *a, const char *first_name, const char *last_name);
exteria_status exteria_auth_password(exteria_auth *a, const uint8_t *password, size_t len);
exteria_status exteria_auth_recovery(exteria_auth *a);
exteria_status exteria_auth_recover_code(exteria_auth *a, const char *code);
exteria_status exteria_auth_email(exteria_auth *a, const char *email);
exteria_status exteria_auth_email_code(exteria_auth *a, const exteria_tl_value *verification);
exteria_status exteria_auth_qr(exteria_auth *a, const int64_t *except_ids, uint32_t count);
exteria_status exteria_auth_qr_refresh(exteria_auth *a);
exteria_status exteria_auth_resume(exteria_auth *a);
exteria_status exteria_auth_result(exteria_auth *a, uint64_t id, const exteria_mt_rpc_result *result);
exteria_status exteria_auth_tick(exteria_auth *a);
/* milliseconds until exteria_auth_tick has something to do (a request timeout or the end of a qr token), UINT32_MAX when it has nothing waiting */
uint32_t exteria_auth_next_ms(const exteria_auth *a);
exteria_status exteria_auth_qr_url(const exteria_tl_value *token, char *out, size_t cap);

#endif
