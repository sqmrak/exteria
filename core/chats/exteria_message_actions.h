#ifndef EXTERIA_MESSAGE_ACTIONS_H
#define EXTERIA_MESSAGE_ACTIONS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_messages.h"
#include "exteria_tl.h"

/* requests a change of sharing, or answers a request when request_id is positive */
exteria_status exteria_sharing_request(exteria_arena *arena, const exteria_peer_ref *peer, int enabled, int32_t request_id, exteria_tl_value **out);

#define EXTERIA_SHARING_PERIOD_DEFAULT 86400
exteria_status exteria_sharing_period_parse(const exteria_tl_value *answer, int32_t *seconds);
/* the server's expired bit wins; the deadline is inclusive as in Telegram */
int exteria_sharing_expired(int server_expired, int32_t date, int32_t period, int64_t now);

/* a covered part of a code span must be revealed before the whole span can be copied */
int exteria_code_has_hidden_spoiler(size_t offset, size_t length, const exteria_entity *entities, size_t count);

typedef enum exteria_read_action {
    EXTERIA_READ_AUTOMATIC,
    EXTERIA_READ_EXPLICIT,
    EXTERIA_READ_ONCE
} exteria_read_action;
int exteria_read_action_allowed(int ghost, exteria_read_action action);

/* what a long press on a message can offer; the rules below pick the ones that can work */
typedef enum exteria_message_action {
    EXTERIA_ACTION_REACT = 1 << 0,
    EXTERIA_ACTION_REPLY = 1 << 1,
    EXTERIA_ACTION_COPY = 1 << 2,
    EXTERIA_ACTION_COPY_LINK = 1 << 3,
    EXTERIA_ACTION_EDIT = 1 << 4,
    EXTERIA_ACTION_FORWARD = 1 << 5,
    EXTERIA_ACTION_PIN = 1 << 6,
    EXTERIA_ACTION_UNPIN = 1 << 7,
    EXTERIA_ACTION_DELETE = 1 << 8,
    EXTERIA_ACTION_DETAILS = 1 << 9,
    EXTERIA_ACTION_REPEAT = 1 << 10,
    EXTERIA_ACTION_SAVE = 1 << 11,
    EXTERIA_ACTION_GALLERY = 1 << 12,   /* the photo or video goes to the photo library of the phone */
    EXTERIA_ACTION_SELECT = 1 << 13,    /* starts the selection of several messages */
    EXTERIA_ACTION_TRANSCRIBE = 1 << 14,    /* the words of a voice message, as text */
    EXTERIA_ACTION_BOOKMARK = 1 << 15,      /* keeps the message in the list of bookmarks of this phone */
    EXTERIA_ACTION_UNBOOKMARK = 1 << 16,
    EXTERIA_ACTION_TRANSLATE = 1 << 17,     /* the words of the message, in the language the person reads */
    EXTERIA_ACTION_COPY_PHOTO = 1 << 18,    /* the picture of a photo goes to the pasteboard */
    EXTERIA_ACTION_HISTORY = 1 << 19,       /* everything the sender of the message wrote in this group */
    EXTERIA_ACTION_REPORT = 1 << 20,        /* messages.report for a message of somebody else */
    EXTERIA_ACTION_FORWARD_HIDDEN = 1 << 21,    /* forward without the name of the author */
    EXTERIA_ACTION_REMIND = 1 << 22,            /* a reminder about the message arrives in the favorites at a time the person picks */
    EXTERIA_ACTION_REPLY_PRIVATE = 1 << 23,     /* the sender of a group message is written to in a chat of their own */
    EXTERIA_ACTION_EDIT_HISTORY = 1 << 24,      /* what the message said before its edits; the client adds it, since only it knows whether the versions were kept */
    EXTERIA_ACTION_REACTORS = 1 << 25          /* the people and dates of a message's reactions */
} exteria_message_action;

