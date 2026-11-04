#include "exteria_photo_edit.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

static double clamp(double value, double low, double high) {
    return value < low ? low : (value > high ? high : value);
}

exteria_status exteria_photo_crop_pixels(uint32_t width, uint32_t height, double x, double y,
                                       double crop_width, double crop_height, exteria_photo_crop *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!width || !height || width > EXTERIA_PHOTO_SIDE_MAX || height > EXTERIA_PHOTO_SIDE_MAX ||
        !isfinite(x) || !isfinite(y) || !isfinite(crop_width) || !isfinite(crop_height) ||
        x < 0 || y < 0 || crop_width <= 0 || crop_height <= 0 || x + crop_width > 1.000001 || y + crop_height > 1.000001)
        return EXTERIA_E_ARG;
    out->x = (uint32_t)floor(x * width);
    out->y = (uint32_t)floor(y * height);
    uint32_t right = (uint32_t)ceil(clamp(x + crop_width, 0, 1) * width);
    uint32_t bottom = (uint32_t)ceil(clamp(y + crop_height, 0, 1) * height);
    if (out->x >= width || out->y >= height || right <= out->x || bottom <= out->y) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_ARG;
    }
    out->width = right - out->x;
    out->height = bottom - out->y;
    return EXTERIA_OK;
}

static uint8_t byte(double value) { return (uint8_t)(clamp(value, 0, 1) * 255 + 0.5); }

exteria_status exteria_photo_adjust(uint8_t *pixels, size_t capacity, uint32_t width, uint32_t height,
                                  size_t stride, const exteria_photo_adjustments *adjustments) {
    if (!pixels || !adjustments || !width || !height || width > EXTERIA_PHOTO_SIDE_MAX || height > EXTERIA_PHOTO_SIDE_MAX ||
        stride < (size_t)width * 4 || stride > SIZE_MAX / height || capacity < stride * height) return EXTERIA_E_ARG;
    for (size_t i = 0; i < EXTERIA_PHOTO_TOOLS; ++i) {
        float value = adjustments->values[i];
        if (!isfinite(value) || value < ((i == EXTERIA_PHOTO_FADE || i >= EXTERIA_PHOTO_VIGNETTE) ? 0 : -1) || value > 1)
            return EXTERIA_E_ARG;
    }
    const float *v = adjustments->values;
    size_t bytes = stride * height;
    uint8_t *original = v[EXTERIA_PHOTO_SHARPEN] > 0 ? malloc(bytes) : NULL;
    if (v[EXTERIA_PHOTO_SHARPEN] > 0 && !original) return EXTERIA_E_NOMEM;
    double exposure = pow(2, v[EXTERIA_PHOTO_EXPOSURE] * 2);
    double contrast = 1 + v[EXTERIA_PHOTO_CONTRAST] * 0.75;
    double saturation = 1 + v[EXTERIA_PHOTO_SATURATION];
    double warmth = v[EXTERIA_PHOTO_WARMTH] * 0.12;
    double fade = v[EXTERIA_PHOTO_FADE] * 0.3;
    for (uint32_t y = 0; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            uint8_t *p = pixels + y * stride + x * 4;
            double r = p[0] / 255.0, g = p[1] / 255.0, b = p[2] / 255.0;
            double luma = r * 0.2126 + g * 0.7152 + b * 0.0722;
            double tone = v[EXTERIA_PHOTO_SHADOWS] * (1 - luma) * (1 - luma) * 0.4 +
                          v[EXTERIA_PHOTO_HIGHLIGHTS] * luma * luma * 0.4;
            r = (r * exposure + tone - 0.5) * contrast + 0.5 + warmth;
            g = (g * exposure + tone - 0.5) * contrast + 0.5;
            b = (b * exposure + tone - 0.5) * contrast + 0.5 - warmth;
            luma = r * 0.2126 + g * 0.7152 + b * 0.0722;
            r = luma + (r - luma) * saturation;
            g = luma + (g - luma) * saturation;
            b = luma + (b - luma) * saturation;
            double dx = (2.0 * x + 1) / width - 1, dy = (2.0 * y + 1) / height - 1;
            double vignette = 1 - v[EXTERIA_PHOTO_VIGNETTE] * clamp((dx * dx + dy * dy) * 0.5, 0, 1) * 0.8;
            /* fixed pixel noise keeps previews and exports identical */
            uint32_t noise = (x * 374761393u + y * 668265263u) ^ 0x9e3779b9u;
            noise = (noise ^ (noise >> 13)) * 1274126177u;
            double grain = (((noise >> 24) / 255.0) - 0.5) * v[EXTERIA_PHOTO_GRAIN] * 0.18;
            p[0] = byte((r * (1 - fade) + fade * 0.5) * vignette + grain);
            p[1] = byte((g * (1 - fade) + fade * 0.5) * vignette + grain);
            p[2] = byte((b * (1 - fade) + fade * 0.5) * vignette + grain);
        }
    }
    if (original) {
        memcpy(original, pixels, bytes);
        double strength = v[EXTERIA_PHOTO_SHARPEN] * 0.5;
        for (uint32_t y = 1; y + 1 < height; ++y) {
            for (uint32_t x = 1; x + 1 < width; ++x) {
                size_t offset = y * stride + x * 4;
                for (size_t channel = 0; channel < 3; ++channel) {
                    size_t at = offset + channel;
                    double center = original[at];
                    double edges = original[at - 4] + original[at + 4] + original[at - stride] + original[at + stride];
                    pixels[at] = byte((center + strength * (4 * center - edges)) / 255.0);
                }
            }
        }
        free(original);
    }
    return EXTERIA_OK;
}

