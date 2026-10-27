#include "test_util.h"
#include "exteria_message_actions.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_action_context sent_text(void) {
    exteria_action_context c;
    memset(&c, 0, sizeof(c));
    c.peer_kind = 2;
    c.message_id = 40;
    c.has_text = 1;
    c.media = EXTERIA_PREVIEW_TEXT;
    c.reactions_possible = 1;
    return c;
}

static void test_rules(void) {
    exteria_action_context c = sent_text();
    uint32_t base = EXTERIA_ACTION_REACT | EXTERIA_ACTION_REPLY | EXTERIA_ACTION_COPY | EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_SAVE |
                    EXTERIA_ACTION_PIN | EXTERIA_ACTION_DETAILS | EXTERIA_ACTION_SELECT | EXTERIA_ACTION_BOOKMARK | EXTERIA_ACTION_FORWARD_HIDDEN | EXTERIA_ACTION_REMIND;
    /* somebody else's text in a group: no edit, no delete, no link in a basic group, but it can be reported */
    CHECK_EQ_INT(exteria_message_actions_for(&c), base | EXTERIA_ACTION_REPORT);
    /* our own text adds edit, repeat and delete */
    c.outgoing = 1;
    CHECK_EQ_INT(exteria_message_actions_for(&c), base | EXTERIA_ACTION_EDIT | EXTERIA_ACTION_REPEAT | EXTERIA_ACTION_DELETE);
    /* formatting cannot go back through a plain field */
    c.has_entities = 1;
    CHECK_EQ_INT(exteria_message_actions_for(&c), base | EXTERIA_ACTION_DELETE);
    c.has_entities = 0;
    /* a photo with a caption can be copied and its caption edited, but not repeated as a text */
    c.media = EXTERIA_PREVIEW_PHOTO;
    CHECK_EQ_INT(exteria_message_actions_for(&c), base | EXTERIA_ACTION_EDIT | EXTERIA_ACTION_DELETE);
    /* a caption may also be added to one that has none, and to a video, an animation, a file and a song, not to a round video, a voice note or a sticker */
    c.has_text = 0;
    c.media = EXTERIA_PREVIEW_PHOTO;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT);
    c.media = EXTERIA_PREVIEW_VIDEO;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT);
    c.media = EXTERIA_PREVIEW_GIF;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT);
    c.media = EXTERIA_PREVIEW_FILE;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT);
    c.media = EXTERIA_PREVIEW_AUDIO;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT);
    c.media = EXTERIA_PREVIEW_VIDEO_MESSAGE;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT));
    c.media = EXTERIA_PREVIEW_VOICE;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT));
    c.media = EXTERIA_PREVIEW_STICKER;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT));
    c.media = EXTERIA_PREVIEW_LOCATION;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT));
    /* somebody else's picture, or a caption with formatting, is not edited */
    c.media = EXTERIA_PREVIEW_PHOTO;
    c.has_entities = 1;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT));
    c.has_entities = 0;
    c.outgoing = 0;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT));
    c.outgoing = 1;
    c.has_text = 1;
    c.media = EXTERIA_PREVIEW_TEXT;
    /* the pinned one offers the unpin instead */
    c.pinned_now = 1;
    CHECK_EQ_INT(exteria_message_actions_for(&c), (base & ~EXTERIA_ACTION_PIN) | EXTERIA_ACTION_UNPIN | EXTERIA_ACTION_EDIT |
                                                  EXTERIA_ACTION_REPEAT | EXTERIA_ACTION_DELETE);
    c.pinned_now = 0;
    /* no words, nothing to copy; a sticker has none */
    c.has_text = 0;
    c.outgoing = 0;
    c.media = EXTERIA_PREVIEW_STICKER;
    CHECK_EQ_INT(exteria_message_actions_for(&c), (base | EXTERIA_ACTION_REPORT) & ~EXTERIA_ACTION_COPY);
    /* a public channel or supergroup gives a link */
    c = sent_text();
    c.peer_kind = 3;
    c.has_username = 1;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_COPY_LINK);
    /* a private one has a link too, which the server makes */
    c.has_username = 0;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_COPY_LINK);
    c.peer_kind = 2;
    c.has_username = 1;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_COPY_LINK));
    /* in the favorites a message is not saved onto itself, and everything else stays */
    c = sent_text();
    c.saved_chat = 1;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_SAVE));
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_FORWARD);
    /* a forward of somebody else stands on the left there and is still ours to delete */
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_DELETE);
}

