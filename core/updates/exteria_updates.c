#include "exteria_updates.h"

#include <limits.h>
#include <string.h>

#include "exteria_tl_ids.h"
#include "exteria_reactions.h"

#define UPDATE_MAX 4096u

static void select_gap(exteria_updates *u) {
    u->needs_difference = u->global_gap || u->channel_count;
    u->gap_channel = u->global_gap || !u->channel_count ? 0 : u->channels[0];
}

exteria_status exteria_updates_need(exteria_updates *u, int64_t channel_id) {
    uint32_t i;
    if (!u || channel_id < 0) return EXTERIA_E_ARG;
    if (!channel_id) u->global_gap = 1;
    else {
        for (i = 0; i < u->channel_count; ++i) if (u->channels[i] == channel_id) return EXTERIA_OK;
        if (u->channel_count == 128) return EXTERIA_E_LIMIT;
        u->channels[u->channel_count++] = channel_id;
    }
    select_gap(u);
    return EXTERIA_OK;
}

static exteria_status gap(exteria_updates *u, int64_t channel_id) {
    exteria_status status = exteria_updates_need(u, channel_id);
    if (status == EXTERIA_OK && channel_id) status = exteria_updates_need(u, 0);
    return status == EXTERIA_OK ? EXTERIA_E_RETRY : status;
}

static exteria_status cursor_read(exteria_updates *u, int64_t channel, exteria_cursor *c) {
    exteria_status status = exteria_store_cursor_get(u->store, channel, c);
    return status == EXTERIA_E_NOTFOUND ? EXTERIA_OK : status;
}

static exteria_status cursor_value(const exteria_tl_value *v, exteria_cursor *c) {
    memset(c, 0, sizeof(*c));
    if (exteria_tl_get_i32(v, "pts", &c->pts) != EXTERIA_OK ||
        exteria_tl_get_i32(v, "qts", &c->qts) != EXTERIA_OK ||
        exteria_tl_get_i32(v, "seq", &c->seq) != EXTERIA_OK ||
        exteria_tl_get_i32(v, "date", &c->date) != EXTERIA_OK ||
        c->pts < 0 || c->qts < 0 || c->seq < 0 || c->date < 0) return EXTERIA_E_MALFORMED;
    return EXTERIA_OK;
}

static exteria_status transaction_end(exteria_updates *u, exteria_status status) {
    exteria_status cleanup;
    if (status == EXTERIA_OK) {
        status = exteria_store_commit(u->store);
        if (status == EXTERIA_OK) return status;
    }
    cleanup = exteria_store_rollback(u->store);
    return cleanup == EXTERIA_OK ? status : cleanup;
}

exteria_status exteria_updates_init(exteria_updates *u, exteria_store *store, int64_t account_id) {
    exteria_cursor c;
    exteria_status status;
    if (!u || !store || account_id <= 0) return EXTERIA_E_ARG;
    memset(u, 0, sizeof(*u));
    u->store = store;
    u->account = account_id;
    status = exteria_store_cursor_get(store, 0, &c);
    u->needs_difference = 1;
    u->global_gap = 1;
    return status == EXTERIA_E_NOTFOUND ? EXTERIA_OK : status;
}

/* the highest version the message has, found as the newest record below the next message's numbers */
static exteria_status newest_version(void *ctx, int64_t id, const exteria_tl_value *value) {
    (void)value;
    *(int64_t *)ctx = id;
    return EXTERIA_OK;
}

