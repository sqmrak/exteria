#include "exteria_profile.h"

#include <string.h>

#include "exteria_avatars.h"
#include "exteria_store.h"
#include "exteria_tl_ids.h"

exteria_status exteria_full_user_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request, *self;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "users.getFullUser");
    self = exteria_tl_new_obj(arena, "inputUserSelf");
    if (!request || !self) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "id", self);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_full_user_peer_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out) {
    exteria_tl_value *request, *user;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !peer) return EXTERIA_E_ARG;
    if (peer->self) return exteria_full_user_request(arena, out);
    if (peer->kind != 1 || peer->id <= 0 || peer->access_hash == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "users.getFullUser");
    user = exteria_tl_new_obj(arena, "inputUser");
    if (!request || !user) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, user, "user_id", peer->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, user, "access_hash", peer->access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", user);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static const exteria_tl_value *find_entity(const exteria_tl_value *list, int64_t id) {
    uint32_t i;
    for (i = 0; list && list->kind == EXTERIA_TL_V_VEC && i < list->u.vec.count; ++i) {
        int64_t entity_id;
        if (exteria_tl_get_i64(list->u.vec.items[i], "id", &entity_id) == EXTERIA_OK && entity_id == id) return list->u.vec.items[i];
    }
    return NULL;
}

