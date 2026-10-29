#include "exteria_reaction_layout.h"
#include "test_util.h"

#include <math.h>

static void stack_positions(void) {
    /* the screen between 30 and 470 holds a pill of 52, a card of 250 and two gaps of 8, which leaves 122 for the message */
    const double bubbles[][2] = {{100, 160}, {40, 90}, {300, 360}, {420, 460}, {35, 600}, {200, 322}};
    for (size_t i = 0; i < sizeof(bubbles) / sizeof(bubbles[0]); ++i) {
        double pill = -1, card = -1, shift = 0;
        CHECK_EQ_INT(exteria_reaction_menu_stack(30, 470, bubbles[i][0], bubbles[i][1], 52, 250, 8, &pill, &card, &shift), EXTERIA_OK);
        CHECK(pill >= 30);
        CHECK(card + 250 <= 470);
        if (bubbles[i][1] - bubbles[i][0] <= 122) {
            CHECK(pill + 52 + 8 == bubbles[i][0] + shift);
            CHECK(card == bubbles[i][1] + shift + 8);
        }
    }
    double pill, card, shift;
    /* a message that has room stays where it is, with the pill above it and the card below */
    CHECK_EQ_INT(exteria_reaction_menu_stack(30, 470, 100, 160, 52, 250, 8, &pill, &card, &shift), EXTERIA_OK);
    CHECK(shift == 0 && pill == 40 && card == 168);
    /* near the top it comes down, near the bottom it goes up */
    CHECK_EQ_INT(exteria_reaction_menu_stack(30, 470, 40, 90, 52, 250, 8, &pill, &card, &shift), EXTERIA_OK);
    CHECK(shift == 50 && pill == 30);
    CHECK_EQ_INT(exteria_reaction_menu_stack(30, 470, 420, 460, 52, 250, 8, &pill, &card, &shift), EXTERIA_OK);
    CHECK(shift == -248 && card == 220);
    /* with no pill the message keeps the gap to the card alone */
    CHECK_EQ_INT(exteria_reaction_menu_stack(30, 470, 100, 160, 0, 250, 8, &pill, &card, &shift), EXTERIA_OK);
    CHECK(shift == 0 && card == 168);
}

static void invalid_input(void) {
    double pill = 1, card = 1, shift = 1;
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 100, 10, 20, 52, 50, 8, &pill, &card, &shift), EXTERIA_E_ARG);
    CHECK(pill == 0 && card == 0 && shift == 0);
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 500, 10, NAN, 52, 200, 8, &pill, &card, &shift), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 500, NAN, 20, 52, 200, 8, &pill, &card, &shift), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 500, 30, 20, 52, 200, 8, &pill, &card, &shift), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 500, 10, 20, -1, 200, 8, &pill, &card, &shift), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_menu_stack(0, 500, 10, 20, 52, 200, 8, NULL, &card, &shift), EXTERIA_E_ARG);
}

int main(void) {
    stack_positions();
    invalid_input();
    return test_finish("test_reaction_menu");
}
