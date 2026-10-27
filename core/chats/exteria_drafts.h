#ifndef EXTERIA_DRAFTS_H
#define EXTERIA_DRAFTS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_messages.h"
#include "exteria_tl.h"

/* a message that was typed and not sent, as the account keeps it on the server for every one of its phones */

/* the longest draft the server keeps is 4096 UTF-16 units, which is at most four UTF-8 bytes each */
#define EXTERIA_DRAFT_TEXT_MAX (4 * 4096 + 4)

typedef struct exteria_draft {
    uint8_t present;        /* something is kept: text or a message being answered; zero for draftMessageEmpty */
    uint8_t no_webpage;     /* the link preview was taken away */
    int32_t date;
    int32_t reply_to;       /* the message being answered, zero for none (a topic root is not an answer) */
    uint8_t entity_count;
    exteria_entity entities[EXTERIA_MESSAGE_ENTITIES_MAX];
    char urls[EXTERIA_MESSAGE_URLS_MAX];
    char text[EXTERIA_DRAFT_TEXT_MAX];
} exteria_draft;

/* reads a draftMessage or draftMessageEmpty. topic_id is the forum topic the draft belongs to (zero for a whole chat), whose root a reply may name without
   answering anything. out is always initialised; EXTERIA_E_MALFORMED for any other object or a text that does not fit */
exteria_status exteria_draft_read(const exteria_tl_value *draft, int32_t topic_id, exteria_draft *out);

/* messages.saveDraft for the chat of peer (with its topic, which the draft then belongs to). An empty text and no reply_to clear the draft on the server */
exteria_status exteria_draft_save_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *text, const exteria_send_entity *entities,
                                          size_t entity_count, int32_t reply_to, int no_webpage, exteria_tl_value **out);

/* the draft of an updateDraftMessage: the chat and topic it belongs to, and the DraftMessage itself (not copied). EXTERIA_E_UNSUPPORTED for an update of
   another kind or a draft of the saved chats of a monoforum, which the app does not show */
exteria_status exteria_draft_update_read(const exteria_tl_value *update, int32_t *peer_kind, int64_t *peer_id, int32_t *topic_id,
                                         const exteria_tl_value **draft);

/* what the walks below report for a chat or topic; draft is NULL when it has none. A non-zero answer stops the walk and is returned */
typedef exteria_status (*exteria_draft_visit)(void *ctx, int32_t peer_kind, int64_t peer_id, int32_t topic_id, const exteria_tl_value *draft);

/* every dialog of a messages.dialogs, dialogsSlice or dialogsNotModified answer, in order; the folder entry has no draft and is skipped */
exteria_status exteria_draft_dialogs_visit(const exteria_tl_value *answer, exteria_draft_visit visit, void *ctx);
/* every topic of a messages.forumTopics answer for the forum of the peer */
exteria_status exteria_draft_topics_visit(const exteria_tl_value *answer, int32_t peer_kind, int64_t peer_id, exteria_draft_visit visit, void *ctx);

#endif
