#include "exteria_mention.h"
#include "test_util.h"

static void scan_ok(const char *text, size_t caret, size_t start, const char *query) {
    exteria_mention_token token;
    CHECK_EQ_INT(exteria_mention_scan(text, caret, &token), 1);
    CHECK_EQ_INT(token.start, start);
    CHECK_EQ_INT(token.end, caret);
    CHECK(strcmp(token.query, query) == 0);
}

static void scan_none(const char *text, size_t caret) {
    exteria_mention_token token;
    CHECK_EQ_INT(exteria_mention_scan(text, caret, &token), 0);
    CHECK_EQ_INT(token.start, 0);
    CHECK_EQ_INT(token.query[0], 0);
}

static void test_scan(void) {
    scan_ok("@", 1, 0, "");
    scan_ok("@ab", 3, 0, "ab");
    scan_ok("hello @ivan", 11, 6, "ivan");
    scan_ok("hello @", 7, 6, "");
    scan_ok("a\n@x_1", 6, 2, "x_1");
    scan_ok("(@bob", 5, 1, "bob");
    /* the caret in the middle of a name takes the part before it */
    scan_ok("@alexander", 5, 0, "alex");
    /* a name in another script is a query too: bytes of a UTF-8 letter are name characters */
    scan_ok("@\xD0\x98\xD0\xB2", 5, 0, "\xD0\x98\xD0\xB2");
    /* an address, a lone word, the caret before the name or after a space are not mentions */
    scan_none("a@b.c", 3);
    scan_none("mail user@host", 14);
    scan_none("hello", 5);
    scan_none("@ivan ", 6);
    scan_none("@ivan", 0);
    scan_none("", 0);
    scan_none("@ab", 9);
    scan_none("a@b", 3);
    /* a query past the cap is not offered */
    {
        char text[80];
        memset(text, 'a', sizeof(text));
        text[0] = '@';
        text[EXTERIA_MENTION_QUERY_MAX + 1] = 0;
        scan_none(text, EXTERIA_MENTION_QUERY_MAX + 1);
        text[EXTERIA_MENTION_QUERY_MAX] = 0;
        scan_ok(text, EXTERIA_MENTION_QUERY_MAX, 0, text + 1);
    }
    CHECK_EQ_INT(exteria_mention_scan(NULL, 0, NULL), 0);
}

int main(void) {
    test_scan();
    return test_finish("test_mention");
}
