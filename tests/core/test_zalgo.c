#include "exteria_zalgo.h"
#include "test_util.h"

static void filter(const char *in, const char *expected) {
    char out[256];
    size_t n = exteria_zalgo_filter(in, out, sizeof(out));
    CHECK_EQ_INT(n, strlen(expected));
    CHECK(strcmp(out, expected) == 0);
}

static void test_filter(void) {
    /* plain text, empty text and text with one or two marks stay as they are */
    filter("", "");
    filter("hello", "hello");
    filter("\xD0\x96\xD0\xB8\xD0\xB2", "\xD0\x96\xD0\xB8\xD0\xB2");
    filter("a\xCC\x81", "a\xCC\x81");
    filter("a\xCC\x82\xCC\x81", "a\xCC\x82\xCC\x81");
    /* a third mark and everything after it is dropped, and the next letter starts a new count */
    filter("a\xCC\x82\xCC\x81\xCC\x83\xCC\x84" "b\xCC\x81", "a\xCC\x82\xCC\x81" "b\xCC\x81");
    /* marks from the other blocks count too: extended (U+1AB0), supplement (U+1DC0), for symbols (U+20D0) and half marks (U+FE20) */
    filter("a\xE1\xAA\xB0\xE1\xB7\x80\xE2\x83\x90\xEF\xB8\xA0", "a\xE1\xAA\xB0\xE1\xB7\x80");
    /* a mark with nothing before it is kept up to the limit */
    filter("\xCC\x81\xCC\x81\xCC\x81", "\xCC\x81\xCC\x81");
    /* bytes that are not UTF-8 pass through and end a run: a lone continuation byte, a truncated lead, an overlong mark */
    filter("a\xCC\x81\x80\xCC\x81\xCC\x81\xCC\x81", "a\xCC\x81\x80\xCC\x81\xCC\x81");
    filter("a\xE2\x83", "a\xE2\x83");
    filter("a\xC1\x81", "a\xC1\x81");
    /* a four byte letter keeps its marks to the limit as well */
    filter("\xF0\x9D\x90\x80\xCC\x81\xCC\x82\xCC\x83", "\xF0\x9D\x90\x80\xCC\x81\xCC\x82");
}

static void test_arguments(void) {
    char out[8] = "xxxxxxx";
    CHECK_EQ_INT(exteria_zalgo_filter(NULL, out, sizeof(out)), (size_t)-1);
    CHECK_EQ_INT(exteria_zalgo_filter("a", NULL, 4), (size_t)-1);
    CHECK_EQ_INT(exteria_zalgo_filter("a", out, 0), (size_t)-1);
    /* a buffer that cannot hold the text and its terminator is refused and left empty */
    CHECK_EQ_INT(exteria_zalgo_filter("abcd", out, 4), (size_t)-1);
    CHECK(out[0] == 0);
    CHECK_EQ_INT(exteria_zalgo_filter("abc", out, 4), 3);
}

int main(void) {
    test_filter();
    test_arguments();
    return test_finish("test_zalgo");
}
