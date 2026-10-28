#ifndef EXTERIA_CHANNEL_H
#define EXTERIA_CHANNEL_H

#include <stdint.h>

#include "exteria_dialogs.h"
#include "exteria_people.h"
#include "exteria_messages.h"
#include "exteria_profile.h"
#include "exteria_tl.h"

#define EXTERIA_CHANNEL_USERNAME_MAX 64
#define EXTERIA_CHANNEL_LINK_MAX 128
#define EXTERIA_CHANNEL_TITLE_MAX 128
#define EXTERIA_MEMBERS_PAGE 50
#define EXTERIA_MEMBERS_MAX 100
#define EXTERIA_MEMBER_RANK_MAX 64
#define EXTERIA_MEMBERS_QUERY_MAX 64

/* the rights of an administrator, one bit each, in the order the editor lists them */
#define EXTERIA_ADMIN_CHANGE_INFO     0x001u
#define EXTERIA_ADMIN_POST_MESSAGES   0x002u
#define EXTERIA_ADMIN_EDIT_MESSAGES   0x004u
#define EXTERIA_ADMIN_DELETE_MESSAGES 0x008u
#define EXTERIA_ADMIN_BAN_USERS       0x010u
#define EXTERIA_ADMIN_INVITE_USERS    0x020u
#define EXTERIA_ADMIN_PIN_MESSAGES    0x040u
#define EXTERIA_ADMIN_ADD_ADMINS      0x080u
#define EXTERIA_ADMIN_MANAGE_CALL     0x100u
#define EXTERIA_ADMIN_ANONYMOUS       0x200u
#define EXTERIA_ADMIN_MANAGE_TOPICS   0x400u
#define EXTERIA_ADMIN_ALL             0x7FFu

/* what the profile of a channel shows, read from a channels.getFullChannel answer */
typedef struct exteria_full_channel {
    exteria_dialog_row dialog;      /* the channel as a chat: title, picture, access hash */
    uint8_t megagroup;              /* a group built on a channel, as opposed to a broadcast channel */
    uint8_t membership_known;       /* a min channel does not carry the account's membership */
    uint8_t verified;
    uint8_t muted;                  /* notifications are off now */
    uint8_t can_view_stats;
    uint8_t gifts_available;        /* the channel takes gifts */
    uint8_t creator;                /* the account made the channel, so it holds every right */
    uint8_t signatures;             /* posts carry the name of the admin who wrote them */
    uint32_t admin_rights;          /* EXTERIA_ADMIN_* of the account when it is an admin */
    char about[EXTERIA_ABOUT_MAX];
    char username[EXTERIA_CHANNEL_USERNAME_MAX];    /* empty for a private channel */
    char link[EXTERIA_CHANNEL_LINK_MAX];            /* the invite link an admin sees, empty otherwise */
    int32_t participants;
    int32_t admins;
    int32_t banned;
    int32_t gifts;
    int32_t pinned_message;         /* the pinned message of the channel, zero for none */
    uint8_t has_linked;
    exteria_dialog_row linked;      /* the discussion group of a broadcast channel */
    /* who the account writes as here when it has chosen someone else than itself: a channel or an anonymous identity; zero for itself */
    int32_t send_as_kind;           /* 1 user, 3 channel, as exteria_peer; zero when none */
    int64_t send_as_id;
} exteria_full_channel;

/* channels.getFullChannel for a channel (kind 3 with an access hash) */
exteria_status exteria_full_channel_request(exteria_arena *arena, const exteria_peer_ref *channel, exteria_tl_value **out);
exteria_status exteria_discussion_request(exteria_arena *arena, const exteria_peer_ref *channel, int32_t post_id, exteria_tl_value **out);
exteria_status exteria_discussion_parse(const exteria_tl_value *answer, int64_t channel_id, exteria_dialog_row *out);
/* a messages.chatFull of that channel; now (unix seconds) decides whether a mute is still running; anything else,
   or a full chat that is not a channel, is EXTERIA_E_MALFORMED. out is always initialised */
exteria_status exteria_full_channel_parse(const exteria_tl_value *answer, int64_t channel_id, int32_t now, exteria_full_channel *out);
/* the EXTERIA_ADMIN_* bits a chatAdminRights object sets; a missing or foreign object is none */
uint32_t exteria_admin_rights_read(const exteria_tl_value *rights);