/* the text of a message before an edit stays as a version of it: the stored object goes under the kind of the versions, numbered after the ones that are there */
static exteria_status keep_edit(exteria_updates *u, const exteria_tl_value *m, exteria_peer peer, int32_t id) {
    exteria_arena arena;
    exteria_tl_value *previous = NULL;
    const uint8_t *old_text = NULL, *new_text = NULL;
    size_t old_len = 0, new_len = 0;
    int32_t old_edit = 0, new_edit = 0;
    int64_t base = (int64_t)id * EXTERIA_EDIT_VERSIONS, top = 0;
    exteria_status status;
    /* only a message that carries an edit date was edited; the same message from a page of history does not */
    if (!exteria_tl_has(m, "edit_date")) return EXTERIA_OK;
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    status = exteria_store_get(u->store, EXTERIA_RECORD_MESSAGE, peer, id, &arena, &previous);
    if (status == EXTERIA_E_NOTFOUND) {
        exteria_arena_free(&arena);
        return EXTERIA_OK;
    }
    if (status == EXTERIA_OK) {
        exteria_tl_get_bytes(previous, "message", &old_text, &old_len);
        exteria_tl_get_bytes(m, "message", &new_text, &new_len);
        if (exteria_tl_has(previous, "edit_date")) exteria_tl_get_i32(previous, "edit_date", &old_edit);
        exteria_tl_get_i32(m, "edit_date", &new_edit);
        /* the same words, or an older copy, are not a new version */
        if ((old_len == new_len && (!old_len || memcmp(old_text, new_text, old_len) == 0)) || new_edit < old_edit) {
            exteria_arena_free(&arena);
            return EXTERIA_OK;
        }
        status = exteria_store_page(u->store, EXTERIA_RECORD_MESSAGE_EDIT, peer, base + EXTERIA_EDIT_VERSIONS, 1, newest_version, &top);
    }
    if (status == EXTERIA_OK) {
        int64_t version = top > base ? top - base + 1 : 1;
        if (version < EXTERIA_EDIT_VERSIONS) status = exteria_store_put(u->store, EXTERIA_RECORD_MESSAGE_EDIT, peer, base + version, previous);
    }
    exteria_arena_free(&arena);
    return status;
}

exteria_status exteria_updates_cache_message(exteria_updates *u, const exteria_tl_value *m) {
    exteria_peer peer;
    int32_t id;
    exteria_status status;
    if (!u || !m) return EXTERIA_E_ARG;
    if (exteria_tl_get_i32(m, "id", &id) != EXTERIA_OK || id <= 0) return EXTERIA_E_MALFORMED;
    status = exteria_peer_from_tl(exteria_tl_get(m, "peer_id"), &peer);
    if (status != EXTERIA_OK) return status;
    if (u->keep & EXTERIA_KEEP_EDITS) {
        status = keep_edit(u, m, peer, id);
        if (status != EXTERIA_OK) return status;
    }
    if (exteria_tl_has(exteria_tl_get(m, "reactions"), "min")) {
        exteria_arena arena;
        exteria_writer encoded;
        exteria_tl_value *previous = NULL, *copy = NULL;
        exteria_arena_init(&arena, 16u * 1024u * 1024u);
        status = exteria_store_get(u->store, EXTERIA_RECORD_MESSAGE, peer, id, &arena, &previous);
        if (status == EXTERIA_E_NOTFOUND) status = EXTERIA_OK;
        exteria_writer_init(&encoded, 1024u * 1024u);
        if (status == EXTERIA_OK) status = exteria_tl_encode(m, &encoded, NULL);
        if (status == EXTERIA_OK) status = exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY,
            encoded.data, encoded.len, &copy);
        if (status == EXTERIA_OK) status = exteria_reactions_merge_min((exteria_tl_value *)exteria_tl_get(copy, "reactions"),
            exteria_tl_get(previous, "reactions"));
        if (status == EXTERIA_OK) status = exteria_store_put(u->store, EXTERIA_RECORD_MESSAGE, peer, id, copy);
        exteria_writer_free(&encoded);
        exteria_arena_free(&arena);
        return status;
    }
    return exteria_store_put(u->store, EXTERIA_RECORD_MESSAGE, peer, id, m);
}

/* whether AyuMoments keeps what is deleted in this chat: a private chat, a group, a channel, or a chat with a bot, each by its own switch */
static int keeps_deleted_in(exteria_updates *u, exteria_peer peer) {
    exteria_arena arena;
    exteria_tl_value *record = NULL;
    uint32_t wanted;
    exteria_peer holder = {0, 0};
    if (!(u->keep & EXTERIA_KEEP_DELETED)) return 0;
    if (peer.kind == 2) return (u->keep & EXTERIA_KEEP_GROUPS) != 0;
    exteria_arena_init(&arena, 1024u * 1024u);
    if (peer.kind == 1) {
        wanted = EXTERIA_KEEP_PRIVATE;
        if (exteria_store_get(u->store, EXTERIA_RECORD_USER, holder, peer.id, &arena, &record) == EXTERIA_OK && exteria_tl_has(record, "bot")) wanted = EXTERIA_KEEP_BOTS;
    } else {
        /* a channel is a broadcast or a supergroup, and the chat record knows which */
        wanted = EXTERIA_KEEP_GROUPS;
        if (exteria_store_get(u->store, EXTERIA_RECORD_CHAT, peer, peer.id, &arena, &record) == EXTERIA_OK && exteria_tl_has(record, "broadcast")) wanted = EXTERIA_KEEP_CHANNELS;
    }
    exteria_arena_free(&arena);
    return (u->keep & wanted) != 0;
}

