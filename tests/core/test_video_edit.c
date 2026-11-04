#include "test_util.h"
#include "exteria_video_edit.h"
#include <math.h>

int main(void) {
    double start = -1, duration = -1;
    CHECK_EQ_INT(exteria_video_edit_range(60, 0.25, 0.75, &start, &duration), EXTERIA_OK);
    CHECK(fabs(start - 15) < 0.0001 && fabs(duration - 30) < 0.0001);
    const double invalid[][3] = {{0, 0, 1}, {NAN, 0, 1}, {10, -0.1, 1}, {10, 0, 1.1}, {10, 0.5, 0.5}, {1, 0, 0.01}, {86401, 0, 1}};
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); ++i) {
        start = duration = -1;
        CHECK_EQ_INT(exteria_video_edit_range(invalid[i][0], invalid[i][1], invalid[i][2], &start, &duration), EXTERIA_E_ARG);
        CHECK(start == 0 && duration == 0);
    }
    CHECK_EQ_INT(exteria_video_edit_range(1, 0, 1, NULL, &duration), EXTERIA_E_ARG);
    double x, y, width, height;
    CHECK_EQ_INT(exteria_video_edit_crop(1920, 1080, 1, &x, &y, &width, &height), EXTERIA_OK);
    CHECK(x == 420 && y == 0 && width == 1080 && height == 1080);
    CHECK_EQ_INT(exteria_video_edit_crop(1080, 1920, 16.0 / 9.0, &x, &y, &width, &height), EXTERIA_OK);
    CHECK(x == 0 && y == 656.25 && width == 1080 && height == 607.5);
    CHECK_EQ_INT(exteria_video_edit_crop(1920, 1080, 0, &x, &y, &width, &height), EXTERIA_OK);
    CHECK(x == 0 && y == 0 && width == 1920 && height == 1080);
    CHECK_EQ_INT(exteria_video_edit_crop(1920, 1080, NAN, &x, &y, &width, &height), EXTERIA_E_ARG);
    CHECK(x == 0 && y == 0 && width == 0 && height == 0);
    CHECK(exteria_video_edit_aspect(0) == 0 && exteria_video_edit_aspect(1) == 1);
    CHECK(exteria_video_edit_aspect(5) == 9.0 / 16 && exteria_video_edit_aspect(6) < 0);
    CHECK(exteria_video_edit_handle(0, 0.5, 0.8, 0.1) == 0.5);
    CHECK(exteria_video_edit_handle(0, 0.75, 0.8, 0.1) == 0.8 - 0.1);
    CHECK(exteria_video_edit_handle(0, -3, 0.8, 0.1) == 0);
    CHECK(exteria_video_edit_handle(1, 0.85, 0.2, 0.1) == 0.85);
    CHECK(exteria_video_edit_handle(1, 0.25, 0.2, 0.1) == 0.2 + 0.1);
    CHECK(exteria_video_edit_handle(1, 9, 0.2, 0.1) == 1);
    CHECK(exteria_video_edit_handle(1, NAN, 0.2, 0.1) == 0.2);
    CHECK(exteria_video_edit_handle(0, 0.5, 0.05, 0.1) == 0.05);
    CHECK(exteria_video_edit_handle(1, 0.99, 0.95, 0.1) == 0.95);
    CHECK(exteria_video_edit_handle(0, 0.5, 0.8, 1) == 0.8);
    CHECK(exteria_video_edit_handle(0, 0.5, 1.5, 0.1) == 1.5);
    return test_finish("test_video_edit");
}
