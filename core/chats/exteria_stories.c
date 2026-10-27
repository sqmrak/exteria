#include "exteria_stories.h"

#include <string.h>

#include "exteria_store.h"
#include "exteria_tl_ids.h"

/* a story fills the screen, so its photo is read near 1280 px, where a message bubble takes 320 px */
#define STORY_PHOTO_TARGET 1280

static void copy_caption(char *dst, size_t cap, const exteria_tl_value *item) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (exteria_tl_get_bytes(item, "caption", &data, &len) != EXTERIA_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

exteria_status exteria_story_read(const exteria_tl_value *item, exteria_story_row *out) {
    const exteria_tl_value *views;
    int32_t value;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!item) return EXTERIA_E_MALFORMED;
    if (exteria_tl_is(item, EXTERIA_TL_ID_storyItemDeleted)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(item, EXTERIA_TL_ID_storyItem) && !exteria_tl_is(item, EXTERIA_TL_ID_storyItemSkipped))
        return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_i32(item, "id", &out->id) != EXTERIA_OK || out->id <= 0 ||
        exteria_tl_get_i32(item, "date", &out->date) != EXTERIA_OK ||
        exteria_tl_get_i32(item, "expire_date", &out->expire_date) != EXTERIA_OK) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    out->close_friends = exteria_tl_has(item, "close_friends") ? 1 : 0;
    if (exteria_tl_is(item, EXTERIA_TL_ID_storyItemSkipped)) {
        out->skipped = 1;
        return EXTERIA_OK;
    }
    out->pinned = exteria_tl_has(item, "pinned") ? 1 : 0;
    out->out = exteria_tl_has(item, "out") ? 1 : 0;
    out->edited = exteria_tl_has(item, "edited") ? 1 : 0;
    out->noforwards = exteria_tl_has(item, "noforwards") ? 1 : 0;
    exteria_media_classify_sized(exteria_tl_get(item, "media"), STORY_PHOTO_TARGET, &out->media);
    if (exteria_tl_has(item, "music")) exteria_document_read(exteria_tl_get(item, "music"), &out->music);
    copy_caption(out->caption, sizeof(out->caption), item);
    views = exteria_tl_get(item, "views");
    if (views && exteria_tl_get_i32(views, "views_count", &value) == EXTERIA_OK && value > 0) out->views = value;
    if (exteria_tl_has(item, "sent_reaction") &&
        exteria_reaction_parse(exteria_tl_get(item, "sent_reaction"), &out->reaction) == EXTERIA_OK) out->reacted = 1;
    return EXTERIA_OK;
}

/* the story list of one poster: the live count, the unseen ones and the first of them */
static exteria_status read_peer_stories(const exteria_tl_value *entry, const exteria_tl_value *users, const exteria_tl_value *chats,
                                        int64_t self_id, exteria_story_peer *peer, exteria_story_row *rows, size_t cap,
                                        size_t *count) {
    const exteria_tl_value *list;
    exteria_peer who;
    uint32_t i;
    size_t n = 0;
    memset(peer, 0, sizeof(*peer));
    if (!exteria_tl_is(entry, EXTERIA_TL_ID_peerStories) || exteria_peer_from_tl(exteria_tl_get(entry, "peer"), &who) != EXTERIA_OK ||
        (who.kind != 1 && who.kind != 3) || who.id <= 0 || exteria_tl_get_vec(entry, "stories", &list) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    if (list->u.vec.count > EXTERIA_STORIES_MAX) return EXTERIA_E_LIMIT;
    if (exteria_tl_has(entry, "max_read_id") && (exteria_tl_get_i32(entry, "max_read_id", &peer->max_read_id) != EXTERIA_OK ||
                                                 peer->max_read_id < 0)) return EXTERIA_E_MALFORMED;
    peer->owner.peer_kind = who.kind;
    peer->owner.peer_id = who.id;
    exteria_dialog_peer_read(&peer->owner, users, chats, self_id);
    for (i = 0; i < list->u.vec.count; ++i) {
        exteria_story_row row;
        exteria_status status = exteria_story_read(list->u.vec.items[i], &row);
        /* a deleted or malformed item drops out; the rest of the poster's stories stay */
        if (status != EXTERIA_OK) continue;
        ++peer->count;
        if (row.date > peer->newest_date) peer->newest_date = row.date;
        if (row.id > peer->max_read_id) {
            ++peer->unread;
            if (!peer->first_unread_id || row.id < peer->first_unread_id) peer->first_unread_id = row.id;
            if (row.close_friends) peer->close_friends = 1;
        }
        if (rows && n < cap) rows[n++] = row;
    }
    if (count) *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_story_peers_parse(const exteria_tl_value *answer, int64_t self_id, exteria_story_peer *peers,
                                         size_t cap, size_t *count, int *more) {
    const exteria_tl_value *list, *users, *chats;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (more) *more = 0;
    if (!peers || !count || !cap) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_stories_allStoriesNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_stories_allStories) ||
        exteria_tl_get_vec(answer, "peer_stories", &list) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "chats", &chats) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (list->u.vec.count > EXTERIA_STORY_PEERS_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        exteria_story_peer peer;
        exteria_status status = read_peer_stories(list->u.vec.items[i], users, chats, self_id, &peer, NULL, 0, NULL);
        /* one odd poster must not hide the strip */
        if (status != EXTERIA_OK || !peer.count || peer.owner.deleted || !peer.owner.title[0]) continue;
        peers[n++] = peer;
    }
    *count = n;
    if (more) *more = exteria_tl_has(answer, "has_more") ? 1 : 0;
    return EXTERIA_OK;
}