/* a message the server says is gone: it is removed from the chat, or kept under the kind of the deleted ones when
   the person asked for that */
static exteria_status delete_message(exteria_updates *u, const exteria_peer *channel, int32_t id) {
    exteria_peer peer;
    exteria_status status;
    if (channel) peer = *channel;
    else {
        status = exteria_store_find_common_message(u->store, id, &peer);
        if (status == EXTERIA_E_NOTFOUND) return EXTERIA_OK;
        if (status != EXTERIA_OK) return status;
    }
    if (keeps_deleted_in(u, peer)) {
        status = exteria_store_move(u->store, EXTERIA_RECORD_MESSAGE, EXTERIA_RECORD_DELETED_MESSAGE, peer, id);
        return status == EXTERIA_E_NOTFOUND ? EXTERIA_OK : status;
    }
    return channel ? exteria_store_delete(u->store, EXTERIA_RECORD_MESSAGE, peer, id) : exteria_store_delete_common_message(u->store, id);
}

static exteria_status cache_vector(exteria_updates *u, const exteria_tl_value *v, const char *field,
                                  exteria_record_kind kind) {
    const exteria_tl_value *vec = exteria_tl_get(v, field);
    uint32_t i;
    if (!vec) return EXTERIA_OK;
    if (vec->kind != EXTERIA_TL_V_VEC || vec->u.vec.count > UPDATE_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < vec->u.vec.count; ++i) {
        const exteria_tl_value *item = vec->u.vec.items[i];
        exteria_status status;
        exteria_peer peer = {0, 0};
        int64_t id;
        if (kind == EXTERIA_RECORD_MESSAGE) status = exteria_updates_cache_message(u, item);
        else {
            if (exteria_tl_get_i64(item, "id", &id) != EXTERIA_OK || id <= 0) return EXTERIA_E_MALFORMED;
            if (kind == EXTERIA_RECORD_CHAT) {
                peer.kind = exteria_tl_is(item, EXTERIA_TL_ID_channel) || exteria_tl_is(item, EXTERIA_TL_ID_channelForbidden) ||
                            exteria_tl_is(item, EXTERIA_TL_ID_community) || exteria_tl_is(item, EXTERIA_TL_ID_communityForbidden) ? 3 : 2;
                peer.id = id;
            }
            /* a user or channel seen in part (min) has no access hash that works for this account and no photo the account can fetch; it is left out when the store holds the
               whole object, or the photo of everyone who ever showed up in a group as a stub would vanish */
            if ((kind == EXTERIA_RECORD_USER || kind == EXTERIA_RECORD_CHAT) && exteria_tl_has(item, "min")) {
                exteria_arena arena;
                exteria_tl_value *held = NULL;
                int whole;
                exteria_arena_init(&arena, 1024u * 1024u);
                whole = exteria_store_get(u->store, kind, peer, id, &arena, &held) == EXTERIA_OK && held && !exteria_tl_has(held, "min");
                exteria_arena_free(&arena);
                if (whole) continue;
            }
            status = exteria_store_put(u->store, kind, peer, id, item);
        }
        if (status != EXTERIA_OK) return status;
    }
    return EXTERIA_OK;
}

static exteria_status update_channel(const exteria_tl_value *v, int64_t *out) {
    const exteria_tl_value *m, *peer;
    *out = 0;
    if (exteria_tl_has(v, "channel_id")) {
        if (exteria_tl_get_i64(v, "channel_id", out) != EXTERIA_OK || *out <= 0) return EXTERIA_E_MALFORMED;
        return EXTERIA_OK;
    }
    m = exteria_tl_get(v, "message");
    peer = exteria_tl_get(m, "peer_id");
    if (exteria_tl_is(peer, EXTERIA_TL_ID_peerChannel)) {
        if (exteria_tl_get_i64(peer, "channel_id", out) != EXTERIA_OK || *out <= 0) return EXTERIA_E_MALFORMED;
    }
    return EXTERIA_OK;
}

