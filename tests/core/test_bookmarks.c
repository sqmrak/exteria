#include "test_util.h"
#include "exteria_bookmarks.h"

static exteria_bookmarks list;

static exteria_bookmark mark(int32_t kind, int64_t peer, int32_t message, const char *title, const char *text) {
    exteria_bookmark b;
    memset(&b, 0, sizeof(b));
    b.peer_kind = kind;
    b.peer_id = peer;
    b.peer_hash = peer * 7;
    b.dialog_kind = 3;
    b.message_id = message;
    b.date = 1000 + message;
    b.added = 5000;
    snprintf(b.title, sizeof(b.title), "%s", title);
    snprintf(b.text, sizeof(b.text), "%s", text);
    return b;
}

static void test_add_remove(void) {
    exteria_bookmark a = mark(3, 500, 10, "News", "first"), b = mark(1, 5, 20, "Ann", "second"), again = mark(3, 500, 10, "News", "edited");
    exteria_bookmarks_init(&list);
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &a), EXTERIA_OK);
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &b), EXTERIA_OK);
    /* the newest is first */
    CHECK_EQ_INT(list.count, 2);
    CHECK_EQ_INT(list.items[0].message_id, 20);
    CHECK_EQ_INT(list.items[1].message_id, 10);
    CHECK(exteria_bookmarks_contains(&list, 3, 500, 10));
    CHECK(!exteria_bookmarks_contains(&list, 3, 500, 11));
    /* the same message again moves to the front with its new text instead of appearing twice */
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &again), EXTERIA_OK);
    CHECK_EQ_INT(list.count, 2);
    CHECK_EQ_INT(list.items[0].message_id, 10);
    CHECK(strcmp(list.items[0].text, "edited") == 0);
    CHECK_EQ_INT(list.items[1].message_id, 20);
    /* a chat and a message number are one key together: the same number in another chat is another message */
    b = mark(3, 600, 10, "Other", "x");
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &b), EXTERIA_OK);
    CHECK_EQ_INT(list.count, 3);
    CHECK_EQ_INT(exteria_bookmarks_remove(&list, 3, 500, 10), EXTERIA_OK);
    CHECK_EQ_INT(list.count, 2);
    CHECK(!exteria_bookmarks_contains(&list, 3, 500, 10));
    CHECK_EQ_INT(exteria_bookmarks_remove(&list, 3, 500, 10), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(list.items[0].peer_id, 600);
    CHECK_EQ_INT(list.items[1].peer_id, 5);
    /* what was moved out leaves nothing behind */
    CHECK_EQ_INT(list.items[2].peer_id, 0);
}

static void test_capacity(void) {
    size_t i;
    exteria_bookmark e;
    exteria_bookmarks_init(&list);
    for (i = 1; i <= EXTERIA_BOOKMARKS_MAX + 5; ++i) {
        e = mark(2, 40, (int32_t)i, "Group", "m");
        CHECK_EQ_INT(exteria_bookmarks_add(&list, &e), EXTERIA_OK);
    }
    CHECK_EQ_INT(list.count, EXTERIA_BOOKMARKS_MAX);
    /* the five oldest are gone, the newest is first */
    CHECK_EQ_INT(list.items[0].message_id, EXTERIA_BOOKMARKS_MAX + 5);
    CHECK_EQ_INT(list.items[EXTERIA_BOOKMARKS_MAX - 1].message_id, 6);
    CHECK(!exteria_bookmarks_contains(&list, 2, 40, 5));
    /* an entry already in a full list is refreshed, nothing falls off */
    e = mark(2, 40, 6, "Group", "again");
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &e), EXTERIA_OK);
    CHECK_EQ_INT(list.count, EXTERIA_BOOKMARKS_MAX);
    CHECK_EQ_INT(list.items[0].message_id, 6);
    CHECK(exteria_bookmarks_contains(&list, 2, 40, 7));
}

static void test_invalid(void) {
    exteria_bookmark e = mark(3, 500, 10, "T", "x");
    exteria_bookmarks_init(&list);
    e.peer_kind = 0;
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &e), EXTERIA_E_ARG);
    e.peer_kind = 4;
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &e), EXTERIA_E_ARG);
    e = mark(3, 0, 10, "T", "x");
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &e), EXTERIA_E_ARG);
    e = mark(3, 500, 0, "T", "x");
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &e), EXTERIA_E_ARG);
    e = mark(3, 500, 10, "T", "x");
    memset(e.title, 'a', sizeof(e.title));
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &e), EXTERIA_E_ARG);
    e = mark(3, 500, 10, "T", "x");
    memset(e.text, 'a', sizeof(e.text));
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &e), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_bookmarks_add(&list, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_bookmarks_add(NULL, &e), EXTERIA_E_ARG);
    CHECK_EQ_INT(list.count, 0);
    CHECK_EQ_INT(exteria_bookmarks_remove(NULL, 3, 500, 10), EXTERIA_E_ARG);
    CHECK(!exteria_bookmarks_contains(NULL, 3, 500, 10));
}

