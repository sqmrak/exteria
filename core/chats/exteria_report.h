#ifndef EXTERIA_REPORT_H
#define EXTERIA_REPORT_H

#include <stdint.h>

#include "exteria_messages.h"
#include "exteria_tl.h"

#define EXTERIA_REPORT_MESSAGE_MAX 512

typedef enum exteria_report_reason {
    EXTERIA_REPORT_SPAM,
    EXTERIA_REPORT_VIOLENCE,
    EXTERIA_REPORT_PORNOGRAPHY,
    EXTERIA_REPORT_CHILD_ABUSE,
    EXTERIA_REPORT_COPYRIGHT,
    EXTERIA_REPORT_ILLEGAL_DRUGS,
    EXTERIA_REPORT_PERSONAL_DETAILS,
    EXTERIA_REPORT_OTHER,
    EXTERIA_REPORT_REASON_COUNT
} exteria_report_reason;

/* account.reportPeer for a user, group or channel. message is the comment, at most EXTERIA_REPORT_MESSAGE_MAX
   bytes (EXTERIA_E_LIMIT beyond that); the server wants one for EXTERIA_REPORT_OTHER, so an empty one is
   EXTERIA_E_ARG there */
exteria_status exteria_report_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_report_reason reason, const char *message,
                                      exteria_tl_value **out);
/* the Bool it answers: EXTERIA_OK for true, EXTERIA_E_STATE for false (the server took nothing), EXTERIA_E_MALFORMED otherwise */
exteria_status exteria_report_parse(const exteria_tl_value *answer);

/* messages.report is a dialogue: the first request names no option and the server answers with a list to choose
   from, each choice is sent back as the bytes it came with */
#define EXTERIA_REPORT_OPTIONS_MAX 16
#define EXTERIA_REPORT_OPTION_TEXT_MAX 128
#define EXTERIA_REPORT_TOKEN_MAX 64
#define EXTERIA_REPORT_IDS_MAX 100

typedef enum exteria_report_step {
    EXTERIA_REPORT_STEP_DONE = 1,       /* the server took the report */
    EXTERIA_REPORT_STEP_CHOOSE,         /* pick one of the options */
    EXTERIA_REPORT_STEP_COMMENT         /* the server wants words, or takes none when comment_optional is set */
} exteria_report_step;

typedef struct exteria_report_option {
    char text[EXTERIA_REPORT_OPTION_TEXT_MAX];
    uint8_t token[EXTERIA_REPORT_TOKEN_MAX];
    size_t token_len;
} exteria_report_option;

typedef struct exteria_message_report_answer {
    exteria_report_step step;
    char title[EXTERIA_REPORT_OPTION_TEXT_MAX];
    exteria_report_option options[EXTERIA_REPORT_OPTIONS_MAX];
    size_t option_count;
    /* for STEP_COMMENT: the token the comment is sent with */
    uint8_t token[EXTERIA_REPORT_TOKEN_MAX];
    size_t token_len;
    uint8_t comment_optional;
} exteria_message_report_answer;

/* messages.report of ids in one chat. token is the option picked so far (NULL or empty for the first request) */
exteria_status exteria_message_report_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                              const uint8_t *token, size_t token_len, const char *comment, exteria_tl_value **out);
/* the reportResult it answers. out is always initialised; EXTERIA_E_MALFORMED for anything else or a list with no usable option */
exteria_status exteria_message_report_parse(const exteria_tl_value *answer, exteria_message_report_answer *out);

#endif
