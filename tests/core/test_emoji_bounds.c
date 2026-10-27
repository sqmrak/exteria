#include "test_util.h"
#include "exteria_emoji.h"

int main(void) {
    uint8_t pixels[8 * 6 * 4] = {0};
    size_t bounds[4];
    CHECK_EQ_INT(exteria_emoji_alpha_bounds(pixels, sizeof(pixels), 8, 6, 32, bounds), 0);
    for (size_t y = 2; y < 5; ++y)
        for (size_t x = 1; x < 7; ++x) pixels[y * 32 + x * 4 + 3] = 255;
    pixels[3] = 15;
    CHECK_EQ_INT(exteria_emoji_alpha_bounds(pixels, sizeof(pixels), 8, 6, 32, bounds), 1);
    CHECK_EQ_INT(bounds[0], 1); CHECK_EQ_INT(bounds[1], 2);
    CHECK_EQ_INT(bounds[2], 6); CHECK_EQ_INT(bounds[3], 3);
    CHECK_EQ_INT(exteria_emoji_alpha_bounds(pixels, sizeof(pixels) - 1, 8, 6, 32, bounds), 0);
    CHECK_EQ_INT(bounds[2], 0);
    CHECK_EQ_INT(exteria_emoji_alpha_bounds(pixels, sizeof(pixels), 8, 6, SIZE_MAX, bounds), 0);
    CHECK_EQ_INT(exteria_emoji_alpha_bounds(pixels, sizeof(pixels), 8, 6, 31, bounds), 0);
    CHECK_EQ_INT(exteria_emoji_alpha_bounds(NULL, 0, 8, 6, 32, bounds), 0);
    CHECK_EQ_INT(exteria_emoji_alpha_bounds(pixels, sizeof(pixels), 0, 6, 32, bounds), 0);
    CHECK_EQ_INT(exteria_emoji_alpha_bounds(pixels, sizeof(pixels), 8, 6, 32, NULL), 0);
    pixels[3] = 16;
    pixels[5 * 32 + 7 * 4 + 3] = 255;
    CHECK_EQ_INT(exteria_emoji_alpha_bounds(pixels, sizeof(pixels), 8, 6, 32, bounds), 1);
    CHECK_EQ_INT(bounds[0], 0); CHECK_EQ_INT(bounds[1], 0);
    CHECK_EQ_INT(bounds[2], 8); CHECK_EQ_INT(bounds[3], 6);
    return 0;
}