static exteria_status short_message(exteria_updates *u, const exteria_tl_value *v) {
    exteria_arena a;
    exteria_tl_value *m, *peer, *from;
    int64_t peer_id, from_id;
    int32_t id, date;
    uint32_t i;
    int chat = exteria_tl_is(v, EXTERIA_TL_ID_updateShortChatMessage);
    static const char *const optional[] = {"out", "mentioned", "media_unread", "silent", "fwd_from",
                                           "via_bot_id", "reply_to", "entities", "ttl_period"};
    exteria_status status;
    if (exteria_tl_get_i64(v, chat ? "chat_id" : "user_id", &peer_id) != EXTERIA_OK || peer_id <= 0 ||
        exteria_tl_get_i32(v, "id", &id) != EXTERIA_OK || id <= 0 ||
        exteria_tl_get_i32(v, "date", &date) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    from_id = exteria_tl_has(v, "out") ? u->account : peer_id;
    if (chat && exteria_tl_get_i64(v, "from_id", &from_id) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    exteria_arena_init(&a, 65536);
    m = exteria_tl_new_obj(&a, "message");
    peer = exteria_tl_new_obj(&a, chat ? "peerChat" : "peerUser");
    from = exteria_tl_new_obj(&a, "peerUser");
    status = m && peer && from ? exteria_tl_set_i64(&a, peer, chat ? "chat_id" : "user_id", peer_id) : EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(&a, from, "user_id", from_id);
    if (status == EXTERIA_OK) status = exteria_tl_set(m, "peer_id", peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(m, "from_id", from);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(&a, m, "id", id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(&a, m, "date", date);
    if (status == EXTERIA_OK) status = exteria_tl_set(m, "message", (exteria_tl_value *)exteria_tl_get(v, "message"));
    for (i = 0; status == EXTERIA_OK && i < sizeof(optional) / sizeof(optional[0]); ++i) {
        const exteria_tl_value *value = exteria_tl_get(v, optional[i]);
        if (value) status = exteria_tl_set(m, optional[i], (exteria_tl_value *)value);
    }
    if (status == EXTERIA_OK) status = exteria_updates_cache_message(u, m);
    exteria_arena_free(&a);
    return status;
}

static exteria_status apply_reactions(exteria_updates *u, const exteria_tl_value *v) {
    exteria_peer peer;
    int32_t id;
    exteria_arena arena;
    exteria_tl_value *message = NULL;
    exteria_tl_value *reactions = (exteria_tl_value *)exteria_tl_get(v, "reactions");
    exteria_reactions parsed;
    exteria_status status;
    if (exteria_peer_from_tl(exteria_tl_get(v, "peer"), &peer) != EXTERIA_OK ||
        exteria_tl_get_i32(v, "msg_id", &id) != EXTERIA_OK || id <= 0 || !reactions) return EXTERIA_E_MALFORMED;
    status = exteria_reactions_read(reactions, &parsed);
    if (status != EXTERIA_OK) return status;
    exteria_arena_init(&arena, 8u * 1024u * 1024u);
    status = exteria_store_get(u->store, EXTERIA_RECORD_MESSAGE, peer, id, &arena, &message);
    /* an update for unloaded history must not create a message without its text and media */
    if (status == EXTERIA_E_NOTFOUND) status = EXTERIA_OK;
    else if (status == EXTERIA_OK) {
        exteria_writer encoded;
        exteria_writer_init(&encoded, 65536);
        status = exteria_tl_encode(reactions, &encoded, NULL);
        if (status == EXTERIA_OK) status = exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY,
            encoded.data, encoded.len, &reactions);
        exteria_writer_free(&encoded);
        if (status == EXTERIA_OK) status = exteria_reactions_merge_min(reactions, exteria_tl_get(message, "reactions"));
        if (status == EXTERIA_OK) status = exteria_tl_set(message, "reactions", reactions);
        if (status == EXTERIA_OK) status = exteria_store_put(u->store, EXTERIA_RECORD_MESSAGE, peer, id, message);
    }
    exteria_arena_free(&arena);
    return status;
}

static exteria_status apply_one(exteria_updates *u, const exteria_tl_value *v, int authoritative,
                               int apply_unordered, exteria_cursor *global) {
    int64_t channel = 0;
    int32_t pts = 0, count = 0, qts = 0;
    int has_pts = exteria_tl_has(v, "pts"), has_qts = exteria_tl_has(v, "qts");
    exteria_cursor local;
    exteria_status status;
    uint32_t id = exteria_tl_id(v);
    if (!id) return EXTERIA_E_MALFORMED;
    status = update_channel(v, &channel);
    if (status != EXTERIA_OK) return status;
    if (id == EXTERIA_TL_ID_updateChannelTooLong) {
        if (!authoritative) return gap(u, channel);
        status = exteria_updates_need(u, channel);
        if (status != EXTERIA_OK) return status;
        return exteria_store_journal_add(u->store, v);
    }
    if (!authoritative) {
        if (has_pts) {
            if (exteria_tl_get_i32(v, "pts", &pts) != EXTERIA_OK || pts < 0) return EXTERIA_E_MALFORMED;
            if (exteria_tl_has(v, "pts_count") &&
                (exteria_tl_get_i32(v, "pts_count", &count) != EXTERIA_OK || count < 0)) return EXTERIA_E_MALFORMED;
            if (channel) {
                status = exteria_store_cursor_get(u->store, channel, &local);
                if (status == EXTERIA_E_NOTFOUND) { return gap(u, channel); }
                if (status != EXTERIA_OK) return status;
            } else local = *global;
            if ((int64_t)local.pts + count > pts) return EXTERIA_OK;
            if ((int64_t)local.pts + count < pts) { return gap(u, channel); }
            local.pts = pts;
            if (channel) {
                status = exteria_store_cursor_put(u->store, channel, &local);
                if (status != EXTERIA_OK) return status;
            } else global->pts = pts;
        } else if (has_qts) {
            if (exteria_tl_get_i32(v, "qts", &qts) != EXTERIA_OK || qts < 0) return EXTERIA_E_MALFORMED;
            if ((int64_t)global->qts + 1 > qts) return EXTERIA_OK;
            if ((int64_t)global->qts + 1 < qts) { return gap(u, 0); }
            global->qts = qts;
        } else if (!apply_unordered) return EXTERIA_OK;
    }
    if (id == EXTERIA_TL_ID_updateNewMessage || id == EXTERIA_TL_ID_updateEditMessage ||
        id == EXTERIA_TL_ID_updateNewChannelMessage || id == EXTERIA_TL_ID_updateEditChannelMessage ||
        id == EXTERIA_TL_ID_updateNewScheduledMessage) {
        status = exteria_updates_cache_message(u, exteria_tl_get(v, "message"));
    } else if (id == EXTERIA_TL_ID_updateShortMessage || id == EXTERIA_TL_ID_updateShortChatMessage) {
        status = short_message(u, v);
    } else if (id == EXTERIA_TL_ID_updateMessageReactions) {
        status = apply_reactions(u, v);
    } else if (id == EXTERIA_TL_ID_updateMessageID) {
        int32_t server_id;
        int64_t random_id;
        if (exteria_tl_get_i32(v, "id", &server_id) != EXTERIA_OK || server_id <= 0 ||
            exteria_tl_get_i64(v, "random_id", &random_id) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        status = exteria_store_outbox_set(u->store, random_id, EXTERIA_OUTBOX_SENT, server_id, 0);
        /* another device's random_id is not in this outbox */
        if (status == EXTERIA_E_NOTFOUND) status = EXTERIA_OK;
    } else if (id == EXTERIA_TL_ID_updateDeleteChannelMessages || id == EXTERIA_TL_ID_updateDeleteMessages) {
        const exteria_tl_value *vec = exteria_tl_get(v, "messages");
        uint32_t i;
        exteria_peer peer = {3, channel};
        if (!vec || vec->kind != EXTERIA_TL_V_VEC || vec->u.vec.count > UPDATE_MAX) return EXTERIA_E_MALFORMED;
        for (i = 0; i < vec->u.vec.count; ++i) {
            const exteria_tl_value *item = vec->u.vec.items[i];
            if (!item || item->kind != EXTERIA_TL_V_I32 || item->u.i32 <= 0) return EXTERIA_E_MALFORMED;
            status = delete_message(u, channel ? &peer : NULL, item->u.i32);
            if (status != EXTERIA_OK) return status;
        }
    } else if (id == EXTERIA_TL_ID_updateDraftMessage) {
        /* the account keeps the draft and the client event shows it live; a journal entry per edit from another phone would only pile up */
        return EXTERIA_OK;
    } else if (id == EXTERIA_TL_ID_updateNotifySettings) {
        /* the settings of the account are read through account.getNotifySettings and getNotifyExceptions, which answer with a list of these, and nothing
           consumes them from the journal */
        return EXTERIA_OK;
    } else status = EXTERIA_OK;
    /* all accepted updates survive a crash until their owning feature consumes the journal */
    if (status == EXTERIA_OK) status = exteria_store_journal_add(u->store, v);
    return status;
}

static exteria_status apply_vector(exteria_updates *u, const exteria_tl_value *v, const char *field,
                                   int authoritative, int unordered, exteria_cursor *global) {
    const exteria_tl_value *vec = exteria_tl_get(v, field);
    uint32_t i;
    if (!vec) return EXTERIA_OK;
    if (vec->kind != EXTERIA_TL_V_VEC || vec->u.vec.count > UPDATE_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < vec->u.vec.count; ++i) {
        exteria_status status = apply_one(u, vec->u.vec.items[i], authoritative, unordered, global);
        if (status != EXTERIA_OK) return status;
    }
    return EXTERIA_OK;
}

static exteria_status apply(exteria_updates *u, const exteria_tl_value *v, int64_t random_id) {
    exteria_cursor c;
    exteria_status status;
    int32_t seq = 0, start = 0, date = 0;
    int unordered = 1;
    uint32_t id;
    if (!u || !v) return EXTERIA_E_ARG;
    id = exteria_tl_id(v);
    if (id == EXTERIA_TL_ID_updatesTooLong) { return gap(u, 0); }
    status = exteria_store_cursor_get(u->store, 0, &c);
    if (status == EXTERIA_E_NOTFOUND) { return gap(u, 0); }
    if (status != EXTERIA_OK) return status;
    if (exteria_tl_has(v, "seq")) {
        if (exteria_tl_get_i32(v, "seq", &seq) != EXTERIA_OK || seq < 0) return EXTERIA_E_MALFORMED;
        start = seq;
        if (exteria_tl_has(v, "seq_start") && exteria_tl_get_i32(v, "seq_start", &start) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        if (start < 0 || start > seq) return EXTERIA_E_MALFORMED;
        if (start && (int64_t)c.seq + 1 > start) unordered = 0;
        if (start && (int64_t)c.seq + 1 < start) { return gap(u, 0); }
    }
    if (exteria_tl_has(v, "date") && (exteria_tl_get_i32(v, "date", &date) != EXTERIA_OK || date < 0)) return EXTERIA_E_MALFORMED;
    status = exteria_store_begin(u->store);
    if (status != EXTERIA_OK) return status;
    status = cache_vector(u, v, "users", EXTERIA_RECORD_USER);
    if (status == EXTERIA_OK) status = cache_vector(u, v, "chats", EXTERIA_RECORD_CHAT);
    if (status == EXTERIA_OK) {
        if (id == EXTERIA_TL_ID_updates || id == EXTERIA_TL_ID_updatesCombined)
            status = apply_vector(u, v, "updates", 0, unordered, &c);
        else if (id == EXTERIA_TL_ID_updateShort) status = apply_one(u, exteria_tl_get(v, "update"), 0, 1, &c);
        else if (id == EXTERIA_TL_ID_updateShortMessage || id == EXTERIA_TL_ID_updateShortChatMessage ||
                 id == EXTERIA_TL_ID_updateShortSentMessage) status = apply_one(u, v, 0, 1, &c);
        else status = EXTERIA_E_UNSUPPORTED;
    }
    if (status == EXTERIA_OK && random_id && id == EXTERIA_TL_ID_updateShortSentMessage) {
        int32_t server_id;
        status = exteria_tl_get_i32(v, "id", &server_id);
        if (status == EXTERIA_OK) status = exteria_store_outbox_set(u->store, random_id, EXTERIA_OUTBOX_SENT, server_id, 0);
    }
    if (status == EXTERIA_OK) {
        if (unordered && seq) c.seq = seq;
        if (date > c.date) c.date = date;
        status = exteria_store_cursor_put(u->store, 0, &c);
    }
    return transaction_end(u, status);
}

exteria_status exteria_updates_state(exteria_updates *u, const exteria_tl_value *state) {
    exteria_cursor c;
    exteria_status status;
    if (!u || !state) return EXTERIA_E_ARG;
    status = cursor_value(state, &c);
    if (status != EXTERIA_OK) return status;
    status = exteria_store_begin(u->store);
    if (status != EXTERIA_OK) return status;
    status = exteria_store_cursor_put(u->store, 0, &c);
    status = transaction_end(u, status);
    if (status == EXTERIA_OK) { u->global_gap = 0; select_gap(u); }
    return status;
}

exteria_status exteria_updates_difference(exteria_updates *u, int64_t channel, const exteria_tl_value *v) {
    exteria_cursor c, next;
    exteria_status status;
    uint32_t id;
    int more = 0, history = 0;
    if (!u || !v || channel < 0) return EXTERIA_E_ARG;
    id = exteria_tl_id(v);
    status = cursor_read(u, channel, &c);
    if (status != EXTERIA_OK) return status;
    next = c;
    if (!channel) {
        if (id == EXTERIA_TL_ID_updates_difference || id == EXTERIA_TL_ID_updates_differenceSlice) {
            more = id == EXTERIA_TL_ID_updates_differenceSlice;
            status = cursor_value(exteria_tl_get(v, more ? "intermediate_state" : "state"), &next);
        } else if (id == EXTERIA_TL_ID_updates_differenceEmpty) {
            if (exteria_tl_get_i32(v, "date", &next.date) != EXTERIA_OK ||
                exteria_tl_get_i32(v, "seq", &next.seq) != EXTERIA_OK) status = EXTERIA_E_MALFORMED;
        } else if (id == EXTERIA_TL_ID_updates_differenceTooLong) {
            status = exteria_tl_get_i32(v, "pts", &next.pts);
            history = 1;
            more = 1;
        } else status = EXTERIA_E_UNSUPPORTED;
    } else {
        if (id == EXTERIA_TL_ID_updates_channelDifferenceTooLong) {
            status = exteria_tl_get_i32(exteria_tl_get(v, "dialog"), "pts", &next.pts);
            history = 1;
        } else if (id == EXTERIA_TL_ID_updates_channelDifference || id == EXTERIA_TL_ID_updates_channelDifferenceEmpty)
            status = exteria_tl_get_i32(v, "pts", &next.pts);
        else status = EXTERIA_E_UNSUPPORTED;
        more = !exteria_tl_has(v, "final");
    }
    if (status != EXTERIA_OK) return status;
    /* the date of the cursor is raised by the date of every container of live updates, which can be later than the
       date the server gives for its state */
    if (next.date < c.date) next.date = c.date;
    if (next.pts < c.pts || next.qts < c.qts || next.seq < c.seq) return EXTERIA_E_MALFORMED;
    status = exteria_store_begin(u->store);
    if (status != EXTERIA_OK) return status;
    status = cache_vector(u, v, "users", EXTERIA_RECORD_USER);
    if (status == EXTERIA_OK) status = cache_vector(u, v, "chats", EXTERIA_RECORD_CHAT);
    if (status == EXTERIA_OK) status = cache_vector(u, v, "new_messages", EXTERIA_RECORD_MESSAGE);
    if (status == EXTERIA_OK) status = cache_vector(u, v, "messages", EXTERIA_RECORD_MESSAGE);
    if (status == EXTERIA_OK) status = apply_vector(u, v, "other_updates", 1, 1, &c);
    if (status == EXTERIA_OK) status = exteria_store_journal_add(u->store, v);
    if (status == EXTERIA_OK) status = exteria_store_cursor_put(u->store, channel, &next);
    status = transaction_end(u, status);
    if (status == EXTERIA_OK) {
        uint32_t i;
        if (!channel) u->global_gap = more;
        else if (!more) {
            for (i = 0; i < u->channel_count; ++i) if (u->channels[i] == channel) {
                memmove(u->channels + i, u->channels + i + 1, (u->channel_count - i - 1u) * sizeof(u->channels[0]));
                --u->channel_count;
                break;
            }
        }
        u->more_difference = more;
        u->needs_history = history;
        select_gap(u);
    }
    return status;
}

exteria_status exteria_updates_request(exteria_updates *u, int64_t channel,
                                      const exteria_tl_value *input_channel, exteria_arena *arena,
                                      exteria_tl_value **out) {
    exteria_cursor c;
    exteria_tl_value *v, *filter;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!u || !arena || channel < 0) return EXTERIA_E_ARG;
    status = exteria_store_cursor_get(u->store, channel, &c);
    if (status != EXTERIA_OK && status != EXTERIA_E_NOTFOUND) return status;
    if (!channel && status == EXTERIA_E_NOTFOUND) {
        v = exteria_tl_new_obj(arena, "updates.getState");
        if (!v) return EXTERIA_E_NOMEM;
    } else if (!channel) {
        v = exteria_tl_new_obj(arena, "updates.getDifference");
        status = v ? exteria_tl_set_i32(arena, v, "pts", c.pts) : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, v, "qts", c.qts);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, v, "date", c.date);
        if (status != EXTERIA_OK) return status;
    } else {
        int64_t id;
        if (exteria_tl_get_i64(input_channel, "channel_id", &id) != EXTERIA_OK || id != channel) return EXTERIA_E_ARG;
        /* a channel without a cursor must first load its dialog pts, zero would skip its history */
        if (status == EXTERIA_E_NOTFOUND) return EXTERIA_E_NOTFOUND;
        v = exteria_tl_new_obj(arena, "updates.getChannelDifference");
        filter = exteria_tl_new_obj(arena, "channelMessagesFilterEmpty");
        status = v && filter ? exteria_tl_set(v, "channel", (exteria_tl_value *)input_channel) : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK) status = exteria_tl_set(v, "filter", filter);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, v, "pts", c.pts);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, v, "limit", 100);
        if (status != EXTERIA_OK) return status;
    }
    *out = v;
    return EXTERIA_OK;
}