typedef enum exteria_member_list {
    EXTERIA_MEMBERS_RECENT = 0,     /* the subscribers, newest first; a query searches them by name */
    EXTERIA_MEMBERS_ADMINS,
    EXTERIA_MEMBERS_KICKED          /* the blacklist; a query searches it by name */
} exteria_member_list;

typedef enum exteria_member_role {
    EXTERIA_MEMBER_PLAIN = 0,
    EXTERIA_MEMBER_CREATOR,
    EXTERIA_MEMBER_ADMIN,
    EXTERIA_MEMBER_BANNED
} exteria_member_role;

typedef struct exteria_channel_member {
    exteria_person_row person;
    uint8_t role;                   /* exteria_member_role */
    uint8_t can_edit;               /* an admin whose rights the account may change */
    uint8_t self;                   /* the account itself */
    uint32_t rights;                /* EXTERIA_ADMIN_* of an admin; every right for the creator */
    int32_t date;                   /* when the person joined, was promoted or was banned; zero when unknown */
    char rank[EXTERIA_MEMBER_RANK_MAX];
} exteria_channel_member;

/* channels.getParticipants for one page of a list */
exteria_status exteria_channel_members_request(exteria_arena *arena, const exteria_peer_ref *channel, exteria_member_list list, const char *query,
                                              int32_t offset, int32_t limit, exteria_tl_value **out);
/* the answer to it: rows in server order, at most cap, and the total the server counts for the list; participants
   that are not users, and users the answer does not describe, are left out */
exteria_status exteria_channel_members_parse(const exteria_tl_value *answer, exteria_channel_member *rows, size_t cap, size_t *count, int32_t *total);

/* channels.editAdmin: makes the user an admin with exactly these rights, or an ordinary subscriber again when
   rights is zero */
exteria_status exteria_channel_admin_request(exteria_arena *arena, const exteria_peer_ref *channel, const exteria_peer_ref *user, uint32_t rights,
                                            const char *rank, exteria_tl_value **out);
/* channels.editBanned: puts the user on the blacklist (the user is removed and cannot return), or takes the user off it again */
exteria_status exteria_channel_ban_request(exteria_arena *arena, const exteria_peer_ref *channel, const exteria_peer_ref *user, int banned,
                                          exteria_tl_value **out);
/* channels.inviteToChannel: adds these users (one to EXTERIA_INVITE_MAX, each a user with an access hash) to the supergroup */
#define EXTERIA_INVITE_MAX 20
exteria_status exteria_channel_invite_request(exteria_arena *arena, const exteria_peer_ref *channel, const exteria_peer_ref *users, size_t count,
                                             exteria_tl_value **out);
/* how many users messages.invitedUsers says could not be added, because of their privacy settings or for another reason of their own */
exteria_status exteria_channel_invite_missing(const exteria_tl_value *answer, size_t *missing);
/* channels.editTitle */
exteria_status exteria_channel_title_request(exteria_arena *arena, const exteria_peer_ref *channel, const char *title, exteria_tl_value **out);
/* messages.editChatAbout; an empty text clears the description */
exteria_status exteria_channel_about_request(exteria_arena *arena, const exteria_peer_ref *channel, const char *about, exteria_tl_value **out);
/* channels.updateUsername; an empty name makes the channel private. check asks channels.checkUsername instead, which only says whether it is free */
exteria_status exteria_channel_username_request(exteria_arena *arena, const exteria_peer_ref *channel, const char *username, int check,
                                               exteria_tl_value **out);
/* channels.toggleSignatures */
exteria_status exteria_channel_signatures_request(exteria_arena *arena, const exteria_peer_ref *channel, int enabled, exteria_tl_value **out);
/* a Bool answer: EXTERIA_OK for true, EXTERIA_E_STATE for false, EXTERIA_E_MALFORMED for anything else */
exteria_status exteria_channel_bool_parse(const exteria_tl_value *answer);

/* channels.joinChannel */
exteria_status exteria_channel_join_request(exteria_arena *arena, const exteria_peer_ref *channel, exteria_tl_value **out);
/* the answer to it: EXTERIA_OK when the account is in, EXTERIA_E_UNSUPPORTED when the channel asks for a web view check first,
   EXTERIA_E_MALFORMED for anything else */
exteria_status exteria_channel_join_parse(const exteria_tl_value *answer);
int exteria_channel_already_left(int peer_kind, const char *error_name);
/* resolves a min channel through the message that named it, without reusing its unusable hash */
exteria_status exteria_channel_from_message_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id,
                                                   int64_t channel_id, exteria_tl_value **out);

#endif
