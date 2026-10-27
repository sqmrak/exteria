#include "exteria_yuv.h"

#include <string.h>

#define MIN_SIDE 2
#define MAX_SIDE 4096
#define FIXED 8

exteria_status exteria_yuv_capture_rotation(exteria_capture_orientation orientation, int output_rotates, int *rotation) {
    static const int turns[] = {90, 270, 180, 0};
    if (!rotation) return EXTERIA_E_ARG;
    *rotation = 0;
    if ((int)orientation < EXTERIA_CAPTURE_PORTRAIT || orientation > EXTERIA_CAPTURE_LANDSCAPE_RIGHT) return EXTERIA_E_ARG;
    if (!output_rotates) *rotation = turns[orientation];
    return EXTERIA_OK;
}

static int valid_side(int v) {
    return v >= MIN_SIDE && v <= MAX_SIDE;
}

static int valid_out_side(int v) {
    return v >= 1 && v <= MAX_SIDE;
}

static uint8_t clamp8(int v) {
    return (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
}

/* the pixel of the source that pixel (x, y) of the turned and mirrored picture comes from */
static void source_position(int rotation, int mirror, int x, int y, int dw, int sw, int sh, int *sx, int *sy) {
    int ux = mirror ? dw - 1 - x : x;
    switch (rotation) {
    case 90:
        /* clockwise: the top row of the result is the left column of the source, read from the bottom up */
        *sx = y;
        *sy = sh - 1 - ux;
        break;
    case 180:
        *sx = sw - 1 - ux;
        *sy = sh - 1 - y;
        break;
    case 270:
        *sx = sw - 1 - y;
        *sy = ux;
        break;
    default:
        *sx = ux;
        *sy = y;
        break;
    }
}

typedef struct transform {
    int rotation;
    int mirror;
    int rw, rh;     /* the size of the picture after the turn */
    int sw, sh;     /* the size of the source plane in samples */
} transform;

/* one sample of the turned picture at (fx, fy) in 1/256 of a sample, blended from the four around it; step and offset pick luma (1, 0) or U (2, 0) and V (2, 1) */
static int sample_turned(const uint8_t *plane, int stride, int step, int offset, const transform *t, int fx, int fy) {
    int px = fx >> FIXED, py = fy >> FIXED, wx = fx & 255, wy = fy & 255;
    int px1, py1, sx[4], sy[4], k, v[4], top, bottom;
    if (px < 0) {
        px = 0;
        wx = 0;
    }
    if (py < 0) {
        py = 0;
        wy = 0;
    }
    if (px >= t->rw - 1) {
        px = t->rw - 1;
        wx = 0;
    }
    if (py >= t->rh - 1) {
        py = t->rh - 1;
        wy = 0;
    }
    px1 = px + (wx ? 1 : 0);
    py1 = py + (wy ? 1 : 0);
    source_position(t->rotation, t->mirror, px, py, t->rw, t->sw, t->sh, &sx[0], &sy[0]);
    source_position(t->rotation, t->mirror, px1, py, t->rw, t->sw, t->sh, &sx[1], &sy[1]);
    source_position(t->rotation, t->mirror, px, py1, t->rw, t->sw, t->sh, &sx[2], &sy[2]);
    source_position(t->rotation, t->mirror, px1, py1, t->rw, t->sw, t->sh, &sx[3], &sy[3]);
    for (k = 0; k < 4; ++k) v[k] = plane[(size_t)sy[k] * (size_t)stride + (size_t)sx[k] * (size_t)step + (size_t)offset];
    top = v[0] * (256 - wx) + v[1] * wx;
    bottom = v[2] * (256 - wx) + v[3] * wx;
    return (top * (256 - wy) + bottom * wy + 32768) >> 16;
}

/* where output sample x of dw falls on a picture rw wide, in 1/256 of a sample: centre to centre */
static int map_axis(int x, int rw, int dw) {
    return (int)((((long long)(2 * x + 1) * rw * 128) / dw) - 128);
}

exteria_status exteria_yuv_nv12_to_i420(const uint8_t *luma, int luma_stride, const uint8_t *chroma, int chroma_stride, int width, int height, int rotation,
                                        int mirror, const exteria_yuv_target *target) {
    transform lt, ct;
    int x, y, k;
    if (!luma || !chroma || !target || !target->plane[0] || !target->plane[1] || !target->plane[2]) return EXTERIA_E_ARG;
    if (!valid_side(width) || !valid_side(height) || !valid_side(target->width) || !valid_side(target->height)) return EXTERIA_E_ARG;
    if ((width & 1) || (height & 1) || (target->width & 1) || (target->height & 1)) return EXTERIA_E_ARG;
    if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) return EXTERIA_E_ARG;
    if (luma_stride < width || chroma_stride < width || target->stride[0] < target->width || target->stride[1] < target->width / 2 ||
        target->stride[2] < target->width / 2) return EXTERIA_E_ARG;
    lt.rotation = ct.rotation = rotation;
    lt.mirror = ct.mirror = mirror ? 1 : 0;
    lt.sw = width;
    lt.sh = height;
    lt.rw = (rotation == 90 || rotation == 270) ? height : width;
    lt.rh = (rotation == 90 || rotation == 270) ? width : height;
    ct.sw = width / 2;
    ct.sh = height / 2;
    ct.rw = lt.rw / 2;
    ct.rh = lt.rh / 2;
    for (y = 0; y < target->height; ++y) {
        int fy = map_axis(y, lt.rh, target->height);
        for (x = 0; x < target->width; ++x) {
            target->plane[0][(size_t)y * (size_t)target->stride[0] + (size_t)x] = (uint8_t)sample_turned(luma, luma_stride, 1, 0, &lt, map_axis(x, lt.rw, target->width), fy);
        }
    }
    for (y = 0; y < target->height / 2; ++y) {
        int fy = map_axis(y, ct.rh, target->height / 2);
        for (x = 0; x < target->width / 2; ++x) {
            int fx = map_axis(x, ct.rw, target->width / 2);
            for (k = 0; k < 2; ++k) {
                target->plane[1 + k][(size_t)y * (size_t)target->stride[1 + k] + (size_t)x] = (uint8_t)sample_turned(chroma, chroma_stride, 2, k, &ct, fx, fy);
            }
        }
    }
    return EXTERIA_OK;
}