static void test_gallery_and_selection(void) {
    exteria_action_context c = sent_text();
    uint32_t masks[EXTERIA_MESSAGES_MAX + 1], together;
    size_t i;
    /* a photo, a video, a gif and a round video go to the library once the app can fetch their file; a sticker or a song never */
    c.has_text = 0;
    c.media_fetchable = 1;
    c.media = EXTERIA_PREVIEW_PHOTO;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_GALLERY);
    c.media = EXTERIA_PREVIEW_VIDEO;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_GALLERY);
    c.media = EXTERIA_PREVIEW_GIF;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_GALLERY);
    c.media = EXTERIA_PREVIEW_VIDEO_MESSAGE;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_GALLERY);
    c.media = EXTERIA_PREVIEW_STICKER;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_GALLERY));
    c.media = EXTERIA_PREVIEW_AUDIO;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_GALLERY));
    c.media = EXTERIA_PREVIEW_PHOTO;
    c.media_fetchable = 0;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_GALLERY));
    /* a message still on its way cannot be selected either */
    c = sent_text();
    c.message_id = 0;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_SELECT));

    /* selection: forward and delete need every message to allow it, copy needs one with words */
    masks[0] = EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_DELETE | EXTERIA_ACTION_COPY;
    masks[1] = EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_DELETE;
    CHECK_EQ_INT(exteria_selection_actions(masks, 2), EXTERIA_ACTION_SELECT | EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_DELETE | EXTERIA_ACTION_COPY);
    masks[1] = EXTERIA_ACTION_FORWARD;
    CHECK_EQ_INT(exteria_selection_actions(masks, 2), EXTERIA_ACTION_SELECT | EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_COPY);
    masks[0] = EXTERIA_ACTION_DELETE;
    CHECK_EQ_INT(exteria_selection_actions(masks, 2), EXTERIA_ACTION_SELECT);
    CHECK_EQ_INT(exteria_selection_actions(masks, 0), 0);
    CHECK_EQ_INT(exteria_selection_actions(NULL, 3), 0);
    /* the largest set one request carries, and one more that it does not */
    for (i = 0; i < EXTERIA_MESSAGES_MAX + 1; ++i) masks[i] = EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_DELETE;
    together = exteria_selection_actions(masks, EXTERIA_MESSAGES_MAX);
    CHECK_EQ_INT(together, EXTERIA_ACTION_SELECT | EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_DELETE);
    CHECK_EQ_INT(exteria_selection_actions(masks, EXTERIA_MESSAGES_MAX + 1), EXTERIA_ACTION_SELECT);
}

