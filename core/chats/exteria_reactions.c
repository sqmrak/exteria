#include "exteria_reactions.h"

#include <string.h>

#include "exteria_messages.h"
#include "exteria_store.h"
#include "exteria_tl_ids.h"

static int valid_utf8(const uint8_t *data, size_t len) {
    size_t i = 0;
    while (i < len) {
        uint32_t cp;
        unsigned n, j;
        uint8_t c = data[i++];
        if (c < 0x80u) { if (c < 0x20u || c == 0x7fu) return 0; continue; }
        if (c >= 0xc2u && c <= 0xdfu) { cp = c & 0x1fu; n = 1; }
        else if (c >= 0xe0u && c <= 0xefu) { cp = c & 0x0fu; n = 2; }
        else if (c >= 0xf0u && c <= 0xf4u) { cp = c & 7u; n = 3; }
        else return 0;
        if (n > len - i) return 0;
        for (j = 0; j < n; ++j) {
            c = data[i++];
            if ((c & 0xc0u) != 0x80u) return 0;
            cp = (cp << 6) | (c & 0x3fu);
        }
        if ((n == 2 && cp < 0x800u) || (n == 3 && cp < 0x10000u) ||
            (cp >= 0xd800u && cp <= 0xdfffu) || cp > 0x10ffffu) return 0;
    }
    return 1;
}

static exteria_status read_emoji(const exteria_tl_value *v, const char *field, exteria_reaction *out) {
    const uint8_t *data;
    size_t len;
    if (exteria_tl_get_bytes(v, field, &data, &len) != EXTERIA_OK || !len ||
        len >= sizeof(out->emoji) || !data || !valid_utf8(data, len)) return EXTERIA_E_MALFORMED;
    out->kind = EXTERIA_REACTION_EMOJI;
    memcpy(out->emoji, data, len);
    out->emoji[len] = 0;
    return EXTERIA_OK;
}

static exteria_status read_reaction(const exteria_tl_value *v, exteria_reaction *out) {
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(v, EXTERIA_TL_ID_reactionEmoji)) return read_emoji(v, "emoticon", out);
    if (exteria_tl_is(v, EXTERIA_TL_ID_reactionCustomEmoji)) {
        if (exteria_tl_get_i64(v, "document_id", &out->document_id) != EXTERIA_OK || out->document_id <= 0)
            return EXTERIA_E_MALFORMED;
        out->kind = EXTERIA_REACTION_CUSTOM;
        return EXTERIA_OK;
    }
    if (exteria_tl_is(v, EXTERIA_TL_ID_reactionPaid)) {
        out->kind = EXTERIA_REACTION_PAID;
        return EXTERIA_OK;
    }
    return EXTERIA_E_MALFORMED;
}

exteria_status exteria_reaction_parse(const exteria_tl_value *value, exteria_reaction *out) {
    if (!out) return EXTERIA_E_ARG;
    return read_reaction(value, out);
}

int exteria_reaction_equal(const exteria_reaction *a, const exteria_reaction *b) {
    if (!a || !b || a->kind != b->kind) return 0;
    if (a->kind == EXTERIA_REACTION_EMOJI) return !strncmp(a->emoji, b->emoji, sizeof(a->emoji));
    if (a->kind == EXTERIA_REACTION_CUSTOM) return a->document_id == b->document_id;
    return a->kind == EXTERIA_REACTION_PAID;
}

