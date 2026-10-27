#include "exteria_notify_prefs.h"

#include <string.h>

#include "exteria_dialogs.h"
#include "exteria_tl_ids.h"

#define YEAR_SECONDS (365 * 24 * 3600)

static int is_vec(const exteria_tl_value *v) {
    return v && v->kind == EXTERIA_TL_V_VEC;
}

static void copy_text(char *dst, size_t cap, const exteria_tl_value *obj, const char *field) {
    const uint8_t *data = NULL;
    size_t len = 0, n;
    dst[0] = 0;
    if (exteria_tl_get_bytes(obj, field, &data, &len) != EXTERIA_OK || !data) return;
    n = len < cap - 1 ? len : cap - 1;
    /* cut at a character boundary so a long title does not end in half a letter */
    while (n > 0 && n < len && (data[n] & 0xC0) == 0x80) --n;
    memcpy(dst, data, n);
    dst[n] = 0;
}

static int bool_value(const exteria_tl_value *v, uint8_t *out) {
    if (exteria_tl_is(v, EXTERIA_TL_ID_boolTrue)) {
        *out = 1;
        return 1;
    }
    if (exteria_tl_is(v, EXTERIA_TL_ID_boolFalse)) {
        *out = 0;
        return 1;
    }
    return 0;
}

static void sound_read(const exteria_tl_value *v, exteria_notify_sound *out, uint8_t *has) {
    memset(out, 0, sizeof(*out));
    *has = 0;
    if (!v) return;
    if (exteria_tl_is(v, EXTERIA_TL_ID_notificationSoundDefault)) {
        out->kind = EXTERIA_SOUND_DEFAULT;
        *has = 1;
    } else if (exteria_tl_is(v, EXTERIA_TL_ID_notificationSoundNone)) {
        out->kind = EXTERIA_SOUND_NONE;
        *has = 1;
    } else if (exteria_tl_is(v, EXTERIA_TL_ID_notificationSoundLocal)) {
        out->kind = EXTERIA_SOUND_LOCAL;
        copy_text(out->title, sizeof(out->title), v, "title");
        copy_text(out->data, sizeof(out->data), v, "data");
        *has = 1;
    } else if (exteria_tl_is(v, EXTERIA_TL_ID_notificationSoundRingtone)) {
        out->kind = EXTERIA_SOUND_RINGTONE;
        exteria_tl_get_i64(v, "id", &out->ringtone_id);
        *has = out->ringtone_id != 0;
    }
}

exteria_status exteria_peer_notify_read(const exteria_tl_value *settings, exteria_peer_notify *out) {
    int32_t value;
    uint8_t flag;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!settings) return EXTERIA_OK;
    if (exteria_tl_get_i32(settings, "mute_until", &value) == EXTERIA_OK) {
        out->has_mute = 1;
        out->mute_until = value;
    }
    if (bool_value(exteria_tl_get(settings, "show_previews"), &flag)) {
        out->has_previews = 1;
        out->previews = flag;
    }
    if (bool_value(exteria_tl_get(settings, "silent"), &flag)) {
        out->has_silent = 1;
        out->silent = flag;
    }
    sound_read(exteria_tl_get(settings, "ios_sound"), &out->sound, &out->has_sound);
    if (bool_value(exteria_tl_get(settings, "stories_muted"), &flag)) {
        out->has_stories_muted = 1;
        out->stories_muted = flag;
    }
    if (bool_value(exteria_tl_get(settings, "stories_hide_sender"), &flag)) {
        out->has_stories_hide_sender = 1;
        out->stories_hide_sender = flag;
    }
    sound_read(exteria_tl_get(settings, "stories_ios_sound"), &out->stories_sound, &out->has_stories_sound);
    return EXTERIA_OK;
}

static exteria_tl_value *sound_build(exteria_arena *arena, const exteria_notify_sound *sound, exteria_status *status) {
    exteria_tl_value *v;
    switch (sound->kind) {
    case EXTERIA_SOUND_NONE:
        return exteria_tl_new_obj(arena, "notificationSoundNone");
    case EXTERIA_SOUND_LOCAL:
        v = exteria_tl_new_obj(arena, "notificationSoundLocal");
        if (!v) return NULL;
        *status = exteria_tl_set_str(arena, v, "title", sound->title);
        if (*status == EXTERIA_OK) *status = exteria_tl_set_str(arena, v, "data", sound->data);
        return v;
    case EXTERIA_SOUND_RINGTONE:
        v = exteria_tl_new_obj(arena, "notificationSoundRingtone");
        if (!v) return NULL;
        *status = exteria_tl_set_i64(arena, v, "id", sound->ringtone_id);
        return v;
    default:
        return exteria_tl_new_obj(arena, "notificationSoundDefault");
    }
}

