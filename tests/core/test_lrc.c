#include "exteria_lrc.h"
#include "test_util.h"

static void parses_stamps(void) {
    const char *text = "[ar:Someone]\r\n[ti:Song]\n[00:01.50]first line\n[00:12.5] second <00:13.00>line  \n[01:02.345]third\n[00:20.00]\nnot a line\n";
    exteria_lrc lrc;
    CHECK_EQ_INT(exteria_lrc_parse(text, strlen(text), &lrc), EXTERIA_OK);
    CHECK_EQ_INT(lrc.count, 3);
    CHECK_EQ_INT(lrc.lines[0].start_ms, 1500);
    CHECK(strcmp(lrc.lines[0].text, "first line") == 0);
    CHECK_EQ_INT(lrc.lines[1].start_ms, 12500);
    CHECK(strcmp(lrc.lines[1].text, "second line") == 0);
    CHECK_EQ_INT(lrc.lines[2].start_ms, 62345);
    exteria_lrc_free(&lrc);
    CHECK(lrc.lines == NULL && lrc.count == 0);
}

static void repeated_and_unordered(void) {
    const char *text = "\xEF\xBB\xBF[00:30.00]b\n[00:10.00][00:50.00]chorus\n[00:30.00]c\n[00:05.00]a";
    exteria_lrc lrc;
    CHECK_EQ_INT(exteria_lrc_parse(text, strlen(text), &lrc), EXTERIA_OK);
    CHECK_EQ_INT(lrc.count, 5);
    CHECK(strcmp(lrc.lines[0].text, "a") == 0);
    CHECK(strcmp(lrc.lines[1].text, "chorus") == 0);
    /* lines that start together keep the order of the file */
    CHECK(strcmp(lrc.lines[2].text, "b") == 0);
    CHECK(strcmp(lrc.lines[3].text, "c") == 0);
    CHECK_EQ_INT(lrc.lines[4].start_ms, 50000);
    CHECK_EQ_INT(exteria_lrc_active(&lrc, 0), -1);
    CHECK_EQ_INT(exteria_lrc_active(&lrc, 5000), 0);
    CHECK_EQ_INT(exteria_lrc_active(&lrc, 29999), 1);
    CHECK_EQ_INT(exteria_lrc_active(&lrc, 30000), 3);
    CHECK_EQ_INT(exteria_lrc_active(&lrc, 999999), 4);
    exteria_lrc_free(&lrc);
}

static void rejects_plain_text(void) {
    exteria_lrc lrc;
    const char *plain = "just words\nand more words\n[verse] not a stamp\n[1:5.0] bad\n[00:75.00] bad seconds";
    CHECK_EQ_INT(exteria_lrc_parse(plain, strlen(plain), &lrc), EXTERIA_E_MALFORMED);
    CHECK(lrc.lines == NULL && lrc.count == 0);
    CHECK_EQ_INT(exteria_lrc_parse("", 0, &lrc), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_lrc_parse(NULL, 0, &lrc), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_lrc_parse("x", 1, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_lrc_active(NULL, 5), -1);
    char *big = malloc(EXTERIA_LRC_INPUT_MAX + 1);
    memset(big, 'a', EXTERIA_LRC_INPUT_MAX + 1);
    CHECK_EQ_INT(exteria_lrc_parse(big, EXTERIA_LRC_INPUT_MAX + 1, &lrc), EXTERIA_E_LIMIT);
    free(big);
}

static void bounds(void) {
    /* more lines than the cap keep the first ones; a long line is cut on a character boundary */
    size_t size = 40u * 3000u;
    char *text = malloc(size + 1), *p = text;
    for (unsigned i = 0; i < 3000 && (size_t)(p - text) < size - 40; ++i) p += sprintf(p, "[%02u:%02u.00]line %u\n", (i / 60) % 100, i % 60, i);
    exteria_lrc lrc;
    CHECK_EQ_INT(exteria_lrc_parse(text, (size_t)(p - text), &lrc), EXTERIA_OK);
    CHECK_EQ_INT(lrc.count, EXTERIA_LRC_LINES_MAX);
    exteria_lrc_free(&lrc);
    free(text);
    char *wide = malloc(EXTERIA_LRC_TEXT_MAX * 3 + 16);
    strcpy(wide, "[00:01.00]");
    size_t n = 10;
    for (unsigned i = 0; i < EXTERIA_LRC_TEXT_MAX; ++i) { memcpy(wide + n, "\xD1\x8F", 2); n += 2; }
    CHECK_EQ_INT(exteria_lrc_parse(wide, n, &lrc), EXTERIA_OK);
    size_t got = strlen(lrc.lines[0].text);
    CHECK(got <= EXTERIA_LRC_TEXT_MAX && got % 2 == 0);
    exteria_lrc_free(&lrc);
    free(wide);
}

static void search_text(void) {
    char out[64];
    CHECK_EQ_INT(exteria_lrc_search_text("Song (Remastered) [Live] feat. Someone Else", out, sizeof out), EXTERIA_OK);
    CHECK(strcmp(out, "Song") == 0);
    CHECK_EQ_INT(exteria_lrc_search_text("  Artist ft Guest ", out, sizeof out), EXTERIA_OK);
    CHECK(strcmp(out, "Artist") == 0);
    CHECK_EQ_INT(exteria_lrc_search_text("Daft Punk", out, sizeof out), EXTERIA_OK);
    CHECK(strcmp(out, "Daft Punk") == 0);
    /* "ft" inside a word is no credit */
    CHECK_EQ_INT(exteria_lrc_search_text("Soft Cell", out, sizeof out), EXTERIA_OK);
    CHECK(strcmp(out, "Soft Cell") == 0);
    CHECK_EQ_INT(exteria_lrc_search_text("Группа (live)", out, sizeof out), EXTERIA_OK);
    CHECK(strcmp(out, "Группа") == 0);
    /* nothing left: the original stays */
    CHECK_EQ_INT(exteria_lrc_search_text("(Intro)", out, sizeof out), EXTERIA_OK);
    CHECK(strcmp(out, "(Intro)") == 0);
    CHECK_EQ_INT(exteria_lrc_search_text("a long title that does not fit", out, 8), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_lrc_search_text(NULL, out, sizeof out), EXTERIA_E_ARG);
}

int main(void) {
    parses_stamps();
    repeated_and_unordered();
    rejects_plain_text();
    bounds();
    search_text();
    return test_finish("test_lrc");
}