exteria_status exteria_updates_apply(exteria_updates *u, const exteria_tl_value *v) {
    return apply(u, v, 0);
}

exteria_status exteria_updates_sent(exteria_updates *u, int64_t random_id, const exteria_tl_value *v) {
    if (!random_id) return EXTERIA_E_ARG;
    return apply(u, v, random_id);
}

exteria_status exteria_updates_cache(exteria_updates *u, const exteria_tl_value *v) {
    exteria_status status;
    const exteria_tl_value *dialogs;
    uint32_t i;
    if (!u || !v) return EXTERIA_E_ARG;
    status = exteria_store_begin(u->store);
    if (status != EXTERIA_OK) return status;
    status = cache_vector(u, v, "users", EXTERIA_RECORD_USER);
    if (status == EXTERIA_OK) status = cache_vector(u, v, "chats", EXTERIA_RECORD_CHAT);
    if (status == EXTERIA_OK) status = cache_vector(u, v, "messages", EXTERIA_RECORD_MESSAGE);
    dialogs = exteria_tl_get(v, "dialogs");
    if (status == EXTERIA_OK && dialogs) {
        if (dialogs->kind != EXTERIA_TL_V_VEC || dialogs->u.vec.count > UPDATE_MAX) status = EXTERIA_E_MALFORMED;
        else for (i = 0; i < dialogs->u.vec.count && status == EXTERIA_OK; ++i) {
            const exteria_tl_value *dialog = dialogs->u.vec.items[i];
            exteria_peer peer;
            status = exteria_peer_from_tl(exteria_tl_get(dialog, "peer"), &peer);
            if (status == EXTERIA_OK) status = exteria_store_put(u->store, EXTERIA_RECORD_DIALOG, peer, peer.id, dialog);
            if (status == EXTERIA_OK && peer.kind == 3 && exteria_tl_has(dialog, "pts")) {
                exteria_cursor c;
                int32_t pts;
                status = cursor_read(u, peer.id, &c);
                if (status == EXTERIA_OK) status = exteria_tl_get_i32(dialog, "pts", &pts);
                /* a cached dialog must not move the updates cursor past events that have not been applied */
                if (status == EXTERIA_OK && c.pts == 0) { c.pts = pts; status = exteria_store_cursor_put(u->store, peer.id, &c); }
            }
        }
    }
    return transaction_end(u, status);
}