static exteria_status set_sound(exteria_arena *arena, exteria_tl_value *obj, const char *field, const exteria_notify_sound *sound) {
    exteria_status status = EXTERIA_OK;
    exteria_tl_value *v = sound_build(arena, sound, &status);
    if (!v) return EXTERIA_E_NOMEM;
    if (status != EXTERIA_OK) return status;
    return exteria_tl_set(obj, field, v);
}

static exteria_status set_bool(exteria_arena *arena, exteria_tl_value *obj, const char *field, int value) {
    exteria_tl_value *v = exteria_tl_new_obj(arena, value ? "boolTrue" : "boolFalse");
    if (!v) return EXTERIA_E_NOMEM;
    return exteria_tl_set(obj, field, v);
}

exteria_status exteria_peer_notify_build(exteria_arena *arena, const exteria_peer_notify *settings, exteria_tl_value **out) {
    exteria_tl_value *v;
    exteria_status status = EXTERIA_OK;
    if (out) *out = NULL;
    if (!arena || !settings || !out) return EXTERIA_E_ARG;
    v = exteria_tl_new_obj(arena, "inputPeerNotifySettings");
    if (!v) return EXTERIA_E_NOMEM;
    if (settings->has_previews) status = set_bool(arena, v, "show_previews", settings->previews);
    if (status == EXTERIA_OK && settings->has_silent) status = set_bool(arena, v, "silent", settings->silent);
    if (status == EXTERIA_OK && settings->has_mute) status = exteria_tl_set_i32(arena, v, "mute_until", settings->mute_until);
    if (status == EXTERIA_OK && settings->has_sound) status = set_sound(arena, v, "sound", &settings->sound);
    if (status == EXTERIA_OK && settings->has_stories_muted) status = set_bool(arena, v, "stories_muted", settings->stories_muted);
    if (status == EXTERIA_OK && settings->has_stories_hide_sender) status = set_bool(arena, v, "stories_hide_sender", settings->stories_hide_sender);
    if (status == EXTERIA_OK && settings->has_stories_sound) status = set_sound(arena, v, "stories_sound", &settings->stories_sound);
    if (status != EXTERIA_OK) return status;
    *out = v;
    return EXTERIA_OK;
}

static const char *scope_ctor(exteria_notify_scope scope) {
    switch (scope) {
    case EXTERIA_SCOPE_USERS: return "inputNotifyUsers";
    case EXTERIA_SCOPE_CHATS: return "inputNotifyChats";
    default: return "inputNotifyBroadcasts";
    }
}

exteria_status exteria_notify_scope_request(exteria_arena *arena, exteria_notify_scope scope, exteria_tl_value **out) {
    exteria_tl_value *request, *target;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || (int)scope < 0 || scope >= EXTERIA_SCOPE_COUNT) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.getNotifySettings");
    target = exteria_tl_new_obj(arena, scope_ctor(scope));
    if (!request || !target) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", target);
    if (status != EXTERIA_OK) return status;
    *out = request;
    return EXTERIA_OK;
}

/* the InputNotifyPeer that names one chat, or one topic of a forum */
static exteria_status chat_target(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **target) {
    exteria_tl_value *chat = NULL;
    exteria_status status = exteria_input_peer(arena, peer, &chat);
    if (status != EXTERIA_OK) return status;
    if (peer->topic_id > 0) {
        *target = exteria_tl_new_obj(arena, "inputNotifyForumTopic");
        if (!*target) return EXTERIA_E_NOMEM;
        status = exteria_tl_set(*target, "peer", chat);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, *target, "top_msg_id", peer->topic_id);
        return status;
    }
    *target = exteria_tl_new_obj(arena, "inputNotifyPeer");
    if (!*target) return EXTERIA_E_NOMEM;
    return exteria_tl_set(*target, "peer", chat);
}

