#ifndef EXTERIA_PHOTO_EDIT_H
#define EXTERIA_PHOTO_EDIT_H

#include <stddef.h>
#include <stdint.h>
#include "exteria_status.h"

#define EXTERIA_PHOTO_SIDE_MAX 2560
#define EXTERIA_PHOTO_TOOLS 10
#define EXTERIA_PHOTO_BLUR_RADIUS_MAX 64

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
typedef struct { uint32_t x, y, width, height; } exteria_photo_region;

/* normalized crop coordinates must describe a rectangle wholly inside the image */
exteria_status exteria_photo_crop_pixels(uint32_t width, uint32_t height, double x, double y,
                                       double crop_width, double crop_height, exteria_photo_crop *out);
/* opaque rgba pixels, row padding and alpha are preserved; invalid inputs leave pixels untouched */
exteria_status exteria_photo_adjust(uint8_t *pixels, size_t capacity, uint32_t width, uint32_t height,
                                  size_t stride, const exteria_photo_adjustments *adjustments);

/* the part of the image a blur of radius reads and writes for a stroke whose pixels span [left, right] x [top, bottom]: the box grown by three radii (the three passes of the
   blur), cut to the image. the stroke itself stays at least a radius inside it, so the edge of the region never shows through the clip of the stroke */
exteria_status exteria_photo_blur_region(uint32_t width, uint32_t height, double left, double top, double right, double bottom,
                                       uint32_t radius, exteria_photo_region *out);
/* three box passes over the region, which approach a gaussian of the same reach; pixels beyond the region count as its edge pixel. radius runs from 1 to
   EXTERIA_PHOTO_BLUR_RADIUS_MAX, and the region lies wholly in the image. alpha is blurred with the colors, so opaque pixels stay opaque */
exteria_status exteria_photo_blur(uint8_t *pixels, size_t capacity, uint32_t width, uint32_t height, size_t stride,
                                const exteria_photo_region *region, uint32_t radius);
/* the radius for a strength from 0 to 1 on an image whose short side is short_side pixels, so the preview and the export of one edit look the same */
uint32_t exteria_photo_blur_radius(double strength, uint32_t short_side);

#endif