static void test_bookmark_and_transcribe(void) {
    exteria_action_context c = sent_text();
    exteria_tl_value *request = NULL, *answer;
    exteria_peer_ref user = {1, 5, 9, 0, 0}, nohash = {3, 500, 0, 0, 0};
    exteria_transcript t;
    const uint8_t *data;
    size_t len;
    char longest[EXTERIA_TRANSCRIPT_MAX + 8];
    exteria_writer wire;
    /* a bookmarked message offers the way out of the list instead of the way in */
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_BOOKMARK);
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_UNBOOKMARK));
    c.bookmarked = 1;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_BOOKMARK));
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_UNBOOKMARK);
    /* translation needs words, and the settings to ask for it */
    c.has_text = 1;
    c.translate_wanted = 0;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_TRANSLATE));
    c.translate_wanted = 1;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_TRANSLATE);
    c.has_text = 0;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_TRANSLATE));
    c.has_text = 1;
    c.service = 1;
    CHECK_EQ_INT(exteria_message_actions_for(&c), 0);
    c.service = 0;
    c.has_text = 0;
    /* only a voice message is transcribed */
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_TRANSCRIBE));
    c.has_text = 0;
    c.media = EXTERIA_PREVIEW_VOICE;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_TRANSCRIBE);
    c.media = EXTERIA_PREVIEW_AUDIO;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_TRANSCRIBE));
    c.media = EXTERIA_PREVIEW_VOICE;
    c.message_id = 0;
    CHECK(!(exteria_message_actions_for(&c) & (EXTERIA_ACTION_TRANSCRIBE | EXTERIA_ACTION_BOOKMARK | EXTERIA_ACTION_UNBOOKMARK)));

    CHECK_EQ_INT(exteria_transcribe_request(&arena, &user, 77, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_transcribeAudio);
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_transcribe_request(&arena, &user, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_transcribe_request(&arena, &nohash, 7, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_transcribe_request(&arena, NULL, 7, &request), EXTERIA_E_ARG);

    answer = exteria_tl_new_obj(&arena, "messages.transcribedAudio");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, answer, "transcription_id", 99), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, answer, "text", "привет мир"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_transcribe_parse(answer, &t), EXTERIA_OK);
    CHECK_EQ_INT(t.pending, 0);
    CHECK_EQ_INT(t.id, 99);
    CHECK(strcmp(t.text, "привет мир") == 0);
    CHECK_EQ_INT(exteria_tl_set_flag(answer, "pending"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_transcribe_parse(answer, &t), EXTERIA_OK);
    CHECK_EQ_INT(t.pending, 1);
    /* a text longer than the buffer is cut where a character ends */
    memset(longest, 'a', sizeof(longest));
    longest[EXTERIA_TRANSCRIPT_MAX - 2] = '\xD0';
    longest[EXTERIA_TRANSCRIPT_MAX - 1] = '\xB0';
    longest[EXTERIA_TRANSCRIPT_MAX + 4] = '\0';
    answer = exteria_tl_new_obj(&arena, "messages.transcribedAudio");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, answer, "transcription_id", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, answer, "text", longest), EXTERIA_OK);
    CHECK_EQ_INT(exteria_transcribe_parse(answer, &t), EXTERIA_OK);
    CHECK(strlen(t.text) < EXTERIA_TRANSCRIPT_MAX);
    /* the cut did not leave half of the two byte letter at its end */
    CHECK(strlen(t.text) == 0 || ((uint8_t)t.text[strlen(t.text) - 1] & 0xC0) != 0x80);
    CHECK_EQ_INT(exteria_tl_get_bytes(answer, "text", &data, &len), EXTERIA_OK);
    CHECK(len > strlen(t.text));
    /* anything else, a missing field, and a null answer are not a transcript */
    CHECK_EQ_INT(exteria_transcribe_parse(exteria_tl_new_obj(&arena, "boolTrue"), &t), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(t.id, 0);
    CHECK_EQ_INT(exteria_transcribe_parse(exteria_tl_new_obj(&arena, "messages.transcribedAudio"), &t), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_transcribe_parse(NULL, &t), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_transcribe_parse(answer, NULL), EXTERIA_E_ARG);
}

static void test_read_date(void) {
    exteria_tl_value *request = NULL, *answer;
    exteria_peer_ref user = {1, 5, 9, 0, 0}, nohash = {3, 500, 0, 0, 0};
    exteria_writer wire;
    int32_t date = 99;
    CHECK_EQ_INT(exteria_read_date_request(&arena, &user, 70, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getOutboxReadDate);
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_read_date_request(&arena, &user, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_read_date_request(&arena, &nohash, 7, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_read_date_request(&arena, NULL, 7, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_read_date_request(&arena, &user, 7, NULL), EXTERIA_E_ARG);

    answer = exteria_tl_new_obj(&arena, "outboxReadDate");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, answer, "date", 1760000000), EXTERIA_OK);
    CHECK_EQ_INT(exteria_read_date_parse(answer, &date), EXTERIA_OK);
    CHECK_EQ_INT(date, 1760000000);
    /* a date that is not a time, anything else, and nothing are no answer, and leave a zero */
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, answer, "date", 0), EXTERIA_OK);
    date = 5;
    CHECK_EQ_INT(exteria_read_date_parse(answer, &date), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(date, 0);
    CHECK_EQ_INT(exteria_read_date_parse(exteria_tl_new_obj(&arena, "boolTrue"), &date), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_read_date_parse(NULL, &date), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_read_date_parse(answer, NULL), EXTERIA_E_ARG);
}

