#ifndef EXTERIA_PHOTO_EDIT_H
#define EXTERIA_PHOTO_EDIT_H

#include <stddef.h>
#include <stdint.h>
#include "exteria_status.h"

#define EXTERIA_PHOTO_SIDE_MAX 1280
#define EXTERIA_PHOTO_TOOLS 10

typedef enum {
    EXTERIA_PHOTO_EXPOSURE,
    EXTERIA_PHOTO_CONTRAST,
    EXTERIA_PHOTO_SATURATION,
    EXTERIA_PHOTO_WARMTH,
    EXTERIA_PHOTO_FADE,
    EXTERIA_PHOTO_SHADOWS,
    EXTERIA_PHOTO_HIGHLIGHTS,
    EXTERIA_PHOTO_VIGNETTE,
    EXTERIA_PHOTO_GRAIN,
    EXTERIA_PHOTO_SHARPEN
} exteria_photo_tool;

typedef struct { float values[EXTERIA_PHOTO_TOOLS]; } exteria_photo_adjustments;
typedef struct { uint32_t x, y, width, height; } exteria_photo_crop;

/* normalized crop coordinates must describe a rectangle wholly inside the image */
exteria_status exteria_photo_crop_pixels(uint32_t width, uint32_t height, double x, double y,
                                       double crop_width, double crop_height, exteria_photo_crop *out);
/* opaque rgba pixels, row padding and alpha are preserved; invalid inputs leave pixels untouched */
exteria_status exteria_photo_adjust(uint8_t *pixels, size_t capacity, uint32_t width, uint32_t height,
                                  size_t stride, const exteria_photo_adjustments *adjustments);

#endif
