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
    /* blur: region, radius and pixels */
    exteria_photo_region region;
    CHECK_EQ_INT(exteria_photo_blur_region(1000, 800, 400, 300, 500, 350, 10, &region), EXTERIA_OK);
    CHECK_EQ_INT(region.x, 370); CHECK_EQ_INT(region.y, 270); CHECK_EQ_INT(region.width, 160); CHECK_EQ_INT(region.height, 110);
    CHECK_EQ_INT(exteria_photo_blur_region(1000, 800, -20, -20, 10, 10, 10, &region), EXTERIA_OK);
    CHECK_EQ_INT(region.x, 0); CHECK_EQ_INT(region.y, 0); CHECK_EQ_INT(region.width, 40); CHECK_EQ_INT(region.height, 40);
    CHECK_EQ_INT(exteria_photo_blur_region(1000, 800, 990, 790, 1200, 900, 64, &region), EXTERIA_OK);
    CHECK_EQ_INT(region.x + region.width, 1000); CHECK_EQ_INT(region.y + region.height, 800);
    CHECK_EQ_INT(exteria_photo_blur_region(1000, 800, 1001, 0, 1100, 10, 1, &region), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_blur_region(1000, 800, 0, 0, 10, 10, 0, &region), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_blur_region(1000, 800, 0, 0, 10, 10, EXTERIA_PHOTO_BLUR_RADIUS_MAX + 1, &region), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_blur_region(1000, 800, 10, 0, 0, 10, 4, &region), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_blur_region(1000, 800, NAN, 0, 10, 10, 4, &region), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_blur_region(1000, 800, 0, 0, 10, 10, 4, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_photo_blur_radius(1, 1920), 57); CHECK_EQ_INT(exteria_photo_blur_radius(1, 100000), EXTERIA_PHOTO_BLUR_RADIUS_MAX);
    CHECK_EQ_INT(exteria_photo_blur_radius(0, 1920), 1); CHECK_EQ_INT(exteria_photo_blur_radius(NAN, 1920), 1);
    CHECK_EQ_INT(exteria_photo_blur_radius(0.5, 0), 1); CHECK_EQ_INT(exteria_photo_blur_radius(7, 100), 3);
    {
        enum { W = 9, H = 7, STRIDE = W * 4 + 8 };
        uint8_t image[STRIDE * H], flat[STRIDE * H], copy[STRIDE * H];
        memset(image, 0x5a, sizeof(image));
        memcpy(flat, image, sizeof(image));
        exteria_photo_region all = {0, 0, W, H};
        /* a flat picture stays flat and the padding of the rows is not touched */
        CHECK_EQ_INT(exteria_photo_blur(image, sizeof(image), W, H, STRIDE, &all, 3), EXTERIA_OK);
        CHECK_MEM(image, flat, sizeof(image));
        /* one white pixel spreads, its neighbors rise, the sum of the light stays within rounding, and the pixels outside the region are kept */
        memset(image, 0, sizeof(image));
        image[3 * STRIDE + 4 * 4] = image[3 * STRIDE + 4 * 4 + 1] = image[3 * STRIDE + 4 * 4 + 2] = image[3 * STRIDE + 4 * 4 + 3] = 255;
        memcpy(copy, image, sizeof(image));
        exteria_photo_region inner = {2, 1, 5, 5};
        CHECK_EQ_INT(exteria_photo_blur(image, sizeof(image), W, H, STRIDE, &inner, 1), EXTERIA_OK);
        CHECK(image[3 * STRIDE + 4 * 4] > 0 && image[3 * STRIDE + 4 * 4] < 255);
        CHECK(image[3 * STRIDE + 3 * 4] > 0 && image[2 * STRIDE + 4 * 4] > 0);
        CHECK_EQ_INT(image[3 * STRIDE + 3 * 4], image[3 * STRIDE + 5 * 4]);
        CHECK_EQ_INT(image[3 * STRIDE + 4 * 4 + 3], image[3 * STRIDE + 4 * 4]);
        for (size_t y = 0; y < H; ++y)
            for (size_t b = 0; b < STRIDE; ++b) {
                int inside = y >= 1 && y < 6 && b >= 8 && b < 28;
                if (!inside) CHECK_EQ_INT(image[y * STRIDE + b], copy[y * STRIDE + b]);
            }
        CHECK_EQ_INT(exteria_photo_blur(image, sizeof(image), W, H, STRIDE, &inner, 0), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_photo_blur(image, sizeof(image), W, H, STRIDE, &inner, EXTERIA_PHOTO_BLUR_RADIUS_MAX + 1), EXTERIA_E_ARG);
        exteria_photo_region outside = {5, 0, 5, 3};
        CHECK_EQ_INT(exteria_photo_blur(image, sizeof(image), W, H, STRIDE, &outside, 1), EXTERIA_E_ARG);
        exteria_photo_region empty = {0, 0, 0, 3};
        CHECK_EQ_INT(exteria_photo_blur(image, sizeof(image), W, H, STRIDE, &empty, 1), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_photo_blur(image, STRIDE * H - 1, W, H, STRIDE, &all, 1), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_photo_blur(NULL, sizeof(image), W, H, STRIDE, &all, 1), EXTERIA_E_ARG);
        /* a radius wider than the region still works: the edge pixel stands in for what is beyond */
        exteria_photo_region one = {4, 3, 1, 1};
        CHECK_EQ_INT(exteria_photo_blur(image, sizeof(image), W, H, STRIDE, &one, 64), EXTERIA_OK);
    }
    return test_finish("test_photo_edit");
}