static int quiet_update(const exteria_tl_value *item) {
    return exteria_tl_is(item, EXTERIA_TL_ID_updateUserStatus) || exteria_tl_is(item, EXTERIA_TL_ID_updateUserTyping) ||
           exteria_tl_is(item, EXTERIA_TL_ID_updateChatUserTyping) || exteria_tl_is(item, EXTERIA_TL_ID_updateChannelUserTyping) ||
           exteria_tl_is(item, EXTERIA_TL_ID_updateUserName) || exteria_tl_is(item, EXTERIA_TL_ID_updateUserEmojiStatus) ||
           exteria_tl_is(item, EXTERIA_TL_ID_updateReadHistoryOutbox) || exteria_tl_is(item, EXTERIA_TL_ID_updateReadChannelOutbox) ||
           exteria_tl_is(item, EXTERIA_TL_ID_updateDraftMessage);
}

int exteria_updates_quiet(const exteria_tl_value *updates) {
    const exteria_tl_value *vec;
    uint32_t i;
    if (!updates) return 0;
    if (exteria_tl_is(updates, EXTERIA_TL_ID_updateShort)) return quiet_update(exteria_tl_get(updates, "update"));
    if (!exteria_tl_is(updates, EXTERIA_TL_ID_updates) && !exteria_tl_is(updates, EXTERIA_TL_ID_updatesCombined)) return 0;
    vec = exteria_tl_get(updates, "updates");
    if (!vec || vec->kind != EXTERIA_TL_V_VEC || vec->u.vec.count == 0) return 0;
    for (i = 0; i < vec->u.vec.count; ++i) {
        if (!quiet_update(vec->u.vec.items[i])) return 0;
    }
    return 1;
}
