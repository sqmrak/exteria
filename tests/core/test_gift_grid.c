#include "exteria_gift_grid.h"
#include "test_util.h"

int main(void) {
    int columns = 0;
    double tile = 0, margin = 0;
    exteria_gift_grid_layout(704, 460, &columns, &tile, &margin);
    CHECK_EQ_INT(columns, 4);
    CHECK(tile == 105);
    CHECK(margin == 130);
    exteria_gift_grid_layout(320, 460, &columns, &tile, &margin);
    CHECK_EQ_INT(columns, 3);
    CHECK(margin >= 0 && tile > 0);
    exteria_gift_grid_layout(0, 460, &columns, &tile, &margin);
    CHECK_EQ_INT(columns, 2);
    CHECK(tile == 0);
    return test_finish("gift_grid");
}