exteria_status exteria_notify_peer_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out) {
    exteria_tl_value *request, *target = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !peer || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.getNotifySettings");
    if (!request) return EXTERIA_E_NOMEM;
    status = chat_target(arena, peer, &target);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", target);
    if (status != EXTERIA_OK) return status;
    *out = request;
    return EXTERIA_OK;
}

exteria_status exteria_notify_update_request(exteria_arena *arena, int has_scope, exteria_notify_scope scope, const exteria_peer_ref *peer,
                                             const exteria_peer_notify *settings, exteria_tl_value **out) {
    exteria_tl_value *request, *target = NULL, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !settings || !out) return EXTERIA_E_ARG;
    if (has_scope ? ((int)scope < 0 || scope >= EXTERIA_SCOPE_COUNT) : !peer) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.updateNotifySettings");
    if (!request) return EXTERIA_E_NOMEM;
    if (has_scope) {
        target = exteria_tl_new_obj(arena, scope_ctor(scope));
        if (!target) return EXTERIA_E_NOMEM;
    } else {
        status = chat_target(arena, peer, &target);
        if (status != EXTERIA_OK) return status;
    }
    status = exteria_peer_notify_build(arena, settings, &input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", target);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "settings", input);
    if (status != EXTERIA_OK) return status;
    *out = request;
    return EXTERIA_OK;
}

exteria_status exteria_notify_bool_result(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolTrue)) return EXTERIA_OK;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_boolFalse)) return EXTERIA_E_STATE;
    return EXTERIA_E_MALFORMED;
}

exteria_status exteria_notify_exceptions_request(exteria_arena *arena, int compare_sound, int compare_stories, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status = EXTERIA_OK;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.getNotifyExceptions");
    if (!request) return EXTERIA_E_NOMEM;
    if (compare_sound) status = exteria_tl_set_flag(request, "compare_sound");
    if (status == EXTERIA_OK && compare_stories) status = exteria_tl_set_flag(request, "compare_stories");
    if (status != EXTERIA_OK) return status;
    *out = request;
    return EXTERIA_OK;
}

static const exteria_tl_value *update_list(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_updates) || exteria_tl_is(answer, EXTERIA_TL_ID_updatesCombined)) return exteria_tl_get(answer, "updates");
    return NULL;
}

