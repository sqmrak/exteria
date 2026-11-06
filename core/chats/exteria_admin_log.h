#ifndef EXTERIA_ADMIN_LOG_H
#define EXTERIA_ADMIN_LOG_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_channel.h"
#include "exteria_status.h"
#include "exteria_tl.h"

/* the recent actions of a group or channel: what its admins did in the last 48 hours, newest first */

#define EXTERIA_ADMIN_LOG_PAGE 50
#define EXTERIA_ADMIN_LOG_TEXT_MAX 512
#define EXTERIA_ADMIN_LOG_NAME_MAX EXTERIA_PERSON_NAME_MAX
#define EXTERIA_ADMIN_LOG_QUERY_MAX 128

typedef enum exteria_admin_event_kind {
    EXTERIA_LOG_OTHER = 0,          /* an action this app has no sentence for; the row says only who did something */
    EXTERIA_LOG_JOIN,
    EXTERIA_LOG_JOIN_BY_INVITE,
    EXTERIA_LOG_JOIN_BY_REQUEST,    /* target is the admin who approved it */
    EXTERIA_LOG_LEAVE,
    EXTERIA_LOG_INVITE,             /* target was added by actor */
    EXTERIA_LOG_BAN,                /* target cannot read the chat any more */
    EXTERIA_LOG_RESTRICT,           /* target stays but lost some rights */
    EXTERIA_LOG_UNBAN,
    EXTERIA_LOG_PROMOTE,
    EXTERIA_LOG_ADMIN_RIGHTS,       /* an admin whose rights changed */
    EXTERIA_LOG_DEMOTE,
    EXTERIA_LOG_EDIT_RANK,          /* old_text and new_text are the tag */
    EXTERIA_LOG_TITLE,
    EXTERIA_LOG_ABOUT,
    EXTERIA_LOG_USERNAME,
    EXTERIA_LOG_PHOTO,
    EXTERIA_LOG_INVITES,            /* flag: members may add people */
    EXTERIA_LOG_SIGNATURES,         /* flag */
    EXTERIA_LOG_SIGNATURE_PROFILES, /* flag */
    EXTERIA_LOG_HISTORY_HIDDEN,     /* flag: new members do not see the old messages */
    EXTERIA_LOG_NO_FORWARDS,        /* flag */
    EXTERIA_LOG_FORUM,              /* flag */
    EXTERIA_LOG_ANTI_SPAM,          /* flag */
    EXTERIA_LOG_SLOW_MODE,          /* new_number seconds, zero for off */
    EXTERIA_LOG_HISTORY_TTL,        /* new_number seconds, zero for off */
    EXTERIA_LOG_LINKED_CHAT,
    EXTERIA_LOG_DEFAULT_RIGHTS,
    EXTERIA_LOG_PIN,
    EXTERIA_LOG_UNPIN,
    EXTERIA_LOG_EDIT_MESSAGE,       /* old_text before, new_text after */
    EXTERIA_LOG_DELETE_MESSAGE,
    EXTERIA_LOG_SEND_MESSAGE,
    EXTERIA_LOG_STOP_POLL,
    EXTERIA_LOG_CALL_START,
    EXTERIA_LOG_CALL_END,
    EXTERIA_LOG_TOPIC_CREATE,       /* new_text is the title */
    EXTERIA_LOG_TOPIC_EDIT,
    EXTERIA_LOG_TOPIC_DELETE,
    EXTERIA_LOG_INVITE_REVOKE,
    EXTERIA_LOG_INVITE_DELETE
} exteria_admin_event_kind;

typedef struct exteria_admin_event {
    int64_t id;                     /* the next page asks for ids below the last one */
    int32_t date;                   /* unix seconds */
    uint8_t kind;                   /* exteria_admin_event_kind */
    uint8_t flag;                   /* the new value of a switch */
    uint8_t has_media;              /* the message of the event carries media; its text may be empty */
    uint8_t has_target;
    int32_t message_id;             /* of the message the event is about, zero when none */
    int32_t new_number;
    int64_t actor_id;
    int64_t target_id;
    char actor_name[EXTERIA_ADMIN_LOG_NAME_MAX];
    char actor_username[EXTERIA_PERSON_USERNAME_MAX];
    char target_name[EXTERIA_ADMIN_LOG_NAME_MAX];
    char old_text[EXTERIA_ADMIN_LOG_TEXT_MAX];
    char new_text[EXTERIA_ADMIN_LOG_TEXT_MAX];
} exteria_admin_event;

/* channels.getAdminLog: one page of EXTERIA_ADMIN_LOG_PAGE at most, of the events with an id below max_id (zero for the newest), matching the
   text of the query when it is not empty; limit 1 to EXTERIA_ADMIN_LOG_PAGE */
exteria_status exteria_admin_log_request(exteria_arena *arena, const exteria_peer_ref *channel, const char *query, int64_t max_id, int32_t limit,
                                         exteria_tl_value **out);
/* the answer to it: events in server order, at most cap (more is EXTERIA_E_LIMIT); an item that is not an event is EXTERIA_E_MALFORMED, and an
   action that has no sentence here comes as EXTERIA_LOG_OTHER, so a new server action cannot empty the screen */
exteria_status exteria_admin_log_parse(const exteria_tl_value *answer, exteria_admin_event *rows, size_t cap, size_t *count);

#endif