exteria_status exteria_reaction_people_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id,
                                               const char *offset, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out || message_id <= 0 || (offset && strlen(offset) >= EXTERIA_REACTION_OFFSET_MAX)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.getMessageReactionsList");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "id", message_id);
    if (status == EXTERIA_OK && offset && offset[0]) status = exteria_tl_set_str(arena, request, "offset", offset);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", EXTERIA_REACTION_PEOPLE_PAGE);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_reaction_people_parse(const exteria_tl_value *answer, exteria_reaction_person *rows, size_t capacity,
                                             size_t *count, char *next, size_t next_capacity) {
    const exteria_tl_value *items;
    const uint8_t *offset;
    size_t length;
    if (count) *count = 0;
    if (next && next_capacity) next[0] = 0;
    if (!rows || !capacity || !count || !next || !next_capacity) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_messageReactionsList) || exteria_tl_get_vec(answer, "reactions", &items) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    if (items->u.vec.count > capacity || items->u.vec.count > EXTERIA_REACTION_PEOPLE_PAGE) return EXTERIA_E_LIMIT;
    if (exteria_tl_has(answer, "next_offset")) {
        if (exteria_tl_get_bytes(answer, "next_offset", &offset, &length) != EXTERIA_OK || !offset || !length || length >= next_capacity ||
            length >= EXTERIA_REACTION_OFFSET_MAX || memchr(offset, 0, length) || !valid_utf8(offset, length)) return EXTERIA_E_MALFORMED;
        memcpy(next, offset, length);
        next[length] = 0;
    }
    for (uint32_t i = 0; i < items->u.vec.count; ++i) {
        const exteria_tl_value *item = items->u.vec.items[i];
        exteria_peer peer;
        exteria_reaction_person row;
        memset(&row, 0, sizeof(row));
        if (!exteria_tl_is(item, EXTERIA_TL_ID_messagePeerReaction) || exteria_peer_from_tl(exteria_tl_get(item, "peer_id"), &peer) != EXTERIA_OK ||
            peer.id <= 0 || exteria_tl_get_i32(item, "date", &row.date) != EXTERIA_OK || row.date < 0 ||
            read_reaction(exteria_tl_get(item, "reaction"), &row.reaction) != EXTERIA_OK) {
            next[0] = 0;
            return EXTERIA_E_MALFORMED;
        }
        row.peer_kind = peer.kind;
        row.peer_id = peer.id;
        rows[i] = row;
    }
    *count = items->u.vec.count;
    return EXTERIA_OK;
}

/* the users in recent_reactions go to the reaction they chose, at most EXTERIA_REACTORS_MAX each and once each; an
   entry of a peer that is not a user, one whose reaction the message does not count, and a malformed one are left
   out */
static void read_reactors(const exteria_tl_value *value, exteria_reactions *reactions) {
    const exteria_tl_value *recent;
    uint32_t i;
    uint8_t j, k;
    if (exteria_tl_get_vec(value, "recent_reactions", &recent) != EXTERIA_OK) return;
    for (i = 0; i < recent->u.vec.count; ++i) {
        const exteria_tl_value *entry = recent->u.vec.items[i], *peer;
        exteria_reaction chosen;
        int64_t user = 0;
        if (!exteria_tl_is(entry, EXTERIA_TL_ID_messagePeerReaction)) continue;
        peer = exteria_tl_get(entry, "peer_id");
        if (!exteria_tl_is(peer, EXTERIA_TL_ID_peerUser) || exteria_tl_get_i64(peer, "user_id", &user) != EXTERIA_OK || user <= 0) continue;
        if (read_reaction(exteria_tl_get(entry, "reaction"), &chosen) != EXTERIA_OK) continue;
        for (j = 0; j < reactions->count; ++j) {
            exteria_reaction *item = &reactions->items[j];
            int seen = 0;
            if (!exteria_reaction_equal(item, &chosen)) continue;
            for (k = 0; k < item->reactor_count; ++k) seen = seen || item->reactors[k] == user;
            if (!seen && item->reactor_count < EXTERIA_REACTORS_MAX) item->reactors[item->reactor_count++] = user;
            break;
        }
    }
}

