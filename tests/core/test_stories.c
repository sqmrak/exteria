#include "test_util.h"
#include "exteria_stories.h"
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
static void i32(exteria_tl_value *v, const char *field, int32_t x) {
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, field, x), EXTERIA_OK);
}
static void i64(exteria_tl_value *v, const char *field, int64_t x) {
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, field, x), EXTERIA_OK);
}
static void str(exteria_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, field, x), EXTERIA_OK);
}
static void flag(exteria_tl_value *v, const char *field) {
    CHECK_EQ_INT(exteria_tl_set_flag(v, field), EXTERIA_OK);
}
static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *vec = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(vec, i, items[i]), EXTERIA_OK);
    return vec;
}
static exteria_tl_value *story(int32_t id, int32_t date) {
    exteria_tl_value *v = obj("storyItem");
    i32(v, "id", id);
    i32(v, "date", date);
    i32(v, "expire_date", date + 86400);
    set(v, "media", obj("messageMediaEmpty"));
    return v;
}
static exteria_tl_value *peer_stories(int64_t user, int32_t max_read, exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *v = obj("peerStories"), *peer = obj("peerUser");
    i64(peer, "user_id", user);
    set(v, "peer", peer);
    if (max_read) i32(v, "max_read_id", max_read);
    set(v, "stories", vec_of(items, n));
    return v;
}
static exteria_tl_value *user(int64_t id, const char *name) {
    exteria_tl_value *v = obj("user");
    i64(v, "id", id);
    i64(v, "access_hash", 77);
    str(v, "first_name", name);
    return v;
}

static exteria_tl_value *track(int64_t id, const char *title, const char *performer) {
    static const uint8_t reference[] = {4, 5, 6};
    exteria_tl_value *d = obj("document"), *audio = obj("documentAttributeAudio"), *attributes[1];
    i64(d, "id", id);
    i64(d, "access_hash", id * 3);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, d, "file_reference", reference, sizeof(reference)), EXTERIA_OK);
    i32(d, "dc_id", 2);
    i64(d, "size", 3000000);
    str(d, "mime_type", "audio/mpeg");
    i32(audio, "duration", 190);
    str(audio, "title", title);
    str(audio, "performer", performer);
    attributes[0] = audio;
    set(d, "attributes", vec_of(attributes, 1));
    return d;
}

