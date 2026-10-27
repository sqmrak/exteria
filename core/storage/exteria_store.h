#ifndef EXTERIA_STORE_H
#define EXTERIA_STORE_H

#include "exteria_tl.h"

typedef struct exteria_store exteria_store;

typedef enum exteria_record_kind {
    EXTERIA_RECORD_USER = 1,
    EXTERIA_RECORD_CHAT,
    EXTERIA_RECORD_DIALOG,
    EXTERIA_RECORD_MESSAGE,
    EXTERIA_RECORD_MEDIA,
    EXTERIA_RECORD_FOLDER,
    EXTERIA_RECORD_DRAFT,
    EXTERIA_RECORD_FILE_JOB,
    /* a message the other side deleted, kept as it was: the same object as a message, under the same chat and id */
    EXTERIA_RECORD_DELETED_MESSAGE,
    /* what a message said before an edit; the id is the id of the message times a thousand plus the number of the version, 1 for the oldest */
    EXTERIA_RECORD_MESSAGE_EDIT
} exteria_record_kind;

#define EXTERIA_EDIT_VERSIONS 1000

typedef struct exteria_peer {
    int32_t kind;
    int64_t id;
} exteria_peer;

typedef struct exteria_cursor {
    int32_t pts;
    int32_t qts;
    int32_t seq;
    int32_t date;
} exteria_cursor;

typedef enum exteria_outbox_state {
    EXTERIA_OUTBOX_PENDING = 0,
    EXTERIA_OUTBOX_SENDING,
    EXTERIA_OUTBOX_SENT,
    EXTERIA_OUTBOX_FAILED
} exteria_outbox_state;

typedef struct exteria_outbox_item {
    int64_t random_id;
    exteria_peer peer;
    int32_t server_id;
    exteria_outbox_state state;
    int32_t error;
    const exteria_tl_value *request;
} exteria_outbox_item;

typedef exteria_status (*exteria_record_visit)(void *ctx, int64_t id, const exteria_tl_value *value);

exteria_status exteria_store_open(exteria_store **out, const char *path, int64_t account_id);
exteria_status exteria_store_close(exteria_store *s);
exteria_status exteria_store_begin(exteria_store *s);
exteria_status exteria_store_commit(exteria_store *s);
exteria_status exteria_store_rollback(exteria_store *s);
exteria_status exteria_store_cursor_get(exteria_store *s, int64_t channel_id, exteria_cursor *out);
exteria_status exteria_store_cursor_put(exteria_store *s, int64_t channel_id, const exteria_cursor *value);
exteria_status exteria_store_put(exteria_store *s, exteria_record_kind kind, exteria_peer peer,
                                int64_t id, const exteria_tl_value *value);
exteria_status exteria_store_get(exteria_store *s, exteria_record_kind kind, exteria_peer peer,
                                int64_t id, exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_store_delete(exteria_store *s, exteria_record_kind kind, exteria_peer peer, int64_t id);
exteria_status exteria_store_delete_common_message(exteria_store *s, int32_t id);
/* puts a record under another kind, replacing one that is there; EXTERIA_E_NOTFOUND when the first is not */
exteria_status exteria_store_move(exteria_store *s, exteria_record_kind from, exteria_record_kind to, exteria_peer peer, int64_t id);
/* the chat of a message of the common numbering (a private chat or a basic group), which updateDeleteMessages names by its id alone; EXTERIA_E_NOTFOUND when the
   store has no such message */
exteria_status exteria_store_find_common_message(exteria_store *s, int32_t id, exteria_peer *peer);
/* how many records of the kind the account has, and the removal of all of them */
exteria_status exteria_store_count(exteria_store *s, exteria_record_kind kind, int64_t *count);
exteria_status exteria_store_clear(exteria_store *s, exteria_record_kind kind);
exteria_status exteria_store_page(exteria_store *s, exteria_record_kind kind, exteria_peer peer,
                                 int64_t before_id, uint32_t limit, exteria_record_visit visit, void *ctx);
exteria_status exteria_store_outbox_add(exteria_store *s, exteria_peer peer, const exteria_tl_value *request);
exteria_status exteria_store_outbox_next(exteria_store *s, exteria_arena *arena, exteria_outbox_item *out);
exteria_status exteria_store_outbox_set(exteria_store *s, int64_t random_id, exteria_outbox_state state,
                                       int32_t server_id, int32_t error);
exteria_status exteria_store_outbox_recover(exteria_store *s);
exteria_status exteria_store_journal_add(exteria_store *s, const exteria_tl_value *value);
exteria_status exteria_store_journal_page(exteria_store *s, int64_t after_id, uint32_t limit,
                                         exteria_record_visit visit, void *ctx);
exteria_status exteria_store_journal_ack(exteria_store *s, int64_t through_id);
/* a number that grows whenever a write could change what a reader of the chat's records sees: a record of the
   chat, a user or chat record (names and photos), or a sweep over every chat */
uint64_t exteria_store_peer_version(const exteria_store *s, exteria_peer peer);
exteria_status exteria_peer_from_tl(const exteria_tl_value *value, exteria_peer *out);

#endif