exteria_status exteria_story_peer_parse(const exteria_tl_value *answer, int64_t self_id, exteria_story_peer *peer,
                                        exteria_story_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *users, *chats;
    if (count) *count = 0;
    if (!peer || !rows || !count || !cap) return EXTERIA_E_ARG;
    memset(peer, 0, sizeof(*peer));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_stories_peerStories) ||
        exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "chats", &chats) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    return read_peer_stories(exteria_tl_get(answer, "stories"), users, chats, self_id, peer, rows, cap, count);
}

exteria_status exteria_stories_parse(const exteria_tl_value *answer, exteria_story_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *list;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!rows || !count || !cap) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_stories_stories) || exteria_tl_get_vec(answer, "stories", &list) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    if (list->u.vec.count > EXTERIA_STORIES_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        if (exteria_story_read(list->u.vec.items[i], &rows[n]) == EXTERIA_OK) ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_story_all_request(exteria_arena *arena, int next, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status = EXTERIA_OK;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "stories.getAllStories");
    if (!request) return EXTERIA_E_NOMEM;
    if (next) status = exteria_tl_set_flag(request, "next");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* a request whose first field is the poster */
static exteria_status peer_request(exteria_arena *arena, const char *name, const exteria_peer_ref *peer, exteria_tl_value **request) {
    exteria_tl_value *input;
    exteria_status status;
    *request = NULL;
    if (!arena) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    *request = exteria_tl_new_obj(arena, name);
    if (!*request) return EXTERIA_E_NOMEM;
    return exteria_tl_set(*request, "peer", input);
}

exteria_status exteria_story_peer_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    status = peer_request(arena, "stories.getPeerStories", peer, &request);
    *out = status == EXTERIA_OK ? request : NULL;
    return status;
}

static exteria_status ids_request(exteria_arena *arena, const char *name, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                  exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    size_t i;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!ids || !count || count > EXTERIA_STORIES_MAX) return EXTERIA_E_ARG;
    for (i = 0; i < count; ++i) if (ids[i] <= 0) return EXTERIA_E_ARG;
    status = peer_request(arena, name, peer, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32_vec(arena, request, "id", ids, (uint32_t)count);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_story_ids_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                         exteria_tl_value **out) {
    return ids_request(arena, "stories.getStoriesByID", peer, ids, count, out);
}

exteria_status exteria_story_views_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                           exteria_tl_value **out) {
    return ids_request(arena, "stories.incrementStoryViews", peer, ids, count, out);
}

exteria_status exteria_story_read_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t max_id, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (max_id <= 0) return EXTERIA_E_ARG;
    status = peer_request(arena, "stories.readStories", peer, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "max_id", max_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static exteria_status page_request(exteria_arena *arena, const char *name, const exteria_peer_ref *peer, int32_t offset_id, int32_t limit,
                                    exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (offset_id < 0 || limit < 1 || limit > EXTERIA_STORIES_MAX) return EXTERIA_E_ARG;
    status = peer_request(arena, name, peer, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_story_pinned_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset_id, int32_t limit,
                                            exteria_tl_value **out) {
    return page_request(arena, "stories.getPinnedStories", peer, offset_id, limit, out);
}

exteria_status exteria_story_archive_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset_id, int32_t limit,
                                             exteria_tl_value **out) {
    return page_request(arena, "stories.getStoriesArchive", peer, offset_id, limit, out);
}

exteria_status exteria_story_react_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id,
                                           const exteria_reaction *reaction, exteria_tl_value **out) {
    exteria_tl_value *request, *value;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (id <= 0) return EXTERIA_E_ARG;
    status = peer_request(arena, "stories.sendReaction", peer, &request);
    if (status != EXTERIA_OK) return status;
    if (reaction) {
        status = exteria_reaction_build(arena, reaction, &value);
    } else {
        value = exteria_tl_new_obj(arena, "reactionEmpty");
        status = value ? EXTERIA_OK : EXTERIA_E_NOMEM;
    }
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "story_id", id);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "reaction", value);
    if (status == EXTERIA_OK && reaction) status = exteria_tl_set_flag(request, "add_to_recent");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_story_reply_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t story_id, const char *text,
                                           int64_t random_id, exteria_tl_value **out) {
    exteria_tl_value *request, *reply, *reply_peer;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || story_id <= 0) return EXTERIA_E_ARG;
    status = exteria_send_text_request(arena, peer, text, NULL, 0, random_id, &request);
    if (status != EXTERIA_OK) return status;
    status = exteria_input_peer(arena, peer, &reply_peer);
    reply = exteria_tl_new_obj(arena, "inputReplyToStory");
    if (status == EXTERIA_OK && !reply) status = EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = exteria_tl_set(reply, "peer", reply_peer);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, reply, "story_id", story_id);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "reply_to", reply);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_story_send_photo_request(exteria_arena *arena, exteria_tl_value *file, int64_t random_id, exteria_tl_value **out) {
    exteria_tl_value *request, *peer, *media, *rules, *rule;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !file || !out || random_id == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "stories.sendStory");
    peer = exteria_tl_new_obj(arena, "inputPeerSelf");
    media = exteria_tl_new_obj(arena, "inputMediaUploadedPhoto");
    rule = exteria_tl_new_obj(arena, "inputPrivacyValueAllowAll");
    rules = exteria_tl_new_vec(arena, 1);
    if (!request || !peer || !media || !rule || !rules) return EXTERIA_E_NOMEM;
    status = exteria_tl_vec_set(rules, 0, rule);
    if (status == EXTERIA_OK) status = exteria_tl_set(media, "file", file);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "media", media);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "privacy_rules", rules);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "period", EXTERIA_STORY_PERIOD);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}