exteria_status exteria_reactions_read(const exteria_tl_value *value, exteria_reactions *out) {
    exteria_reactions parsed;
    const exteria_tl_value *results;
    uint32_t i, j;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!value) return EXTERIA_OK;
    memset(&parsed, 0, sizeof(parsed));
    if (!exteria_tl_is(value, EXTERIA_TL_ID_messageReactions) ||
        exteria_tl_get_vec(value, "results", &results) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (results->u.vec.count > EXTERIA_REACTIONS_MAX) return EXTERIA_E_LIMIT;
    parsed.min = exteria_tl_has(value, "min") ? 1 : 0;
    for (i = 0; i < results->u.vec.count; ++i) {
        exteria_reaction *r = &parsed.items[parsed.count];
        const exteria_tl_value *v = results->u.vec.items[i];
        if (!exteria_tl_is(v, EXTERIA_TL_ID_reactionCount) ||
            read_reaction(exteria_tl_get(v, "reaction"), r) != EXTERIA_OK ||
            exteria_tl_get_i32(v, "count", &r->count) != EXTERIA_OK || r->count <= 0) return EXTERIA_E_MALFORMED;
        r->chosen = exteria_tl_has(v, "chosen_order") ? 1 : 0;
        if (r->chosen && (exteria_tl_get_i32(v, "chosen_order", &r->chosen_order) != EXTERIA_OK || r->chosen_order < 0))
            return EXTERIA_E_MALFORMED;
        for (j = 0; j < parsed.count; ++j)
            if (exteria_reaction_equal(r, &parsed.items[j])) return EXTERIA_E_MALFORMED;
        ++parsed.count;
    }
    read_reactors(value, &parsed);
    *out = parsed;
    return EXTERIA_OK;
}

exteria_faces exteria_reaction_faces(const exteria_reactions *all, size_t index, int private_chat) {
    const exteria_reaction *r;
    int64_t total = 0;
    size_t i;
    if (!all || index >= all->count) return EXTERIA_FACES_NONE;
    r = &all->items[index];
    if (r->kind == EXTERIA_REACTION_PAID) return EXTERIA_FACES_NONE;
    if (private_chat) {
        if (r->count == 2) return EXTERIA_FACES_SELF_AND_OTHER;
        if (r->count == 1) return r->chosen ? EXTERIA_FACES_SELF : EXTERIA_FACES_OTHER;
        return EXTERIA_FACES_NONE;
    }
    for (i = 0; i < all->count; ++i) total += all->items[i].count;
    if (r->count <= EXTERIA_REACTORS_MAX && total <= EXTERIA_REACTORS_MAX && r->reactor_count == r->count) return EXTERIA_FACES_REACTORS;
    return EXTERIA_FACES_NONE;
}

exteria_status exteria_reaction_catalog_read(const exteria_tl_value *answer, exteria_reaction *items,
                                             size_t cap, size_t *count) {
    const exteria_tl_value *vec;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!items || !count || !cap) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_availableReactions) ||
        exteria_tl_get_vec(answer, "reactions", &vec) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (vec->u.vec.count > EXTERIA_REACTION_CATALOG_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < vec->u.vec.count; ++i) {
        exteria_reaction r;
        const exteria_tl_value *v = vec->u.vec.items[i];
        memset(&r, 0, sizeof(r));
        if (!exteria_tl_is(v, EXTERIA_TL_ID_availableReaction)) return EXTERIA_E_MALFORMED;
        if (exteria_tl_has(v, "inactive") || exteria_tl_has(v, "premium")) continue;
        if (read_emoji(v, "reaction", &r) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        if (n == cap) return EXTERIA_E_LIMIT;
        items[n++] = r;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_reaction_policy_read(const exteria_tl_value *answer, exteria_reactions *allowed, int *all) {
    const exteria_tl_value *full, *policy, *vec;
    uint32_t i;
    if (!allowed || !all) return EXTERIA_E_ARG;
    memset(allowed, 0, sizeof(*allowed));
    *all = 0;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatFull)) return EXTERIA_E_MALFORMED;
    full = exteria_tl_get(answer, "full_chat");
    if (!exteria_tl_is(full, EXTERIA_TL_ID_chatFull) && !exteria_tl_is(full, EXTERIA_TL_ID_channelFull))
        return EXTERIA_E_MALFORMED;
    policy = exteria_tl_get(full, "available_reactions");
    if (!policy || exteria_tl_is(policy, EXTERIA_TL_ID_chatReactionsNone)) return EXTERIA_OK;
    if (exteria_tl_is(policy, EXTERIA_TL_ID_chatReactionsAll)) { *all = 1; return EXTERIA_OK; }
    if (!exteria_tl_is(policy, EXTERIA_TL_ID_chatReactionsSome) ||
        exteria_tl_get_vec(policy, "reactions", &vec) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (vec->u.vec.count > EXTERIA_REACTIONS_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < vec->u.vec.count; ++i) {
        exteria_status status = read_reaction(vec->u.vec.items[i], &allowed->items[i]);
        if (status != EXTERIA_OK) { memset(allowed, 0, sizeof(*allowed)); return status; }
        ++allowed->count;
    }
    return EXTERIA_OK;
}

int exteria_reaction_policy_custom(const exteria_tl_value *answer) {
    const exteria_tl_value *full, *policy;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatFull)) return 0;
    full = exteria_tl_get(answer, "full_chat");
    if (!exteria_tl_is(full, EXTERIA_TL_ID_chatFull) && !exteria_tl_is(full, EXTERIA_TL_ID_channelFull)) return 0;
    policy = exteria_tl_get(full, "available_reactions");
    return exteria_tl_is(policy, EXTERIA_TL_ID_chatReactionsAll) && exteria_tl_has(policy, "allow_custom");
}

