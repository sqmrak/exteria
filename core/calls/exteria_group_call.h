#ifndef EXTERIA_GROUP_CALL_H
#define EXTERIA_GROUP_CALL_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_messages.h"
#include "exteria_people.h"
#include "exteria_status.h"
#include "exteria_tl.h"

/* the signaling of group calls (voice chats): the phone.* requests that make, join and leave one, and the reading of a GroupCall, its participants and the
   updates about them. the media of the call is the business of exteria_tgc_group */

#define EXTERIA_GROUP_PARTICIPANTS_MAX 200
#define EXTERIA_GROUP_TITLE_MAX 128
#define EXTERIA_GROUP_LINK_MAX 256
#define EXTERIA_GROUP_OFFSET_MAX 64
#define EXTERIA_GROUP_JOIN_PARAMS_MAX 2048
#define EXTERIA_GROUP_INVITE_HASH_MAX 64
/* the volume of a member in the units of phone.editGroupCallParticipant: ten thousand is the normal level, twenty thousand the loudest the server takes */
#define EXTERIA_GROUP_VOLUME_DEFAULT 10000
#define EXTERIA_GROUP_VOLUME_MAX 20000

typedef struct exteria_group_call_ref {
    int64_t id;
    int64_t access_hash;
} exteria_group_call_ref;

typedef struct exteria_group_call_info {
    exteria_group_call_ref ref;
    uint8_t discarded;              /* a groupCallDiscarded: the call is over */
    uint8_t join_muted;             /* new members start muted */
    uint8_t can_change_join_muted;
    uint8_t creator;
    uint8_t rtmp_stream;            /* a live stream, which this app does not join */
    uint8_t conference;             /* an end-to-end encrypted conference, which this app does not join */
    uint8_t can_start_video;
    int32_t participants_count;
    int32_t version;
    int32_t schedule_date;          /* unix time a scheduled call starts, zero for one that runs */
    int32_t duration;               /* seconds, of a discarded call */
    char title[EXTERIA_GROUP_TITLE_MAX];
    char invite_link[EXTERIA_GROUP_LINK_MAX];
} exteria_group_call_info;

typedef struct exteria_group_participant {
    int32_t peer_kind;              /* 1 user, 2 chat, 3 channel, as exteria_peer */
    int64_t peer_id;
    int64_t access_hash;            /* of a user, zero when the answer carried none */
    uint32_t source;                /* the ssrc of the audio of this member */
    int32_t date;                   /* when it joined */
    int32_t active_date;            /* when it last spoke, zero when it has not */
    int32_t volume;                 /* the volume the admins or this account set, in percent times 100; zero for the default */
    uint8_t muted;
    uint8_t left;
    uint8_t can_self_unmute;
    uint8_t just_joined;
    uint8_t self;
    uint8_t muted_by_you;
    uint8_t has_video;
    uint8_t has_presentation;
    uint8_t deleted;
    exteria_photo_ref photo;
    char name[EXTERIA_PERSON_NAME_MAX];
} exteria_group_participant;

/* an inputGroupCall (the call field of a full chat), or one built from a GroupCall; EXTERIA_E_MALFORMED for anything else, an id of zero included */
exteria_status exteria_group_call_ref_read(const exteria_tl_value *input, exteria_group_call_ref *out);
/* a groupCall or a groupCallDiscarded */
exteria_status exteria_group_call_info_read(const exteria_tl_value *call, exteria_group_call_info *out);
/* one groupCallParticipant; users and chats are the vectors of the answer or the update container the participant came in (either may be NULL), from which the
   name and the photo are taken */
exteria_status exteria_group_participant_read(const exteria_tl_value *participant, const exteria_tl_value *users, const exteria_tl_value *chats,
                                              exteria_group_participant *out);
/* a vector of participants; one that cannot be read is skipped. *count is how many were kept, up to cap */
exteria_status exteria_group_participants_read(const exteria_tl_value *vector, const exteria_tl_value *users, const exteria_tl_value *chats,
                                               exteria_group_participant *out, size_t cap, size_t *count);

