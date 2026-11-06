#include "exteria_text_split.h"
#include "test_util.h"

#define MAX_PARTS 64

static size_t widen(const char *ascii, uint16_t *out, size_t cap) {
    size_t n = strlen(ascii);
    size_t i;
    if (n > cap) n = cap;
    for (i = 0; i < n; ++i) out[i] = (uint8_t)ascii[i];
    return n;
}

static size_t split(const uint16_t *units, size_t len, size_t limit, exteria_text_part *parts) {
    size_t count = 0;
    size_t total = exteria_text_split(units, len, limit, parts, MAX_PARTS, &count);
    CHECK_EQ_INT(count, total);
    return total;
}

static void test_short(void) {
    uint16_t units[64];
    exteria_text_part parts[MAX_PARTS];
    size_t n = widen("  hello  ", units, 64);
    CHECK_EQ_INT(split(units, n, 4096, parts), 1);
    CHECK_EQ_INT(parts[0].begin, 2);
    CHECK_EQ_INT(parts[0].end, 7);
    CHECK_EQ_INT(split(units, 0, 4096, parts), 0);
    n = widen("   \n ", units, 64);
    CHECK_EQ_INT(split(units, n, 4096, parts), 0);
    CHECK_EQ_INT(exteria_text_split(units, n, 1, parts, MAX_PARTS, NULL), 0);
}

/* the limit counts units, and a text of exactly the limit is one message */
static void test_exact(void) {
    static uint16_t units[8192];
    exteria_text_part parts[MAX_PARTS];
    size_t i;
    for (i = 0; i < 4096; ++i) units[i] = 'a';
    CHECK_EQ_INT(split(units, 4096, 4096, parts), 1);
    CHECK_EQ_INT(parts[0].end, 4096);
    for (i = 0; i < 4097; ++i) units[i] = 'a';
    CHECK_EQ_INT(split(units, 4097, 4096, parts), 2);
    CHECK_EQ_INT(parts[0].end, 4096);
    CHECK_EQ_INT(parts[1].begin, 4096);
    CHECK_EQ_INT(parts[1].end, 4097);
}

/* the order of the cuts: blank line, line break, space after a full stop, other white space */
static void test_breaks(void) {
    uint16_t units[128];
    exteria_text_part parts[MAX_PARTS];
    size_t n = widen("aaaa bbbb\n\ncccc dddd", units, 128);
    CHECK_EQ_INT(split(units, n, 12, parts), 2);
    CHECK_EQ_INT(parts[0].end, 9);
    CHECK_EQ_INT(parts[1].begin, 11);
    n = widen("aaaa bbbb\ncccc dddd eeee", units, 128);
    CHECK_EQ_INT(split(units, n, 14, parts), 2);
    CHECK_EQ_INT(parts[0].end, 9);
    CHECK_EQ_INT(parts[1].begin, 10);
    /* the full stop cut comes first even where a later space would fill the piece better, and the rest is cut again */
    n = widen("aa. bbbb cccc dddd", units, 128);
    CHECK_EQ_INT(split(units, n, 12, parts), 3);
    CHECK_EQ_INT(parts[0].end, 3);
    CHECK_EQ_INT(parts[1].begin, 4);
    n = widen("aaaa bbbb cccc dddd", units, 128);
    CHECK_EQ_INT(split(units, n, 12, parts), 2);
    CHECK_EQ_INT(parts[0].end, 9);
    CHECK_EQ_INT(parts[1].begin, 10);
    CHECK_EQ_INT(parts[1].end, 19);
}

/* no break at all: the cut is at the limit and no unit is lost */
static void test_hard(void) {
    uint16_t units[40];
    exteria_text_part parts[MAX_PARTS];
    size_t i, covered = 0, total;
    for (i = 0; i < 25; ++i) units[i] = 'x';
    total = split(units, 25, 10, parts);
    CHECK_EQ_INT(total, 3);
    for (i = 0; i < total; ++i) covered += parts[i].end - parts[i].begin;
    CHECK_EQ_INT(covered, 25);
    CHECK_EQ_INT(parts[1].begin, 10);
}

/* a pair is never cut in two */
static void test_surrogates(void) {
    uint16_t units[40];
    exteria_text_part parts[MAX_PARTS];
    size_t i, total;
    for (i = 0; i < 20; i += 2) {
        units[i] = 0xD83D;
        units[i + 1] = 0xDE00;
    }
    total = split(units, 20, 5, parts);
    CHECK_EQ_INT(total, 5);
    for (i = 0; i < total; ++i) {
        CHECK_EQ_INT(parts[i].begin % 2, 0);
        CHECK_EQ_INT(parts[i].end % 2, 0);
        CHECK(parts[i].end - parts[i].begin <= 5);
    }
}

/* only the capacity of the array is written, the count still says what the text needs */
static void test_capacity(void) {
    uint16_t units[100];
    exteria_text_part parts[2];
    size_t count = 9, i;
    for (i = 0; i < 100; ++i) units[i] = 'y';
    CHECK_EQ_INT(exteria_text_split(units, 100, 10, parts, 2, &count), 10);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(exteria_text_split(units, 100, 10, NULL, 0, &count), 10);
    CHECK_EQ_INT(count, 0);
}

/* a long text of words and paragraphs: every piece fits, and the words come back in order */
static void test_long(void) {
    static uint16_t units[20000];
    exteria_text_part parts[MAX_PARTS];
    size_t n = 0, i, total, words = 0, back = 0;
    while (n < 19000) {
        const char *word = (n / 50) % 7 == 0 ? "para.\n" : "word ";
        size_t k;
        for (k = 0; word[k]; ++k) units[n++] = (uint8_t)word[k];
    }
    total = split(units, n, 4096, parts);
    CHECK(total >= 5 && total <= 7);
    for (i = 0; i < total; ++i) {
        CHECK(parts[i].end - parts[i].begin <= 4096);
        CHECK(parts[i].begin >= back);
        back = parts[i].end;
    }
    for (i = 0; i < n; ++i) if (units[i] == 'w' || units[i] == 'p') ++words;
    {
        size_t kept = 0, j;
        for (i = 0; i < total; ++i) for (j = parts[i].begin; j < parts[i].end; ++j) if (units[j] == 'w' || units[j] == 'p') ++kept;
        CHECK_EQ_INT(kept, words);
    }
}

int main(void) {
    test_short();
    test_exact();
    test_breaks();
    test_hard();
    test_surrogates();
    test_capacity();
    test_long();
    return test_finish("test_text_split");
}