static void test_group_read_dates(void) {
    exteria_peer_ref group = {2, 500, 0, 0, 0}, user = {1, 5, 9, 0, 0};
    exteria_tl_value *request = NULL, *vec, *first, *second;
    size_t count = 99;
    exteria_group_read_date rows[2];
    exteria_writer wire;
    CHECK_EQ_INT(exteria_group_read_dates_request(&arena, &group, 70, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getMessageReadParticipants);
    exteria_writer_init(&wire, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_group_read_dates_request(&arena, &user, 70, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_group_read_dates_request(&arena, &group, 0, &request), EXTERIA_E_ARG);
    vec = exteria_tl_new_vec(&arena, 2);
    first = exteria_tl_new_obj(&arena, "readParticipantDate");
    second = exteria_tl_new_obj(&arena, "readParticipantDate");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, first, "user_id", 3), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, first, "date", 100), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, second, "user_id", 4), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, second, "date", 200), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 0, first), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 1, second), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_read_dates_parse(vec, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].user_id, 3);
    CHECK_EQ_INT(rows[1].date, 200);
    CHECK_EQ_INT(exteria_group_read_dates_parse(vec, rows, 1, &count), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, second, "date", -1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_group_read_dates_parse(vec, rows, 2, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    vec = exteria_tl_new_vec(&arena, 0);
    CHECK_EQ_INT(exteria_group_read_dates_parse(vec, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_group_read_dates_parse(NULL, rows, 2, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_group_read_dates_parse(vec, rows, 2, NULL), EXTERIA_E_ARG);
}

static void test_broadcast(void) {
    exteria_action_context c = sent_text();
    uint32_t mask;
    c.peer_kind = 3;
    c.broadcast = 1;
    /* a reader of a channel can react, copy and pass it on, and nothing that writes into it */
    mask = exteria_message_actions_for(&c);
    CHECK(mask & (EXTERIA_ACTION_REACT | EXTERIA_ACTION_COPY | EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_SAVE));
    CHECK(!(mask & (EXTERIA_ACTION_REPLY | EXTERIA_ACTION_PIN | EXTERIA_ACTION_UNPIN | EXTERIA_ACTION_DELETE | EXTERIA_ACTION_EDIT)));
    /* an admin who may post can reply, pin and delete any post, and edit their own */
    c.can_post = 1;
    mask = exteria_message_actions_for(&c);
    CHECK(mask & (EXTERIA_ACTION_REPLY | EXTERIA_ACTION_PIN | EXTERIA_ACTION_DELETE));
    CHECK(!(mask & EXTERIA_ACTION_EDIT));
    c.outgoing = 1;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_EDIT);
}

static void test_unsent_and_service(void) {
    exteria_action_context c = sent_text();
    /* a message still on its way can only be copied */
    c.message_id = 0;
    c.outgoing = 1;
    CHECK_EQ_INT(exteria_message_actions_for(&c), EXTERIA_ACTION_COPY);
    c.message_id = -5;
    CHECK_EQ_INT(exteria_message_actions_for(&c), EXTERIA_ACTION_COPY);
    c.has_text = 0;
    CHECK_EQ_INT(exteria_message_actions_for(&c), 0);
    c = sent_text();
    c.service = 1;
    CHECK_EQ_INT(exteria_message_actions_for(&c), 0);
    CHECK_EQ_INT(exteria_message_actions_for(NULL), 0);
}

static void test_delete(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref user = {1, 5, 9, 0, 0}, group = {2, 40, 0, 0, 0}, channel = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0};
    int32_t ids[3] = {4, 5, 6};
    int32_t bad[2] = {4, 0};
    int32_t many[EXTERIA_MESSAGES_MAX + 1];
    const exteria_tl_value *list;
    exteria_writer wire;
    size_t i;
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &user, ids, 3, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_deleteMessages);
    CHECK(exteria_tl_has(request, "revoke"));
    list = exteria_tl_get(request, "id");
    CHECK(list && list->kind == EXTERIA_TL_V_VEC && list->u.vec.count == 3);
    exteria_writer_init(&wire, 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &group, ids, 1, 0, &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(request, "revoke"));
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &channel, ids, 3, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_deleteMessages);
    CHECK(exteria_tl_is(exteria_tl_get(request, "channel"), EXTERIA_TL_ID_inputChannel));
    exteria_writer_init(&wire, 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    /* the channel needs its access hash, ids are positive, and one request carries up to 100 */
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &nohash, ids, 3, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &user, bad, 2, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &user, ids, 0, 0, &request), EXTERIA_E_ARG);
    for (i = 0; i < EXTERIA_MESSAGES_MAX + 1; ++i) many[i] = (int32_t)i + 1;
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &user, many, EXTERIA_MESSAGES_MAX, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &user, many, EXTERIA_MESSAGES_MAX + 1, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, NULL, ids, 3, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &user, NULL, 3, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_delete_messages_request(&arena, &user, ids, 3, 0, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_delete_messages_parse(exteria_tl_new_obj(&arena, "messages.affectedMessages")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_delete_messages_parse(exteria_tl_new_obj(&arena, "boolTrue")), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_delete_messages_parse(NULL), EXTERIA_E_MALFORMED);
}

