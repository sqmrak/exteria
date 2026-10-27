#include "exteria_reaction_layout.h"
#include "test_util.h"

#include <math.h>

static void stack_positions(void) {
    const double bubbles[] = {50, 150, 240, 400, 900};
    for (size_t i = 0; i < sizeof(bubbles) / sizeof(bubbles[0]); ++i) {
        double pill = -1, card = -1, shift = 1;
        CHECK_EQ_INT(exteria_reaction_menu_stack(30, 470, bubbles[i], 52, 250, 8, &pill, &card, &shift), EXTERIA_OK);
        CHECK(pill >= 30);
        CHECK(card + 250 <= 470);
        CHECK(pill + 52 + 8 == card);
        CHECK(bubbles[i] + shift + 8 <= pill);
        CHECK(shift <= 0);
        if (bubbles[i] == 50) CHECK(shift == 0);
    }
}

static void invalid_input(void) {
    double pill = 1, card = 1, shift = 1;
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 100, 20, 52, 50, 8, &pill, &card, &shift), EXTERIA_E_ARG);
    CHECK(pill == 0 && card == 0 && shift == 0);
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 500, NAN, 52, 200, 8, &pill, &card, &shift), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 500, 20, -1, 200, 8, &pill, &card, &shift), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 500, 20, 52, 200, 8, NULL, &card, &shift), EXTERIA_E_ARG);
}

int main(void) {
    stack_positions();
    invalid_input();
    return test_finish("test_reaction_menu");
}
