#include "exteria_text_class.h"
#include "test_util.h"

static void test_classes(void) {
    static const struct {
        uint32_t cp;
        exteria_cp_class expected;
    } table[] = {
        /* what every font draws, and what draws nothing */
        {0x0000, EXTERIA_CP_PLAIN}, {'a', EXTERIA_CP_PLAIN}, {0x00E9, EXTERIA_CP_PLAIN}, {0x024F, EXTERIA_CP_PLAIN},
        {0x0301, EXTERIA_CP_PLAIN}, {0x0416, EXTERIA_CP_PLAIN}, {0x2003, EXTERIA_CP_PLAIN}, {0x2019, EXTERIA_CP_PLAIN},
        {0x2026, EXTERIA_CP_PLAIN}, {0x202F, EXTERIA_CP_PLAIN}, {0x205F, EXTERIA_CP_PLAIN}, {0xFFFC, EXTERIA_CP_PLAIN},
        /* formatting characters ride with the run before them */
        {0x00AD, EXTERIA_CP_ATTACH}, {0x200B, EXTERIA_CP_ATTACH}, {0x200D, EXTERIA_CP_ATTACH}, {0x200F, EXTERIA_CP_ATTACH},
        {0x202A, EXTERIA_CP_ATTACH}, {0x2060, EXTERIA_CP_ATTACH}, {0x206F, EXTERIA_CP_ATTACH}, {0xFE0E, EXTERIA_CP_ATTACH},
        {0xFE0F, EXTERIA_CP_ATTACH}, {0xFEFF, EXTERIA_CP_ATTACH}, {0xE0020, EXTERIA_CP_ATTACH}, {0xE01EF, EXTERIA_CP_ATTACH},
        /* what needs a glyph lookup: letters of other scripts, symbols, math letters, plane 1 and 2 */
        {0x0250, EXTERIA_CP_CHECK}, {0x0370, EXTERIA_CP_CHECK}, {0x05D0, EXTERIA_CP_CHECK}, {0x2022 + 0x100, EXTERIA_CP_CHECK},
        {0x2460, EXTERIA_CP_CHECK}, {0x2603, EXTERIA_CP_CHECK}, {0x3042, EXTERIA_CP_CHECK}, {0xFE20, EXTERIA_CP_CHECK},
        {0xFF21, EXTERIA_CP_CHECK}, {0x1D400, EXTERIA_CP_CHECK}, {0x1D7FF, EXTERIA_CP_CHECK}, {0x1F170, EXTERIA_CP_CHECK},
        {0x20000, EXTERIA_CP_CHECK}, {0xE0000 - 1, EXTERIA_CP_CHECK},
        /* surrogates alone and values past the last code point cannot be drawn */
        {0xD800, EXTERIA_CP_PLAIN}, {0xDFFF, EXTERIA_CP_PLAIN}, {0x110000, EXTERIA_CP_PLAIN}, {0xFFFFFFFFu, EXTERIA_CP_PLAIN},
    };
    size_t i;
    for (i = 0; i < sizeof(table) / sizeof(table[0]); ++i) {
        if (exteria_cp_class_of(table[i].cp) != table[i].expected) fprintf(stderr, "code point %X\n", (unsigned)table[i].cp);
        CHECK_EQ_INT(exteria_cp_class_of(table[i].cp), table[i].expected);
    }
}

static void test_utf16(void) {
    uint32_t cp = 7;
    /* "a", a math script capital H (a pair), "b" */
    const uint16_t text[] = {0x0061, 0xD835, 0xDCBD, 0x0062};
    CHECK_EQ_INT(exteria_utf16_next(text, 4, 0, &cp), 1);
    CHECK_EQ_INT(cp, 0x61);
    CHECK_EQ_INT(exteria_utf16_next(text, 4, 1, &cp), 2);
    CHECK_EQ_INT(cp, 0x1D4BD);
    CHECK_EQ_INT(exteria_utf16_next(text, 4, 3, &cp), 1);
    CHECK_EQ_INT(cp, 0x62);

    /* the first and the last pair of the supplementary planes */
    {
        const uint16_t low[] = {0xD800, 0xDC00}, high[] = {0xDBFF, 0xDFFF};
        CHECK_EQ_INT(exteria_utf16_next(low, 2, 0, &cp), 2);
        CHECK_EQ_INT(cp, 0x10000);
        CHECK_EQ_INT(exteria_utf16_next(high, 2, 0, &cp), 2);
        CHECK_EQ_INT(cp, 0x10FFFF);
    }

    /* a high surrogate at the end, one followed by a plain unit, and a low one alone each take a single unit */
    {
        const uint16_t cut[] = {0x0061, 0xD835}, wrong[] = {0xD835, 0x0062}, alone[] = {0xDCBD, 0x0063};
        CHECK_EQ_INT(exteria_utf16_next(cut, 2, 1, &cp), 1);
        CHECK_EQ_INT(cp, 0xD835);
        CHECK_EQ_INT(exteria_utf16_next(wrong, 2, 0, &cp), 1);
        CHECK_EQ_INT(cp, 0xD835);
        CHECK_EQ_INT(exteria_utf16_next(alone, 2, 0, &cp), 1);
        CHECK_EQ_INT(cp, 0xDCBD);
    }

    /* bad arguments leave a defined result and consume nothing */
    cp = 9;
    CHECK_EQ_INT(exteria_utf16_next(text, 4, 4, &cp), 0);
    CHECK_EQ_INT(cp, 0);
    CHECK_EQ_INT(exteria_utf16_next(NULL, 4, 0, &cp), 0);
    CHECK_EQ_INT(exteria_utf16_next(text, 0, 0, &cp), 0);
    CHECK_EQ_INT(exteria_utf16_next(text, 4, 0, NULL), 1);

    /* a walk over a mixed string visits every code point once */
    {
        const uint16_t mixed[] = {0x0048, 0xD835, 0xDCBD, 0x200D, 0x0436, 0xD83D, 0xDE00, 0xD83D};
        size_t at = 0, count = 0;
        while (at < 8) {
            size_t used = exteria_utf16_next(mixed, 8, at, &cp);
            CHECK(used == 1 || used == 2);
            at += used;
            ++count;
        }
        CHECK_EQ_INT(at, 8);
        CHECK_EQ_INT(count, 6);
    }
}

int main(void) {
    test_classes();
    test_utf16();
    return test_finish("test_text_class");
}
