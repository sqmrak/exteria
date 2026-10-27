#ifndef EXTERIA_LOGINS_H
#define EXTERIA_LOGINS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_tl.h"

/* a login the server does not trust yet: a session that signed in from a place the account has not been used from */

#define EXTERIA_LOGIN_DEVICE_MAX 96
#define EXTERIA_LOGIN_PLACE_MAX 96
#define EXTERIA_LOGINS_MAX 8

typedef struct exteria_unconfirmed_login {
    int64_t hash;                           /* names the session to confirm or end */
    int32_t date;                           /* when it signed in, unix seconds */
    char device[EXTERIA_LOGIN_DEVICE_MAX];  /* "iPhone4,1", or the app's name when the device is not given */
    char place[EXTERIA_LOGIN_PLACE_MAX];    /* "frankfurt am Main, Germany"; empty when the server gives no place */
} exteria_unconfirmed_login;

exteria_status exteria_logins_request(exteria_arena *arena, exteria_tl_value **out);
/* an account.authorizations answer: the unconfirmed sessions other than this one, newest first */
exteria_status exteria_logins_parse(const exteria_tl_value *answer, exteria_unconfirmed_login *out, size_t cap, size_t *count);

/* account.changeAuthorizationSettings with confirmed: the owner says the login was theirs */
exteria_status exteria_login_confirm_request(exteria_arena *arena, int64_t hash, exteria_tl_value **out);
/* account.resetAuthorization: the owner says it was not them, and the session ends */
exteria_status exteria_login_reset_request(exteria_arena *arena, int64_t hash, exteria_tl_value **out);

#endif
