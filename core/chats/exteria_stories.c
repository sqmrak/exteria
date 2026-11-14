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
    out->contacts = exteria_tl_has(item, "contacts") ? 1 : 0;
    out->selected = exteria_tl_has(item, "selected_contacts") ? 1 : 0;
    exteria_media_classify_sized(exteria_tl_get(item, "media"), STORY_PHOTO_TARGET, &out->media);
    if (exteria_tl_has(item, "music")) exteria_document_read(exteria_tl_get(item, "music"), &out->music);
    copy_caption(out->caption, sizeof(out->caption), item);
    views = exteria_tl_get(item, "views");
    if (views && exteria_tl_get_i32(views, "views_count", &value) == EXTERIA_OK && value > 0) out->views = value;
    if (views && exteria_tl_get_i32(views, "reactions_count", &value) == EXTERIA_OK && value > 0) out->reactions = value;
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

exteria_status exteria_story_viewers_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t story_id, const char *offset, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || story_id <= 0 || (offset && strlen(offset) >= EXTERIA_STORY_VIEWERS_OFFSET_MAX)) return EXTERIA_E_ARG;
    status = peer_request(arena, "stories.getStoryViewsList", peer, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "id", story_id);
    /* the offset is a required field; an empty one asks for the first page */
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "offset", offset ? offset : "");
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", EXTERIA_STORY_VIEWERS_PAGE);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_story_viewers_parse(const exteria_tl_value *answer, exteria_story_viewer *rows, size_t capacity, size_t *count, char *next, size_t next_capacity,
                                           int32_t *total, int32_t *reactions) {
    const exteria_tl_value *views;
    const uint8_t *offset;
    size_t length, kept = 0;
    if (count) *count = 0;
    if (next && next_capacity) next[0] = 0;
    if (total) *total = 0;
    if (reactions) *reactions = 0;
    if (!rows || !capacity || !count || !next || !next_capacity) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_stories_storyViewsList) || exteria_tl_get_vec(answer, "views", &views) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (views->u.vec.count > capacity) return EXTERIA_E_LIMIT;
    if (total) exteria_tl_get_i32(answer, "views_count", total);
    if (reactions) exteria_tl_get_i32(answer, "reactions_count", reactions);
    if (exteria_tl_has(answer, "next_offset")) {
        if (exteria_tl_get_bytes(answer, "next_offset", &offset, &length) != EXTERIA_OK || !offset || length >= next_capacity || length >= EXTERIA_STORY_VIEWERS_OFFSET_MAX ||
            memchr(offset, 0, length)) return EXTERIA_E_MALFORMED;
        memcpy(next, offset, length);
        next[length] = 0;
    }
    for (uint32_t i = 0; i < views->u.vec.count; ++i) {
        const exteria_tl_value *item = views->u.vec.items[i];
        exteria_story_viewer row;
        memset(&row, 0, sizeof(row));
        /* only a plain view names a user; forwards and reposts name a message or a story */
        if (!exteria_tl_is(item, EXTERIA_TL_ID_storyView)) continue;
        if (exteria_tl_get_i64(item, "user_id", &row.user_id) != EXTERIA_OK || row.user_id <= 0 || exteria_tl_get_i32(item, "date", &row.date) != EXTERIA_OK) {
            next[0] = 0;
            return EXTERIA_E_MALFORMED;
        }
        row.blocked = exteria_tl_has(item, "blocked") ? 1 : 0;
        if (exteria_tl_has(item, "reaction") && exteria_reaction_parse(exteria_tl_get(item, "reaction"), &row.reaction) == EXTERIA_OK) row.reacted = 1;
        rows[kept++] = row;
    }
    *count = kept;
    return EXTERIA_OK;
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

exteria_status exteria_story_forward_request(exteria_arena *arena, const exteria_peer_ref *target, const exteria_peer_ref *owner, int32_t story_id,
                                             int64_t random_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *media, *story_peer;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !target || !owner || !out || story_id <= 0 || random_id == 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, target, &input);
    if (status == EXTERIA_OK) status = exteria_input_peer(arena, owner, &story_peer);
    if (status != EXTERIA_OK) return status;
    media = exteria_tl_new_obj(arena, "inputMediaStory");
    request = exteria_tl_new_obj(arena, "messages.sendMedia");
    if (!media || !request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(media, "peer", story_peer);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, media, "id", story_id);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_set_topic_reply(arena, request, target);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "media", media);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "message", "");
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "random_id", random_id);
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