exteria_status exteria_yuv_i420_to_bgra(const exteria_i420 *src, uint8_t *out, int out_stride, int out_width, int out_height) {
    int x, y;
    if (!src || !out || !src->plane[0] || !src->plane[1] || !src->plane[2]) return EXTERIA_E_ARG;
    if (!valid_side(src->width) || !valid_side(src->height) || !valid_out_side(out_width) || !valid_out_side(out_height)) return EXTERIA_E_ARG;
    if (src->stride[0] < src->width || src->stride[1] < (src->width + 1) / 2 || src->stride[2] < (src->width + 1) / 2) return EXTERIA_E_ARG;
    if (out_stride < out_width * 4) return EXTERIA_E_LIMIT;
    for (y = 0; y < out_height; ++y) {
        int sy = (int)(((long long)y * src->height) / out_height);
        const uint8_t *yrow = src->plane[0] + (size_t)sy * (size_t)src->stride[0];
        const uint8_t *urow = src->plane[1] + (size_t)(sy / 2) * (size_t)src->stride[1];
        const uint8_t *vrow = src->plane[2] + (size_t)(sy / 2) * (size_t)src->stride[2];
        uint8_t *dst = out + (size_t)y * (size_t)out_stride;
        for (x = 0; x < out_width; ++x) {
            int sx = (int)(((long long)x * src->width) / out_width);
            int c = 298 * (yrow[sx] - 16), d = urow[sx / 2] - 128, e = vrow[sx / 2] - 128;
            dst[0] = clamp8((c + 516 * d + 128) >> 8);
            dst[1] = clamp8((c - 100 * d - 208 * e + 128) >> 8);
            dst[2] = clamp8((c + 409 * e + 128) >> 8);
            dst[3] = 255;
            dst += 4;
        }
    }
    return EXTERIA_OK;
}
