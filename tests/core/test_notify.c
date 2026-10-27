#include "test_util.h"
#include "exteria_notify.h"

#define NOW 1700000000

static exteria_notify_settings settings(void) {
    exteria_notify_settings s;
    memset(&s, 0, sizeof(s));
    s.enabled = 1;
    exteria_notify_rules_init(&s.rules);
    return s;
}

/* an unread incoming message of a user chat; the tests change what they test */
static exteria_dialog_row row(int64_t peer, int32_t top, const char *title, const char *text) {
    exteria_dialog_row r;
    memset(&r, 0, sizeof(r));
    r.peer_kind = 1;
    r.peer_id = peer;
    r.kind = EXTERIA_DIALOG_USER;
    r.top_message = top;
    r.unread_count = 1;
    r.date = NOW - 30;
    r.preview = EXTERIA_PREVIEW_TEXT;
    snprintf(r.title, sizeof(r.title), "%s", title);
    snprintf(r.text, sizeof(r.text), "%s", text);
    return r;
}

static size_t run(exteria_notify_state *state, const exteria_notify_settings *s, const exteria_dialog_row *rows, size_t n, exteria_notify_event *events,
                  size_t cap, size_t *more) {
    size_t count = 99;
    *more = 99;
    CHECK_EQ_INT(exteria_notify_diff(state, s, rows, n, NOW, 0, 0, events, cap, &count, more), EXTERIA_OK);
    return count;
}

static void test_baseline_and_new(void) {
    exteria_notify_state state;
    exteria_notify_settings s = settings();
    exteria_dialog_row rows[2];
    exteria_notify_event events[4];
    size_t more;
    exteria_notify_state_init(&state);
    rows[0] = row(10, 100, "Ann", "hello");
    rows[1] = row(11, 50, "Bob", "old");
    /* the first look only takes the baseline: everything unread already was there */
    CHECK_EQ_INT(run(&state, &s, rows, 2, events, 4, &more), 0);
    CHECK_EQ_INT(state.baselined, 1);
    CHECK_EQ_INT(state.count, 2);
    /* the same list again has nothing new */
    CHECK_EQ_INT(run(&state, &s, rows, 2, events, 4, &more), 0);
    /* a newer message of one chat is announced with its title and text */
    rows[0] = row(10, 101, "Ann", "second");
    CHECK_EQ_INT(run(&state, &s, rows, 2, events, 4, &more), 1);
    CHECK_EQ_INT(more, 0);
    CHECK_EQ_INT(events[0].peer_kind, 1);
    CHECK_EQ_INT(events[0].peer_id, 10);
    CHECK_EQ_INT(events[0].message_id, 101);
    CHECK(!strcmp(events[0].title, "Ann"));
    CHECK(!strcmp(events[0].body, "second"));
    /* and only once */
    CHECK_EQ_INT(run(&state, &s, rows, 2, events, 4, &more), 0);
    /* a chat the first look did not know that brings a message now is new */
    rows[1] = row(12, 7, "Cy", "hi");
    CHECK_EQ_INT(run(&state, &s, rows, 2, events, 4, &more), 1);
    CHECK_EQ_INT(events[0].peer_id, 12);
}