static exteria_status rating_parse(const exteria_tl_value *value, exteria_star_rating *rating) {
    if (!exteria_tl_is(value, EXTERIA_TL_ID_starsRating) ||
        exteria_tl_get_i32(value, "level", &rating->level) != EXTERIA_OK ||
        exteria_tl_get_i64(value, "current_level_stars", &rating->current_level_stars) != EXTERIA_OK ||
        exteria_tl_get_i64(value, "stars", &rating->stars) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (exteria_tl_has(value, "next_level_stars")) {
        if (exteria_tl_get_i64(value, "next_level_stars", &rating->next_level_stars) != EXTERIA_OK ||
            rating->next_level_stars <= rating->current_level_stars) return EXTERIA_E_MALFORMED;
        rating->has_next = 1;
    }
    return EXTERIA_OK;
}

/* a text field copied whole into a buffer, cut at a character boundary */
static void copy_field(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

exteria_status exteria_full_user_parse(const exteria_tl_value *answer, exteria_full_user *out) {
    const exteria_tl_value *full, *users, *chats, *entity, *birthday;
    const uint8_t *data;
    size_t len;
    int64_t id = 0, channel_id = 0;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_users_userFull)) return EXTERIA_E_MALFORMED;
    full = exteria_tl_get(answer, "full_user");
    if (!exteria_tl_is(full, EXTERIA_TL_ID_userFull)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_has(full, "stars_rating")) {
        if (rating_parse(exteria_tl_get(full, "stars_rating"), &out->rating) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        out->has_rating = 1;
    }
    if (exteria_tl_has(full, "stars_my_pending_rating")) {
        if (rating_parse(exteria_tl_get(full, "stars_my_pending_rating"), &out->pending_rating) != EXTERIA_OK ||
            exteria_tl_get_i32(full, "stars_my_pending_rating_date", &out->pending_rating_date) != EXTERIA_OK || out->pending_rating_date <= 0)
            return EXTERIA_E_MALFORMED;
        out->has_pending_rating = 1;
    }
    if (exteria_tl_has(full, "about") && exteria_tl_get_bytes(full, "about", &data, &len) == EXTERIA_OK && data) {
        if (len >= sizeof(out->about)) {
            len = sizeof(out->about) - 1;
            while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
        }
        memcpy(out->about, data, len);
        out->about[len] = 0;
    }
    if (exteria_tl_has(full, "note")) {
        const exteria_tl_value *note = exteria_tl_get(full, "note");
        if (exteria_tl_is(note, EXTERIA_TL_ID_textWithEntities)) copy_field(out->note, sizeof(out->note), note, "text");
    }
    out->has_personal_photo = exteria_tl_has(full, "personal_photo") ? 1 : 0;
    if (exteria_tl_has(full, "fallback_photo")) {
        exteria_photo_read(exteria_tl_get(full, "fallback_photo"), EXTERIA_AVATAR_TARGET, &out->public_photo);
        out->has_public_photo = out->public_photo.ref.source == EXTERIA_MEDIA_SOURCE_PHOTO && out->public_photo.ref.id != 0;
    }
    if (exteria_tl_get_i32(full, "common_chats_count", &out->common_chats) != EXTERIA_OK || out->common_chats < 0) out->common_chats = 0;
    out->require_premium = exteria_tl_has(full, "contact_require_premium") ? 1 : 0;
    out->blocked = exteria_tl_has(full, "blocked") ? 1 : 0;
    out->sharing_restricted = exteria_tl_has(full, "noforwards_my_enabled") || exteria_tl_has(full, "noforwards_peer_enabled");
    users = exteria_tl_get(answer, "users");
    chats = exteria_tl_get(answer, "chats");
    if (exteria_tl_get_i64(full, "id", &id) == EXTERIA_OK && id > 0) {
        entity = find_entity(users, id);
        if (entity && exteria_person_parse(entity, &out->person) == EXTERIA_OK) out->has_person = 1;
    }
    birthday = exteria_tl_get(full, "birthday");
    if (birthday && exteria_tl_get_i32(birthday, "day", &out->birthday_day) == EXTERIA_OK &&
        exteria_tl_get_i32(birthday, "month", &out->birthday_month) == EXTERIA_OK && out->birthday_day >= 1 && out->birthday_day <= 31 &&
        out->birthday_month >= 1 && out->birthday_month <= 12) {
        out->has_birthday = 1;
        if (exteria_tl_has(birthday, "year")) exteria_tl_get_i32(birthday, "year", &out->birthday_year);
    }
    if (exteria_tl_has(full, "personal_channel_id") && exteria_tl_get_i64(full, "personal_channel_id", &channel_id) == EXTERIA_OK && channel_id > 0) {
        entity = find_entity(chats, channel_id);
        if (entity && exteria_tl_is(entity, EXTERIA_TL_ID_channel)) {
            out->channel.peer_kind = 3;
            out->channel.peer_id = channel_id;
            exteria_dialog_peer_read(&out->channel, users, chats, 0);
            if (out->channel.title[0]) {
                out->has_channel = 1;
                exteria_tl_get_i32(entity, "participants_count", &out->channel_participants);
                if (exteria_tl_has(full, "personal_channel_message")) exteria_tl_get_i32(full, "personal_channel_message", &out->channel_message);
            } else {
                memset(&out->channel, 0, sizeof(out->channel));
            }
        }
    }
    if (exteria_tl_has(full, "business_intro")) {
        const exteria_tl_value *intro = exteria_tl_get(full, "business_intro");
        if (exteria_tl_is(intro, EXTERIA_TL_ID_businessIntro)) {
            copy_field(out->intro_title, sizeof(out->intro_title), intro, "title");
            copy_field(out->intro_text, sizeof(out->intro_text), intro, "description");
            if (exteria_tl_has(intro, "sticker") && exteria_sticker_read(exteria_tl_get(intro, "sticker"), &out->intro_sticker) == EXTERIA_OK)
                out->has_intro_sticker = 1;
            out->has_intro = out->intro_title[0] || out->intro_text[0] || out->has_intro_sticker;
        }
    }
    if (exteria_tl_has(full, "saved_music")) {
        exteria_document_read(exteria_tl_get(full, "saved_music"), &out->music);
        out->has_music = out->music.ref.source != EXTERIA_MEDIA_SOURCE_NONE;
        if (!out->has_music) memset(&out->music, 0, sizeof(out->music));
    }
    return EXTERIA_OK;
}

exteria_status exteria_saved_music_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request, *user;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !peer || offset < 0 || limit < 1 || limit > EXTERIA_MUSIC_PAGE) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "users.getSavedMusic");
    if (!request) return EXTERIA_E_NOMEM;
    if (peer->self) {
        user = exteria_tl_new_obj(arena, "inputUserSelf");
        if (!user) return EXTERIA_E_NOMEM;
        status = EXTERIA_OK;
    } else {
        if (peer->kind != 1 || peer->id <= 0 || peer->access_hash == 0) return EXTERIA_E_ARG;
        user = exteria_tl_new_obj(arena, "inputUser");
        if (!user) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_i64(arena, user, "user_id", peer->id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, user, "access_hash", peer->access_hash);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", user);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset", offset);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    /* a hash of zero asks for the full page; the list is not kept between runs, so there is nothing to compare against */
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_save_music_request(exteria_arena *arena, const exteria_media_ref *song, int unsave, exteria_tl_value **out) {
    exteria_tl_value *request, *document;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !song || song->source != EXTERIA_MEDIA_SOURCE_DOCUMENT || song->id == 0 || song->ref_len == 0 || song->thumb[0]) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.saveMusic");
    document = exteria_tl_new_obj(arena, "inputDocument");
    if (!request || !document) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, document, "id", song->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, document, "access_hash", song->access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, document, "file_reference", song->file_ref, song->ref_len);
    if (status == EXTERIA_OK && unsave) status = exteria_tl_set_flag(request, "unsave");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", document);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_saved_music_parse(const exteria_tl_value *answer, exteria_media_info *tracks, size_t cap, size_t *count, int32_t *total) {
    const exteria_tl_value *documents;
    uint32_t i;
    if (!tracks || !count || !total) return EXTERIA_E_ARG;
    *count = 0;
    *total = 0;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_users_savedMusic)) return EXTERIA_E_MALFORMED;
    documents = exteria_tl_get(answer, "documents");
    if (!documents || documents->kind != EXTERIA_TL_V_VEC || exteria_tl_get_i32(answer, "count", total) != EXTERIA_OK || *total < 0) {
        *total = 0;
        return EXTERIA_E_MALFORMED;
    }
    for (i = 0; i < documents->u.vec.count && *count < cap; ++i) {
        exteria_media_info *track = &tracks[*count];
        exteria_document_read(documents->u.vec.items[i], track);
        if (track->ref.source == EXTERIA_MEDIA_SOURCE_NONE) continue;
        ++*count;
    }
    return EXTERIA_OK;
}

