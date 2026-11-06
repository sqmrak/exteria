#include "exteria_stack_blur.h"

#include <stdlib.h>

/* one channel of one line. the line is padded by radius copies of its ends, then two sliding boxes of radius + 1 samples are laid over it: the first by
   the second is the triangle. the sums are exact integers, so the result equals the direct sum of the weights and costs a few additions per pixel */
static void blur_channel(uint8_t *line, size_t step, uint32_t count, uint32_t radius, uint32_t *padded, uint32_t *boxed) {
    uint32_t span = radius + 1;
    uint32_t divisor = span * span;
    for (uint32_t i = 0; i < count + 2 * radius; ++i) {
        uint32_t source = i < radius ? 0 : (i - radius >= count ? count - 1 : i - radius);
        padded[i] = line[(size_t)source * step];
    }
    uint32_t window = 0;
    for (uint32_t j = 0; j < span; ++j) window += padded[j];
    boxed[0] = window;
    for (uint32_t i = 1; i < count + radius; ++i) {
        window = window - padded[i - 1] + padded[i - 1 + span];
        boxed[i] = window;
    }
    window = 0;
    for (uint32_t j = 0; j < span; ++j) window += boxed[j];
    for (uint32_t x = 0; x < count; ++x) {
        if (x) window = window - boxed[x - 1] + boxed[x - 1 + span];
        line[(size_t)x * step] = (uint8_t)((window + divisor / 2) / divisor);
    }
}

exteria_status exteria_stack_blur_rgba(uint8_t *pixels, size_t capacity, uint32_t width, uint32_t height, uint32_t radius) {
    if (!pixels || !width || !height || radius > EXTERIA_STACK_BLUR_RADIUS_MAX) return EXTERIA_E_ARG;
    if ((uint64_t)width * height > SIZE_MAX / 4) return EXTERIA_E_LIMIT;
    size_t needed = (size_t)width * height * 4;
    if (capacity < needed) return EXTERIA_E_LIMIT;
    if (!radius) return EXTERIA_OK;
    uint32_t longest = width > height ? width : height;
    uint32_t *padded = malloc(((size_t)longest + 2 * radius) * sizeof(uint32_t));
    uint32_t *boxed = malloc(((size_t)longest + radius) * sizeof(uint32_t));
    if (!padded || !boxed) {
        free(padded);
        free(boxed);
        return EXTERIA_E_NOMEM;
    }
    size_t row = (size_t)width * 4;
    for (uint32_t y = 0; y < height; ++y)
        for (int c = 0; c < 4; ++c) blur_channel(pixels + (size_t)y * row + (size_t)c, 4, width, radius, padded, boxed);
    for (uint32_t x = 0; x < width; ++x)
        for (int c = 0; c < 4; ++c) blur_channel(pixels + (size_t)x * 4 + (size_t)c, row, height, radius, padded, boxed);
    free(padded);
    free(boxed);
    return EXTERIA_OK;
}