static void test_filters(void) {
    exteria_notify_state state;
    exteria_notify_settings s = settings();
    exteria_dialog_row base[1], r;
    exteria_notify_event events[4];
    size_t more;
    base[0] = row(10, 1, "Ann", "x");
    exteria_notify_state_init(&state);
    run(&state, &s, base, 1, events, 4, &more);

    r = row(10, 2, "Ann", "muted");
    r.notify.has_mute = 1;
    r.notify.mute_until = NOW + 3600;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    r = row(10, 3, "Ann", "ours");
    r.outgoing = 1;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    r = row(10, 4, "Ann", "read elsewhere");
    r.unread_count = 0;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    r = row(10, 5, "Ann", "read up to it");
    r.read_inbox_max_id = 5;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    r = row(10, 6, "Ann", "saved");
    r.saved = 1;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    r = row(10, 7, "Ann", "archive entry");
    r.folder = 1;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    r = row(10, 8, "Ann", "deleted");
    r.deleted = 1;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    /* a chat that was only filtered still moves on: its next message is judged by itself */
    r = row(10, 9, "Ann", "after the filters");
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);

    /* the switches of kinds and the master switch */
    r = row(20, 1, "Team", "t");
    r.peer_kind = 2;
    r.kind = EXTERIA_DIALOG_GROUP;
    run(&state, &s, &r, 1, events, 4, &more);
    r.top_message = 2;
    s.rules.scope[EXTERIA_SCOPE_CHATS].has_mute = 1;
    s.rules.scope[EXTERIA_SCOPE_CHATS].mute_until = EXTERIA_NOTIFY_MUTE_FOREVER;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    s.rules.scope[EXTERIA_SCOPE_CHATS].has_mute = 0;
    r.top_message = 3;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
    r = row(30, 1, "News", "n");
    r.peer_kind = 3;
    r.kind = EXTERIA_DIALOG_CHANNEL;
    run(&state, &s, &r, 1, events, 4, &more);
    r.top_message = 2;
    s.rules.scope[EXTERIA_SCOPE_BROADCASTS].has_mute = 1;
    s.rules.scope[EXTERIA_SCOPE_BROADCASTS].mute_until = EXTERIA_NOTIFY_MUTE_FOREVER;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    s.rules.scope[EXTERIA_SCOPE_BROADCASTS].has_mute = 0;
    r = row(10, 10, "Ann", "disabled");
    s.enabled = 0;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    s.enabled = 1;

    /* the chat on screen stays quiet */
    r = row(10, 11, "Ann", "on screen");
    {
        size_t count = 99;
        CHECK_EQ_INT(exteria_notify_diff(&state, &s, &r, 1, NOW, 1, 10, events, 4, &count, &more), EXTERIA_OK);
        CHECK_EQ_INT(count, 0);
    }
    /* a message older than the catch-up window is not news, one inside it is */
    r = row(10, 12, "Ann", "old");
    r.date = NOW - EXTERIA_NOTIFY_CATCHUP_SECONDS - 10;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    r = row(10, 13, "Ann", "recent");
    r.date = NOW - EXTERIA_NOTIFY_CATCHUP_SECONDS + 10;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
}

static void test_words(void) {
    exteria_notify_state state;
    exteria_notify_settings s = settings();
    exteria_dialog_row r, base;
    exteria_notify_event events[2];
    size_t more;
    base = row(10, 1, "Ann", "x");
    exteria_notify_state_init(&state);
    run(&state, &s, &base, 1, events, 2, &more);

    /* a message without text says what it is, in the language of the settings */
    r = row(10, 2, "Ann", "");
    r.preview = EXTERIA_PREVIEW_PHOTO;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 2, &more), 1);
    CHECK(!strcmp(events[0].body, "Photo"));
    s.russian = 1;
    r = row(10, 3, "Ann", "");
    r.preview = EXTERIA_PREVIEW_VOICE;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 2, &more), 1);
    CHECK(!strcmp(events[0].body, "\xD0\x93\xD0\xBE\xD0\xBB\xD0\xBE\xD1\x81\xD0\xBE\xD0\xB2\xD0\xBE\xD0\xB5 \xD1\x81\xD0\xBE\xD0\xBE\xD0\xB1\xD1\x89\xD0\xB5\xD0\xBD\xD0\xB8\xD0\xB5"));
    s.russian = 0;
    /* with previews off the text stays home */
    s.rules.scope[EXTERIA_SCOPE_USERS].has_previews = 1;
    s.rules.scope[EXTERIA_SCOPE_USERS].previews = 0;
    r = row(10, 4, "Ann", "secret");
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 2, &more), 1);
    CHECK(!strcmp(events[0].body, "New message"));
    s.rules.scope[EXTERIA_SCOPE_USERS].has_previews = 0;
    /* a group names who wrote; an empty title falls back to the name of the service; line breaks become spaces */
    r = row(20, 1, "", "line one\nline two");
    r.peer_kind = 2;
    r.kind = EXTERIA_DIALOG_GROUP;
    snprintf(r.sender, sizeof(r.sender), "Dan");
    run(&state, &s, &r, 1, events, 2, &more);
    r.top_message = 2;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 2, &more), 1);
    CHECK(!strcmp(events[0].title, "Telegram"));
    CHECK(!strcmp(events[0].body, "Dan: line one line two"));
    {
        char text[64];
        exteria_notify_more_text(&s, 3, text, sizeof(text));
        CHECK(!strcmp(text, "And 3 more"));
        s.russian = 1;
        exteria_notify_more_text(&s, 3, text, sizeof(text));
        CHECK(strstr(text, "3") != NULL);
        exteria_notify_more_text(&s, 3, text, 3);
        CHECK_EQ_INT(strlen(text), 2);
    }
}

