#include "test_util.h"
#include "exteria_photo_edit.h"
#include <math.h>

int main(void) {
    exteria_photo_crop crop;
    CHECK_EQ_INT(exteria_photo_crop_pixels(1280, 960, 0.25, 0.25, 0.5, 0.5, &crop), EXTERIA_OK);
    CHECK_EQ_INT(crop.x, 320); CHECK_EQ_INT(crop.y, 240);
    CHECK_EQ_INT(crop.width, 640); CHECK_EQ_INT(crop.height, 480);
    CHECK_EQ_INT(exteria_photo_crop_pixels(1, 1, 0, 0, 1, 1, &crop), EXTERIA_OK);
    CHECK_EQ_INT(crop.width, 1);
    const double bad[][4] = {{-0.1,0,1,1},{0,0,0,1},{0,0,1,0},{0.8,0,0.3,1},{NAN,0,1,1},{0,INFINITY,1,1}};
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        CHECK_EQ_INT(exteria_photo_crop_pixels(100, 100, bad[i][0], bad[i][1], bad[i][2], bad[i][3], &crop), EXTERIA_E_ARG);
        CHECK_EQ_INT(crop.width, 0);
    }
    CHECK_EQ_INT(exteria_photo_crop_pixels(0, 10, 0, 0, 1, 1, &crop), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_crop_pixels(2560, 1920, 0.25, 0.25, 0.5, 0.5, &crop), EXTERIA_OK);
    CHECK_EQ_INT(crop.x, 640); CHECK_EQ_INT(crop.y, 480);
    CHECK_EQ_INT(crop.width, 1280); CHECK_EQ_INT(crop.height, 960);
    CHECK_EQ_INT(exteria_photo_crop_pixels(2561, 10, 0, 0, 1, 1, &crop), EXTERIA_E_ARG);
    uint8_t pixels[48], before[48];
    for (size_t i = 0; i < sizeof(pixels); ++i) pixels[i] = (uint8_t)(i * 5);
    memcpy(before, pixels, sizeof(pixels));
    exteria_photo_adjustments settings = {{0}};
    CHECK_EQ_INT(exteria_photo_adjust(pixels, sizeof(pixels), 3, 3, 16, &settings), EXTERIA_OK);
    CHECK_MEM(pixels, before, sizeof(pixels));
    CHECK_EQ_INT(exteria_photo_adjust(pixels, 47, 3, 3, 16, &settings), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_adjust(pixels, 48, 3, 3, SIZE_MAX, &settings), EXTERIA_E_ARG);
    settings.values[0] = NAN;
    CHECK_EQ_INT(exteria_photo_adjust(pixels, 48, 3, 3, 16, &settings), EXTERIA_E_ARG);
    CHECK_MEM(pixels, before, sizeof(pixels));
    settings.values[0] = 0;
    settings.values[EXTERIA_PHOTO_SATURATION] = -1;
    CHECK_EQ_INT(exteria_photo_adjust(pixels, 48, 3, 3, 16, &settings), EXTERIA_OK);
    for (size_t y = 0; y < 3; ++y) {
        for (size_t x = 0; x < 3; ++x) {
            size_t at = y * 16 + x * 4;
            CHECK_EQ_INT(pixels[at], pixels[at+1]); CHECK_EQ_INT(pixels[at], pixels[at+2]);
            CHECK_EQ_INT(pixels[at+3], before[at+3]);
        }
        CHECK_MEM(pixels + y * 16 + 12, before + y * 16 + 12, 4);
    }
    before[20] = 40;
    for (size_t tool = 0; tool < EXTERIA_PHOTO_TOOLS; ++tool) {
        memset(&settings, 0, sizeof(settings));
        settings.values[tool] = 1;
        memcpy(pixels, before, sizeof(pixels));
        CHECK_EQ_INT(exteria_photo_adjust(pixels, 48, 3, 3, 16, &settings), EXTERIA_OK);
        CHECK(memcmp(pixels, before, sizeof(pixels)) != 0);
    }
    return test_finish("test_photo_edit");
}
