#include "exteria_dialogs.h"
#include "exteria_notify_prefs.h"

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>

#include "exteria_messages.h"
#include "exteria_people.h"
#include "exteria_store.h"
#include "exteria_tl_ids.h"

/* the nearest photo size to this many pixels on the long side is the picture of a chat list row; the small size of a photo is 90 long */
#define DIALOG_THUMB_TARGET 90

/* a text field copied into a fixed buffer: line breaks become spaces, runs of spaces collapse,
   and the cut never lands inside a multi byte sequence */
static void copy_text(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len, i, out = 0;
    int space = 1;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK) return;
    for (i = 0; i < len && out + 1 < cap; ++i) {
        uint8_t c = data[i];
        if (c == '\n' || c == '\r' || c == '\t') c = ' ';
        if (c == ' ') {
            if (space) continue;
            space = 1;
        } else {
            space = 0;
        }
        dst[out++] = (char)c;
    }
    /* a sequence that did not fit whole is dropped with its lead byte */
    if (i < len && out > 0 && ((uint8_t)dst[out - 1] & 0x80u)) {
        while (out > 0 && ((uint8_t)dst[out - 1] & 0xC0u) == 0x80u) --out;
        if (out > 0 && ((uint8_t)dst[out - 1] & 0xC0u) == 0xC0u) --out;
    }
    while (out > 0 && dst[out - 1] == ' ') --out;
    dst[out] = 0;
}

static int same_peer(const exteria_tl_value *peer, int32_t kind, int64_t id) {
    exteria_peer p;
    return exteria_peer_from_tl(peer, &p) == EXTERIA_OK && p.kind == kind && p.id == id;
}

static int is_message(const exteria_tl_value *m) {
    uint32_t id = exteria_tl_id(m);
    return id == EXTERIA_TL_ID_message || id == EXTERIA_TL_ID_messageService || id == EXTERIA_TL_ID_messageEmpty;
}

static const exteria_tl_value *find_message(const exteria_tl_value *messages, int32_t kind, int64_t peer_id, int32_t id) {
    uint32_t i;
    for (i = 0; i < messages->u.vec.count; ++i) {
        const exteria_tl_value *m = messages->u.vec.items[i];
        int32_t message_id;
        if (!is_message(m) || exteria_tl_get_i32(m, "id", &message_id) != EXTERIA_OK || message_id != id) continue;
        if (same_peer(exteria_tl_get(m, "peer_id"), kind, peer_id)) return m;
    }
    return NULL;
}

/* a message of the favorites names the chat it came from in saved_peer_id, not in peer_id */
static const exteria_tl_value *find_saved_message(const exteria_tl_value *messages, int32_t kind, int64_t peer_id, int32_t id) {
    uint32_t i;
    for (i = 0; i < messages->u.vec.count; ++i) {
        const exteria_tl_value *m = messages->u.vec.items[i];
        int32_t message_id;
        if (!is_message(m) || exteria_tl_get_i32(m, "id", &message_id) != EXTERIA_OK || message_id != id) continue;
        if (same_peer(exteria_tl_get(m, "saved_peer_id"), kind, peer_id)) return m;
    }
    return NULL;
}

static const exteria_tl_value *find_entity(const exteria_tl_value *list, int64_t id) {
    uint32_t i;
    for (i = 0; i < list->u.vec.count; ++i) {
        const exteria_tl_value *e = list->u.vec.items[i];
        int64_t entity_id;
        if (exteria_tl_get_i64(e, "id", &entity_id) == EXTERIA_OK && entity_id == id) return e;
    }
    return NULL;
}

static void user_title(char *dst, size_t cap, const exteria_tl_value *user) {
    char first[EXTERIA_DIALOG_TITLE_MAX], last[EXTERIA_DIALOG_TITLE_MAX];
    size_t a, b;
    copy_text(first, sizeof(first), user, "first_name");
    copy_text(last, sizeof(last), user, "last_name");
    a = strlen(first);
    b = strlen(last);
    if (a + b + 2 > cap) {
        /* a pair too long for the row keeps the first name whole */
        last[0] = 0;
        b = 0;
    }
    if (a && b) {
        memcpy(dst, first, a);
        dst[a] = ' ';
        memcpy(dst + a + 1, last, b + 1);
    } else if (a || b) {
        memcpy(dst, a ? first : last, (a ? a : b) + 1);
    } else {
        copy_text(dst, cap, user, "username");
    }
    dst[cap - 1] = 0;
}

