#include "test_util.h"
#include "exteria_translate_text.h"

#include <string.h>

static void restore(const char *original, const char *translated, const char *expected) {
    char out[128];
    CHECK_EQ_INT(exteria_tr_restore_newlines(original, translated, out, sizeof(out)), EXTERIA_OK);
    CHECK(!strcmp(out, expected));
}

static void test_restore(void) {
    /* every single break came back as two */
    restore("a\nb\nc", "A\n\nB\n\nC", "A\nB\nC");
    /* a blank line of the original stays one */
    restore("a\n\nb\nc", "A\n\n\n\nB\n\nC", "A\n\nB\nC");
    /* nothing to restore against */
    restore("a b", "A\n\nB", "A\n\nB");
    restore("", "A\n\nB", "A\n\nB");
    /* more runs than the original had keep their own length */
    restore("a\nb", "A\n\nB\n\nC", "A\nB\n\nC");
    /* the ends of the text are not joints */
    restore("a\nb", "\n\nA\n\nB\n\n", "\n\nA\nB\n\n");
    restore("a\nb", "AB", "AB");
    restore("a\nb", "", "");
    restore("\xE4\xBD\xA0\nx", "\xE4\xBD\xA0\n\nx", "\xE4\xBD\xA0\nx");
}

static void test_bounds(void) {
    char out[8];
    CHECK_EQ_INT(exteria_tr_restore_newlines("a\nb", "A\n\nB", out, sizeof(out)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tr_restore_newlines("a\nb", "AAAAAAAAAA", out, sizeof(out)), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(out[0], 0);
    CHECK_EQ_INT(exteria_tr_restore_newlines("a", "AAAAAAAAAA", out, sizeof(out)), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tr_restore_newlines("a\nb", "A\n\nB", out, 3), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tr_restore_newlines(NULL, "A", out, sizeof(out)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tr_restore_newlines("a", NULL, out, sizeof(out)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tr_restore_newlines("a", "A", NULL, sizeof(out)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tr_restore_newlines("a", "A", out, 0), EXTERIA_E_ARG);
}

int main(void) {
    test_restore();
    test_bounds();
    return test_finish("test_translate_text");
}