exteria_story_privacy exteria_story_row_privacy(const exteria_story_row *row) {
    if (!row) return EXTERIA_STORY_EVERYONE;
    if (row->close_friends) return EXTERIA_STORY_CLOSE_FRIENDS;
    if (row->contacts) return EXTERIA_STORY_CONTACTS;
    return EXTERIA_STORY_EVERYONE;
}

/* the rule list of an audience: the base rule (none for a chosen list), the people the choice allows, and the people it leaves out */
static exteria_status user_rule(exteria_arena *arena, const char *name, const exteria_story_user *users, size_t count, exteria_tl_value **out) {
    exteria_tl_value *rule, *list;
    exteria_status status;
    rule = exteria_tl_new_obj(arena, name);
    list = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!rule || !list) return EXTERIA_E_NOMEM;
    for (size_t i = 0; i < count; ++i) {
        exteria_tl_value *user = exteria_tl_new_obj(arena, "inputUser");
        if (!user) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i64(arena, user, "user_id", users[i].id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, user, "access_hash", users[i].access_hash);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, (uint32_t)i, user);
        if (status != EXTERIA_OK) return status;
    }
    status = exteria_tl_set(rule, "users", list);
    if (status == EXTERIA_OK) *out = rule;
    return status;
}

static exteria_status audience_rules(exteria_arena *arena, const exteria_story_audience *audience, exteria_tl_value **out) {
    static const char *const names[] = {"inputPrivacyValueAllowAll", "inputPrivacyValueAllowContacts", "inputPrivacyValueAllowCloseFriends"};
    exteria_tl_value *rules, *rule;
    exteria_status status;
    uint32_t total = 0, at = 0;
    *out = NULL;
    if (!audience || (int)audience->base < 0 || (int)audience->base > EXTERIA_STORY_SELECTED) return EXTERIA_E_ARG;
    if (audience->allow_count > EXTERIA_STORY_USERS_MAX || audience->deny_count > EXTERIA_STORY_USERS_MAX) return EXTERIA_E_LIMIT;
    /* a chosen list needs people; the others may leave some out, and the close friends have nobody to leave out */
    if (audience->base == EXTERIA_STORY_SELECTED && !audience->allow_count) return EXTERIA_E_ARG;
    if (audience->base == EXTERIA_STORY_SELECTED) total = 1;
    else total = 1 + (audience->deny_count && audience->base != EXTERIA_STORY_CLOSE_FRIENDS ? 1u : 0u);
    rules = exteria_tl_new_vec(arena, total);
    if (!rules) return EXTERIA_E_NOMEM;
    if (audience->base == EXTERIA_STORY_SELECTED) {
        status = user_rule(arena, "inputPrivacyValueAllowUsers", audience->allow, audience->allow_count, &rule);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(rules, at++, rule);
    } else {
        rule = exteria_tl_new_obj(arena, names[audience->base]);
        if (!rule) return EXTERIA_E_NOMEM;
        status = exteria_tl_vec_set(rules, at++, rule);
        if (status == EXTERIA_OK && audience->deny_count && audience->base != EXTERIA_STORY_CLOSE_FRIENDS) {
            status = user_rule(arena, "inputPrivacyValueDisallowUsers", audience->deny, audience->deny_count, &rule);
            if (status == EXTERIA_OK) status = exteria_tl_vec_set(rules, at++, rule);
        }
    }
    if (status == EXTERIA_OK) *out = rules;
    return status;
}

/* the old calls take only a base choice */
static void base_audience(exteria_story_audience *audience, exteria_story_privacy privacy) {
    memset(audience, 0, sizeof(*audience));
    audience->base = privacy;
}