static void read_hash(exteria_dialog_row *row, const exteria_tl_value *entity) {
    int64_t hash;
    /* a min object comes from a mention and carries no hash that works for this account */
    if (!exteria_tl_has(entity, "min") && exteria_tl_get_i64(entity, "access_hash", &hash) == EXTERIA_OK) row->peer_hash = hash;
}

/* the community a chat or bot was added to, with what opening it needs when the answer carries the community itself */
static void read_linked_community(exteria_dialog_row *row, const exteria_tl_value *entity, const exteria_tl_value *chats) {
    const exteria_tl_value *community;
    int64_t id;
    if (!entity || exteria_tl_get_i64(entity, "linked_community_id", &id) != EXTERIA_OK || id <= 0) return;
    row->linked_community_id = id;
    community = chats ? find_entity(chats, id) : NULL;
    if (!community) return;
    if (!exteria_tl_has(community, "min")) {
        int64_t hash;
        if (exteria_tl_get_i64(community, "access_hash", &hash) == EXTERIA_OK) row->linked_community_hash = hash;
    }
    copy_text(row->linked_community_title, sizeof(row->linked_community_title), community, "title");
}

static void fill_user(exteria_dialog_row *row, const exteria_tl_value *users, const exteria_tl_value *chats, int64_t self_id) {
    const exteria_tl_value *user = find_entity(users, row->peer_id);
    row->kind = EXTERIA_DIALOG_USER;
    row->saved = row->peer_id == self_id;
    row->contact = user && exteria_tl_has(user, "contact");
    if (!user || exteria_tl_is(user, EXTERIA_TL_ID_userEmpty)) {
        row->deleted = 1;
        row->presence = EXTERIA_PRESENCE_DELETED;
        return;
    }
    if (exteria_tl_has(user, "self")) row->saved = 1;
    if (exteria_tl_has(user, "bot")) row->kind = EXTERIA_DIALOG_BOT;
    if (exteria_tl_has(user, "verified")) row->verified = 1;
    if (exteria_tl_has(user, "premium")) row->premium = 1;
    exteria_emoji_status_read(user, &row->emoji_status, &row->emoji_status_until);
    if (exteria_tl_has(user, "deleted")) row->deleted = 1;
    exteria_presence_read(exteria_tl_get(user, "status"), &row->presence, &row->seen);
    if (row->deleted) {
        row->presence = EXTERIA_PRESENCE_DELETED;
        row->seen = 0;
    }
    exteria_photo_ref_read(user, 1, row->peer_id, &row->photo);
    read_hash(row, user);
    user_title(row->title, sizeof(row->title), user);
    read_linked_community(row, user, chats);
}

static void fill_chat(exteria_dialog_row *row, const exteria_tl_value *chats) {
    const exteria_tl_value *chat = find_entity(chats, row->peer_id);
    row->kind = row->peer_kind == 3 ? EXTERIA_DIALOG_CHANNEL : EXTERIA_DIALOG_GROUP;
    if (!chat) return;
    copy_text(row->title, sizeof(row->title), chat, "title");
    if (exteria_tl_get_i32(chat, "participants_count", &row->participants_count) != EXTERIA_OK || row->participants_count < 0) row->participants_count = 0;
    if (row->peer_kind == 3 && exteria_tl_has(chat, "megagroup")) row->kind = EXTERIA_DIALOG_GROUP;
    if (row->kind == EXTERIA_DIALOG_CHANNEL) {
        const exteria_tl_value *rights = exteria_tl_get(chat, "admin_rights");
        row->can_post = exteria_tl_has(chat, "creator") || (rights && exteria_tl_has(rights, "post_messages")) ? 1 : 0;
    }
    if (exteria_tl_has(chat, "verified")) row->verified = 1;
    if (row->peer_kind == 3 && exteria_tl_has(chat, "forum")) row->forum = 1;
    if (exteria_tl_is(chat, EXTERIA_TL_ID_community)) {
        row->community = 1;
        row->community_collapsed = exteria_tl_has(chat, "collapsed_in_dialogs") ? 1 : 0;
    }
    row->left = exteria_tl_has(chat, "left") ? 1 : 0;
    exteria_photo_ref_read(chat, row->peer_kind, row->peer_id, &row->photo);
    if (row->peer_kind == 3) read_hash(row, chat);
    read_linked_community(row, chat, chats);
}

