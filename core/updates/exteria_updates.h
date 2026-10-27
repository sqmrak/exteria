#ifndef EXTERIA_UPDATES_H
#define EXTERIA_UPDATES_H

#include "exteria_store.h"

/* what AyuMoments keeps of the messages the other side takes away: bits of exteria_updates.keep */
enum {
    EXTERIA_KEEP_DELETED = 1,       /* a deleted message stays, under the kind of the deleted ones, in the chats the bits below name */
    EXTERIA_KEEP_PRIVATE = 2,
    EXTERIA_KEEP_GROUPS = 4,
    EXTERIA_KEEP_CHANNELS = 8,
    EXTERIA_KEEP_BOTS = 16,
    EXTERIA_KEEP_EDITS = 32         /* the text before an edit stays as a version of the message */
};

typedef struct exteria_updates {
    exteria_store *store;
    int64_t account;
    int64_t gap_channel;
    int needs_difference;
    int needs_history;
    int more_difference;
    int global_gap;
    int64_t channels[128];
    uint32_t channel_count;
    uint32_t keep;
} exteria_updates;

exteria_status exteria_updates_init(exteria_updates *u, exteria_store *store, int64_t account_id);
exteria_status exteria_updates_need(exteria_updates *u, int64_t channel_id);
exteria_status exteria_updates_apply(exteria_updates *u, const exteria_tl_value *updates);
exteria_status exteria_updates_sent(exteria_updates *u, int64_t random_id, const exteria_tl_value *updates);
exteria_status exteria_updates_cache(exteria_updates *u, const exteria_tl_value *response);
exteria_status exteria_updates_state(exteria_updates *u, const exteria_tl_value *state);
exteria_status exteria_updates_difference(exteria_updates *u, int64_t channel_id, const exteria_tl_value *difference);
exteria_status exteria_updates_request(exteria_updates *u, int64_t channel_id,
                                      const exteria_tl_value *input_channel, exteria_arena *arena,
                                      exteria_tl_value **out);
exteria_status exteria_updates_cache_message(exteria_updates *u, const exteria_tl_value *message);
/* whether the container only carries presence, typing, draft and outbox-read updates, which cannot add a message
   or change an unread count */
int exteria_updates_quiet(const exteria_tl_value *updates);

#endif
