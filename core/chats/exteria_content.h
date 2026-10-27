#ifndef EXTERIA_CONTENT_H
#define EXTERIA_CONTENT_H

#include <stdint.h>

#include "exteria_tl.h"

/* the content settings of the account: whether media meant for adults is shown, and whether this account may change that at all (a person who is a
   minor or whose country forbids it may not) */
typedef struct exteria_content_settings {
    uint8_t sensitive_enabled;
    uint8_t sensitive_can_change;
} exteria_content_settings;

/* account.getContentSettings */
exteria_status exteria_content_settings_request(exteria_arena *arena, exteria_tl_value **out);
/* an account.contentSettings answer; anything else is EXTERIA_E_MALFORMED, and out is zero then */
exteria_status exteria_content_settings_parse(const exteria_tl_value *answer, exteria_content_settings *out);
/* account.setContentSettings: shows the sensitive media or hides it */
exteria_status exteria_content_set_request(exteria_arena *arena, int sensitive_enabled, exteria_tl_value **out);
/* the Bool it answers: EXTERIA_OK for true, EXTERIA_E_STATE for false, EXTERIA_E_MALFORMED otherwise */
exteria_status exteria_content_set_parse(const exteria_tl_value *answer);

#endif
