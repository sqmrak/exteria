#include "test_util.h"
#include "exteria_profile.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set(exteria_tl_value *v, const char *field, exteria_tl_value *x) {
    CHECK_EQ_INT(exteria_tl_set(v, field, x), EXTERIA_OK);
}
static void str(exteria_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, field, x), EXTERIA_OK);
}
static void roundtrip(exteria_tl_value *request, uint32_t constructor) {
    exteria_writer writer;
    exteria_tl_value *decoded = NULL;
    exteria_writer_init(&writer, 65536);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, writer.data, writer.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), constructor);
    exteria_writer_free(&writer);
}

static void test_full_user(void) {
    exteria_full_user full;
    exteria_tl_value *answer = obj("users.userFull"), *inner = obj("userFull");
    exteria_tl_value *request = NULL;
    CHECK_EQ_INT(exteria_full_user_request(&arena, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_users_getFullUser);
    CHECK_EQ_INT(exteria_full_user_parse(answer, &full), EXTERIA_E_MALFORMED);
    set(answer, "full_user", inner);
    CHECK_EQ_INT(exteria_full_user_parse(answer, &full), EXTERIA_OK);
    CHECK_EQ_INT(full.about[0], 0);
    CHECK_EQ_INT(full.require_premium, 0);
    CHECK_EQ_INT(exteria_tl_set_flag(inner, "contact_require_premium"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_full_user_parse(answer, &full), EXTERIA_OK);
    CHECK_EQ_INT(full.require_premium, 1);
    str(inner, "about", "another developer\nline two");
    CHECK_EQ_INT(exteria_full_user_parse(answer, &full), EXTERIA_OK);
    CHECK(!strcmp(full.about, "another developer\nline two"));
    {
        char big[EXTERIA_ABOUT_MAX + 40];
        size_t i;
        for (i = 0; i + 2 < sizeof(big); i += 2) { big[i] = (char)0xd0; big[i + 1] = (char)0xb0; }
        big[sizeof(big) - 2] = 0;
        str(inner, "about", big);
        CHECK_EQ_INT(exteria_full_user_parse(answer, &full), EXTERIA_OK);
        CHECK(strlen(full.about) < EXTERIA_ABOUT_MAX);
        CHECK_EQ_INT(strlen(full.about) % 2, 0);
    }
    CHECK_EQ_INT(exteria_full_user_parse(obj("boolTrue"), &full), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(full.about[0], 0);
    CHECK_EQ_INT(exteria_full_user_parse(answer, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_full_user_request(&arena, NULL), EXTERIA_E_ARG);
}

static void test_update(void) {
    exteria_tl_value *request = NULL;
    char name[EXTERIA_NAME_PART_MAX + 2], about[EXTERIA_ABOUT_MAX + 1];
    CHECK_EQ_INT(exteria_profile_update_request(&arena, "Ann", "Lee", "hi", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "first_name"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "last_name"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "about"), 1);
    roundtrip(request, EXTERIA_TL_ID_account_updateProfile);
    /* only the fields that were given go out, and a last name or bio can be cleared with an empty string */
    CHECK_EQ_INT(exteria_profile_update_request(&arena, NULL, "", NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "first_name"), 0);
    CHECK_EQ_INT(exteria_tl_has(request, "last_name"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "about"), 0);
    roundtrip(request, EXTERIA_TL_ID_account_updateProfile);
    CHECK_EQ_INT(exteria_profile_update_request(&arena, NULL, NULL, NULL, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_profile_update_request(&arena, "", NULL, NULL, &request), EXTERIA_E_ARG);
    memset(name, 'a', sizeof(name));
    name[EXTERIA_NAME_PART_MAX + 1] = 0;
    CHECK_EQ_INT(exteria_profile_update_request(&arena, name, NULL, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_profile_update_request(&arena, NULL, name, NULL, &request), EXTERIA_E_ARG);
    name[EXTERIA_NAME_PART_MAX] = 0;
    CHECK_EQ_INT(exteria_profile_update_request(&arena, name, NULL, NULL, &request), EXTERIA_OK);
    memset(about, 'b', sizeof(about));
    about[EXTERIA_ABOUT_MAX] = 0;
    CHECK_EQ_INT(exteria_profile_update_request(&arena, NULL, NULL, about, &request), EXTERIA_E_ARG);
    about[EXTERIA_ABOUT_MAX - 1] = 0;
    CHECK_EQ_INT(exteria_profile_update_request(&arena, NULL, NULL, about, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_profile_update_request(&arena, "Ann", NULL, NULL, NULL), EXTERIA_E_ARG);
}

static void test_username(void) {
    static const char *good[] = {"", "lowspecialist", "abcde", "a_b_c_d1", "A1234", "abcdefghijklmnopqrstuvwxyz012345"};
    static const char *bad[] = {"abcd", "1abcde", "_abcde", "abcde_", "ab-cde", "ab cde", "abcdefghijklmnopqrstuvwxyz0123456", "ab\xc3\xa9" "cde", "@name1"};
    exteria_tl_value *request = NULL;
    size_t i;
    for (i = 0; i < sizeof(good) / sizeof(good[0]); ++i) CHECK_EQ_INT(exteria_username_check(good[i]), EXTERIA_OK);
    for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) CHECK_EQ_INT(exteria_username_check(bad[i]), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_username_check(NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_username_request(&arena, "lowspecialist", &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_updateUsername);
    CHECK_EQ_INT(exteria_username_request(&arena, "", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_username_request(&arena, "ab", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

static void test_photo(void) {
    exteria_tl_value *request = NULL, *file = obj("inputFile");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, file, "id", 5), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, file, "parts", 1), EXTERIA_OK);
    str(file, "name", "photo.jpg");
    str(file, "md5_checksum", "");
    CHECK_EQ_INT(exteria_profile_photo_request(&arena, file, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_photos_uploadProfilePhoto);
    CHECK_EQ_INT(exteria_profile_photo_request(&arena, NULL, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *vec = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(vec, i, items[i]), EXTERIA_OK);
    return vec;
}

static exteria_tl_value *user(int64_t id, const char *name, const char *phone) {
    exteria_tl_value *v = obj("user");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "access_hash", 99), EXTERIA_OK);
    str(v, "first_name", name);
    if (phone) str(v, "phone", phone);
    return v;
}

static exteria_tl_value *channel(int64_t id, const char *title, int with_hash) {
    exteria_tl_value *v = obj("channel");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "id", id), EXTERIA_OK);
    if (with_hash) CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "access_hash", 55), EXTERIA_OK);
    str(v, "title", title);
    CHECK_EQ_INT(exteria_tl_set_flag(v, "broadcast"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "participants_count", 83), EXTERIA_OK);
    return v;
}

static void test_peer_profile(void) {
    exteria_full_user *full = calloc(1, sizeof(*full));
    exteria_tl_value *answer = obj("users.userFull"), *inner = obj("userFull"), *birthday = obj("birthday"), *request = NULL;
    exteria_tl_value *users[1], *chats[2];
    exteria_peer_ref other = {1, 5, 7, 0, 0}, bad = {1, 5, 0, 0, 0}, group = {2, 5, 0, 0, 0};
    CHECK(full != NULL);
    CHECK_EQ_INT(exteria_full_user_peer_request(&arena, &other, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_users_getFullUser);
    CHECK_EQ_INT(exteria_full_user_peer_request(&arena, &bad, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_full_user_peer_request(&arena, &group, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    {
        exteria_peer_ref self = {1, 1, 0, 1, 0};
        CHECK_EQ_INT(exteria_full_user_peer_request(&arena, &self, &request), EXTERIA_OK);
    }
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, inner, "id", 5), EXTERIA_OK);
    str(inner, "about", "bio");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, birthday, "day", 12), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, birthday, "month", 3), EXTERIA_OK);
    set(inner, "birthday", birthday);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, inner, "personal_channel_id", 700), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, inner, "personal_channel_message", 42), EXTERIA_OK);
    set(answer, "full_user", inner);
    users[0] = user(5, "Kim", "79991234567");
    chats[0] = channel(700, "Kim news", 1);
    set(answer, "users", vec_of(users, 1));
    set(answer, "chats", vec_of(chats, 1));
    CHECK_EQ_INT(exteria_full_user_parse(answer, full), EXTERIA_OK);
    CHECK_EQ_INT(full->has_person, 1);
    CHECK(!strcmp(full->person.name, "Kim"));
    CHECK(!strcmp(full->person.phone, "79991234567"));
    CHECK_EQ_INT(full->has_birthday, 1);
    CHECK_EQ_INT(full->birthday_day, 12);
    CHECK_EQ_INT(full->birthday_month, 3);
    CHECK_EQ_INT(full->birthday_year, 0);
    CHECK_EQ_INT(full->has_channel, 1);
    CHECK_EQ_INT(full->channel.peer_id, 700);
    CHECK_EQ_INT(full->channel.peer_hash, 55);
    CHECK(!strcmp(full->channel.title, "Kim news"));
    CHECK_EQ_INT(full->channel_participants, 83);
    CHECK_EQ_INT(full->channel_message, 42);
    /* a channel the answer does not carry, or a birthday outside the calendar, is left out */
    set(answer, "chats", exteria_tl_new_vec(&arena, 0));
    CHECK_EQ_INT(exteria_full_user_parse(answer, full), EXTERIA_OK);
    CHECK_EQ_INT(full->has_channel, 0);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, birthday, "month", 13), EXTERIA_OK);
    CHECK_EQ_INT(exteria_full_user_parse(answer, full), EXTERIA_OK);
    CHECK_EQ_INT(full->has_birthday, 0);
    free(full);
}