exteria_status exteria_story_publish_photo_audience_request(exteria_arena *arena, exteria_tl_value *file, int64_t random_id, const char *caption,
                                                            const exteria_story_audience *audience, exteria_tl_value **out) {
    exteria_tl_value *request, *rules = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || (caption && strlen(caption) > EXTERIA_STORY_CAPTION_MAX - 1)) return EXTERIA_E_ARG;
    status = audience_rules(arena, audience, &rules);
    if (status != EXTERIA_OK) return status;
    status = exteria_story_send_photo_request(arena, file, random_id, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "privacy_rules", rules);
    if (status == EXTERIA_OK && caption && caption[0]) status = exteria_tl_set_str(arena, request, "caption", caption);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_story_publish_photo_request(exteria_arena *arena, exteria_tl_value *file, int64_t random_id, const char *caption,
                                                   exteria_story_privacy privacy, exteria_tl_value **out) {
    exteria_story_audience audience;
    if (out) *out = NULL;
    if ((int)privacy < 0 || (int)privacy > EXTERIA_STORY_CLOSE_FRIENDS) return EXTERIA_E_ARG;
    base_audience(&audience, privacy);
    return exteria_story_publish_photo_audience_request(arena, file, random_id, caption, &audience, out);
}

exteria_status exteria_story_edit_audience_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, const char *caption, int set_audience,
                                                   const exteria_story_audience *audience, exteria_tl_value **out) {
    exteria_tl_value *request, *rules = NULL, *entities;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || id <= 0 || (caption && strlen(caption) > EXTERIA_STORY_CAPTION_MAX - 1)) return EXTERIA_E_ARG;
    if (set_audience) {
        status = audience_rules(arena, audience, &rules);
        if (status != EXTERIA_OK) return status;
    }
    status = peer_request(arena, "stories.editStory", peer, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "id", id);
    if (status == EXTERIA_OK && caption) {
        /* the caption and its entities share one flag, so the entities go with it, empty */
        entities = exteria_tl_new_vec(arena, 0);
        status = entities ? exteria_tl_set_str(arena, request, "caption", caption) : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "entities", entities);
    }
    if (status == EXTERIA_OK && rules) status = exteria_tl_set(request, "privacy_rules", rules);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_story_edit_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, const char *caption, int set_privacy,
                                          exteria_story_privacy privacy, exteria_tl_value **out) {
    exteria_story_audience audience;
    if (out) *out = NULL;
    if ((int)privacy < 0 || (int)privacy > EXTERIA_STORY_CLOSE_FRIENDS) return EXTERIA_E_ARG;
    base_audience(&audience, privacy);
    return exteria_story_edit_audience_request(arena, peer, id, caption, set_privacy, &audience, out);
}

exteria_status exteria_story_link_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || id <= 0) return EXTERIA_E_ARG;
    status = peer_request(arena, "stories.exportStoryLink", peer, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "id", id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_story_link_parse(const exteria_tl_value *answer, char *link, size_t cap) {
    const uint8_t *data;
    size_t len;
    if (link && cap) link[0] = 0;
    if (!link || cap < 2) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_exportedStoryLink) || exteria_tl_get_bytes(answer, "link", &data, &len) != EXTERIA_OK || !len) return EXTERIA_E_MALFORMED;
    if (len >= cap || len > 255) return EXTERIA_E_LIMIT;
    memcpy(link, data, len);
    link[len] = 0;
    return EXTERIA_OK;
}

exteria_status exteria_story_hide_peer_request(exteria_arena *arena, const exteria_peer_ref *peer, int hidden, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!out) return EXTERIA_E_ARG;
    status = peer_request(arena, "stories.togglePeerStoriesHidden", peer, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "hidden", exteria_tl_new_obj(arena, hidden ? "boolTrue" : "boolFalse"));
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_story_delete_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                            exteria_tl_value **out) {
    return ids_request(arena, "stories.deleteStories", peer, ids, count, out);
}

exteria_status exteria_story_pin_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count, int pinned,
                                         exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status = ids_request(arena, "stories.togglePinned", peer, ids, count, &request);
    if (out) *out = NULL;
    if (!out) return EXTERIA_E_ARG;
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "pinned", exteria_tl_new_obj(arena, pinned ? "boolTrue" : "boolFalse"));
    if (status == EXTERIA_OK) *out = request;
    return status;
}