static void test_pin_and_edit(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref user = {1, 5, 9, 0, 0}, saved = {1, 1, 0, 1, 0}, nohash = {3, 500, 0, 0, 0};
    exteria_writer wire;
    const uint8_t *data;
    size_t len;
    char longest[EXTERIA_MESSAGE_TEXT_MAX + 1];
    CHECK_EQ_INT(exteria_pin_message_request(&arena, &user, 12, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_updatePinnedMessage);
    CHECK(!exteria_tl_has(request, "unpin"));
    CHECK_EQ_INT(exteria_pin_message_request(&arena, &user, 12, 1, &request), EXTERIA_OK);
    CHECK(exteria_tl_has(request, "unpin"));
    exteria_writer_init(&wire, 512);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_pin_message_request(&arena, &saved, 3, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_pin_message_request(&arena, &user, 0, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_pin_message_request(&arena, &nohash, 3, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_pin_message_request(&arena, NULL, 3, 0, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_edit_message_request(&arena, &user, 12, "new words", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_editMessage);
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "message", &data, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 9);
    CHECK_MEM(data, "new words", 9);
    exteria_writer_init(&wire, 512);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_edit_message_request(&arena, &user, 12, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_edit_message_request(&arena, &user, 0, "x", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_edit_message_request(&arena, &user, 12, NULL, &request), EXTERIA_E_ARG);
    memset(longest, 'a', sizeof(longest));
    longest[EXTERIA_MESSAGE_TEXT_MAX] = '\0';
    CHECK_EQ_INT(exteria_edit_message_request(&arena, &user, 12, longest, &request), EXTERIA_E_LIMIT);
    longest[EXTERIA_MESSAGE_TEXT_MAX - 1] = '\0';
    CHECK_EQ_INT(exteria_edit_message_request(&arena, &user, 12, longest, &request), EXTERIA_OK);

    /* a caption may be taken away: the field is sent empty, and no media with it */
    CHECK_EQ_INT(exteria_edit_caption_request(&arena, &user, 12, "", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_editMessage);
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "message", &data, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 0);
    CHECK(!exteria_tl_has(request, "media"));
    exteria_writer_init(&wire, 512);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_edit_caption_request(&arena, &user, 12, "a caption", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "message", &data, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 9);
    CHECK_EQ_INT(exteria_edit_caption_request(&arena, &user, 0, "x", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_edit_caption_request(&arena, &user, 12, NULL, &request), EXTERIA_E_ARG);
    longest[EXTERIA_MESSAGE_TEXT_MAX - 1] = 'a';
    longest[EXTERIA_MESSAGE_TEXT_MAX] = '\0';
    CHECK_EQ_INT(exteria_edit_caption_request(&arena, &user, 12, longest, &request), EXTERIA_E_LIMIT);
}

static void test_forward(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref from = {3, 500, 7, 0, 0}, to = {1, 5, 9, 0, 0}, saved = {1, 1, 0, 1, 0}, nohash = {3, 600, 0, 0, 0};
    int32_t ids[2] = {10, 11};
    int64_t random[2] = {111, 222}, zero[2] = {111, 0};
    const exteria_tl_value *list;
    exteria_writer wire;
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, &from, &to, ids, random, 2, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_forwardMessages);
    CHECK(exteria_tl_is(exteria_tl_get(request, "from_peer"), EXTERIA_TL_ID_inputPeerChannel));
    CHECK(exteria_tl_is(exteria_tl_get(request, "to_peer"), EXTERIA_TL_ID_inputPeerUser));
    list = exteria_tl_get(request, "random_id");
    CHECK(list && list->kind == EXTERIA_TL_V_VEC && list->u.vec.count == 2);
    exteria_writer_init(&wire, 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    /* to the favorites */
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, &from, &saved, ids, random, 2, 0, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "to_peer"), EXTERIA_TL_ID_inputPeerSelf));
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, &from, &to, ids, zero, 2, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, &nohash, &to, ids, random, 2, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, &from, &nohash, ids, random, 2, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, &from, &to, ids, random, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, &from, &to, ids, NULL, 2, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, NULL, &to, ids, random, 2, 0, &request), EXTERIA_E_ARG);
}

static void test_chat_search(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref channel = {3, 500, 7, 0, 0}, nohash = {3, 500, 0, 0, 0};
    exteria_writer wire;
    const uint8_t *data;
    size_t len;
    char longest[EXTERIA_CHAT_SEARCH_QUERY_MAX + 2];
    CHECK_EQ_INT(exteria_chat_search_request(&arena, &channel, "hello there", 50, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_search);
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "q", &data, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 11);
    CHECK_MEM(data, "hello there", 11);
    CHECK(exteria_tl_is(exteria_tl_get(request, "filter"), EXTERIA_TL_ID_inputMessagesFilterEmpty));
    exteria_writer_init(&wire, 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    /* the pinned list keeps its own filter and no text */
    CHECK_EQ_INT(exteria_pinned_request(&arena, &channel, 10, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "filter"), EXTERIA_TL_ID_inputMessagesFilterPinned));
    CHECK_EQ_INT(exteria_chat_search_request(&arena, &channel, "", 50, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_chat_search_request(&arena, &channel, NULL, 50, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_chat_search_request(&arena, &channel, "x", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_chat_search_request(&arena, &channel, "x", EXTERIA_MESSAGES_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_chat_search_request(&arena, &nohash, "x", 10, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_chat_search_request(&arena, NULL, "x", 10, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_chat_search_request(&arena, &channel, "x", 10, NULL), EXTERIA_E_ARG);
    memset(longest, 'a', sizeof(longest));
    longest[EXTERIA_CHAT_SEARCH_QUERY_MAX] = '\0';
    CHECK_EQ_INT(exteria_chat_search_request(&arena, &channel, longest, 10, &request), EXTERIA_OK);
    longest[EXTERIA_CHAT_SEARCH_QUERY_MAX] = 'a';
    longest[EXTERIA_CHAT_SEARCH_QUERY_MAX + 1] = '\0';
    CHECK_EQ_INT(exteria_chat_search_request(&arena, &channel, longest, 10, &request), EXTERIA_E_LIMIT);
    CHECK(request == NULL);
}

static void test_new_rules(void) {
    exteria_action_context c = sent_text();
    /* a photo that can be fetched is copied to the pasteboard; one without a file, or any other kind, is not */
    c.media = EXTERIA_PREVIEW_PHOTO;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_COPY_PHOTO));
    c.media_fetchable = 1;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_COPY_PHOTO);
    c.media = EXTERIA_PREVIEW_VIDEO;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_COPY_PHOTO));
    /* a report is for the messages of others, and not in the favorites */
    c = sent_text();
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_REPORT);
    c.outgoing = 1;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_REPORT));
    c.outgoing = 0;
    c.saved_chat = 1;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_REPORT));
    c = sent_text();
    c.message_id = 0;
    CHECK(!(exteria_message_actions_for(&c) & (EXTERIA_ACTION_REPORT | EXTERIA_ACTION_FORWARD_HIDDEN | EXTERIA_ACTION_REMIND)));
    c = sent_text();
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_REMIND);
    /* the history of a sender is offered in a group of any kind, never in a channel or a private chat */
    c = sent_text();
    c.sender_user = 1;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_HISTORY);
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_REPLY_PRIVATE);
    c.outgoing = 1;
    CHECK(!(exteria_message_actions_for(&c) & (EXTERIA_ACTION_HISTORY | EXTERIA_ACTION_REPLY_PRIVATE)));
    c.outgoing = 0;
    c.peer_kind = 3;
    CHECK(exteria_message_actions_for(&c) & EXTERIA_ACTION_HISTORY);
    c.broadcast = 1;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_HISTORY));
    c.broadcast = 0;
    c.peer_kind = 1;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_HISTORY));
    c.peer_kind = 2;
    c.sender_user = 0;
    CHECK(!(exteria_message_actions_for(&c) & EXTERIA_ACTION_HISTORY));
}

