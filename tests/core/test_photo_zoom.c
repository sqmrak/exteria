#include "test_util.h"
#include "exteria_photo_zoom.h"
#include <math.h>

static int near(double a, double b) { return fabs(a - b) < 1e-9; }

int main(void) {
    double x, y;
    /* the spot under the finger stays under it: a spot at (30, 10) from the center of the picture shows at focal (40, 20) when the picture is at (10, 10) and zoom 1 */
    CHECK_EQ_INT(exteria_photo_zoom_about(1, 10, 10, 40, 20, 2, &x, &y), EXTERIA_OK);
    CHECK(near(x, -20) && near(y, 0));
    /* an unchanged zoom moves nothing */
    CHECK_EQ_INT(exteria_photo_zoom_about(3, 5, -7, 100, 100, 3, &x, &y), EXTERIA_OK);
    CHECK(near(x, 5) && near(y, -7));
    /* a focal point at the picture center only keeps the picture there */
    CHECK_EQ_INT(exteria_photo_zoom_about(1, 12, 3, 12, 3, 4, &x, &y), EXTERIA_OK);
    CHECK(near(x, 12) && near(y, 3));
    CHECK_EQ_INT(exteria_photo_zoom_about(0, 0, 0, 0, 0, 2, &x, &y), EXTERIA_E_ARG);
    CHECK(x == 0 && y == 0);
    CHECK_EQ_INT(exteria_photo_zoom_about(1, NAN, 0, 0, 0, 2, &x, &y), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_zoom_about(1, 0, 0, 0, 0, 2, NULL, &y), EXTERIA_E_ARG);

    double zoom = 1;
    x = 50; y = -50;
    /* at zoom 1 a picture that fits the area cannot be moved */
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 1, &zoom, &x, &y), EXTERIA_OK);
    CHECK(near(zoom, 1) && near(x, 0) && near(y, 0));
    /* enlarged to 2: 600 wide in a 400 area leaves 100 of reach on x, 400 high in 600 leaves none on y */
    zoom = 2; x = 500; y = 500;
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 1, &zoom, &x, &y), EXTERIA_OK);
    CHECK(near(x, 100) && near(y, 0));
    zoom = 2; x = -500; y = 0;
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 1, &zoom, &x, &y), EXTERIA_OK);
    CHECK(near(x, -100));
    /* the zoom stays between the minimum and the maximum */
    zoom = 100; x = 0; y = 0;
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 1, &zoom, &x, &y), EXTERIA_OK);
    CHECK(near(zoom, EXTERIA_PHOTO_ZOOM_MAX));
    zoom = 0.2; x = 0; y = 0;
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 0.8, &zoom, &x, &y), EXTERIA_OK);
    CHECK(near(zoom, 0.8));
    zoom = 0.2;
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 1, &zoom, &x, &y), EXTERIA_OK);
    CHECK(near(zoom, 1));
    /* bad input leaves the values alone */
    zoom = 2; x = 7; y = 8;
    CHECK_EQ_INT(exteria_photo_zoom_clamp(0, 200, 400, 600, 1, &zoom, &x, &y), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 0, &zoom, &x, &y), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 9, &zoom, &x, &y), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 1, NULL, &x, &y), EXTERIA_E_ARG);
    zoom = NAN;
    CHECK_EQ_INT(exteria_photo_zoom_clamp(300, 200, 400, 600, 1, &zoom, &x, &y), EXTERIA_E_ARG);
    CHECK(near(x, 7) && near(y, 8));
    return test_finish("test_photo_zoom");
}