void exteria_dialog_peer_read(exteria_dialog_row *row, const exteria_tl_value *users, const exteria_tl_value *chats, int64_t self_id) {
    if (row->peer_kind == 1) fill_user(row, users, chats, self_id);
    else fill_chat(row, chats);
}

static void fill_message(exteria_dialog_row *row, const exteria_tl_value *m, const exteria_tl_value *users, int64_t self_id) {
    const exteria_tl_value *from;
    exteria_peer sender;
    exteria_media_info media;
    int32_t date = 0;
    if (!m || exteria_tl_is(m, EXTERIA_TL_ID_messageEmpty)) return;
    exteria_tl_get_i32(m, "date", &date);
    row->date = date;
    row->outgoing = exteria_tl_has(m, "out") ? 1 : 0;
    row->forwarded = exteria_tl_get(m, "fwd_from") != NULL;
    from = exteria_tl_get(m, "from_id");
    if (exteria_peer_from_tl(from, &sender) == EXTERIA_OK && sender.kind == 1) {
        row->sender_is_self = sender.id == self_id || row->outgoing;
        /* a user chat names nobody; a group names who spoke last unless it was us */
        if (row->kind != EXTERIA_DIALOG_USER && row->kind != EXTERIA_DIALOG_BOT && !row->sender_is_self) {
            const exteria_tl_value *user = find_entity(users, sender.id);
            if (user) {
                user_title(row->sender, sizeof(row->sender), user);
                row->sender_id = sender.id;
                exteria_photo_ref_read(user, 1, sender.id, &row->sender_photo);
            }
        }
    } else {
        row->sender_is_self = row->outgoing;
    }
    if (exteria_tl_is(m, EXTERIA_TL_ID_messageService)) {
        row->preview = EXTERIA_PREVIEW_SERVICE;
        row->service = exteria_service_summary(exteria_tl_get(m, "action"), row->text, sizeof(row->text), &row->service_value, NULL);
        return;
    }
    copy_text(row->text, sizeof(row->text), m, "message");
    exteria_media_classify_sized(exteria_tl_get(m, "media"), DIALOG_THUMB_TARGET, &media);
    row->preview = media.kind;
    /* a photo is its own picture; a video, gif or round video shows the thumbnail the server keeps beside it */
    if (media.kind == EXTERIA_PREVIEW_PHOTO) row->thumb = media.ref;
    else if (media.kind == EXTERIA_PREVIEW_VIDEO || media.kind == EXTERIA_PREVIEW_GIF || media.kind == EXTERIA_PREVIEW_VIDEO_MESSAGE) row->thumb = media.preview;
    /* a caption wins over the sticker emoji or file name that would stand in for it */
    if (!row->text[0]) {
        const char *detail = media.kind == EXTERIA_PREVIEW_STICKER ? media.alt : (media.kind == EXTERIA_PREVIEW_FILE ? media.name : "");
        snprintf(row->text, sizeof(row->text), "%s", detail);
    }
    if (row->preview == EXTERIA_PREVIEW_TEXT && !row->text[0]) row->preview = EXTERIA_PREVIEW_NONE;
}