exteria_status exteria_reaction_list_request(exteria_arena *arena, int recent, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || limit < 1 || limit > 100) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, recent ? "messages.getRecentReactions" : "messages.getTopReactions");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_reaction_list_read(const exteria_tl_value *answer, exteria_reaction *items, size_t cap, size_t *count) {
    const exteria_tl_value *vec;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!items || !count || !cap) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_reactionsNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_reactions) || exteria_tl_get_vec(answer, "reactions", &vec) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    for (i = 0; i < vec->u.vec.count && n < cap; ++i) {
        exteria_reaction r;
        if (read_reaction(vec->u.vec.items[i], &r) != EXTERIA_OK || r.kind != EXTERIA_REACTION_CUSTOM) continue;
        items[n++] = r;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_reaction_build(exteria_arena *arena, const exteria_reaction *r, exteria_tl_value **out) {
    size_t len;
    *out = NULL;
    if (r->kind == EXTERIA_REACTION_EMOJI) {
        const char *end = memchr(r->emoji, 0, sizeof(r->emoji));
        if (!end) return EXTERIA_E_ARG;
        len = (size_t)(end - r->emoji);
        if (!len || !valid_utf8((const uint8_t *)r->emoji, len)) return EXTERIA_E_ARG;
        *out = exteria_tl_new_obj(arena, "reactionEmoji");
        return *out ? exteria_tl_set_str(arena, *out, "emoticon", r->emoji) : EXTERIA_E_NOMEM;
    }
    if (r->kind == EXTERIA_REACTION_CUSTOM && r->document_id > 0) {
        *out = exteria_tl_new_obj(arena, "reactionCustomEmoji");
        return *out ? exteria_tl_set_i64(arena, *out, "document_id", r->document_id) : EXTERIA_E_NOMEM;
    }
    return EXTERIA_E_ARG;
}

exteria_status exteria_send_reactions_request(exteria_arena *arena, const exteria_peer_ref *peer,
                                              int32_t id, const exteria_reaction *items, size_t count,
                                              exteria_tl_value **out) {
    exteria_tl_value *input, *request, *vec;
    exteria_status status;
    size_t i, j;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || id <= 0 || count > EXTERIA_REACTIONS_MAX || (count && !items)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.sendReaction");
    vec = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!request || !vec) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", id);
    for (i = 0; status == EXTERIA_OK && i < count; ++i) {
        exteria_tl_value *r;
        for (j = 0; j < i; ++j) if (exteria_reaction_equal(&items[i], &items[j])) return EXTERIA_E_ARG;
        status = exteria_reaction_build(arena, &items[i], &r);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(vec, (uint32_t)i, r);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "reaction", vec);
    if (status == EXTERIA_OK && count) status = exteria_tl_set_flag(request, "add_to_recent");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_get_reactions_request(exteria_arena *arena, const exteria_peer_ref *peer,
                                             const int32_t *ids, size_t count, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    size_t i;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !ids || !count || count > EXTERIA_MESSAGES_MAX) return EXTERIA_E_ARG;
    for (i = 0; i < count; ++i) if (ids[i] <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.getMessagesReactions");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32_vec(arena, request, "id", ids, (uint32_t)count);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_reaction_update_read(const exteria_tl_value *updates, int32_t peer_kind, int64_t peer_id,
                                            int32_t message_id, exteria_reactions *out) {
    const exteria_tl_value *vec = NULL, *one = NULL;
    uint32_t count, i;
    exteria_status found = EXTERIA_E_NOTFOUND;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!updates || peer_kind < 1 || peer_kind > 3 || peer_id <= 0 || message_id <= 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(updates, EXTERIA_TL_ID_updateShort)) {
        one = exteria_tl_get(updates, "update");
        if (!one) return EXTERIA_E_MALFORMED;
        count = 1;
    } else if (exteria_tl_is(updates, EXTERIA_TL_ID_updates) || exteria_tl_is(updates, EXTERIA_TL_ID_updatesCombined)) {
        if (exteria_tl_get_vec(updates, "updates", &vec) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        count = vec->u.vec.count;
        if (count > 4096) return EXTERIA_E_LIMIT;
    } else if (exteria_tl_is(updates, EXTERIA_TL_ID_updatesTooLong)) return EXTERIA_E_RETRY;
    else return EXTERIA_E_MALFORMED;
    for (i = 0; i < count; ++i) {
        const exteria_tl_value *update = one ? one : vec->u.vec.items[i];
        exteria_peer peer;
        exteria_reactions parsed;
        int32_t id;
        exteria_status status;
        if (!exteria_tl_is(update, EXTERIA_TL_ID_updateMessageReactions)) continue;
        if (exteria_peer_from_tl(exteria_tl_get(update, "peer"), &peer) != EXTERIA_OK ||
            exteria_tl_get_i32(update, "msg_id", &id) != EXTERIA_OK || id <= 0) return EXTERIA_E_MALFORMED;
        if (peer.kind != peer_kind || peer.id != peer_id || id != message_id) continue;
        if (!exteria_tl_get(update, "reactions")) return EXTERIA_E_MALFORMED;
        status = exteria_reactions_read(exteria_tl_get(update, "reactions"), &parsed);
        if (status != EXTERIA_OK) { memset(out, 0, sizeof(*out)); return status; }
        *out = parsed;
        found = EXTERIA_OK;
    }
    return found;
}

exteria_status exteria_reactions_merge_min(exteria_tl_value *incoming, const exteria_tl_value *previous) {
    exteria_reactions next, old;
    const exteria_tl_value *results, *old_results;
    uint32_t i, j;
    exteria_status status = exteria_reactions_read(incoming, &next);
    if (status != EXTERIA_OK || !incoming || !next.min) return status;
    status = exteria_reactions_read(previous, &old);
    if (status != EXTERIA_OK) return status;
    results = exteria_tl_get(incoming, "results");
    old_results = exteria_tl_get(previous, "results");
    for (i = 0; i < next.count; ++i) {
        for (j = 0; j < old.count; ++j) {
            if (old.items[j].chosen && exteria_reaction_equal(&next.items[i], &old.items[j])) {
                status = exteria_tl_set(results->u.vec.items[i], "chosen_order",
                    (exteria_tl_value *)exteria_tl_get(old_results->u.vec.items[j], "chosen_order"));
                if (status != EXTERIA_OK) return status;
                break;
            }
        }
    }
    return EXTERIA_OK;
}
