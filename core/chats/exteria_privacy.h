#ifndef EXTERIA_PRIVACY_H
#define EXTERIA_PRIVACY_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_messages.h"
#include "exteria_photos.h"
#include "exteria_status.h"
#include "exteria_tl.h"

/* the privacy screen: who may see each piece of the account, the people the account blocked */

typedef enum exteria_privacy_key {
    EXTERIA_PRIVACY_PHONE = 0,
    EXTERIA_PRIVACY_LAST_SEEN,
    EXTERIA_PRIVACY_PHOTO,
    EXTERIA_PRIVACY_FORWARDS,
    EXTERIA_PRIVACY_CALLS,
    EXTERIA_PRIVACY_INVITES,
    EXTERIA_PRIVACY_VOICE,
    EXTERIA_PRIVACY_ABOUT,
    EXTERIA_PRIVACY_BIRTHDAY,
    EXTERIA_PRIVACY_MUSIC,
    EXTERIA_PRIVACY_KEY_COUNT
} exteria_privacy_key;

/* what the last rule of a list says for everybody the exceptions do not name; the server's own order of preference is nobody when it says nothing */
typedef enum exteria_privacy_base {
    EXTERIA_PRIVACY_NOBODY = 0,
    EXTERIA_PRIVACY_CONTACTS,
    EXTERIA_PRIVACY_EVERYBODY
} exteria_privacy_base;

#define EXTERIA_PRIVACY_EXCEPT_MAX 300
#define EXTERIA_PRIVACY_NAME_MAX 64

typedef struct exteria_privacy_user {
    int64_t id;
    int64_t access_hash;                    /* what an input user needs to name the person again */
    char name[EXTERIA_PRIVACY_NAME_MAX];
    exteria_photo_ref photo;                /* zeroed when the person has none, or when the person was added on this screen */
} exteria_privacy_user;

typedef struct exteria_privacy_chat {
    int64_t id;
    char title[EXTERIA_PRIVACY_NAME_MAX];
    exteria_photo_ref photo;
} exteria_privacy_chat;

typedef struct exteria_privacy_rules {
    exteria_privacy_base base;
    /* rules the screen does not edit but must send back as they were, or the server forgets them */
    uint8_t allow_premium;
    uint8_t allow_close_friends;
    uint8_t allow_bots;
    uint8_t disallow_bots;
    size_t allow_users_count, disallow_users_count, allow_chats_count, disallow_chats_count;
    exteria_privacy_user allow_users[EXTERIA_PRIVACY_EXCEPT_MAX];
    exteria_privacy_user disallow_users[EXTERIA_PRIVACY_EXCEPT_MAX];
    exteria_privacy_chat allow_chats[EXTERIA_PRIVACY_EXCEPT_MAX];
    exteria_privacy_chat disallow_chats[EXTERIA_PRIVACY_EXCEPT_MAX];
} exteria_privacy_rules;

/* account.getPrivacy for a key; EXTERIA_E_ARG for a key out of range */
exteria_status exteria_privacy_get_request(exteria_arena *arena, exteria_privacy_key key, exteria_tl_value **out);
/* an account.privacyRules answer; a list with more exceptions than the struct holds is EXTERIA_E_LIMIT, since
   writing it back would drop the rest */
exteria_status exteria_privacy_parse(const exteria_tl_value *answer, exteria_privacy_rules *out);
/* account.setPrivacy with the rules as they are: the exceptions first, then what the screen does not edit, then the base */
exteria_status exteria_privacy_set_request(exteria_arena *arena, exteria_privacy_key key, const exteria_privacy_rules *rules, exteria_tl_value **out);

/* one person or chat the account blocked */
#define EXTERIA_BLOCKED_MAX 200
typedef struct exteria_blocked_row {
    int32_t kind;                           /* 1 user, 2 chat, 3 channel, as exteria_peer_ref */
    int64_t id;
    int64_t access_hash;
    int32_t date;
    char name[EXTERIA_PRIVACY_NAME_MAX * 2];
    exteria_photo_ref photo;
} exteria_blocked_row;

exteria_status exteria_blocked_request(exteria_arena *arena, int32_t offset, int32_t limit, exteria_tl_value **out);
/* a contacts.blocked or blockedSlice: the rows in server order, at most cap, and how many the account has in all (the length of the page for a plain
   contacts.blocked) */
exteria_status exteria_blocked_parse(const exteria_tl_value *answer, exteria_blocked_row *rows, size_t cap, size_t *count, int32_t *total);
exteria_status exteria_block_request(exteria_arena *arena, const exteria_peer_ref *peer, int block, exteria_tl_value **out);

/* the days an account may sit idle before the server deletes it; the answer is an accountDaysTTL */
exteria_status exteria_account_ttl_request(exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_account_ttl_parse(const exteria_tl_value *answer, int32_t *days);
/* 30 to 730 days as the server takes them; anything else is EXTERIA_E_ARG */
exteria_status exteria_account_ttl_set_request(exteria_arena *arena, int32_t days, exteria_tl_value **out);

/* the default time of auto-delete for new chats, in seconds, zero for off */
exteria_status exteria_history_ttl_request(exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_history_ttl_parse(const exteria_tl_value *answer, int32_t *seconds);
exteria_status exteria_history_ttl_set_request(exteria_arena *arena, int32_t seconds, exteria_tl_value **out);

/* payments.clearSavedInfo: the saved card, the saved address, or both */
exteria_status exteria_clear_payments_request(exteria_arena *arena, int credentials, int info, exteria_tl_value **out);
/* contacts.resetSaved: forgets the contacts the server got from the phone */
exteria_status exteria_reset_saved_contacts_request(exteria_arena *arena, exteria_tl_value **out);

#endif