static exteria_tl_value *song(int64_t id, const char *title, const char *performer, int32_t seconds, int with_reference) {
    static const uint8_t reference[] = {9, 8, 7};
    exteria_tl_value *d = obj("document"), *audio = obj("documentAttributeAudio"), *attributes[1];
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, d, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, d, "access_hash", id * 3), EXTERIA_OK);
    if (with_reference) CHECK_EQ_INT(exteria_tl_set_bytes(&arena, d, "file_reference", reference, sizeof(reference)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, d, "dc_id", 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, d, "size", 5000000), EXTERIA_OK);
    str(d, "mime_type", "audio/mpeg");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, audio, "duration", seconds), EXTERIA_OK);
    if (title) str(audio, "title", title);
    if (performer) str(audio, "performer", performer);
    attributes[0] = audio;
    set(d, "attributes", vec_of(attributes, 1));
    return d;
}

static void test_music(void) {
    exteria_tl_value *request = NULL, *answer = obj("users.savedMusic"), *docs[4];
    exteria_peer_ref other = {1, 5, 7, 0, 0}, self = {1, 1, 0, 1, 0}, bad = {1, 5, 0, 0, 0}, group = {2, 5, 0, 0, 0};
    exteria_media_info tracks[3];
    size_t count = 99;
    int32_t total = 99;
    exteria_full_user *full = calloc(1, sizeof(*full));
    exteria_tl_value *inner = obj("userFull"), *user_full = obj("users.userFull");
    CHECK(full != NULL);

    CHECK_EQ_INT(exteria_saved_music_request(&arena, &other, 0, EXTERIA_MUSIC_PAGE, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "hash"), 1);
    roundtrip(request, EXTERIA_TL_ID_users_getSavedMusic);
    CHECK_EQ_INT(exteria_saved_music_request(&arena, &self, 30, 1, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_users_getSavedMusic);
    CHECK_EQ_INT(exteria_saved_music_request(&arena, &bad, 0, 10, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_music_request(&arena, &group, 0, 10, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_music_request(&arena, &other, -1, 10, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_music_request(&arena, &other, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_music_request(&arena, &other, 0, EXTERIA_MUSIC_PAGE + 1, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_saved_music_request(&arena, &other, 0, 10, NULL), EXTERIA_E_ARG);

    /* a song without a file reference cannot be fetched and is left out, and the page is cut at the room the caller has */
    docs[0] = song(11, "The Science of Lies", "Demon Hunter", 215, 1);
    docs[1] = song(12, "Lost", "Nobody", 100, 0);
    docs[2] = song(13, NULL, NULL, 61, 1);
    docs[3] = song(14, "Fourth", "Band", 70, 1);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, answer, "count", 57), EXTERIA_OK);
    set(answer, "documents", vec_of(docs, 4));
    CHECK_EQ_INT(exteria_saved_music_parse(answer, tracks, 3, &count, &total), EXTERIA_OK);
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(total, 57);
    CHECK(!strcmp(tracks[0].title, "The Science of Lies"));
    CHECK(!strcmp(tracks[0].performer, "Demon Hunter"));
    CHECK_EQ_INT(tracks[0].duration, 215);
    CHECK_EQ_INT(tracks[0].kind, EXTERIA_PREVIEW_AUDIO);
    CHECK_EQ_INT(tracks[0].ref.id, 11);
    CHECK_EQ_INT(tracks[0].size, 5000000);
    CHECK_EQ_INT(tracks[1].ref.id, 13);
    CHECK_EQ_INT(tracks[1].title[0], 0);
    CHECK_EQ_INT(tracks[1].performer[0], 0);
    CHECK_EQ_INT(tracks[2].ref.id, 14);

    CHECK_EQ_INT(exteria_saved_music_parse(obj("users.savedMusicNotModified"), tracks, 3, &count, &total), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_saved_music_parse(obj("boolTrue"), tracks, 3, &count, &total), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_saved_music_parse(answer, tracks, 3, NULL, &total), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_music_parse(answer, tracks, 0, &count, &total), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);

    /* the profile's first song comes with the full user, and one without a usable file is left out */
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, inner, "id", 5), EXTERIA_OK);
    set(user_full, "full_user", inner);
    CHECK_EQ_INT(exteria_full_user_parse(user_full, full), EXTERIA_OK);
    CHECK_EQ_INT(full->has_music, 0);
    set(inner, "saved_music", song(21, "Intro", "Band", 33, 1));
    CHECK_EQ_INT(exteria_full_user_parse(user_full, full), EXTERIA_OK);
    CHECK_EQ_INT(full->has_music, 1);
    CHECK(!strcmp(full->music.title, "Intro"));
    CHECK_EQ_INT(full->music.ref.id, 21);
    set(inner, "saved_music", song(22, "Gone", "Band", 33, 0));
    CHECK_EQ_INT(exteria_full_user_parse(user_full, full), EXTERIA_OK);
    CHECK_EQ_INT(full->has_music, 0);
    CHECK_EQ_INT(full->music.title[0], 0);
    free(full);
}

static void test_save_music(void) {
    exteria_tl_value *request = NULL;
    exteria_media_ref song;
    memset(&song, 0, sizeof(song));
    song.source = EXTERIA_MEDIA_SOURCE_DOCUMENT;
    song.id = 77;
    song.access_hash = 5;
    song.ref_len = 3;
    song.file_ref[0] = 9;
    song.file_ref[1] = 8;
    song.file_ref[2] = 7;
    CHECK_EQ_INT(exteria_save_music_request(&arena, &song, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "unsave"), 0);
    roundtrip(request, EXTERIA_TL_ID_account_saveMusic);
    CHECK_EQ_INT(exteria_save_music_request(&arena, &song, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "unsave"), 1);
    roundtrip(request, EXTERIA_TL_ID_account_saveMusic);
    /* a cover of the song, a photo, a song without a reference or without an id cannot be saved */
    song.thumb[0] = 'm';
    CHECK_EQ_INT(exteria_save_music_request(&arena, &song, 0, &request), EXTERIA_E_ARG);
    song.thumb[0] = 0;
    song.source = EXTERIA_MEDIA_SOURCE_PHOTO;
    CHECK_EQ_INT(exteria_save_music_request(&arena, &song, 0, &request), EXTERIA_E_ARG);
    song.source = EXTERIA_MEDIA_SOURCE_DOCUMENT;
    song.ref_len = 0;
    CHECK_EQ_INT(exteria_save_music_request(&arena, &song, 0, &request), EXTERIA_E_ARG);
    song.ref_len = 3;
    song.id = 0;
    CHECK_EQ_INT(exteria_save_music_request(&arena, &song, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_save_music_request(&arena, NULL, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_save_music_request(&arena, &song, 0, NULL), EXTERIA_E_ARG);
}

static void test_birthday_channels(void) {
    exteria_tl_value *request = NULL, *answer = obj("messages.chats"), *chats[3];
    exteria_dialog_row rows[4];
    size_t count = 9;
    exteria_peer_ref chan = {3, 700, 55, 0, 0}, nohash = {3, 700, 0, 0, 0}, user_peer = {1, 5, 7, 0, 0};
    CHECK_EQ_INT(exteria_birthday_request(&arena, 29, 2, 2000, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_updateBirthday);
    CHECK_EQ_INT(exteria_tl_has(request, "birthday"), 1);
    CHECK_EQ_INT(exteria_birthday_request(&arena, 29, 2, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_birthday_request(&arena, 29, 2, 2001, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_birthday_request(&arena, 31, 4, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_birthday_request(&arena, 0, 4, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_birthday_request(&arena, 5, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_birthday_request(&arena, 5, 13, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_birthday_request(&arena, 5, 6, 1899, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_birthday_request(&arena, 5, 6, 2101, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_birthday_clear_request(&arena, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "birthday"), 0);
    roundtrip(request, EXTERIA_TL_ID_account_updateBirthday);

    CHECK_EQ_INT(exteria_personal_channel_request(&arena, &chan, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_updatePersonalChannel);
    CHECK_EQ_INT(exteria_personal_channel_request(&arena, NULL, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "channel")), EXTERIA_TL_ID_inputChannelEmpty);
    CHECK_EQ_INT(exteria_personal_channel_request(&arena, &nohash, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_personal_channel_request(&arena, &user_peer, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_admined_channels_request(&arena, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "for_personal"), 1);
    roundtrip(request, EXTERIA_TL_ID_channels_getAdminedPublicChannels);
    chats[0] = channel(1, "One", 1);
    chats[1] = channel(2, "Min", 0);
    chats[2] = obj("chatEmpty");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, chats[2], "id", 3), EXTERIA_OK);
    set(answer, "chats", vec_of(chats, 3));
    CHECK_EQ_INT(exteria_admined_channels_parse(answer, rows, 4, &count), EXTERIA_OK);
    /* the channel without a hash and the one that is no channel are left out */
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].peer_id, 1);
    CHECK_EQ_INT(rows[0].peer_hash, 55);
    CHECK_EQ_INT(exteria_admined_channels_parse(obj("boolTrue"), rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_admined_channels_parse(answer, NULL, 4, &count), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_channel_message_request(&arena, &chan, 42, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_channels_getMessages);
    CHECK_EQ_INT(exteria_channel_message_request(&arena, &chan, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_channel_message_request(&arena, &nohash, 42, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

int main(void) {
    exteria_arena_init(&arena, 16u * 1024u * 1024u);
    test_full_user();
    test_update();
    test_username();
    test_photo();
    test_peer_profile();
    test_birthday_channels();
    test_music();
    test_save_music();
    exteria_arena_free(&arena);
    return test_finish("test_profile");
}