static void test_cap_and_order(void) {
    exteria_notify_state state;
    exteria_notify_settings s = settings();
    exteria_dialog_row rows[5];
    exteria_notify_event events[2];
    size_t more, i;
    exteria_notify_state_init(&state);
    for (i = 0; i < 5; ++i) rows[i] = row(100 + (int64_t)i, 1, "c", "t");
    run(&state, &s, rows, 5, events, 2, &more);
    /* five chats get news; the list is newest first, so rows[0] is the newest */
    for (i = 0; i < 5; ++i) {
        rows[i] = row(100 + (int64_t)i, 2, "c", "t");
        rows[i].top_message = 2;
        rows[i].date = NOW - 10 - (int32_t)i * 10;
    }
    CHECK_EQ_INT(run(&state, &s, rows, 5, events, 2, &more), 2);
    CHECK_EQ_INT(more, 3);
    /* the two newest are kept and the older of those two goes first */
    CHECK_EQ_INT(events[0].peer_id, 101);
    CHECK_EQ_INT(events[1].peer_id, 100);
    /* all five were looked at, so none comes again */
    CHECK_EQ_INT(run(&state, &s, rows, 5, events, 2, &more), 0);
    /* a cap of zero and the arguments */
    {
        size_t count;
        CHECK_EQ_INT(exteria_notify_diff(&state, &s, rows, 5, NOW, 0, 0, NULL, 0, &count, &more), EXTERIA_OK);
        CHECK_EQ_INT(exteria_notify_diff(NULL, &s, rows, 5, NOW, 0, 0, events, 2, &count, &more), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_notify_diff(&state, NULL, rows, 5, NOW, 0, 0, events, 2, &count, &more), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_notify_diff(&state, &s, NULL, 5, NOW, 0, 0, events, 2, &count, &more), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_notify_diff(&state, &s, rows, 5, NOW, 0, 0, events, 2, NULL, &more), EXTERIA_E_ARG);
    }
}

static void test_seen_limit(void) {
    exteria_notify_state state;
    exteria_notify_settings s = settings();
    exteria_dialog_row rows[EXTERIA_DIALOGS_MAX];
    exteria_notify_event events[2];
    size_t more, i, round;
    exteria_notify_state_init(&state);
    /* more chats than the state holds: the oldest remembered ones make room and the count stays bounded */
    for (round = 0; round < 3; ++round) {
        for (i = 0; i < EXTERIA_DIALOGS_MAX; ++i) rows[i] = row(1000 + (int64_t)(round * EXTERIA_DIALOGS_MAX + i), 1, "c", "t");
        run(&state, &s, rows, EXTERIA_DIALOGS_MAX, events, 2, &more);
        CHECK(state.count <= EXTERIA_NOTIFY_SEEN_MAX);
    }
    CHECK_EQ_INT(state.count, EXTERIA_NOTIFY_SEEN_MAX);
    /* the most recently looked at chat is still there */
    CHECK_EQ_INT(state.seen[state.count - 1].peer_id, 1000 + 3 * EXTERIA_DIALOGS_MAX - 1);
}

