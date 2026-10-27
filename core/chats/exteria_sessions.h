#ifndef EXTERIA_SESSIONS_H
#define EXTERIA_SESSIONS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_tl.h"

/* the devices screen: every session the account has, the one it runs on among them */

#define EXTERIA_SESSION_TEXT_MAX 96
#define EXTERIA_SESSION_SHORT_MAX 48
#define EXTERIA_SESSIONS_MAX 100

typedef struct exteria_session_info {
    int64_t hash;                               /* names the session to every call below; zero for the current one, which cannot be ended */
    uint8_t current;                            /* the session this app runs on */
    uint8_t official_app;
    uint8_t password_pending;                   /* signed in, but the two step password has not been given yet */
    uint8_t secret_chats_off;                   /* encrypted_requests_disabled: this device does not take secret chats */
    uint8_t calls_off;                          /* call_requests_disabled */
    uint8_t unconfirmed;
    int32_t api_id;
    int32_t date_created;
    int32_t date_active;                        /* unix seconds; the session is online right now when current is set */
    char device_model[EXTERIA_SESSION_TEXT_MAX];
    char platform[EXTERIA_SESSION_SHORT_MAX];
    char system_version[EXTERIA_SESSION_SHORT_MAX];
    char app_name[EXTERIA_SESSION_SHORT_MAX];
    char app_version[EXTERIA_SESSION_SHORT_MAX];
    char ip[EXTERIA_SESSION_SHORT_MAX];
    char country[EXTERIA_SESSION_TEXT_MAX];
    char region[EXTERIA_SESSION_TEXT_MAX];
} exteria_session_info;

/* what drew an icon for a session: the kind picks the picture and the color of its circle SessionCell does */
typedef enum exteria_session_kind {
    EXTERIA_SESSION_OTHER = 0,
    EXTERIA_SESSION_IPHONE,
    EXTERIA_SESSION_IPAD,
    EXTERIA_SESSION_MAC,
    EXTERIA_SESSION_WINDOWS,
    EXTERIA_SESSION_LINUX,
    EXTERIA_SESSION_UBUNTU,
    EXTERIA_SESSION_ANDROID,
    EXTERIA_SESSION_ANDROID_TABLET,
    EXTERIA_SESSION_DESKTOP,
    EXTERIA_SESSION_CHROME,
    EXTERIA_SESSION_SAFARI,
    EXTERIA_SESSION_EDGE,
    EXTERIA_SESSION_FIREFOX,
    EXTERIA_SESSION_OPERA,
    EXTERIA_SESSION_WEB
} exteria_session_kind;

exteria_status exteria_sessions_request(exteria_arena *arena, exteria_tl_value **out);
/* an account.authorizations answer: the current session first, then the others as the server lists them */
exteria_status exteria_sessions_parse(const exteria_tl_value *answer, exteria_session_info *out, size_t cap, size_t *count, int32_t *ttl_days);

/* the kind of icon, from the platform, the device model and the app name, in the order SessionCell: browsers first
   (by the device model), then the operating systems, then the apps that say "desktop" */
exteria_session_kind exteria_session_kind_of(const exteria_session_info *session);

/* "iPhone4,1", or the platform and the system version when the device model is empty; always NUL terminated, empty
   only when all three are */
void exteria_session_title(const exteria_session_info *session, char *out, size_t cap);
/* "Telegram Android 13.1.0": the app and its version */
void exteria_session_app_line(const exteria_session_info *session, char *out, size_t cap);

/* account.resetAuthorization for one session other than this one; a hash of zero is EXTERIA_E_ARG */
exteria_status exteria_session_end_request(exteria_arena *arena, int64_t hash, exteria_tl_value **out);
/* auth.resetAuthorizations: every session but this one */
exteria_status exteria_sessions_end_others_request(exteria_arena *arena, exteria_tl_value **out);
/* account.changeAuthorizationSettings: whether the session takes secret chats and calls; each of the two is -1 to
   leave it as it is, 0 for no and 1 for yes; both -1 is EXTERIA_E_ARG */
exteria_status exteria_session_settings_request(exteria_arena *arena, int64_t hash, int secret_chats, int calls, exteria_tl_value **out);
/* account.setAuthorizationTTL; days is 1 to 365 */
exteria_status exteria_sessions_ttl_request(exteria_arena *arena, int32_t days, exteria_tl_value **out);
/* auth.acceptLoginToken: the person scanned the QR code of another device, whose login token is the url-safe base64 of the tg://login?token= link */
#define EXTERIA_LOGIN_TOKEN_MAX 64
exteria_status exteria_login_token_from_link(const char *link, uint8_t *token, size_t cap, size_t *len);
exteria_status exteria_login_token_accept_request(exteria_arena *arena, const uint8_t *token, size_t len, exteria_tl_value **out);

#endif