exteria_status exteria_birthday_request(exteria_arena *arena, int32_t day, int32_t month, int32_t year, exteria_tl_value **out) {
    static const int32_t days[12] = {31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    exteria_tl_value *request, *birthday;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || month < 1 || month > 12 || day < 1 || day > days[month - 1] || (year != 0 && (year < 1900 || year > 2100))) return EXTERIA_E_ARG;
    /* a day that only a leap year has needs a year that is one, when the year is given */
    if (year && month == 2 && day == 29 && !((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.updateBirthday");
    birthday = exteria_tl_new_obj(arena, "birthday");
    if (!request || !birthday) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, birthday, "day", day);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, birthday, "month", month);
    if (status == EXTERIA_OK && year) status = exteria_tl_set_i32(arena, birthday, "year", year);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "birthday", birthday);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_birthday_clear_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.updateBirthday");
    if (!request) return EXTERIA_E_NOMEM;
    *out = request;
    return EXTERIA_OK;
}

static exteria_status input_channel(exteria_arena *arena, const exteria_peer_ref *channel, exteria_tl_value **out) {
    exteria_tl_value *v;
    exteria_status status;
    *out = NULL;
    if (!channel || channel->kind != 3 || channel->id <= 0 || channel->access_hash == 0) return EXTERIA_E_ARG;
    v = exteria_tl_new_obj(arena, "inputChannel");
    if (!v) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, v, "channel_id", channel->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, v, "access_hash", channel->access_hash);
    if (status == EXTERIA_OK) *out = v;
    return status;
}