static void test_state_file(void) {
    exteria_notify_state state, back;
    uint8_t bytes[EXTERIA_NOTIFY_STATE_BYTES];
    size_t len;
    exteria_notify_state_init(&state);
    state.baselined = 1;
    state.count = 2;
    state.seen[0].peer_kind = 1;
    state.seen[0].peer_id = 5000000000ll;
    state.seen[0].top_message = 77;
    state.seen[1].peer_kind = 3;
    state.seen[1].peer_id = 1234;
    state.seen[1].top_message = 2147483647;
    CHECK_EQ_INT(exteria_notify_state_pack(&state, bytes, sizeof(bytes), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 8 + 2 * 16);
    CHECK_EQ_INT(exteria_notify_state_unpack(bytes, len, &back), EXTERIA_OK);
    CHECK_EQ_INT(back.baselined, 1);
    CHECK_EQ_INT(back.count, 2);
    CHECK_EQ_INT(back.seen[0].peer_id, 5000000000ll);
    CHECK_EQ_INT(back.seen[1].top_message, 2147483647);
    CHECK_EQ_INT(exteria_notify_state_pack(&state, bytes, 10, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_notify_state_pack(&state, bytes, sizeof(bytes), NULL), EXTERIA_E_ARG);
    /* a file that is cut, has the wrong magic, version or count, or has a tail is refused and leaves a fresh state */
    CHECK_EQ_INT(exteria_notify_state_pack(&state, bytes, sizeof(bytes), &len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_notify_state_unpack(bytes, len - 1, &back), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(back.count, 0);
    CHECK_EQ_INT(back.baselined, 0);
    bytes[0] = 'X';
    CHECK_EQ_INT(exteria_notify_state_unpack(bytes, len, &back), EXTERIA_E_MALFORMED);
    bytes[0] = 'E';
    bytes[4] = 9;
    CHECK_EQ_INT(exteria_notify_state_unpack(bytes, len, &back), EXTERIA_E_MALFORMED);
    bytes[4] = 1;
    bytes[5] = 2;
    CHECK_EQ_INT(exteria_notify_state_unpack(bytes, len, &back), EXTERIA_E_MALFORMED);
    bytes[5] = 1;
    bytes[7] = 0xff;
    CHECK_EQ_INT(exteria_notify_state_unpack(bytes, len, &back), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_notify_state_unpack(NULL, 0, &back), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_notify_state_unpack(bytes, len, NULL), EXTERIA_E_ARG);
}

static void test_lines(void) {
    exteria_notify_event event, back;
    char line[EXTERIA_NOTIFY_LINE_MAX];
    size_t len;
    memset(&event, 0, sizeof(event));
    event.peer_kind = 2;
    event.peer_id = 9000000000ll;
    event.message_id = 321;
    snprintf(event.title, sizeof(event.title), "Team\tchat");
    snprintf(event.body, sizeof(event.body), "Dan: one\ntwo\r\nthree");
    CHECK_EQ_INT(exteria_notify_line_encode(&event, line, sizeof(line), &len), EXTERIA_OK);
    CHECK_EQ_INT(line[len - 1], '\n');
    CHECK_EQ_INT(strlen(line), len);
    CHECK_EQ_INT(exteria_notify_line_decode(line, len - 1, &back), EXTERIA_OK);
    CHECK_EQ_INT(back.peer_kind, 2);
    CHECK_EQ_INT(back.peer_id, 9000000000ll);
    CHECK_EQ_INT(back.message_id, 321);
    CHECK(!strcmp(back.title, "Team chat"));
    CHECK(!strcmp(back.body, "Dan: one two  three"));
    /* the longest texts still fit the line size the daemon uses */
    memset(event.title, 'a', sizeof(event.title) - 1);
    event.title[sizeof(event.title) - 1] = 0;
    memset(event.body, 'b', sizeof(event.body) - 1);
    event.body[sizeof(event.body) - 1] = 0;
    CHECK_EQ_INT(exteria_notify_line_encode(&event, line, sizeof(line), &len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_notify_line_decode(line, len - 1, &back), EXTERIA_OK);
    CHECK_EQ_INT(strlen(back.title), sizeof(event.title) - 1);
    CHECK_EQ_INT(strlen(back.body), sizeof(event.body) - 1);
    CHECK_EQ_INT(exteria_notify_line_encode(&event, line, 20, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_notify_line_encode(NULL, line, sizeof(line), &len), EXTERIA_E_ARG);
    /* lines that are not one of ours */
    {
        static const char *const bad[] = {
            "", "N", "N\t", "X\t1\t5\t7\tt\tb", "N\t0\t5\t7\tt\tb", "N\t4\t5\t7\tt\tb", "N\t1\t0\t7\tt\tb", "N\t1\t-5\t7\tt\tb", "N\t1\t5\t0\tt\tb",
            "N\t1\t5\t3000000000\tt\tb", "N\t1\tabc\t7\tt\tb", "N\t1\t5\t7\t\tb", "N\t1\t5\t7\tt", "N\t1\t5\t7\tt\tb\textra", "N\t1\t99999999999999999999\t7\tt\tb"};
        size_t i;
        for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
            CHECK_EQ_INT(exteria_notify_line_decode(bad[i], strlen(bad[i]), &back), EXTERIA_E_MALFORMED);
            CHECK_EQ_INT(back.title[0], 0);
        }
    }
    /* an empty body is a valid line */
    CHECK_EQ_INT(exteria_notify_line_decode("N\t1\t5\t7\tt\t", 10, &back), EXTERIA_OK);
    CHECK_EQ_INT(back.body[0], 0);
    CHECK_EQ_INT(exteria_notify_line_decode("N\t1\t5\t7\tt\tb", 11, NULL), EXTERIA_E_ARG);
}

static void test_rules(void) {
    exteria_notify_state state;
    exteria_notify_settings s = settings();
    exteria_dialog_row base, r;
    exteria_notify_event events[4];
    size_t more;
    exteria_notify_state_init(&state);
    base = row(10, 1, "Ann", "x");
    run(&state, &s, &base, 1, events, 4, &more);

    /* a chat that turns notifications on stands over a kind that is off */
    s.rules.scope[EXTERIA_SCOPE_USERS].has_mute = 1;
    s.rules.scope[EXTERIA_SCOPE_USERS].mute_until = EXTERIA_NOTIFY_MUTE_FOREVER;
    r = row(10, 2, "Ann", "kind is off");
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    r = row(10, 3, "Ann", "chat is on");
    r.notify.has_mute = 1;
    r.notify.mute_until = 0;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
    /* a mute that is over is no mute */
    s.rules.scope[EXTERIA_SCOPE_USERS].mute_until = NOW - 1;
    r = row(10, 4, "Ann", "mute is over");
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
    s.rules.scope[EXTERIA_SCOPE_USERS].has_mute = 0;

    /* the chat decides about the text, over its kind */
    s.rules.scope[EXTERIA_SCOPE_USERS].has_previews = 1;
    s.rules.scope[EXTERIA_SCOPE_USERS].previews = 0;
    r = row(10, 5, "Ann", "shown here");
    r.notify.has_previews = 1;
    r.notify.previews = 1;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
    CHECK(!strcmp(events[0].body, "shown here"));
    s.rules.scope[EXTERIA_SCOPE_USERS].has_previews = 0;

    /* the tone: the kind's, the chat's over it, and silence over both */
    s.rules.scope[EXTERIA_SCOPE_USERS].has_sound = 1;
    s.rules.scope[EXTERIA_SCOPE_USERS].sound.kind = EXTERIA_SOUND_LOCAL;
    snprintf(s.rules.scope[EXTERIA_SCOPE_USERS].sound.data, EXTERIA_SOUND_NAME_MAX, "sound_in.caf");
    r = row(10, 6, "Ann", "kind tone");
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
    CHECK_EQ_INT(events[0].sound.kind, EXTERIA_SOUND_LOCAL);
    CHECK(!strcmp(events[0].sound.data, "sound_in.caf"));
    r = row(10, 7, "Ann", "chat tone");
    r.notify.has_sound = 1;
    r.notify.sound.kind = EXTERIA_SOUND_NONE;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
    CHECK_EQ_INT(events[0].sound.kind, EXTERIA_SOUND_NONE);
    r = row(10, 8, "Ann", "silent chat");
    r.notify.has_silent = 1;
    r.notify.silent = 1;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
    CHECK_EQ_INT(events[0].sound.kind, EXTERIA_SOUND_NONE);
    s.rules.scope[EXTERIA_SCOPE_USERS].has_sound = 0;

    /* a pinned message and a new contact have switches of their own */
    r = row(10, 9, "Ann", "pinned");
    r.service = EXTERIA_SERVICE_PIN + 1;
    s.rules.pinned_messages = 0;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    s.rules.pinned_messages = 1;
    r.top_message = 10;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
    r = row(10, 11, "Ann", "joined");
    r.service = EXTERIA_SERVICE_CONTACT_JOINED + 1;
    s.rules.contact_joined = 0;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 0);
    s.rules.contact_joined = 1;
    r.top_message = 12;
    CHECK_EQ_INT(run(&state, &s, &r, 1, events, 4, &more), 1);
}

int main(void) {
    test_baseline_and_new();
    test_filters();
    test_words();
    test_cap_and_order();
    test_seen_limit();
    test_state_file();
    test_lines();
    test_rules();
    return test_finish("test_notify");
}
