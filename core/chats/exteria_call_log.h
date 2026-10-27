#ifndef EXTERIA_CALL_LOG_H
#define EXTERIA_CALL_LOG_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_messages.h"
#include "exteria_people.h"
#include "exteria_status.h"
#include "exteria_tl.h"

/* the calls of the account, for the Calls tab: one row for each service message of a call, newest first, with the
   person on the other end */

#define EXTERIA_CALL_LOG_MAX 100

typedef struct exteria_call_log_row {
    int32_t message_id;
    int32_t date;
    int32_t duration;           /* seconds talked, zero for a call that did not connect */
    uint8_t outgoing;
    uint8_t video;
    uint8_t outcome;            /* exteria_call_outcome */
    int64_t user_id;            /* the other person */
    int64_t access_hash;
    uint8_t deleted;
    exteria_photo_ref photo;
    char name[EXTERIA_PERSON_NAME_MAX];
} exteria_call_log_row;

/* a messages.searchGlobal for phone call messages, no text, the newest limit of them (1 to EXTERIA_CALL_LOG_MAX) */
exteria_status exteria_call_log_request(exteria_arena *arena, int32_t limit, exteria_tl_value **out);
/* the answer to it: only messages of a call with a person are kept, a message that cannot be read or whose person
   the answer does not carry is skipped */
exteria_status exteria_call_log_parse(const exteria_tl_value *answer, exteria_call_log_row *rows, size_t cap, size_t *count);

#endif
