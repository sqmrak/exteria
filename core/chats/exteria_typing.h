#ifndef EXTERIA_TYPING_H
#define EXTERIA_TYPING_H

#include <stdint.h>

#include "exteria_tl.h"

/* what the live updates say about someone typing */

typedef enum exteria_typing_action {
    EXTERIA_TYPING_CANCEL = 0,
    EXTERIA_TYPING_TEXT,
    EXTERIA_TYPING_VOICE,       /* recording a voice message or a video message */
    EXTERIA_TYPING_PHOTO,
    EXTERIA_TYPING_VIDEO,
    EXTERIA_TYPING_FILE,
    EXTERIA_TYPING_STICKER,     /* choosing a sticker or an emoji */
    EXTERIA_TYPING_OTHER        /* a game, a place, a contact, speaking in a call */
} exteria_typing_action;

typedef struct exteria_typing {
    int32_t peer_kind;          /* 1 user, 2 chat, 3 channel, as exteria_peer */
    int64_t peer_id;            /* the chat the action happens in; for kind 1 the person themselves */
    int64_t user_id;            /* who acts; zero for an anonymous sender */
    int32_t top_message;        /* the topic of a forum or the thread of a discussion, zero for the chat itself */
    exteria_typing_action action;
} exteria_typing;

/* 1 for a typing update that was read into out (peer_id, user_id and action filled), 0 for any other object or for one whose peer or action cannot be read.
   out is always initialised */
int exteria_typing_read(const exteria_tl_value *update, exteria_typing *out);

#endif
