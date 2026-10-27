#ifndef EXTERIA_BOOKMARKS_H
#define EXTERIA_BOOKMARKS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

#define EXTERIA_BOOKMARKS_MAX 200
#define EXTERIA_BOOKMARK_TITLE_MAX 96
#define EXTERIA_BOOKMARK_TEXT_MAX 120
#define EXTERIA_BOOKMARKS_FILE_MAX (20u + EXTERIA_BOOKMARKS_MAX * 252u)

/* a message the person marked to find again: where it is, enough to open its chat, and a line to recognise it by */
typedef struct exteria_bookmark {
    int32_t peer_kind;      /* 1 user, 2 chat, 3 channel */
    int64_t peer_id;
    int64_t peer_hash;      /* the access hash an input peer needs; zero for a basic group */
    int32_t dialog_kind;    /* exteria_dialog_kind of the chat, so the chat opens as the kind it is */
    int32_t message_id;
    int32_t date;           /* when the message was sent */
    int32_t added;          /* when it was bookmarked, unix seconds */
    char title[EXTERIA_BOOKMARK_TITLE_MAX];     /* the chat's name, UTF-8 */
    char text[EXTERIA_BOOKMARK_TEXT_MAX];       /* the start of the message, UTF-8, or the word for its media */
} exteria_bookmark;

/* newest first; the list holds at most EXTERIA_BOOKMARKS_MAX and drops the oldest beyond it */
typedef struct exteria_bookmarks {
    size_t count;
    exteria_bookmark items[EXTERIA_BOOKMARKS_MAX];
} exteria_bookmarks;

void exteria_bookmarks_init(exteria_bookmarks *list);
/* puts the entry first; one that is already there (same chat and message) is replaced and moves to the front
   instead of appearing twice */
exteria_status exteria_bookmarks_add(exteria_bookmarks *list, const exteria_bookmark *entry);
/* EXTERIA_E_NOTFOUND when the message was not bookmarked */
exteria_status exteria_bookmarks_remove(exteria_bookmarks *list, int32_t peer_kind, int64_t peer_id, int32_t message_id);
int exteria_bookmarks_contains(const exteria_bookmarks *list, int32_t peer_kind, int64_t peer_id, int32_t message_id);

/* a file for one account: a header with its id, then the entries. cap must be EXTERIA_BOOKMARKS_FILE_MAX or what the list needs */
exteria_status exteria_bookmarks_pack(const exteria_bookmarks *list, int64_t account_id, uint8_t *out, size_t cap, size_t *len);
/* EXTERIA_E_MALFORMED for a file that is not whole or has an entry that add would refuse */
exteria_status exteria_bookmarks_unpack(const uint8_t *data, size_t len, int64_t account_id, exteria_bookmarks *out);

#endif