exteria_status exteria_notify_exceptions_parse(const exteria_tl_value *answer, int64_t self_id, exteria_notify_exception *out, size_t cap, size_t *count) {
    const exteria_tl_value *updates, *users, *chats;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!out || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_updatesTooLong)) return EXTERIA_OK;
    updates = update_list(answer);
    if (!is_vec(updates)) return EXTERIA_E_MALFORMED;
    users = exteria_tl_get(answer, "users");
    chats = exteria_tl_get(answer, "chats");
    for (i = 0; i < updates->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *update = updates->u.vec.items[i], *notify, *peer;
        exteria_notify_exception *entry;
        exteria_dialog_row row;
        int32_t topic = 0;
        if (!exteria_tl_is(update, EXTERIA_TL_ID_updateNotifySettings)) continue;
        notify = exteria_tl_get(update, "peer");
        if (exteria_tl_is(notify, EXTERIA_TL_ID_notifyForumTopic)) {
            exteria_tl_get_i32(notify, "top_msg_id", &topic);
        } else if (!exteria_tl_is(notify, EXTERIA_TL_ID_notifyPeer)) {
            continue;
        }
        peer = exteria_tl_get(notify, "peer");
        entry = &out[n];
        memset(entry, 0, sizeof(*entry));
        memset(&row, 0, sizeof(row));
        if (exteria_tl_is(peer, EXTERIA_TL_ID_peerUser) && exteria_tl_get_i64(peer, "user_id", &row.peer_id) == EXTERIA_OK) row.peer_kind = 1;
        else if (exteria_tl_is(peer, EXTERIA_TL_ID_peerChat) && exteria_tl_get_i64(peer, "chat_id", &row.peer_id) == EXTERIA_OK) row.peer_kind = 2;
        else if (exteria_tl_is(peer, EXTERIA_TL_ID_peerChannel) && exteria_tl_get_i64(peer, "channel_id", &row.peer_id) == EXTERIA_OK) row.peer_kind = 3;
        else continue;
        exteria_dialog_peer_read(&row, users, chats, self_id);
        entry->peer_kind = row.peer_kind;
        entry->peer_id = row.peer_id;
        entry->peer_hash = row.peer_hash;
        entry->deleted = row.deleted;
        entry->broadcast = row.kind == EXTERIA_DIALOG_CHANNEL;
        entry->forum_topic = topic > 0;
        memcpy(entry->title, row.title, sizeof(entry->title) < sizeof(row.title) ? sizeof(entry->title) : sizeof(row.title));
        entry->title[sizeof(entry->title) - 1] = 0;
        exteria_peer_notify_read(exteria_tl_get(update, "notify_settings"), &entry->settings);
        ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_notify_reset_request(exteria_arena *arena, exteria_tl_value **out) {
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    *out = exteria_tl_new_obj(arena, "account.resetNotifySettings");
    return *out ? EXTERIA_OK : EXTERIA_E_NOMEM;
}

exteria_status exteria_notify_signup_request(exteria_arena *arena, int silent, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.setContactSignUpNotification");
    if (!request) return EXTERIA_E_NOMEM;
    status = set_bool(arena, request, "silent", silent);
    if (status != EXTERIA_OK) return status;
    *out = request;
    return EXTERIA_OK;
}

exteria_status exteria_reaction_notify_request(exteria_arena *arena, exteria_tl_value **out) {
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    *out = exteria_tl_new_obj(arena, "account.getReactionsNotifySettings");
    return *out ? EXTERIA_OK : EXTERIA_E_NOMEM;
}

static int32_t reaction_from(const exteria_tl_value *v) {
    if (exteria_tl_is(v, EXTERIA_TL_ID_reactionNotificationsFromContacts)) return EXTERIA_REACTION_FROM_CONTACTS;
    if (exteria_tl_is(v, EXTERIA_TL_ID_reactionNotificationsFromAll)) return EXTERIA_REACTION_FROM_EVERYONE;
    return EXTERIA_REACTION_FROM_NOBODY;
}

exteria_status exteria_reaction_notify_read(const exteria_tl_value *answer, exteria_reaction_notify *out) {
    uint8_t flag, has;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    out->previews = 1;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_reactionsNotifySettings)) return EXTERIA_E_MALFORMED;
    out->messages_from = reaction_from(exteria_tl_get(answer, "messages_notify_from"));
    out->stories_from = reaction_from(exteria_tl_get(answer, "stories_notify_from"));
    if (bool_value(exteria_tl_get(answer, "show_previews"), &flag)) out->previews = flag;
    sound_read(exteria_tl_get(answer, "sound"), &out->sound, &has);
    return EXTERIA_OK;
}

static exteria_status set_from(exteria_arena *arena, exteria_tl_value *obj, const char *field, int32_t from) {
    exteria_tl_value *v;
    if (from == EXTERIA_REACTION_FROM_NOBODY) return EXTERIA_OK;
    v = exteria_tl_new_obj(arena, from == EXTERIA_REACTION_FROM_CONTACTS ? "reactionNotificationsFromContacts" : "reactionNotificationsFromAll");
    if (!v) return EXTERIA_E_NOMEM;
    return exteria_tl_set(obj, field, v);
}

exteria_status exteria_reaction_notify_set_request(exteria_arena *arena, const exteria_reaction_notify *settings, exteria_tl_value **out) {
    exteria_tl_value *request, *body;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !settings || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.setReactionsNotifySettings");
    body = exteria_tl_new_obj(arena, "reactionsNotifySettings");
    if (!request || !body) return EXTERIA_E_NOMEM;
    status = set_from(arena, body, "messages_notify_from", settings->messages_from);
    if (status == EXTERIA_OK) status = set_from(arena, body, "stories_notify_from", settings->stories_from);
    if (status == EXTERIA_OK) status = set_sound(arena, body, "sound", &settings->sound);
    if (status == EXTERIA_OK) status = set_bool(arena, body, "show_previews", settings->previews);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "settings", body);
    if (status != EXTERIA_OK) return status;
    *out = request;
    return EXTERIA_OK;
}

exteria_status exteria_ringtones_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.getSavedRingtones");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status != EXTERIA_OK) return status;
    *out = request;
    return EXTERIA_OK;
}