static uint8_t file[EXTERIA_BOOKMARKS_FILE_MAX];

static void test_pack(void) {
    exteria_bookmarks back;
    exteria_bookmark a = mark(3, INT64_C(8202789099), 52164, "slopHLE chat", "ну так ты подшарил"), b = mark(1, 5, 20, "Ann", "second");
    size_t len = 0, i;
    exteria_bookmarks_init(&list);
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &a), EXTERIA_OK);
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &b), EXTERIA_OK);
    /* an account id past 32 bits survives */
    CHECK_EQ_INT(exteria_bookmarks_pack(&list, INT64_C(6731700753), file, sizeof(file), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 20 + 2 * 252);
    CHECK_EQ_INT(exteria_bookmarks_unpack(file, len, INT64_C(6731700753), &back), EXTERIA_OK);
    CHECK_EQ_INT(back.count, 2);
    CHECK_EQ_INT(back.items[0].peer_id, 5);
    CHECK_EQ_INT(back.items[1].peer_id, INT64_C(8202789099));
    CHECK_EQ_INT(back.items[1].peer_hash, INT64_C(8202789099) * 7);
    CHECK_EQ_INT(back.items[1].message_id, 52164);
    CHECK(strcmp(back.items[1].text, "ну так ты подшарил") == 0);
    /* another account's file is not ours, and says so without an error of its own */
    CHECK_EQ_INT(exteria_bookmarks_unpack(file, len, INT64_C(6731700754), &back), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(back.count, 0);
    /* an empty list packs and reads back empty */
    exteria_bookmarks_init(&list);
    CHECK_EQ_INT(exteria_bookmarks_pack(&list, 1, file, sizeof(file), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 20);
    CHECK_EQ_INT(exteria_bookmarks_unpack(file, len, 1, &back), EXTERIA_OK);
    CHECK_EQ_INT(back.count, 0);
    /* too small a buffer, a bad account, and a list that is too long */
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &a), EXTERIA_OK);
    CHECK_EQ_INT(exteria_bookmarks_pack(&list, 1, file, 100, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_bookmarks_pack(&list, 0, file, sizeof(file), &len), EXTERIA_E_ARG);
    list.count = EXTERIA_BOOKMARKS_MAX + 1;
    CHECK_EQ_INT(exteria_bookmarks_pack(&list, 1, file, sizeof(file), &len), EXTERIA_E_ARG);
    exteria_bookmarks_init(&list);

    /* damaged files: every byte of the header, a count that does not match the length, a record that add would refuse */
    CHECK_EQ_INT(exteria_bookmarks_add(&list, &a), EXTERIA_OK);
    CHECK_EQ_INT(exteria_bookmarks_pack(&list, 7, file, sizeof(file), &len), EXTERIA_OK);
    for (i = 0; i < 20; ++i) {
        uint8_t saved = file[i];
        file[i] ^= 0x55;
        /* the account id is the part that reads as another account's file instead of a damaged one */
        exteria_status status = exteria_bookmarks_unpack(file, len, 7, &back);
        CHECK(status == EXTERIA_E_MALFORMED || (i >= 12 && status == EXTERIA_E_NOTFOUND));
        file[i] = saved;
    }
    CHECK_EQ_INT(exteria_bookmarks_unpack(file, len - 1, 7, &back), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bookmarks_unpack(file, 19, 7, &back), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bookmarks_unpack(file, 0, 7, &back), EXTERIA_E_MALFORMED);
    file[20] = 9;   /* a peer kind of 9 */
    CHECK_EQ_INT(exteria_bookmarks_unpack(file, len, 7, &back), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(back.count, 0);
    CHECK_EQ_INT(exteria_bookmarks_unpack(NULL, 20, 7, &back), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_bookmarks_unpack(file, len, 0, &back), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_bookmarks_unpack(file, len, 7, NULL), EXTERIA_E_ARG);
}

int main(void) {
    test_add_remove();
    test_capacity();
    test_invalid();
    test_pack();
    return test_finish("test_bookmarks");
}
