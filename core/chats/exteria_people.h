#ifndef EXTERIA_PEOPLE_H
#define EXTERIA_PEOPLE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_photos.h"
#include "exteria_tl.h"

#define EXTERIA_PEOPLE_MAX 2000
/* telegram delivers service notifications in this account's chat */
#define EXTERIA_TELEGRAM_SERVICE_USER_ID 777000LL
#define EXTERIA_PERSON_NAME_MAX 128
#define EXTERIA_PERSON_USERNAME_MAX 64
#define EXTERIA_PERSON_PHONE_MAX 32

typedef enum exteria_presence {
    EXTERIA_PRESENCE_UNKNOWN = 0,
    EXTERIA_PRESENCE_ONLINE,
    EXTERIA_PRESENCE_OFFLINE,   /* seen is the unix time it went offline */
    EXTERIA_PRESENCE_RECENTLY,
    EXTERIA_PRESENCE_LAST_WEEK,
    EXTERIA_PRESENCE_LAST_MONTH,
    EXTERIA_PRESENCE_DELETED   /* the account is gone; the server sends no status for it, and the UI says so apart from a hidden one */
} exteria_presence;

typedef struct exteria_person_row {
    int64_t id;
    int64_t access_hash;    /* what an input peer needs; zero when the object came from a mention and carries none */
    uint8_t bot;
    uint8_t bot_inline;     /* a bot that answers @name queries in any chat */
    uint8_t bot_inline_geo; /* and asks for the location with them */
    uint8_t bot_no_chats;   /* a bot that cannot be added to groups */
    uint8_t bot_reads_all;  /* a bot that sees every message of a group, not only the commands */
    uint8_t verified;
    uint8_t contact;        /* in the contacts of the account */
    uint8_t mutual;         /* and the account is in the contacts of this user too */
    uint8_t premium;        /* Telegram Premium: may write custom emoji */
    int64_t emoji_status;       /* the custom emoji document shown after the name, zero without one */
    int32_t emoji_status_until; /* unix time the status ends, zero when it has no end */
    uint8_t deleted;
    uint8_t has_name_color;     /* the user chose the color of the name in group chats (a PeerColor with a color id) */
    int32_t name_color;         /* its id, 0 to 6 free for everyone and above them for Premium accounts */
    exteria_presence presence;
    int32_t seen;
    exteria_photo_ref photo;
    char name[EXTERIA_PERSON_NAME_MAX];
    char username[EXTERIA_PERSON_USERNAME_MAX];
    char phone[EXTERIA_PERSON_PHONE_MAX];
    char bot_placeholder[EXTERIA_PERSON_NAME_MAX];  /* the hint the field shows after @name; empty without one */
} exteria_person_row;

/* a UserStatus: online, offline with the time it left, or one of the coarse "recently" ranges; anything else, a
   missing status or one the user hid from us, is unknown */
void exteria_presence_read(const exteria_tl_value *status, exteria_presence *presence, int32_t *seen);

/* the custom emoji a user shows after their name; the caller compares until with the clock, which keeps the parse
   deterministic */
void exteria_emoji_status_read(const exteria_tl_value *user, int64_t *document, int32_t *until);

/* a User object: a userEmpty or a user without an id is EXTERIA_E_MALFORMED */
exteria_status exteria_person_parse(const exteria_tl_value *user, exteria_person_row *out);

/* a channel or community sender, including forbidden objects that still carry a title */
exteria_status exteria_channel_person_parse(const exteria_tl_value *channel, exteria_person_row *out);

#define EXTERIA_GROUP_ROLES_MAX 200
typedef struct exteria_group_role {
    int64_t user_id;
    uint8_t owner;
    uint8_t admin;
    char rank[EXTERIA_PERSON_NAME_MAX];
} exteria_group_role;

exteria_status exteria_group_roles_request(exteria_arena *arena, int32_t kind, int64_t id, int64_t hash, exteria_tl_value **out);
/* the admins of a supergroup, or the participants of a basic group, including custom ranks */
exteria_status exteria_group_roles_parse(const exteria_tl_value *answer, int64_t id, exteria_group_role *rows, size_t cap, size_t *count);

/* a contacts.contacts answer, in server order, at most cap rows */
exteria_status exteria_contacts_parse(const exteria_tl_value *answer, exteria_person_row *rows, size_t cap, size_t *count);

#endif