exteria_status exteria_personal_channel_request(exteria_arena *arena, const exteria_peer_ref *channel, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    if (channel) {
        status = input_channel(arena, channel, &input);
    } else {
        input = exteria_tl_new_obj(arena, "inputChannelEmpty");
        status = input ? EXTERIA_OK : EXTERIA_E_NOMEM;
    }
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "account.updatePersonalChannel");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "channel", input);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_admined_channels_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "channels.getAdminedPublicChannels");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_flag(request, "for_personal");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_admined_channels_parse(const exteria_tl_value *answer, exteria_dialog_row *rows, size_t cap, size_t *count) {
    const exteria_tl_value *chats;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (!rows || !count || !cap) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_chats) || exteria_tl_get_vec(answer, "chats", &chats) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (chats->u.vec.count > 1000) return EXTERIA_E_LIMIT;
    for (i = 0; i < chats->u.vec.count && n < cap; ++i) {
        const exteria_tl_value *chat = chats->u.vec.items[i];
        int64_t id;
        exteria_dialog_row row;
        if (!exteria_tl_is(chat, EXTERIA_TL_ID_channel) || exteria_tl_get_i64(chat, "id", &id) != EXTERIA_OK || id <= 0) continue;
        memset(&row, 0, sizeof(row));
        row.peer_kind = 3;
        row.peer_id = id;
        exteria_dialog_peer_read(&row, chats, chats, 0);
        /* a channel seen only in part has no usable hash, so it cannot be named in a request */
        if (!row.title[0] || row.peer_hash == 0) continue;
        rows[n++] = row;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_channel_message_request(exteria_arena *arena, const exteria_peer_ref *channel, int32_t id, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *ids, *message;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || id <= 0) return EXTERIA_E_ARG;
    status = input_channel(arena, channel, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "channels.getMessages");
    ids = exteria_tl_new_vec(arena, 1);
    message = exteria_tl_new_obj(arena, "inputMessageID");
    if (!request || !ids || !message) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, message, "id", id);
    if (status == EXTERIA_OK) status = exteria_tl_vec_set(ids, 0, message);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "channel", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", ids);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_profile_update_request(exteria_arena *arena, const char *first_name, const char *last_name, const char *about,
                                              exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status = EXTERIA_OK;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || (!first_name && !last_name && !about)) return EXTERIA_E_ARG;
    if (first_name && (!first_name[0] || strlen(first_name) > EXTERIA_NAME_PART_MAX)) return EXTERIA_E_ARG;
    if (last_name && strlen(last_name) > EXTERIA_NAME_PART_MAX) return EXTERIA_E_ARG;
    if (about && strlen(about) >= EXTERIA_ABOUT_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.updateProfile");
    if (!request) return EXTERIA_E_NOMEM;
    if (first_name) status = exteria_tl_set_str(arena, request, "first_name", first_name);
    if (status == EXTERIA_OK && last_name) status = exteria_tl_set_str(arena, request, "last_name", last_name);
    if (status == EXTERIA_OK && about) status = exteria_tl_set_str(arena, request, "about", about);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_username_check(const char *name) {
    size_t len, i;
    if (!name) return EXTERIA_E_ARG;
    len = strlen(name);
    if (len == 0) return EXTERIA_OK;
    if (len < EXTERIA_USERNAME_MIN || len > EXTERIA_USERNAME_MAX) return EXTERIA_E_ARG;
    for (i = 0; i < len; ++i) {
        char c = name[i];
        int letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        int digit = c >= '0' && c <= '9';
        if (!letter && !digit && c != '_') return EXTERIA_E_ARG;
        if (i == 0 && !letter) return EXTERIA_E_ARG;
    }
    if (name[len - 1] == '_') return EXTERIA_E_ARG;
    return EXTERIA_OK;
}

exteria_status exteria_username_request(exteria_arena *arena, const char *name, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || exteria_username_check(name) != EXTERIA_OK) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "account.updateUsername");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "username", name);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_profile_video_request(exteria_arena *arena, exteria_tl_value *video, double start_seconds, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    /* a second out of the clip, and a clip is of ten seconds at most: a value outside it is a mistake of the caller */
    if (!arena || !video || !(start_seconds >= 0) || start_seconds > 10) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "photos.uploadProfilePhoto");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "video", video);
    if (status == EXTERIA_OK) status = exteria_tl_set_f64(arena, request, "video_start_ts", start_seconds);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_profile_photo_request(exteria_arena *arena, exteria_tl_value *file, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !file) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "photos.uploadProfilePhoto");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "file", file);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_profile_public_photo_request(exteria_arena *arena, exteria_tl_value *file, exteria_tl_value **out) {
    exteria_tl_value *request = NULL;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    status = exteria_profile_photo_request(arena, file, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set_flag(request, "fallback");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_profile_photo_delete_request(exteria_arena *arena, const exteria_media_ref *photo, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *list;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !photo || photo->source != EXTERIA_MEDIA_SOURCE_PHOTO || photo->id == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "photos.deletePhotos");
    input = exteria_tl_new_obj(arena, "inputPhoto");
    list = exteria_tl_new_vec(arena, 1);
    if (!request || !input || !list) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "id", photo->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", photo->access_hash);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, input, "file_reference", photo->file_ref, photo->ref_len);
    if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, 0, input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static exteria_status contact_input_user(exteria_arena *arena, const exteria_peer_ref *user, exteria_tl_value **out) {
    exteria_tl_value *input;
    exteria_status status;
    *out = NULL;
    if (!arena || !user || user->kind != 1 || user->id <= 0 || user->access_hash == 0) return EXTERIA_E_ARG;
    input = exteria_tl_new_obj(arena, "inputUser");
    if (!input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "user_id", user->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", user->access_hash);
    if (status == EXTERIA_OK) *out = input;
    return status;
}

exteria_status exteria_common_chats_request(exteria_arena *arena, const exteria_peer_ref *user, int64_t max_id, int32_t limit, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || max_id < 0 || limit < 1 || limit > EXTERIA_COMMON_CHATS_PAGE) return EXTERIA_E_ARG;
    status = contact_input_user(arena, user, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.getCommonChats");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "user_id", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "max_id", max_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_common_chats_parse(const exteria_tl_value *answer, exteria_dialog_row *rows, size_t cap, size_t *count, int64_t *last_id, size_t *raw) {
    const exteria_tl_value *chats;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (last_id) *last_id = 0;
    if (raw) *raw = 0;
    if (!rows || !count || !last_id || !raw || !cap) return EXTERIA_E_ARG;
    if ((!exteria_tl_is(answer, EXTERIA_TL_ID_messages_chats) && !exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatsSlice)) ||
        exteria_tl_get_vec(answer, "chats", &chats) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (chats->u.vec.count > 1000) return EXTERIA_E_LIMIT;
    for (i = 0; i < chats->u.vec.count; ++i) {
        const exteria_tl_value *chat = chats->u.vec.items[i];
        int64_t id;
        exteria_dialog_row row;
        if (exteria_tl_get_i64(chat, "id", &id) != EXTERIA_OK || id <= 0) continue;
        *last_id = id;
        *raw += 1;
        if (n >= cap) continue;
        if (!exteria_tl_is(chat, EXTERIA_TL_ID_chat) && !exteria_tl_is(chat, EXTERIA_TL_ID_channel)) continue;
        memset(&row, 0, sizeof(row));
        row.peer_kind = exteria_tl_is(chat, EXTERIA_TL_ID_channel) ? 3 : 2;
        row.peer_id = id;
        exteria_dialog_peer_read(&row, chats, chats, 0);
        /* a channel seen only in part has no usable hash, so it cannot be opened */
        if (!row.title[0] || (row.peer_kind == 3 && row.peer_hash == 0)) continue;
        rows[n++] = row;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_contact_note_request(exteria_arena *arena, const exteria_peer_ref *user, const char *note, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *text;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!note || strlen(note) >= EXTERIA_CONTACT_NOTE_MAX) return EXTERIA_E_ARG;
    status = contact_input_user(arena, user, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "contacts.updateContactNote");
    text = exteria_tl_new_obj(arena, "textWithEntities");
    if (!request || !text) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, text, "text", note);
    if (status == EXTERIA_OK) status = exteria_tl_set(text, "entities", exteria_tl_new_vec(arena, 0));
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "note", text);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_contact_photo_request(exteria_arena *arena, const exteria_peer_ref *user, exteria_tl_value *file, int suggest, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!file) return EXTERIA_E_ARG;
    status = contact_input_user(arena, user, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "photos.uploadContactProfilePhoto");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "user_id", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "file", file);
    if (status == EXTERIA_OK && suggest) status = exteria_tl_set_flag(request, "suggest");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_contact_photo_reset_request(exteria_arena *arena, const exteria_peer_ref *user, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    status = contact_input_user(arena, user, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "photos.uploadContactProfilePhoto");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "user_id", input);
    /* the save flag without a file is how the server is told to take the personal photo away */
    if (status == EXTERIA_OK) status = exteria_tl_set_flag(request, "save");
    if (status == EXTERIA_OK) *out = request;
    return status;
}