typedef struct exteria_action_context {
    int32_t peer_kind;          /* 1 user, 2 chat, 3 channel */
    int32_t message_id;         /* zero or less for a message that has not been sent yet */
    uint8_t broadcast;          /* the chat is a broadcast channel, where only its admins write */
    uint8_t can_post;           /* the account may post in that broadcast channel */
    uint8_t outgoing;
    uint8_t service;
    uint8_t has_text;
    uint8_t has_entities;       /* bold, links and the like, which a plain field cannot give back */
    exteria_preview_kind media; /* none or text for a message of words alone */
    uint8_t reactions_possible;
    uint8_t has_username;       /* the chat is public, so a message has a link without asking the server */
    uint8_t pinned_now;         /* this message is the one pinned in the chat */
    uint8_t bookmarked;         /* the message is in the bookmarks already */
    uint8_t media_fetchable;    /* the media has a file the app can download, which saving it to the library needs */
    uint8_t translate_wanted;   /* the translate button is on in the settings and the language of the words is not one the person left alone */
    uint8_t saved_chat;         /* the chat is the favorites, where saving a message again would only copy it onto itself */
    uint8_t sender_user;        /* the message was written by a person the app can search for (a user with a hash) */
} exteria_action_context;

/* the actions that apply, as a mask of exteria_message_action; a message not sent yet can only be copied, a
   service line has none */
uint32_t exteria_message_actions_for(const exteria_action_context *context);

#define EXTERIA_TRANSCRIPT_MAX 4100

/* what messages.transcribedAudio says: the text so far, whether the server is still listening, and the id that later updates carry */
typedef struct exteria_transcript {
    uint8_t pending;
    int64_t id;
    char text[EXTERIA_TRANSCRIPT_MAX];
} exteria_transcript;

/* messages.transcribeAudio for a voice message of a chat */
exteria_status exteria_transcribe_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id, exteria_tl_value **out);
/* the answer: EXTERIA_OK with the text (cut at a character boundary when it is longer than
   EXTERIA_TRANSCRIPT_MAX), EXTERIA_E_MALFORMED for anything else. out is always initialised */
exteria_status exteria_transcribe_parse(const exteria_tl_value *answer, exteria_transcript *out);

/* messages.getOutboxReadDate: when the other side of a private chat read a message of ours */
exteria_status exteria_read_date_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id, exteria_tl_value **out);
/* the outboxReadDate it answers: its date, unix seconds; EXTERIA_E_MALFORMED for anything else or a date that is
   not positive; date is zero then */
exteria_status exteria_read_date_parse(const exteria_tl_value *answer, int32_t *date);
exteria_status exteria_group_read_dates_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id, exteria_tl_value **out);
typedef struct exteria_group_read_date {
    int64_t user_id;
    int32_t date;
} exteria_group_read_date;
exteria_status exteria_group_read_dates_parse(const exteria_tl_value *answer, exteria_group_read_date *rows, size_t capacity, size_t *count);

/* what a set of selected messages can do together, from the mask each one has; copy when any of them has words to
   copy, and forward and delete only when every one of them allows it, since one that does not would make the whole
   request fail */
uint32_t exteria_selection_actions(const uint32_t *masks, size_t count);

/* at most EXTERIA_MESSAGES_MAX messages in one request */

/* messages.deleteMessages for a user or basic chat, channels.deleteMessages for a channel. revoke deletes for the other side too,
   and is ignored for a channel, where a delete always reaches everyone */
exteria_status exteria_delete_messages_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                               int revoke, exteria_tl_value **out);
/* the answer to either: EXTERIA_OK for messages.affectedMessages, EXTERIA_E_MALFORMED for anything else */
exteria_status exteria_delete_messages_parse(const exteria_tl_value *answer);

/* messages.updatePinnedMessage */
exteria_status exteria_pin_message_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, int unpin, exteria_tl_value **out);

/* messages.editMessage with a new text and no entities; an empty text is EXTERIA_E_ARG, the server would not take
   it either */
exteria_status exteria_edit_message_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, const char *text,
                                            exteria_tl_value **out);

/* the same for the caption of a message that carries media: no media field is sent, so the picture or the file stays, and an empty text takes the caption away */
exteria_status exteria_edit_caption_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, const char *text,
                                            exteria_tl_value **out);

/* messages.forwardMessages of ids from one chat into another, one random id for each. drop_author sends them as if they were written by the
   forwarder, without the line about where they came from */
exteria_status exteria_forward_messages_request(exteria_arena *arena, const exteria_peer_ref *from, const exteria_peer_ref *to,
                                                const int32_t *ids, const int64_t *random_ids, size_t count, int drop_author,
                                                exteria_tl_value **out);

#endif
