#include "exteria_bookmarks.h"

#include <string.h>

#define MAGIC "EXBK"
#define VERSION 1u
#define HEADER 20u
#define RECORD 252u

static int terminated(const char *text, size_t cap) {
    return memchr(text, 0, cap) != NULL;
}

static int valid(const exteria_bookmark *e) {
    return e && e->peer_kind >= 1 && e->peer_kind <= 3 && e->peer_id > 0 && e->message_id > 0 &&
           terminated(e->title, sizeof(e->title)) && terminated(e->text, sizeof(e->text));
}

static int same(const exteria_bookmark *e, int32_t kind, int64_t peer, int32_t message) {
    return e->peer_kind == kind && e->peer_id == peer && e->message_id == message;
}

void exteria_bookmarks_init(exteria_bookmarks *list) {
    if (list) memset(list, 0, sizeof(*list));
}

static size_t index_of(const exteria_bookmarks *list, int32_t kind, int64_t peer, int32_t message) {
    size_t i;
    for (i = 0; i < list->count; ++i) if (same(&list->items[i], kind, peer, message)) return i;
    return list->count;
}

exteria_status exteria_bookmarks_add(exteria_bookmarks *list, const exteria_bookmark *entry) {
    size_t at;
    if (!list || !valid(entry) || list->count > EXTERIA_BOOKMARKS_MAX) return EXTERIA_E_ARG;
    at = index_of(list, entry->peer_kind, entry->peer_id, entry->message_id);
    if (at == list->count) {
        /* a new one makes room at the front, and the oldest goes when the list is full */
        if (list->count < EXTERIA_BOOKMARKS_MAX) ++list->count;
        at = list->count - 1;
    }
    memmove(&list->items[1], &list->items[0], at * sizeof(list->items[0]));
    list->items[0] = *entry;
    return EXTERIA_OK;
}

exteria_status exteria_bookmarks_remove(exteria_bookmarks *list, int32_t peer_kind, int64_t peer_id, int32_t message_id) {
    size_t at;
    if (!list) return EXTERIA_E_ARG;
    at = index_of(list, peer_kind, peer_id, message_id);
    if (at == list->count) return EXTERIA_E_NOTFOUND;
    memmove(&list->items[at], &list->items[at + 1], (list->count - at - 1) * sizeof(list->items[0]));
    --list->count;
    memset(&list->items[list->count], 0, sizeof(list->items[0]));
    return EXTERIA_OK;
}

int exteria_bookmarks_contains(const exteria_bookmarks *list, int32_t peer_kind, int64_t peer_id, int32_t message_id) {
    return list && index_of(list, peer_kind, peer_id, message_id) < list->count;
}

static void put32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

static void put64(uint8_t *p, uint64_t v) {
    put32(p, (uint32_t)v);
    put32(p + 4, (uint32_t)(v >> 32));
}

static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t get64(const uint8_t *p) {
    return (uint64_t)get32(p) | ((uint64_t)get32(p + 4) << 32);
}

exteria_status exteria_bookmarks_pack(const exteria_bookmarks *list, int64_t account_id, uint8_t *out, size_t cap, size_t *len) {
    size_t i, need;
    if (len) *len = 0;
    if (!list || !out || !len || account_id <= 0 || list->count > EXTERIA_BOOKMARKS_MAX) return EXTERIA_E_ARG;
    need = HEADER + list->count * RECORD;
    if (cap < need) return EXTERIA_E_LIMIT;
    memset(out, 0, need);
    memcpy(out, MAGIC, 4);
    put32(out + 4, VERSION);
    put32(out + 8, (uint32_t)list->count);
    put64(out + 12, (uint64_t)account_id);
    for (i = 0; i < list->count; ++i) {
        const exteria_bookmark *e = &list->items[i];
        uint8_t *p = out + HEADER + i * RECORD;
        if (!valid(e)) return EXTERIA_E_ARG;
        put32(p, (uint32_t)e->peer_kind);
        put64(p + 4, (uint64_t)e->peer_id);
        put64(p + 12, (uint64_t)e->peer_hash);
        put32(p + 20, (uint32_t)e->dialog_kind);
        put32(p + 24, (uint32_t)e->message_id);
        put32(p + 28, (uint32_t)e->date);
        put32(p + 32, (uint32_t)e->added);
        memcpy(p + 36, e->title, sizeof(e->title));
        memcpy(p + 36 + sizeof(e->title), e->text, sizeof(e->text));
    }
    *len = need;
    return EXTERIA_OK;
}

exteria_status exteria_bookmarks_unpack(const uint8_t *data, size_t len, int64_t account_id, exteria_bookmarks *out) {
    uint32_t count, i;
    if (out) exteria_bookmarks_init(out);
    if (!data || !out || account_id <= 0) return EXTERIA_E_ARG;
    if (len < HEADER || memcmp(data, MAGIC, 4) != 0 || get32(data + 4) != VERSION) return EXTERIA_E_MALFORMED;
    count = get32(data + 8);
    if (count > EXTERIA_BOOKMARKS_MAX || len != HEADER + (size_t)count * RECORD) return EXTERIA_E_MALFORMED;
    if ((int64_t)get64(data + 12) != account_id) return EXTERIA_E_NOTFOUND;
    for (i = 0; i < count; ++i) {
        const uint8_t *p = data + HEADER + (size_t)i * RECORD;
        exteria_bookmark *e = &out->items[i];
        e->peer_kind = (int32_t)get32(p);
        e->peer_id = (int64_t)get64(p + 4);
        e->peer_hash = (int64_t)get64(p + 12);
        e->dialog_kind = (int32_t)get32(p + 20);
        e->message_id = (int32_t)get32(p + 24);
        e->date = (int32_t)get32(p + 28);
        e->added = (int32_t)get32(p + 32);
        memcpy(e->title, p + 36, sizeof(e->title));
        memcpy(e->text, p + 36 + sizeof(e->title), sizeof(e->text));
        if (!valid(e)) {
            exteria_bookmarks_init(out);
            return EXTERIA_E_MALFORMED;
        }
    }
    out->count = count;
    return EXTERIA_OK;
}