exteria_status exteria_found_request(exteria_arena *arena, const char *query, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!arena || !query || !out || limit < 1 || limit > EXTERIA_DIALOGS_MAX || strlen(query) > 256) return EXTERIA_E_ARG;
    *out = NULL;
    request = exteria_tl_new_obj(arena, "contacts.search");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "q", query);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static int row_exists(const exteria_dialog_row *rows, size_t n, int32_t kind, int64_t id) {
    size_t i;
    for (i = 0; i < n; ++i) if (rows[i].peer_kind == kind && rows[i].peer_id == id) return 1;
    return 0;
}

exteria_status exteria_found_parse(const exteria_tl_value *answer, int64_t self_id, exteria_dialog_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *lists[2], *chats, *users;
    static const char *const names[2] = {"my_results", "results"};
    size_t n = 0;
    uint32_t list, i;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_contacts_found)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, names[0], &lists[0]) != EXTERIA_OK || exteria_tl_get_vec(answer, names[1], &lists[1]) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "chats", &chats) != EXTERIA_OK || exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (list = 0; list < 2; ++list) {
        for (i = 0; i < lists[list]->u.vec.count && n < cap; ++i) {
            exteria_dialog_row *row = &rows[n];
            exteria_peer peer;
            const exteria_tl_value *entity;
            if (exteria_peer_from_tl(lists[list]->u.vec.items[i], &peer) != EXTERIA_OK || row_exists(rows, n, peer.kind, peer.id)) continue;
            entity = find_entity(peer.kind == 1 ? users : chats, peer.id);
            if (!entity) continue;
            memset(row, 0, sizeof(*row));
            row->peer_kind = peer.kind;
            row->peer_id = peer.id;
            if (peer.kind == 1) fill_user(row, users, chats, self_id);
            else fill_chat(row, chats);
            if (row->deleted) continue;
            {
                char name[EXTERIA_DIALOG_TITLE_MAX];
                copy_text(name, sizeof(name), entity, "username");
                if (name[0]) snprintf(row->text, sizeof(row->text), "@%s", name);
            }
            row->preview = row->text[0] ? EXTERIA_PREVIEW_TEXT : EXTERIA_PREVIEW_NONE;
            ++n;
        }
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_search_parse(const exteria_tl_value *answer, int64_t self_id, exteria_dialog_row *rows, size_t cap,
                                    size_t *count, int32_t *next_rate) {
    const exteria_tl_value *messages, *chats, *users;
    uint32_t i;
    size_t n = 0;
    int32_t rate = 0;
    if (count) *count = 0;
    if (next_rate) *next_rate = 0;
    if (!answer || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_messages) && !exteria_tl_is(answer, EXTERIA_TL_ID_messages_messagesSlice) &&
        !exteria_tl_is(answer, EXTERIA_TL_ID_messages_channelMessages)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "messages", &messages) != EXTERIA_OK || exteria_tl_get_vec(answer, "chats", &chats) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < messages->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *m = messages->u.vec.items[i];
        exteria_dialog_row *row = &rows[n];
        exteria_peer peer;
        int32_t id;
        if (!exteria_tl_is(m, EXTERIA_TL_ID_message) || exteria_tl_get_i32(m, "id", &id) != EXTERIA_OK || id <= 0 ||
            exteria_peer_from_tl(exteria_tl_get(m, "peer_id"), &peer) != EXTERIA_OK) continue;
        memset(row, 0, sizeof(*row));
        row->peer_kind = peer.kind;
        row->peer_id = peer.id;
        if (peer.kind == 1) {
            if (!find_entity(users, peer.id)) continue;
            fill_user(row, users, chats, self_id);
        } else {
            if (!find_entity(chats, peer.id)) continue;
            fill_chat(row, chats);
        }
        row->top_message = id;
        fill_message(row, m, users, self_id);
        ++n;
    }
    if (exteria_tl_get_i32(answer, "next_rate", &rate) == EXTERIA_OK && next_rate) *next_rate = rate;
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_dialogs_parse(const exteria_tl_value *answer, int64_t self_id, int32_t now,
                                     exteria_dialog_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *dialogs, *messages, *chats, *users;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!answer || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    int saved_list = exteria_tl_is(answer, EXTERIA_TL_ID_messages_savedDialogs) || exteria_tl_is(answer, EXTERIA_TL_ID_messages_savedDialogsSlice);
    if (!saved_list && !exteria_tl_is(answer, EXTERIA_TL_ID_messages_dialogs) && !exteria_tl_is(answer, EXTERIA_TL_ID_messages_dialogsSlice) &&
        !exteria_tl_is(answer, EXTERIA_TL_ID_messages_peerDialogs))
        return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "dialogs", &dialogs) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "messages", &messages) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "chats", &chats) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < dialogs->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *d = dialogs->u.vec.items[i];
        const exteria_tl_value *settings;
        exteria_dialog_row *row;
        exteria_peer peer;
        int32_t value;
        int folder = exteria_tl_is(d, EXTERIA_TL_ID_dialogFolder);
        int community = exteria_tl_is(d, EXTERIA_TL_ID_dialogCommunity);
        if (folder) {
            const exteria_tl_value *info = exteria_tl_get(d, "folder");
            int32_t unmuted = 0, muted = 0;
            if (exteria_tl_get_i32(info, "id", &value) != EXTERIA_OK || value <= 0) continue;
            row = &rows[n];
            memset(row, 0, sizeof(*row));
            row->folder = 1;
            row->folder_id = value;
            row->kind = EXTERIA_DIALOG_GROUP;
            copy_text(row->title, sizeof(row->title), info, "title");
            exteria_tl_get_i32(d, "unread_unmuted_peers_count", &unmuted);
            exteria_tl_get_i32(d, "unread_muted_peers_count", &muted);
            if (unmuted < 0) unmuted = 0;
            if (muted < 0) muted = 0;
            row->unread_count = unmuted > INT32_MAX - muted ? INT32_MAX : unmuted + muted;
            row->muted = unmuted == 0 && muted > 0;
            /* the archive has no chat peer, pin or last-message preview of its own */
            if (n > 0) {
                exteria_dialog_row entry = *row;
                memmove(rows + 1, rows, n * sizeof(*rows));
                rows[0] = entry;
            }
            ++n;
            continue;
        }
        if (community) {
            /* a community entry names no peer, only the id of the community, which the chats of the answer carry like a channel */
            peer.kind = 3;
            if (exteria_tl_get_i64(d, "community_id", &peer.id) != EXTERIA_OK || peer.id <= 0 || !find_entity(chats, peer.id)) continue;
        } else if (!exteria_tl_is(d, saved_list ? EXTERIA_TL_ID_savedDialog : EXTERIA_TL_ID_dialog) || exteria_peer_from_tl(exteria_tl_get(d, "peer"), &peer) != EXTERIA_OK) {
            continue;
        }
        row = &rows[n];
        memset(row, 0, sizeof(*row));
        row->peer_kind = peer.kind;
        row->peer_id = peer.id;
        if (peer.kind == 1) fill_user(row, users, chats, self_id);
        else fill_chat(row, chats);
        if (exteria_tl_get_i32(d, "folder_id", &value) == EXTERIA_OK) row->folder_id = value;
        row->pinned = exteria_tl_has(d, "pinned") ? 1 : 0;
        row->unread_mark = exteria_tl_has(d, "unread_mark") ? 1 : 0;
        if (exteria_tl_get_i32(d, "unread_count", &value) == EXTERIA_OK && value > 0) row->unread_count = value;
        if (exteria_tl_get_i32(d, "unread_mentions_count", &value) == EXTERIA_OK && value > 0) row->mentions = value;
        if (exteria_tl_get_i32(d, "read_inbox_max_id", &value) == EXTERIA_OK && value > 0) row->read_inbox_max_id = value;
        if (exteria_tl_get_i32(d, "read_outbox_max_id", &value) == EXTERIA_OK && value > 0) row->read_outbox_max_id = value;
        settings = exteria_tl_get(d, "notify_settings");
        if (exteria_tl_get_i32(settings, "mute_until", &value) == EXTERIA_OK && value > now) row->muted = 1;
        exteria_peer_notify_read(settings, &row->notify);
        if (exteria_tl_get_i32(d, "top_message", &value) == EXTERIA_OK && value > 0) {
            row->top_message = value;
            fill_message(row, saved_list ? find_saved_message(messages, peer.kind, peer.id, value) : find_message(messages, peer.kind, peer.id, value), users, self_id);
            if (row->outgoing && exteria_tl_get_i32(d, "read_outbox_max_id", &value) == EXTERIA_OK) row->read = value >= row->top_message;
        }
        ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_saved_dialogs_request(exteria_arena *arena, int32_t offset_date, int32_t offset_id, int32_t offset_peer_kind, int64_t offset_peer_id,
                                             int64_t offset_peer_hash, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || offset_date < 0 || offset_id < 0 || limit < 1 || limit > EXTERIA_DIALOGS_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getSavedDialogs");
    if (!request) return EXTERIA_E_NOMEM;
    if (offset_peer_kind) {
        exteria_peer_ref offset = {offset_peer_kind, offset_peer_id, offset_peer_hash, 0, 0};
        status = exteria_input_peer(arena, &offset, &input);
    } else {
        input = exteria_tl_new_obj(arena, "inputPeerEmpty");
        status = input ? EXTERIA_OK : EXTERIA_E_NOMEM;
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "offset_peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_date", offset_date);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_topics_request(exteria_arena *arena, int32_t peer_kind, int64_t peer_id, int64_t peer_hash, int32_t offset_date,
                                      int32_t offset_id, int32_t offset_topic, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || peer_kind != 3 || peer_id <= 0 || peer_hash == 0 || offset_date < 0 || offset_id < 0 || offset_topic < 0 ||
        limit < 1 || limit > EXTERIA_DIALOGS_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getForumTopics");
    input = exteria_tl_new_obj(arena, "inputPeerChannel");
    if (!request || !input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "channel_id", peer_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", peer_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_date", offset_date);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_id", offset_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_topic", offset_topic);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_topics_parse(const exteria_tl_value *answer, const exteria_dialog_row *forum, int64_t self_id, int32_t now,
                                    exteria_dialog_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *topics, *messages, *users;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!answer || !forum || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_forumTopics)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "topics", &topics) != EXTERIA_OK || exteria_tl_get_vec(answer, "messages", &messages) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (i = 0; i < topics->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *t = topics->u.vec.items[i], *settings;
        exteria_dialog_row *row = &rows[n];
        int32_t value;
        int64_t icon;
        if (!exteria_tl_is(t, EXTERIA_TL_ID_forumTopic) || exteria_tl_get_i32(t, "id", &value) != EXTERIA_OK || value <= 0) continue;
        *row = *forum;
        row->forum = 0;
        row->pinned = exteria_tl_has(t, "pinned") ? 1 : 0;
        row->topic_id = value;
        row->topic_closed = exteria_tl_has(t, "closed") ? 1 : 0;
        row->unread_mark = row->outgoing = row->read = row->sender_is_self = row->forwarded = 0;
        row->unread_count = row->mentions = row->date = row->top_message = 0;
        row->read_inbox_max_id = row->read_outbox_max_id = 0;
        row->preview = EXTERIA_PREVIEW_NONE;
        row->sender[0] = row->text[0] = 0;
        row->muted = 0;
        copy_text(row->title, sizeof(row->title), t, "title");
        if (exteria_tl_get_i32(t, "icon_color", &value) == EXTERIA_OK) row->topic_icon_color = value & 0xFFFFFF;
        if (exteria_tl_get_i64(t, "icon_emoji_id", &icon) == EXTERIA_OK && icon > 0) row->topic_icon_emoji = icon;
        if (exteria_tl_get_i32(t, "unread_count", &value) == EXTERIA_OK && value > 0) row->unread_count = value;
        if (exteria_tl_get_i32(t, "unread_mentions_count", &value) == EXTERIA_OK && value > 0) row->mentions = value;
        if (exteria_tl_get_i32(t, "read_inbox_max_id", &value) == EXTERIA_OK && value > 0) row->read_inbox_max_id = value;
        if (exteria_tl_get_i32(t, "read_outbox_max_id", &value) == EXTERIA_OK && value > 0) row->read_outbox_max_id = value;
        settings = exteria_tl_get(t, "notify_settings");
        if (exteria_tl_get_i32(settings, "mute_until", &value) == EXTERIA_OK && value > now) row->muted = 1;
        exteria_peer_notify_read(settings, &row->notify);
        if (exteria_tl_get_i32(t, "top_message", &value) == EXTERIA_OK && value > 0) {
            row->top_message = value;
            fill_message(row, find_message(messages, forum->peer_kind, forum->peer_id, value), users, self_id);
            if (row->outgoing && row->read_outbox_max_id > 0) row->read = row->read_outbox_max_id >= row->top_message;
        }
        ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_community_parse(const exteria_tl_value *answer, exteria_community_info *info, exteria_dialog_row *rows,
                                       size_t cap, size_t *count) {
    const exteria_tl_value *full, *peers, *chats, *users, *self;
    size_t n = 0;
    uint32_t i;
    int64_t id;
    if (count) *count = 0;
    if (!answer || !info || !rows || !count || cap == 0) return EXTERIA_E_ARG;
    memset(info, 0, sizeof(*info));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatFull)) return EXTERIA_E_MALFORMED;
    full = exteria_tl_get(answer, "full_chat");
    if (!exteria_tl_is(full, EXTERIA_TL_ID_communityFull) || exteria_tl_get_i64(full, "id", &id) != EXTERIA_OK ||
        exteria_tl_get_vec(full, "linked_peers", &peers) != EXTERIA_OK || exteria_tl_get_vec(answer, "chats", &chats) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    self = find_entity(chats, id);
    if (self) {
        copy_text(info->title, sizeof(info->title), self, "title");
        info->collapsed = exteria_tl_has(self, "collapsed_in_dialogs") ? 1 : 0;
        exteria_photo_ref_read(self, 3, id, &info->photo);
    }
    copy_text(info->about, sizeof(info->about), full, "about");
    for (i = 0; i < peers->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *link = peers->u.vec.items[i], *visible;
        exteria_dialog_row *row = &rows[n];
        exteria_peer peer;
        if (!exteria_tl_is(link, EXTERIA_TL_ID_communityPeer) || exteria_peer_from_tl(exteria_tl_get(link, "peer"), &peer) != EXTERIA_OK ||
            peer.kind == 1 || row_exists(rows, n, peer.kind, peer.id) || !find_entity(chats, peer.id)) continue;
        visible = exteria_tl_get(link, "visible");
        if (visible && exteria_tl_is(visible, EXTERIA_TL_ID_boolFalse)) continue;
        memset(row, 0, sizeof(*row));
        row->peer_kind = peer.kind;
        row->peer_id = peer.id;
        fill_chat(row, chats);
        ++n;
    }
    (void)users;
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_community_previews_apply(const exteria_tl_value *answer, int64_t self_id, int32_t now,
                                               exteria_dialog_row *rows, size_t count) {
    exteria_dialog_row *live;
    exteria_status status;
    size_t found = 0;
    if (!rows || count > EXTERIA_DIALOGS_MAX) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_peerDialogs)) return EXTERIA_E_MALFORMED;
    live = calloc(EXTERIA_DIALOGS_MAX, sizeof(*live));
    if (!live) return EXTERIA_E_NOMEM;
    status = exteria_dialogs_parse(answer, self_id, now, live, EXTERIA_DIALOGS_MAX, &found);
    for (size_t i = 0; status == EXTERIA_OK && i < count; ++i) {
        for (size_t j = 0; j < found; ++j) {
            const exteria_dialog_row *source = &live[j];
            exteria_dialog_row *row = &rows[i];
            if (source->folder || source->peer_kind != row->peer_kind || source->peer_id != row->peer_id) continue;
            row->top_message = source->top_message;
            row->date = source->date;
            row->preview = source->preview;
            row->thumb = source->thumb;
            row->service = source->service;
            row->service_value = source->service_value;
            row->outgoing = source->outgoing;
            row->forwarded = source->forwarded;
            row->read = source->read;
            row->read_inbox_max_id = source->read_inbox_max_id;
            row->read_outbox_max_id = source->read_outbox_max_id;
            row->unread_count = source->unread_count;
            row->mentions = source->mentions;
            row->unread_mark = source->unread_mark;
            row->muted = source->muted;
            row->notify = source->notify;
            row->sender_is_self = source->sender_is_self;
            row->sender_id = source->sender_id;
            row->sender_photo = source->sender_photo;
            memcpy(row->sender, source->sender, sizeof(row->sender));
            memcpy(row->text, source->text, sizeof(row->text));
            break;
        }
    }
    free(live);
    return status;
}