/* a phone.groupCall (answer of phone.getGroupCall) */
exteria_status exteria_group_call_answer_parse(const exteria_tl_value *answer, exteria_group_call_info *info, exteria_group_participant *participants, size_t cap,
                                               size_t *count, char *next_offset, size_t offset_cap);
/* a phone.groupParticipants (answer of phone.getGroupParticipants); version is the version of the call it was read at */
exteria_status exteria_group_participants_answer_parse(const exteria_tl_value *answer, exteria_group_participant *participants, size_t cap, size_t *count,
                                                       int32_t *version, char *next_offset, size_t offset_cap);

/* the updates that matter to a call. updateGroupCall: info of the call; updateGroupCallParticipants: the call, the changed members and the version they bring
   (container is the Updates object the update came in, for its users, or NULL); updateGroupCallConnection: the JSON of the server's answer to a join */
exteria_status exteria_group_update_call(const exteria_tl_value *update, exteria_group_call_info *out);
exteria_status exteria_group_update_participants(const exteria_tl_value *update, const exteria_tl_value *container, exteria_group_call_ref *call,
                                                 exteria_group_participant *out, size_t cap, size_t *count, int32_t *version);
/* a pointer into the update, valid as long as it is; presentation is 1 for the one of a screen share, which this app does not join */
exteria_status exteria_group_update_connection(const exteria_tl_value *update, const char **json, size_t *len, int *presentation);

/* the full chat of a basic group (messages.getFullChat) or of a channel (channels.getFullChannel), whose call field names the voice chat that runs there */
exteria_status exteria_group_full_chat_request(exteria_arena *arena, const exteria_peer_ref *chat, exteria_tl_value **out);
/* the call of such an answer; EXTERIA_E_NOTFOUND when no voice chat runs, EXTERIA_E_MALFORMED for any other answer */
exteria_status exteria_group_full_chat_call(const exteria_tl_value *answer, exteria_group_call_ref *out);

/* the call an Updates answer (of phone.createGroupCall) announces: the first updateGroupCall in it; EXTERIA_E_NOTFOUND when it holds none */
exteria_status exteria_group_updates_find_call(const exteria_tl_value *updates, exteria_group_call_info *out);

/* the requests; peers and calls are checked, and EXTERIA_E_ARG says one of them is not usable */
exteria_status exteria_group_call_get_request(exteria_arena *arena, const exteria_group_call_ref *call, int32_t limit, exteria_tl_value **out);
exteria_status exteria_group_participants_get_request(exteria_arena *arena, const exteria_group_call_ref *call, const char *offset, int32_t limit, exteria_tl_value **out);
/* joins as this account; params is the JSON of exteria_tgc_group_join_payload, invite_hash the hash of a link or NULL */
exteria_status exteria_group_join_request(exteria_arena *arena, const exteria_group_call_ref *call, int muted, const char *params, size_t params_len,
                                          const char *invite_hash, exteria_tl_value **out);
exteria_status exteria_group_leave_request(exteria_arena *arena, const exteria_group_call_ref *call, uint32_t source, exteria_tl_value **out);
exteria_status exteria_group_create_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t random_id, const char *title, exteria_tl_value **out);
exteria_status exteria_group_discard_request(exteria_arena *arena, const exteria_group_call_ref *call, exteria_tl_value **out);
/* mutes or unmutes a member, or sets its volume (volume 0 leaves it as it is, else 1 to 20000); peer is a user of the call or this account */
exteria_status exteria_group_edit_request(exteria_arena *arena, const exteria_group_call_ref *call, const exteria_peer_ref *peer, int set_muted, int muted,
                                          int32_t volume, exteria_tl_value **out);
exteria_status exteria_group_invite_link_request(exteria_arena *arena, const exteria_group_call_ref *call, int can_self_unmute, exteria_tl_value **out);
exteria_status exteria_group_invite_link_parse(const exteria_tl_value *answer, char *link, size_t cap);
/* phone.checkGroupCall: which of these sources the server still has; the answer is a vector of the ones it has */
exteria_status exteria_group_check_request(exteria_arena *arena, const exteria_group_call_ref *call, const int32_t *sources, uint32_t count, exteria_tl_value **out);
exteria_status exteria_group_check_parse(const exteria_tl_value *answer, int32_t source, int *present);

#endif
