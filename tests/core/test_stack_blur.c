#include "test_util.h"
#include "exteria_stack_blur.h"

static uint32_t clamp_index(long index, uint32_t count) {
    if (index < 0) return 0;
    if (index >= (long)count) return count - 1;
    return (uint32_t)index;
}

/* the definition: the weights radius + 1 - |k| along one axis and then along the other, the edge pixel repeated, rounded to the nearest once at the end */
static void reference(const uint8_t *in, uint8_t *out, uint32_t width, uint32_t height, uint32_t radius) {
    uint64_t divisor = (uint64_t)(radius + 1) * (radius + 1) * (radius + 1) * (radius + 1);
    uint32_t *sum = malloc((size_t)width * height * 4 * sizeof(uint32_t));
    for (uint32_t y = 0; y < height; ++y)
        for (uint32_t x = 0; x < width; ++x)
            for (int c = 0; c < 4; ++c) {
                uint32_t total = 0;
                for (long k = -(long)radius; k <= (long)radius; ++k)
                    total += (radius + 1 - (uint32_t)(k < 0 ? -k : k)) * in[((size_t)y * width + clamp_index((long)x + k, width)) * 4 + (size_t)c];
                sum[((size_t)y * width + x) * 4 + (size_t)c] = total;
            }
    for (uint32_t y = 0; y < height; ++y)
        for (uint32_t x = 0; x < width; ++x)
            for (int c = 0; c < 4; ++c) {
                uint64_t total = 0;
                for (long k = -(long)radius; k <= (long)radius; ++k)
                    total += (uint64_t)(radius + 1 - (uint32_t)(k < 0 ? -k : k)) * sum[((size_t)clamp_index((long)y + k, height) * width + x) * 4 + (size_t)c];
                out[((size_t)y * width + x) * 4 + (size_t)c] = (uint8_t)((total + divisor / 2) / divisor);
            }
    free(sum);
}

static uint32_t next(uint32_t *state) {
    *state = *state * 1664525u + 1013904223u;
    return *state >> 24;
}

static void compare(uint32_t width, uint32_t height, uint32_t radius, uint32_t seed) {
    size_t size = (size_t)width * height * 4;
    uint8_t *picture = malloc(size), *blurred = malloc(size), *expected = malloc(size);
    for (size_t i = 0; i < size; ++i) picture[i] = (uint8_t)next(&seed);
    memcpy(blurred, picture, size);
    CHECK_EQ_INT(exteria_stack_blur_rgba(blurred, size, width, height, radius), EXTERIA_OK);
    reference(picture, expected, width, height, radius);
    /* the line sums are exact, the reference rounds once over the two axes, so a rounding of one step is the only difference allowed */
    int worst = 0;
    for (size_t i = 0; i < size; ++i) {
        int d = (int)blurred[i] - (int)expected[i];
        if (d < 0) d = -d;
        if (d > worst) worst = d;
    }
    CHECK(worst <= 1);
    free(picture);
    free(blurred);
    free(expected);
}

int main(void) {
    /* a flat picture stays flat, in every channel, at any radius */
    {
        uint8_t flat[7 * 5 * 4];
        for (size_t i = 0; i < sizeof flat; i += 4) { flat[i] = 200; flat[i + 1] = 17; flat[i + 2] = 255; flat[i + 3] = 0; }
        uint8_t kept[sizeof flat];
        memcpy(kept, flat, sizeof flat);
        CHECK_EQ_INT(exteria_stack_blur_rgba(flat, sizeof flat, 7, 5, 25), EXTERIA_OK);
        CHECK_MEM(flat, kept, sizeof flat);
    }
    /* radius 0 changes nothing */
    {
        uint8_t px[2 * 2 * 4] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
        uint8_t kept[sizeof px];
        memcpy(kept, px, sizeof px);
        CHECK_EQ_INT(exteria_stack_blur_rgba(px, sizeof px, 2, 2, 0), EXTERIA_OK);
        CHECK_MEM(px, kept, sizeof px);
    }
    /* one bright pixel spreads as the product of two triangles: radius 1 gives 1/16 at the corners of the cross, 2/16 on its arms and 4/16 in the middle */
    {
        uint8_t px[5 * 5 * 4] = {0};
        px[(2 * 5 + 2) * 4] = 255;
        CHECK_EQ_INT(exteria_stack_blur_rgba(px, sizeof px, 5, 5, 1), EXTERIA_OK);
        CHECK_EQ_INT(px[(2 * 5 + 2) * 4], 64);
        CHECK_EQ_INT(px[(2 * 5 + 1) * 4], 32);
        CHECK_EQ_INT(px[(1 * 5 + 2) * 4], 32);
        CHECK_EQ_INT(px[(1 * 5 + 1) * 4], 16);
        CHECK_EQ_INT(px[(0 * 5 + 0) * 4], 0);
        CHECK_EQ_INT(px[(2 * 5 + 2) * 4 + 1], 0);
    }
    /* the sums match the definition on noise: odd shapes, a line shorter than the radius, one row and one column */
    compare(16, 9, 3, 1);
    compare(31, 17, 10, 2);
    compare(3, 4, 25, 3);
    compare(1, 8, 4, 4);
    compare(9, 1, 4, 5);
    compare(1, 1, 7, 6);
    compare(40, 30, EXTERIA_STACK_BLUR_RADIUS_MAX, 7);
    /* bad input leaves the pixels alone and says why */
    {
        uint8_t px[4 * 4] = {9, 9, 9, 9, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3};
        uint8_t kept[sizeof px];
        memcpy(kept, px, sizeof px);
        CHECK_EQ_INT(exteria_stack_blur_rgba(NULL, sizeof px, 2, 2, 1), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_stack_blur_rgba(px, sizeof px, 0, 2, 1), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_stack_blur_rgba(px, sizeof px, 2, 0, 1), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_stack_blur_rgba(px, sizeof px, 2, 2, EXTERIA_STACK_BLUR_RADIUS_MAX + 1), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_stack_blur_rgba(px, sizeof px - 1, 2, 2, 1), EXTERIA_E_LIMIT);
        CHECK_EQ_INT(exteria_stack_blur_rgba(px, sizeof px, 0xFFFFFFFFu, 0xFFFFFFFFu, 1), EXTERIA_E_LIMIT);
        CHECK_MEM(px, kept, sizeof px);
    }
    if (g_failures) {
        fprintf(stderr, "%d of %d checks failed\n", g_failures, g_checks);
        return 1;
    }
    printf("stack blur: %d checks passed\n", g_checks);
    return 0;
}