static void test_story_music(void) {
    exteria_story_row row;
    exteria_tl_value *item = story(6, 2000);
    CHECK_EQ_INT(exteria_story_read(item, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.music.ref.source, EXTERIA_MEDIA_SOURCE_NONE);
    set(item, "music", track(31, "IVL", "MACAN & SCIRENA"));
    CHECK_EQ_INT(exteria_story_read(item, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.music.ref.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);
    CHECK_EQ_INT(row.music.ref.id, 31);
    CHECK_EQ_INT(row.music.kind, EXTERIA_PREVIEW_AUDIO);
    CHECK_EQ_INT(row.music.duration, 190);
    CHECK(!strcmp(row.music.title, "IVL"));
    CHECK(!strcmp(row.music.performer, "MACAN & SCIRENA"));
    /* the track does not touch the picture of the story */
    CHECK_EQ_INT(row.media.kind, EXTERIA_PREVIEW_TEXT);
    /* a music field that is not a document leaves the story without a track */
    set(item, "music", obj("documentEmpty"));
    CHECK_EQ_INT(exteria_story_read(item, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.music.ref.source, EXTERIA_MEDIA_SOURCE_NONE);
}

static void test_story_read(void) {
    exteria_story_row row;
    exteria_tl_value *item = story(5, 1000), *views = obj("storyViews"), *reaction = obj("reactionEmoji");
    CHECK_EQ_INT(exteria_story_read(item, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.id, 5);
    CHECK_EQ_INT(row.expire_date, 1000 + 86400);
    CHECK_EQ_INT(row.skipped, 0);
    CHECK_EQ_INT(row.reacted, 0);
    str(item, "caption", "hello");
    flag(item, "pinned");
    i32(views, "views_count", 12);
    set(item, "views", views);
    str(reaction, "emoticon", "❤");
    set(item, "sent_reaction", reaction);
    CHECK_EQ_INT(exteria_story_read(item, &row), EXTERIA_OK);
    CHECK(!strcmp(row.caption, "hello"));
    CHECK_EQ_INT(row.pinned, 1);
    CHECK_EQ_INT(row.views, 12);
    CHECK_EQ_INT(row.reacted, 1);
    CHECK(!strcmp(row.reaction.emoji, "❤"));

    item = obj("storyItemSkipped");
    i32(item, "id", 9);
    i32(item, "date", 50);
    i32(item, "expire_date", 90);
    CHECK_EQ_INT(exteria_story_read(item, &row), EXTERIA_OK);
    CHECK_EQ_INT(row.skipped, 1);
    CHECK_EQ_INT(row.id, 9);

    item = obj("storyItemDeleted");
    i32(item, "id", 3);
    CHECK_EQ_INT(exteria_story_read(item, &row), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(row.id, 0);
    CHECK_EQ_INT(exteria_story_read(obj("boolTrue"), &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_story_read(NULL, &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_story_read(story(0, 1), &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_story_read(story(-4, 1), &row), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_story_read(item, NULL), EXTERIA_E_ARG);

    /* a caption longer than the buffer is cut on a character boundary */
    item = story(6, 1);
    {
        char big[EXTERIA_STORY_CAPTION_MAX + 8];
        size_t i;
        for (i = 0; i + 2 < sizeof(big); i += 2) { big[i] = (char)0xd0; big[i + 1] = (char)0xb0; }
        big[sizeof(big) - 2] = 0;
        str(item, "caption", big);
    }
    CHECK_EQ_INT(exteria_story_read(item, &row), EXTERIA_OK);
    CHECK_EQ_INT(strlen(row.caption) % 2, 0);
    CHECK(strlen(row.caption) < EXTERIA_STORY_CAPTION_MAX);
}

static void test_peers(void) {
    exteria_story_peer peers[4];
    size_t count = 99;
    int more = 7;
    exteria_tl_value *a[] = {story(1, 100), story(2, 200), story(3, 300)}, *b[] = {story(4, 400)}, *c[] = {obj("storyItemDeleted")};
    exteria_tl_value *entries[3], *answer = obj("stories.allStories"), *users[2];
    i32(c[0], "id", 8);
    entries[0] = peer_stories(10, 2, a, 3);
    entries[1] = peer_stories(11, 0, b, 1);
    entries[2] = peer_stories(12, 0, c, 1);
    users[0] = user(10, "Ann");
    users[1] = user(11, "Bob");
    set(answer, "peer_stories", vec_of(entries, 3));
    set(answer, "users", vec_of(users, 2));
    set(answer, "chats", exteria_tl_new_vec(&arena, 0));
    flag(answer, "has_more");
    CHECK_EQ_INT(exteria_story_peers_parse(answer, 1, peers, 4, &count, &more), EXTERIA_OK);
    /* poster 12 has only a deleted story, it has no ring */
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(more, 1);
    CHECK_EQ_INT(peers[0].owner.peer_id, 10);
    CHECK(!strcmp(peers[0].owner.title, "Ann"));
    CHECK_EQ_INT(peers[0].owner.peer_hash, 77);
    CHECK_EQ_INT(peers[0].count, 3);
    CHECK_EQ_INT(peers[0].unread, 1);
    CHECK_EQ_INT(peers[0].first_unread_id, 3);
    CHECK_EQ_INT(peers[0].newest_date, 300);
    CHECK_EQ_INT(peers[1].unread, 1);
    CHECK_EQ_INT(peers[1].first_unread_id, 4);
    CHECK_EQ_INT(peers[0].close_friends, 0);
    CHECK_EQ_INT(peers[1].close_friends, 0);

    /* the green ring needs an unseen close friends story: a seen one leaves the ring as it was */
    flag(a[2], "close_friends");
    CHECK_EQ_INT(exteria_story_peers_parse(answer, 1, peers, 4, &count, &more), EXTERIA_OK);
    CHECK_EQ_INT(peers[0].close_friends, 1);
    CHECK_EQ_INT(peers[1].close_friends, 0);
    entries[0] = peer_stories(10, 3, a, 3);
    set(answer, "peer_stories", vec_of(entries, 3));
    CHECK_EQ_INT(exteria_story_peers_parse(answer, 1, peers, 4, &count, &more), EXTERIA_OK);
    CHECK_EQ_INT(peers[0].unread, 0);
    CHECK_EQ_INT(peers[0].close_friends, 0);
    entries[0] = peer_stories(10, 2, a, 3);
    set(answer, "peer_stories", vec_of(entries, 3));

    CHECK_EQ_INT(exteria_story_peers_parse(answer, 1, peers, 1, &count, &more), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);

    CHECK_EQ_INT(exteria_story_peers_parse(obj("stories.allStoriesNotModified"), 1, peers, 4, &count, &more), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_story_peers_parse(obj("boolTrue"), 1, peers, 4, &count, &more), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_story_peers_parse(answer, 1, NULL, 4, &count, &more), EXTERIA_E_ARG);
    set(answer, "peer_stories", exteria_tl_new_vec(&arena, EXTERIA_STORY_PEERS_MAX + 1));
    CHECK_EQ_INT(exteria_story_peers_parse(answer, 1, peers, 4, &count, &more), EXTERIA_E_LIMIT);

    /* a poster the answer carries no user for has no name and is dropped */
    entries[0] = peer_stories(40, 0, b, 1);
    set(answer, "peer_stories", vec_of(entries, 1));
    CHECK_EQ_INT(exteria_story_peers_parse(answer, 1, peers, 4, &count, &more), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
}

static void test_peer_and_list(void) {
    exteria_story_peer peer;
    exteria_story_row rows[4];
    size_t count;
    exteria_tl_value *a[] = {story(1, 100), story(2, 200)}, *users[1], *answer = obj("stories.peerStories"), *list = obj("stories.stories");
    users[0] = user(10, "Ann");
    set(answer, "stories", peer_stories(10, 1, a, 2));
    set(answer, "users", vec_of(users, 1));
    set(answer, "chats", exteria_tl_new_vec(&arena, 0));
    CHECK_EQ_INT(exteria_story_peer_parse(answer, 1, &peer, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[1].id, 2);
    CHECK_EQ_INT(peer.unread, 1);
    CHECK_EQ_INT(peer.max_read_id, 1);
    CHECK_EQ_INT(exteria_story_peer_parse(answer, 1, &peer, rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(peer.count, 2);
    CHECK_EQ_INT(exteria_story_peer_parse(obj("boolTrue"), 1, &peer, rows, 4, &count), EXTERIA_E_MALFORMED);

    a[1] = obj("storyItemDeleted");
    i32(a[1], "id", 2);
    set(list, "stories", vec_of(a, 2));
    CHECK_EQ_INT(exteria_stories_parse(list, rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].id, 1);
    set(list, "stories", exteria_tl_new_vec(&arena, EXTERIA_STORIES_MAX + 1));
    CHECK_EQ_INT(exteria_stories_parse(list, rows, 4, &count), EXTERIA_E_LIMIT);
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

static void test_send_photo(void) {
    exteria_tl_value *request = NULL, *file = obj("inputFile");
    int32_t period = 0;
    i64(file, "id", 99);
    i32(file, "parts", 1);
    str(file, "name", "story.jpg");
    str(file, "md5_checksum", "");
    CHECK_EQ_INT(exteria_story_send_photo_request(&arena, file, 5, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_sendStory);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "period", &period), EXTERIA_OK);
    CHECK_EQ_INT(period, EXTERIA_STORY_PERIOD);
    CHECK_EQ_INT(exteria_tl_is(exteria_tl_get(request, "peer"), EXTERIA_TL_ID_inputPeerSelf), 1);
    CHECK_EQ_INT(exteria_tl_is(exteria_tl_get(request, "media"), EXTERIA_TL_ID_inputMediaUploadedPhoto), 1);
    /* the story goes to everyone, not to a list of friends */
    CHECK_EQ_INT(exteria_tl_has(request, "pinned"), 0);
    CHECK_EQ_INT(exteria_story_send_photo_request(&arena, file, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_story_send_photo_request(&arena, NULL, 5, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_send_photo_request(&arena, file, 5, NULL), EXTERIA_E_ARG);
}

static void test_manage(void) {
    exteria_peer_ref self = {1, 5, 0, 1, 0};
    exteria_tl_value *request = NULL, *file = obj("inputFile");
    int32_t ids[] = {4, 5};
    int32_t zero[] = {0};
    exteria_story_row row;
    i64(file, "id", 9);
    i32(file, "parts", 1);
    str(file, "name", "story.jpg");
    str(file, "md5_checksum", "");
    CHECK_EQ_INT(exteria_story_publish_photo_request(&arena, file, 5, "hello", EXTERIA_STORY_CLOSE_FRIENDS, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_sendStory);
    CHECK_EQ_INT(exteria_tl_has(request, "caption"), 1);
    CHECK_EQ_INT(exteria_story_publish_photo_request(&arena, file, 5, NULL, EXTERIA_STORY_CONTACTS, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_sendStory);
    CHECK_EQ_INT(exteria_tl_has(request, "caption"), 0);
    CHECK_EQ_INT(exteria_story_publish_photo_request(&arena, file, 5, NULL, (exteria_story_privacy)9, &request), EXTERIA_E_ARG);
    {
        /* an audience with people: everyone but two, only three chosen ones, and the refusals */
        static exteria_story_audience audience;
        memset(&audience, 0, sizeof(audience));
        audience.base = EXTERIA_STORY_EVERYONE;
        audience.deny_count = 2;
        audience.deny[0].id = 11; audience.deny[0].access_hash = 111;
        audience.deny[1].id = 12; audience.deny[1].access_hash = 112;
        CHECK_EQ_INT(exteria_story_publish_photo_audience_request(&arena, file, 5, NULL, &audience, &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_stories_sendStory);
        audience.base = EXTERIA_STORY_SELECTED;
        CHECK_EQ_INT(exteria_story_publish_photo_audience_request(&arena, file, 5, NULL, &audience, &request), EXTERIA_E_ARG);
        audience.allow_count = 3;
        audience.allow[0].id = 21; audience.allow[1].id = 22; audience.allow[2].id = 23;
        CHECK_EQ_INT(exteria_story_publish_photo_audience_request(&arena, file, 5, "x", &audience, &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_stories_sendStory);
        CHECK_EQ_INT(exteria_story_edit_audience_request(&arena, &self, 3, NULL, 1, &audience, &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_stories_editStory);
        audience.allow_count = EXTERIA_STORY_USERS_MAX + 1;
        CHECK_EQ_INT(exteria_story_edit_audience_request(&arena, &self, 3, NULL, 1, &audience, &request), EXTERIA_E_LIMIT);
        CHECK_EQ_INT(exteria_story_publish_photo_request(&arena, file, 5, NULL, EXTERIA_STORY_SELECTED, &request), EXTERIA_E_ARG);
    }
    CHECK_EQ_INT(exteria_story_edit_request(&arena, &self, 3, "new", 1, EXTERIA_STORY_CONTACTS, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_editStory);
    CHECK_EQ_INT(exteria_tl_has(request, "caption"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "privacy_rules"), 1);
    CHECK_EQ_INT(exteria_story_edit_request(&arena, &self, 3, NULL, 0, EXTERIA_STORY_EVERYONE, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_editStory);
    CHECK_EQ_INT(exteria_tl_has(request, "caption"), 0);
    CHECK_EQ_INT(exteria_tl_has(request, "privacy_rules"), 0);
    CHECK_EQ_INT(exteria_story_edit_request(&arena, &self, 0, "x", 0, EXTERIA_STORY_EVERYONE, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_delete_request(&arena, &self, ids, 2, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_deleteStories);
    CHECK_EQ_INT(exteria_story_delete_request(&arena, &self, zero, 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_pin_request(&arena, &self, ids, 2, 0, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_togglePinned);
    CHECK_EQ_INT(exteria_story_pin_request(&arena, &self, ids, 2, 1, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_togglePinned);
    memset(&row, 0, sizeof(row));
    CHECK_EQ_INT(exteria_story_row_privacy(&row), EXTERIA_STORY_EVERYONE);
    row.contacts = 1;
    CHECK_EQ_INT(exteria_story_row_privacy(&row), EXTERIA_STORY_CONTACTS);
    row.close_friends = 1;
    CHECK_EQ_INT(exteria_story_row_privacy(&row), EXTERIA_STORY_CLOSE_FRIENDS);
}

static void test_requests(void) {
    exteria_peer_ref peers[] = {{1, 5, 7, 0, 0}, {3, 7, 9, 0, 0}, {1, 1, 0, 1, 0}};
    exteria_peer_ref bad = {1, 5, 0, 0, 0};
    exteria_reaction like;
    exteria_tl_value *request = NULL;
    int32_t ids[] = {1, 2, 3};
    int32_t zero[] = {1, 0};
    size_t i;
    memset(&like, 0, sizeof(like));
    like.kind = EXTERIA_REACTION_EMOJI;
    strcpy(like.emoji, "❤");
    CHECK_EQ_INT(exteria_story_all_request(&arena, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "next"), 0);
    roundtrip(request, EXTERIA_TL_ID_stories_getAllStories);
    CHECK_EQ_INT(exteria_story_all_request(&arena, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "next"), 1);
    roundtrip(request, EXTERIA_TL_ID_stories_getAllStories);
    for (i = 0; i < sizeof(peers) / sizeof(peers[0]); ++i) {
        CHECK_EQ_INT(exteria_story_peer_request(&arena, &peers[i], &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_stories_getPeerStories);
        CHECK_EQ_INT(exteria_story_ids_request(&arena, &peers[i], ids, 3, &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_stories_getStoriesByID);
        CHECK_EQ_INT(exteria_story_views_request(&arena, &peers[i], ids, 3, &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_stories_incrementStoryViews);
        CHECK_EQ_INT(exteria_story_read_request(&arena, &peers[i], 3, &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_stories_readStories);
        CHECK_EQ_INT(exteria_story_react_request(&arena, &peers[i], 3, &like, &request), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_has(request, "add_to_recent"), 1);
        roundtrip(request, EXTERIA_TL_ID_stories_sendReaction);
        CHECK_EQ_INT(exteria_story_react_request(&arena, &peers[i], 3, NULL, &request), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_has(request, "add_to_recent"), 0);
        CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "reaction")), EXTERIA_TL_ID_reactionEmpty);
        roundtrip(request, EXTERIA_TL_ID_stories_sendReaction);
    }
    CHECK_EQ_INT(exteria_story_reply_request(&arena, &peers[0], 4, "nice", 9, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "reply_to")), EXTERIA_TL_ID_inputReplyToStory);
    roundtrip(request, EXTERIA_TL_ID_messages_sendMessage);

    /* a story goes out as inputMediaStory naming the poster, to a user, a channel or the account itself, and into the topic a forum target names */
    for (i = 0; i < 3; ++i) {
        exteria_peer_ref target = {1, 77, 5, 0, 0};
        const exteria_tl_value *media;
        CHECK_EQ_INT(exteria_story_forward_request(&arena, &target, &peers[i], 8, 11, &request), EXTERIA_OK);
        media = exteria_tl_get(request, "media");
        CHECK_EQ_INT(exteria_tl_id(media), EXTERIA_TL_ID_inputMediaStory);
        CHECK(exteria_tl_get(media, "peer") != NULL);
        CHECK_EQ_INT(exteria_tl_has(request, "reply_to"), 0);
        roundtrip(request, EXTERIA_TL_ID_messages_sendMedia);
    }
    {
        exteria_peer_ref topic = {3, 90, 6, 0, 4};
        CHECK_EQ_INT(exteria_story_forward_request(&arena, &topic, &peers[0], 8, 11, &request), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "reply_to")), EXTERIA_TL_ID_inputReplyToMessage);
        roundtrip(request, EXTERIA_TL_ID_messages_sendMedia);
    }
    {
        exteria_peer_ref target = {1, 77, 5, 0, 0};
        CHECK_EQ_INT(exteria_story_forward_request(&arena, &target, &peers[0], 0, 11, &request), EXTERIA_E_ARG);
        CHECK(request == NULL);
        CHECK_EQ_INT(exteria_story_forward_request(&arena, &target, &peers[0], 8, 0, &request), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_story_forward_request(&arena, &bad, &peers[0], 8, 11, &request), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_story_forward_request(&arena, &target, &bad, 8, 11, &request), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_story_forward_request(&arena, &target, &peers[0], 8, 11, NULL), EXTERIA_E_ARG);
    }

    CHECK_EQ_INT(exteria_story_peer_request(&arena, &bad, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_story_ids_request(&arena, &peers[0], NULL, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_ids_request(&arena, &peers[0], zero, 2, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_ids_request(&arena, &peers[0], ids, EXTERIA_STORIES_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_read_request(&arena, &peers[0], 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_react_request(&arena, &peers[0], 0, &like, &request), EXTERIA_E_ARG);
    like.emoji[0] = 0;
    CHECK_EQ_INT(exteria_story_react_request(&arena, &peers[0], 3, &like, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_reply_request(&arena, &peers[0], 0, "x", 9, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_reply_request(&arena, &peers[0], 4, "", 9, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_reply_request(&arena, &peers[0], 4, "x", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_all_request(&arena, 0, NULL), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_story_pinned_request(&arena, &peers[2], 0, 30, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_getPinnedStories);
    CHECK_EQ_INT(exteria_story_archive_request(&arena, &peers[2], 12, 1, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_stories_getStoriesArchive);
    CHECK_EQ_INT(exteria_story_archive_request(&arena, &peers[2], -1, 30, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_archive_request(&arena, &peers[2], 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_pinned_request(&arena, &peers[2], 0, EXTERIA_STORIES_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_story_pinned_request(&arena, &bad, 0, 5, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

int main(void) {
    exteria_arena_init(&arena, 16u * 1024u * 1024u);
    test_story_read();
    test_story_music();
    test_peers();
    test_peer_and_list();
    test_requests();
    test_send_photo();
    test_manage();
    exteria_arena_free(&arena);
    return test_finish("test_stories");
}