static void test_forward_hidden(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref from = {3, 500, 7, 0, 0}, to = {1, 5, 9, 0, 0};
    int32_t ids[1] = {10};
    int64_t random[1] = {111};
    exteria_writer wire;
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, &from, &to, ids, random, 1, 0, &request), EXTERIA_OK);
    CHECK(!exteria_tl_has(request, "drop_author"));
    CHECK_EQ_INT(exteria_forward_messages_request(&arena, &from, &to, ids, random, 1, 1, &request), EXTERIA_OK);
    CHECK(exteria_tl_has(request, "drop_author"));
    exteria_writer_init(&wire, 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
}

static void test_chat_from(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref group = {2, 500, 0, 0, 0}, person = {1, 7, 99, 0, 0}, nohash = {1, 7, 0, 0, 0}, channel = {3, 8, 5, 0, 0}, self = {1, 1, 0, 1, 0};
    exteria_writer wire;
    CHECK_EQ_INT(exteria_chat_from_request(&arena, &group, &person, 30, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_search);
    CHECK(exteria_tl_is(exteria_tl_get(request, "from_id"), EXTERIA_TL_ID_inputPeerUser));
    CHECK(exteria_tl_is(exteria_tl_get(request, "filter"), EXTERIA_TL_ID_inputMessagesFilterEmpty));
    exteria_writer_init(&wire, 1024);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    /* only a person with a hash can be searched for */
    CHECK_EQ_INT(exteria_chat_from_request(&arena, &group, &nohash, 30, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_chat_from_request(&arena, &group, &channel, 30, &request), EXTERIA_E_ARG);
    /* the account itself is searched by inputPeerSelf */
    CHECK_EQ_INT(exteria_chat_from_request(&arena, &group, &self, 30, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request, "from_id"), EXTERIA_TL_ID_inputPeerSelf));
    CHECK_EQ_INT(exteria_chat_from_request(&arena, &group, NULL, 30, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_chat_from_request(&arena, &group, &person, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_chat_from_request(&arena, &group, &person, 30, NULL), EXTERIA_E_ARG);
}

static void test_message_link(void) {
    exteria_tl_value *request = NULL, *answer_value;
    exteria_peer_ref channel = {3, 500, 7, 0, 0}, group = {2, 600, 0, 0, 0}, nohash = {3, 500, 0, 0, 0};
    char link[64];
    /* the link of a message */
    CHECK_EQ_INT(exteria_message_link_request(&arena, &channel, 77, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_channels_exportMessageLink);
    CHECK_EQ_INT(exteria_message_link_request(&arena, &group, 77, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_message_link_request(&arena, &nohash, 77, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_message_link_request(&arena, &channel, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_message_link_request(&arena, NULL, 77, &request), EXTERIA_E_ARG);
    answer_value = exteria_tl_new_obj(&arena, "exportedMessageLink");
    CHECK(answer_value != NULL);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, answer_value, "link", "https://t.me/c/1/77"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, answer_value, "html", "x"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_message_link_parse(answer_value, link, sizeof(link)), EXTERIA_OK);
    CHECK(strcmp(link, "https://t.me/c/1/77") == 0);
    CHECK_EQ_INT(exteria_message_link_parse(answer_value, link, 8), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(link[0], 0);
    CHECK_EQ_INT(exteria_message_link_parse(exteria_tl_new_obj(&arena, "boolTrue"), link, sizeof(link)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_message_link_parse(answer_value, NULL, 8), EXTERIA_E_ARG);
}

static void test_schedule(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref self = {1, 1, 0, 1, 0};
    int32_t value = 0;
    CHECK_EQ_INT(exteria_send_text_request(&arena, &self, "remind me", NULL, 0, 5, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_set_schedule(&arena, request, 2000000000), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "schedule_date", &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 2000000000);
    CHECK_EQ_INT(exteria_set_schedule(&arena, request, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_set_schedule(&arena, request, -5), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_set_schedule(&arena, NULL, 5), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_set_schedule(NULL, request, 5), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_rules();
    test_broadcast();
    test_gallery_and_selection();
    test_bookmark_and_transcribe();
    test_read_date();
    test_group_read_dates();
    test_unsent_and_service();
    test_delete();
    test_pin_and_edit();
    test_forward();
    test_new_rules();
    test_chat_from();
    test_message_link();
    test_schedule();
    test_forward_hidden();
    test_chat_search();
    exteria_arena_free(&arena);
    return test_finish("test_message_actions");
}