exteria_status exteria_ringtones_parse(const exteria_tl_value *answer, exteria_ringtone_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *list;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!rows || !count || cap == 0) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_account_savedRingtonesNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_account_savedRingtones)) return EXTERIA_E_MALFORMED;
    list = exteria_tl_get(answer, "ringtones");
    if (!is_vec(list)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *document = list->u.vec.items[i], *attributes;
        const uint8_t *reference = NULL;
        size_t length = 0;
        exteria_ringtone_row *row = &rows[n];
        uint32_t a;
        memset(row, 0, sizeof(*row));
        if (!exteria_tl_is(document, EXTERIA_TL_ID_document)) continue;
        if (exteria_tl_get_i64(document, "id", &row->id) != EXTERIA_OK || row->id == 0 || exteria_tl_get_i64(document, "access_hash", &row->access_hash) != EXTERIA_OK) continue;
        if (exteria_tl_get_bytes(document, "file_reference", &reference, &length) != EXTERIA_OK || !reference || length > sizeof(row->file_reference)) continue;
        exteria_tl_get_i32(document, "dc_id", &row->dc);
        memcpy(row->file_reference, reference, length);
        row->file_reference_len = (uint8_t)length;
        {
            int64_t size = 0;
            if (exteria_tl_get_i64(document, "size", &size) == EXTERIA_OK && size > 0 && size < INT32_MAX) row->size = (int32_t)size;
        }
        copy_text(row->mime, sizeof(row->mime), document, "mime_type");
        attributes = exteria_tl_get(document, "attributes");
        if (is_vec(attributes)) {
            for (a = 0; a < attributes->u.vec.count; ++a) {
                const exteria_tl_value *attribute = attributes->u.vec.items[a];
                if (exteria_tl_is(attribute, EXTERIA_TL_ID_documentAttributeAudio)) {
                    exteria_tl_get_i32(attribute, "duration", &row->duration);
                    copy_text(row->title, sizeof(row->title), attribute, "title");
                } else if (exteria_tl_is(attribute, EXTERIA_TL_ID_documentAttributeFilename)) {
                    copy_text(row->file_name, sizeof(row->file_name), attribute, "file_name");
                }
            }
        }
        ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_ringtone_unsave_request(exteria_arena *arena, const exteria_ringtone_row *row, exteria_tl_value **out) {
    exteria_tl_value *request, *document;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !row || !out || row->id == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.saveRingtone");
    document = exteria_tl_new_obj(arena, "inputDocument");
    if (!request || !document) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, document, "id", row->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, document, "access_hash", row->access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, document, "file_reference", row->file_reference, row->file_reference_len);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", document);
    if (status == EXTERIA_OK) status = set_bool(arena, request, "unsave", 1);
    if (status != EXTERIA_OK) return status;
    *out = request;
    return EXTERIA_OK;
}

void exteria_notify_rules_init(exteria_notify_rules *rules) {
    if (!rules) return;
    memset(rules, 0, sizeof(*rules));
    rules->contact_joined = 1;
    rules->pinned_messages = 1;
}

exteria_notify_scope exteria_notify_scope_of(int32_t peer_kind, int is_broadcast) {
    if (peer_kind == 1) return EXTERIA_SCOPE_USERS;
    return is_broadcast ? EXTERIA_SCOPE_BROADCASTS : EXTERIA_SCOPE_CHATS;
}

void exteria_notify_decide(const exteria_notify_rules *rules, exteria_notify_scope scope, const exteria_peer_notify *chat, int32_t now, exteria_notify_decision *out) {
    const exteria_peer_notify *kind;
    int32_t mute_until;
    int silent;
    if (!out) return;
    memset(out, 0, sizeof(*out));
    out->previews = 1;
    if (!rules || (int)scope < 0 || scope >= EXTERIA_SCOPE_COUNT) return;
    kind = &rules->scope[scope];
    mute_until = kind->has_mute ? kind->mute_until : 0;
    if (chat && chat->has_mute) mute_until = chat->mute_until;
    out->notify = mute_until <= now;
    out->previews = chat && chat->has_previews ? chat->previews : (kind->has_previews ? kind->previews : 1);
    silent = chat && chat->has_silent ? chat->silent : (kind->has_silent ? kind->silent : 0);
    if (chat && chat->has_sound) out->sound = chat->sound;
    else if (kind->has_sound) out->sound = kind->sound;
    if (silent) {
        memset(&out->sound, 0, sizeof(out->sound));
        out->sound.kind = EXTERIA_SOUND_NONE;
    }
}

int exteria_notify_mute_state(int32_t mute_until, int32_t now) {
    if (mute_until <= now) return 0;
    if (mute_until - YEAR_SECONDS >= now) return 1;
    return 2;
}