exteria_status exteria_community_collapse_request(exteria_arena *arena, int64_t id, int64_t access_hash, int collapsed, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || id <= 0 || access_hash == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "communities.toggleCommunityCollapsedInDialogs");
    input = exteria_tl_new_obj(arena, "inputChannel");
    if (!request || !input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "channel_id", id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", access_hash);
    if (status == EXTERIA_OK && collapsed) status = exteria_tl_set_flag(request, "collapsed");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "community", input);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_dialogs_ensure_archive(exteria_dialog_row *rows, size_t cap, size_t *count) {
    if (!rows || !count || *count > cap) return EXTERIA_E_ARG;
    for (size_t i = 0; i < *count; ++i) if (rows[i].folder && rows[i].folder_id == 1) return EXTERIA_OK;
    if (*count == cap) return EXTERIA_E_LIMIT;
    memmove(rows + 1, rows, *count * sizeof(*rows));
    memset(rows, 0, sizeof(*rows));
    rows[0].folder = 1;
    rows[0].folder_id = 1;
    rows[0].kind = EXTERIA_DIALOG_GROUP;
    ++*count;
    return EXTERIA_OK;
}

exteria_status exteria_archive_summary_parse(const exteria_tl_value *info, const exteria_tl_value *contents,
                                              int64_t self_id, int32_t now, exteria_dialog_row *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    exteria_dialog_row folder;
    size_t folders = 0, count = 0;
    exteria_status status = exteria_dialogs_parse(info, self_id, now, &folder, 1, &folders);
    if (status != EXTERIA_OK) return status;
    if (folders && (!folder.folder || folder.folder_id != 1)) return EXTERIA_E_MALFORMED;
    exteria_dialog_row *rows = calloc(EXTERIA_DIALOGS_MAX, sizeof(*rows));
    if (!rows) return EXTERIA_E_NOMEM;
    status = exteria_dialogs_parse(contents, self_id, now, rows, EXTERIA_DIALOGS_MAX, &count);
    if (status == EXTERIA_OK && !folders && count) status = EXTERIA_E_MALFORMED;
    if (status == EXTERIA_OK) {
        if (folders) *out = folder;
        else { out->folder = 1; out->folder_id = 1; out->kind = EXTERIA_DIALOG_GROUP; }
        size_t used = 0;
        for (size_t i = 0; i < count; ++i) {
            const exteria_dialog_row *row = rows + i;
            if (row->folder || row->folder_id != 1 || !row->title[0]) continue;
            size_t length = strlen(row->title), room = sizeof(out->text) - used - 1;
            size_t separator = used ? 2 : 0;
            if (room <= separator) break;
            room -= separator;
            size_t take = length < room ? length : room;
            while (take && take < length && ((uint8_t)row->title[take] & 0xC0u) == 0x80u) --take;
            if (!take) break;
            if (separator) { memcpy(out->text + used, ", ", separator); used += separator; }
            memcpy(out->text + used, row->title, take);
            used += take;
            out->text[used] = 0;
            if (take < length) break;
        }
        out->preview = used ? EXTERIA_PREVIEW_TEXT : EXTERIA_PREVIEW_NONE;
    }
    free(rows);
    return status;
}
