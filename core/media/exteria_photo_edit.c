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
