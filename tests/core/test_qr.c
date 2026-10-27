#include "test_util.h"
#include "exteria_qr.h"
#include "qr_vectors.h"

static uint8_t modules[EXTERIA_QR_MAX_MODULES];

static void check_vector(const char *text, int side, int mask, const char *const *rows) {
    int got_side = 0, got_mask = -1, x, y, wrong = 0;
    CHECK_EQ_INT(exteria_qr_encode((const uint8_t *)text, strlen(text), modules, sizeof(modules), &got_side, &got_mask), EXTERIA_OK);
    CHECK_EQ_INT(got_side, side);
    CHECK_EQ_INT(got_mask, mask);
    for (y = 0; y < side; ++y)
        for (x = 0; x < side; ++x)
            if ((modules[y * side + x] ? '1' : '0') != rows[y][x]) ++wrong;
    CHECK_EQ_INT(wrong, 0);
}

static void test_vectors(void) {
    check_vector(qr_text_0, qr_side_0, qr_mask_0, qr_rows_0);
    check_vector(qr_text_1, qr_side_1, qr_mask_1, qr_rows_1);
    check_vector(qr_text_2, qr_side_2, qr_mask_2, qr_rows_2);
    check_vector(qr_text_3, qr_side_3, qr_mask_3, qr_rows_3);
}

/* the fixed parts of every symbol: finders, separators, timing, the dark module */
static void test_structure(void) {
    static const char finder[7][8] = {"1111111", "1000001", "1011101", "1011101", "1011101", "1000001", "1111111"};
    int side, x, y, lengths[] = {1, 14, 15, 62, 63, 106, 107, 152, 153, 213}, i;
    uint8_t data[213];
    memset(data, 'x', sizeof(data));
    for (i = 0; i < (int)(sizeof(lengths) / sizeof(lengths[0])); ++i) {
        CHECK_EQ_INT(exteria_qr_encode(data, (size_t)lengths[i], modules, sizeof(modules), &side, NULL), EXTERIA_OK);
        CHECK(side >= 21 && side <= 57 && (side - 17) % 4 == 0);
        for (y = 0; y < 7; ++y) {
            for (x = 0; x < 7; ++x) {
                CHECK_EQ_INT(modules[y * side + x], finder[y][x] == '1');
                CHECK_EQ_INT(modules[y * side + side - 7 + x], finder[y][x] == '1');
                CHECK_EQ_INT(modules[(side - 7 + y) * side + x], finder[y][x] == '1');
            }
            /* the separator is light */
            CHECK_EQ_INT(modules[y * side + 7], 0);
            CHECK_EQ_INT(modules[7 * side + y], 0);
        }
        for (x = 8; x < side - 8; ++x) CHECK_EQ_INT(modules[6 * side + x], x % 2 == 0);
        for (y = 8; y < side - 8; ++y) CHECK_EQ_INT(modules[y * side + 6], y % 2 == 0);
        CHECK_EQ_INT(modules[(side - 8) * side + 8], 1);
    }
}

static void test_limits(void) {
    uint8_t data[214];
    int side = 5, mask = 5;
    memset(data, 'a', sizeof(data));
    CHECK_EQ_INT(exteria_qr_encode(data, 213, modules, sizeof(modules), &side, &mask), EXTERIA_OK);
    CHECK_EQ_INT(side, 57);
    CHECK_EQ_INT(exteria_qr_encode(data, 214, modules, sizeof(modules), &side, &mask), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(side, 0);
    CHECK_EQ_INT(mask, 0);
    CHECK_EQ_INT(exteria_qr_encode(data, 0, modules, sizeof(modules), &side, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_qr_encode(NULL, 3, modules, sizeof(modules), &side, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_qr_encode(data, 3, NULL, sizeof(modules), &side, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_qr_encode(data, 3, modules, EXTERIA_QR_MAX_MODULES - 1, &side, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_qr_encode(data, 3, modules, sizeof(modules), NULL, NULL), EXTERIA_E_ARG);
    /* the same input always gives the same symbol, and a symbol of a different input differs */
    {
        static uint8_t again[EXTERIA_QR_MAX_MODULES];
        int side_a, side_b;
        CHECK_EQ_INT(exteria_qr_encode(data, 40, modules, sizeof(modules), &side_a, NULL), EXTERIA_OK);
        CHECK_EQ_INT(exteria_qr_encode(data, 40, again, sizeof(again), &side_b, NULL), EXTERIA_OK);
        CHECK_EQ_INT(side_a, side_b);
        CHECK_MEM(modules, again, (size_t)side_a * (size_t)side_a);
        data[39] = 'b';
        CHECK_EQ_INT(exteria_qr_encode(data, 40, again, sizeof(again), &side_b, NULL), EXTERIA_OK);
        CHECK(memcmp(modules, again, (size_t)side_a * (size_t)side_a) != 0);
    }
}

int main(void) {
    test_vectors();
    test_structure();
    test_limits();
    return test_finish("test_qr");
}