uint32_t exteria_photo_blur_radius(double strength, uint32_t short_side) {
    if (!isfinite(strength) || !short_side) return 1;
    double radius = clamp(strength, 0, 1) * short_side * 0.03;
    if (radius < 1) return 1;
    return radius > EXTERIA_PHOTO_BLUR_RADIUS_MAX ? EXTERIA_PHOTO_BLUR_RADIUS_MAX : (uint32_t)radius;
}

exteria_status exteria_photo_blur_region(uint32_t width, uint32_t height, double left, double top, double right, double bottom,
                                       uint32_t radius, exteria_photo_region *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!width || !height || width > EXTERIA_PHOTO_SIDE_MAX || height > EXTERIA_PHOTO_SIDE_MAX ||
        !isfinite(left) || !isfinite(top) || !isfinite(right) || !isfinite(bottom) ||
        radius < 1 || radius > EXTERIA_PHOTO_BLUR_RADIUS_MAX || right < left || bottom < top ||
        right < 0 || bottom < 0 || left > width || top > height)
        return EXTERIA_E_ARG;
    double reach = 3.0 * radius;
    double x0 = clamp(floor(left - reach), 0, width), y0 = clamp(floor(top - reach), 0, height);
    double x1 = clamp(ceil(right + reach), 0, width), y1 = clamp(ceil(bottom + reach), 0, height);
    if (x1 <= x0 || y1 <= y0) return EXTERIA_E_ARG;
    out->x = (uint32_t)x0;
    out->y = (uint32_t)y0;
    out->width = (uint32_t)(x1 - x0);
    out->height = (uint32_t)(y1 - y0);
    return EXTERIA_OK;
}

/* one sliding box over every line: lines are rows or columns of the tight copy, step is the distance between two pixels of a line */
static void box_pass(const uint8_t *from, uint8_t *to, size_t lines, size_t length, size_t line_step, size_t step, uint32_t radius) {
    size_t r = radius, window = 2 * r + 1;
    for (size_t line = 0; line < lines; ++line) {
        for (size_t channel = 0; channel < 4; ++channel) {
            const uint8_t *in = from + line * line_step + channel;
            uint8_t *out = to + line * line_step + channel;
            uint32_t sum = (uint32_t)in[0] * (uint32_t)(r + 1);
            for (size_t k = 1; k <= r; ++k) sum += in[(k < length ? k : length - 1) * step];
            for (size_t i = 0; i < length; ++i) {
                out[i * step] = (uint8_t)((sum + window / 2) / window);
                size_t ahead = i + r + 1, behind = i > r ? i - r : 0;
                sum += in[(ahead < length ? ahead : length - 1) * step];
                sum -= in[behind * step];
            }
        }
    }
}

exteria_status exteria_photo_blur(uint8_t *pixels, size_t capacity, uint32_t width, uint32_t height, size_t stride,
                                const exteria_photo_region *region, uint32_t radius) {
    if (!pixels || !region || !width || !height || width > EXTERIA_PHOTO_SIDE_MAX || height > EXTERIA_PHOTO_SIDE_MAX ||
        stride < (size_t)width * 4 || stride > SIZE_MAX / height || capacity < stride * height ||
        radius < 1 || radius > EXTERIA_PHOTO_BLUR_RADIUS_MAX || !region->width || !region->height ||
        region->x > width || region->width > width - region->x || region->y > height || region->height > height - region->y)
        return EXTERIA_E_ARG;
    size_t row = (size_t)region->width * 4, bytes = row * region->height;
    uint8_t *a = malloc(bytes), *b = malloc(bytes);
    if (!a || !b) {
        free(a);
        free(b);
        return EXTERIA_E_NOMEM;
    }
    for (uint32_t y = 0; y < region->height; ++y)
        memcpy(a + y * row, pixels + (region->y + y) * stride + (size_t)region->x * 4, row);
    for (int pass = 0; pass < 3; ++pass) {
        box_pass(a, b, region->height, region->width, row, 4, radius);
        box_pass(b, a, region->width, region->height, 4, row, radius);
    }
    for (uint32_t y = 0; y < region->height; ++y)
        memcpy(pixels + (region->y + y) * stride + (size_t)region->x * 4, a + y * row, row);
    free(a);
    free(b);
    return EXTERIA_OK;
}
