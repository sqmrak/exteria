#ifndef EXTERIA_NOTIFY_PREFS_H
#define EXTERIA_NOTIFY_PREFS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_arena.h"
#include "exteria_notify_types.h"
#include "exteria_messages.h"
#include "exteria_status.h"
#include "exteria_tl.h"

/* the notification settings of an account, as the server keeps them (peerNotifySettings and its input twin) and
   the rules that turn them into a yes or a no for one chat; no I/O, so the rules are tested on the host */

/* reads a PeerNotifySettings; NULL or an object without fields is a chat with no settings of its own, all has_
   bytes zero */
exteria_status exteria_peer_notify_read(const exteria_tl_value *settings, exteria_peer_notify *out);

/* the inputPeerNotifySettings that carries the fields that have has_ set */
exteria_status exteria_peer_notify_build(exteria_arena *arena, const exteria_peer_notify *settings, exteria_tl_value **out);

/* the kinds of chat the account sets notifications for as a whole, in the order of the settings screen */
typedef enum exteria_notify_scope {
    EXTERIA_SCOPE_USERS = 0,
    EXTERIA_SCOPE_CHATS,
    EXTERIA_SCOPE_BROADCASTS,
    EXTERIA_SCOPE_COUNT
} exteria_notify_scope;

/* account.getNotifySettings of one kind of chat */
exteria_status exteria_notify_scope_request(exteria_arena *arena, exteria_notify_scope scope, exteria_tl_value **out);
/* account.getNotifySettings of one chat (a forum topic when peer->topic_id is set) */
exteria_status exteria_notify_peer_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out);
/* account.updateNotifySettings of one kind of chat (a null peer) or of one chat (a peer; a forum topic when peer->topic_id is set) */
exteria_status exteria_notify_update_request(exteria_arena *arena, int has_scope, exteria_notify_scope scope, const exteria_peer_ref *peer,
                                             const exteria_peer_notify *settings, exteria_tl_value **out);
/* the answer of an update call: a Bool, true when the server took it */
exteria_status exteria_notify_bool_result(const exteria_tl_value *answer);

/* a chat that has settings of its own: who it is and what it holds */
typedef struct exteria_notify_exception {
    int32_t peer_kind;
    int64_t peer_id;
    int64_t peer_hash;
    uint8_t deleted;
    uint8_t broadcast;          /* a channel that only its admins write in; a supergroup is a group */
    uint8_t forum_topic;        /* the entry is for a topic of a forum, which the list does not show */
    char title[128];
    exteria_peer_notify settings;
} exteria_notify_exception;

/* account.getNotifyExceptions of every chat; compare_sound asks for the chats whose sound differs, compare_stories for those whose stories differ */
exteria_status exteria_notify_exceptions_request(exteria_arena *arena, int compare_sound, int compare_stories, exteria_tl_value **out);
/* the Updates of that answer: one entry for each updateNotifySettings that names a chat, in the order given, at
   most cap */
exteria_status exteria_notify_exceptions_parse(const exteria_tl_value *answer, int64_t self_id, exteria_notify_exception *out, size_t cap, size_t *count);

/* account.resetNotifySettings and account.setContactSignUpNotification (silent true turns the news of a new contact off) */
exteria_status exteria_notify_reset_request(exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_notify_signup_request(exteria_arena *arena, int silent, exteria_tl_value **out);

/* who a reaction may come from to be announced */
typedef enum exteria_reaction_from {
    EXTERIA_REACTION_FROM_NOBODY = 0,
    EXTERIA_REACTION_FROM_EVERYONE,
    EXTERIA_REACTION_FROM_CONTACTS
} exteria_reaction_from;

typedef struct exteria_reaction_notify {
    int32_t messages_from;      /* exteria_reaction_from */
    int32_t stories_from;
    uint8_t previews;
    exteria_notify_sound sound;
} exteria_reaction_notify;

exteria_status exteria_reaction_notify_request(exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_reaction_notify_read(const exteria_tl_value *answer, exteria_reaction_notify *out);
exteria_status exteria_reaction_notify_set_request(exteria_arena *arena, const exteria_reaction_notify *settings, exteria_tl_value **out);

/* account.getSavedRingtones: the tones of the cloud, in the order the account keeps them */
typedef struct exteria_ringtone_row {
    int64_t id;
    int64_t access_hash;
    int32_t dc;
    int32_t size;
    int32_t duration;           /* seconds, from the audio attribute; zero when the document has none */
    char title[EXTERIA_SOUND_NAME_MAX];
    char file_name[EXTERIA_SOUND_NAME_MAX];
    char mime[32];
    uint8_t file_reference[128];
    uint8_t file_reference_len;
} exteria_ringtone_row;

exteria_status exteria_ringtones_request(exteria_arena *arena, exteria_tl_value **out);
/* account.savedRingtones; savedRingtonesNotModified is EXTERIA_E_NOTFOUND */
exteria_status exteria_ringtones_parse(const exteria_tl_value *answer, exteria_ringtone_row *rows, size_t cap, size_t *count);
/* account.saveRingtone with unsave set removes the tone from the account */
exteria_status exteria_ringtone_unsave_request(exteria_arena *arena, const exteria_ringtone_row *row, exteria_tl_value **out);

/* ---- the rules ---- */

/* what the settings of the account say, with the few switches that live on the phone only */
typedef struct exteria_notify_rules {
    exteria_peer_notify scope[EXTERIA_SCOPE_COUNT];     /* users, groups, channels; unset fields mean on, shown, the default sound */
    uint8_t contact_joined;     /* announce "joined Telegram" */
    uint8_t pinned_messages;    /* announce a pinned message */
} exteria_notify_rules;

void exteria_notify_rules_init(exteria_notify_rules *rules);

typedef struct exteria_notify_decision {
    uint8_t notify;             /* announce the chat at all */
    uint8_t previews;
    exteria_notify_sound sound; /* kind NONE for a silent delivery */
} exteria_notify_decision;

/* the scope a chat of this peer kind belongs to: a user's chat is USERS, a basic group or a supergroup CHATS, a broadcast channel BROADCASTS */
exteria_notify_scope exteria_notify_scope_of(int32_t peer_kind, int is_broadcast);

/* the settings of a chat over those of its kind; a field the chat sets wins, even when it turns a muted kind on; a
   field it leaves out is the kind's */
void exteria_notify_decide(const exteria_notify_rules *rules, exteria_notify_scope scope, const exteria_peer_notify *chat, int32_t now, exteria_notify_decision *out);

/* for the settings screens: the state of a kind as the words "on", "off" or "off until", by the has_ and mute_until of the settings: 0 on, 1 off for good
   (more than a year ahead), 2 off until mute_until */
int exteria_notify_mute_state(int32_t mute_until, int32_t now);

#endif
