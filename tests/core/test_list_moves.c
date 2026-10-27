#include "test_util.h"
#include "exteria_list_moves.h"

/* rows a table keeps in place when a change is a few inserts, deletes and jumps */

typedef struct {
    const char *name;
    int32_t target[8];
    size_t count;
    uint8_t keep[8];
} list_case;

static void run(const list_case *c) {
    uint8_t keep[8];
    size_t i;
    CHECK_EQ_INT(exteria_list_keep(c->target, c->count, keep, sizeof(keep)), EXTERIA_OK);
    for (i = 0; i < c->count; ++i) {
        if (keep[i] != c->keep[i]) fprintf(stderr, "%s: row %zu keep %d, expected %d\n", c->name, i, keep[i], c->keep[i]);
        CHECK_EQ_INT(keep[i], c->keep[i]);
    }
}

int main(void) {
    static const list_case cases[] = {
        {"same", {0, 1, 2, 3}, 4, {1, 1, 1, 1}},
        {"empty", {0}, 0, {0}},
        {"one to the top", {1, 2, 3, 0}, 4, {1, 1, 1, 0}},
        {"top row down", {3, 0, 1, 2}, 4, {0, 1, 1, 1}},
        /* equal runs keep the later row */
        {"swap", {1, 0}, 2, {0, 1}},
        {"delete the middle", {0, -1, 1}, 3, {1, 0, 1}},
        {"delete all", {-1, -1, -1}, 3, {0, 0, 0}},
        {"insert shifts the rest", {1, 2, 3}, 3, {1, 1, 1}},
        {"jump and delete", {-1, 2, 0, 1}, 4, {0, 0, 1, 1}},
        {"reverse of three", {2, 1, 0}, 3, {0, 0, 1}},
        {"gaps from inserts", {0, 2, 4, 6}, 4, {1, 1, 1, 1}},
        {"one run of three, one out", {0, 4, 2, 6}, 4, {1, 0, 1, 1}},
    };
    uint8_t keep[EXTERIA_LIST_MOVES_MAX + 1];
    int32_t big[EXTERIA_LIST_MOVES_MAX + 1], dup[3] = {0, 1, 1}, low[2] = {0, -2}, high[1] = {EXTERIA_LIST_TARGET_MAX};
    size_t i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) run(&cases[i]);

    /* a full list rotated by one keeps all but one row */
    for (i = 0; i < EXTERIA_LIST_MOVES_MAX; ++i) big[i] = (int32_t)((i + 1) % EXTERIA_LIST_MOVES_MAX);
    CHECK_EQ_INT(exteria_list_keep(big, EXTERIA_LIST_MOVES_MAX, keep, sizeof(keep)), EXTERIA_OK);
    {
        size_t kept = 0;
        for (i = 0; i < EXTERIA_LIST_MOVES_MAX; ++i) kept += keep[i];
        CHECK_EQ_INT(kept, EXTERIA_LIST_MOVES_MAX - 1);
        CHECK_EQ_INT(keep[EXTERIA_LIST_MOVES_MAX - 1], 0);
    }

    CHECK_EQ_INT(exteria_list_keep(big, EXTERIA_LIST_MOVES_MAX + 1, keep, sizeof(keep)), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_list_keep(big, 4, keep, 3), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_list_keep(dup, 3, keep, sizeof(keep)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_list_keep(low, 2, keep, sizeof(keep)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_list_keep(high, 1, keep, sizeof(keep)), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_list_keep(NULL, 2, keep, sizeof(keep)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_list_keep(NULL, 0, NULL, 0), EXTERIA_OK);
    return test_finish("test_list_moves");
}
