#include "exteria_column.h"
#include "test_util.h"

#include <math.h>

static int near(double a, double b) {
    return fabs(a - b) < 1e-9;
}

static void phones_fill_the_safe_area(void) {
    exteria_column c;
    /* a portrait phone with no side insets, and no limit */
    CHECK_EQ_INT(exteria_column_place(390, 0, 0, 0, &c), EXTERIA_OK);
    CHECK(near(c.x, 0) && near(c.width, 390));
    /* landscape on a notched phone: both sides keep clear of the notch and the home bar edge */
    CHECK_EQ_INT(exteria_column_place(844, 47, 47, 0, &c), EXTERIA_OK);
    CHECK(near(c.x, 47) && near(c.width, 750));
    /* a limit wider than the room changes nothing */
    CHECK_EQ_INT(exteria_column_place(844, 47, 47, 2000, &c), EXTERIA_OK);
    CHECK(near(c.x, 47) && near(c.width, 750));
}

static void tablets_center_a_column(void) {
    exteria_column c;
    CHECK_EQ_INT(exteria_column_place(1024, 0, 0, 720, &c), EXTERIA_OK);
    CHECK(near(c.x, 152) && near(c.width, 720));
    CHECK_EQ_INT(exteria_column_place(1366, 0, 0, 720, &c), EXTERIA_OK);
    CHECK(near(c.x, 323) && near(c.width, 720));
    /* portrait is narrower than the limit by little: the room wins */
    CHECK_EQ_INT(exteria_column_place(700, 0, 0, 720, &c), EXTERIA_OK);
    CHECK(near(c.x, 0) && near(c.width, 700));
    /* the limit equals the room */
    CHECK_EQ_INT(exteria_column_place(720, 0, 0, 720, &c), EXTERIA_OK);
    CHECK(near(c.x, 0) && near(c.width, 720));
}

static void uneven_insets_push_the_column(void) {
    exteria_column c;
    /* the room is 600 wide and the column 560: centered on the screen it would cross the left inset, so it rests against it */
    CHECK_EQ_INT(exteria_column_place(700, 100, 0, 560, &c), EXTERIA_OK);
    CHECK(near(c.x, 100) && near(c.width, 560));
    CHECK_EQ_INT(exteria_column_place(700, 0, 100, 560, &c), EXTERIA_OK);
    CHECK(near(c.x, 40) && near(c.width, 560));
    /* a column the screen centers inside the room stays centered */
    CHECK_EQ_INT(exteria_column_place(1000, 20, 0, 400, &c), EXTERIA_OK);
    CHECK(near(c.x, 300) && near(c.width, 400));
}

static void rejects_bad_input(void) {
    exteria_column c;
    c.x = 5;
    c.width = 5;
    CHECK_EQ_INT(exteria_column_place(0, 0, 0, 0, &c), EXTERIA_E_ARG);
    CHECK(near(c.x, 0) && near(c.width, 0));
    CHECK_EQ_INT(exteria_column_place(-1, 0, 0, 0, &c), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_column_place(NAN, 0, 0, 0, &c), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_column_place(INFINITY, 0, 0, 0, &c), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_column_place(300, -1, 0, 0, &c), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_column_place(300, 0, NAN, 0, &c), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_column_place(300, 0, 0, NAN, &c), EXTERIA_E_ARG);
    /* insets that eat the whole width leave nothing to place */
    CHECK_EQ_INT(exteria_column_place(300, 150, 150, 0, &c), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_column_place(300, 200, 150, 0, &c), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_column_place(300, 0, 0, 0, NULL), EXTERIA_E_ARG);
}

int main(void) {
    phones_fill_the_safe_area();
    tablets_center_a_column();
    uneven_insets_push_the_column();
    rejects_bad_input();
    return test_finish("test_column");
}
