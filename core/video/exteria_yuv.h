#ifndef EXTERIA_YUV_H
#define EXTERIA_YUV_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_vp8.h"

/* the picture conversions of a video call, on plain buffers */

typedef struct exteria_yuv_target {
    uint8_t *plane[3];
    int stride[3];
    int width;
    int height;
} exteria_yuv_target;

typedef enum exteria_capture_orientation {
    EXTERIA_CAPTURE_PORTRAIT,
    EXTERIA_CAPTURE_PORTRAIT_UPSIDE_DOWN,
    EXTERIA_CAPTURE_LANDSCAPE_LEFT,
    EXTERIA_CAPTURE_LANDSCAPE_RIGHT
} exteria_capture_orientation;

/* output connections that rotate the buffers need no second turn */
exteria_status exteria_yuv_capture_rotation(exteria_capture_orientation orientation, int output_rotates, int *rotation);

/* the camera frame (NV12: a luma plane and one plane of interleaved U and V at half the size in each direction)
   rotated clockwise by rotation (0, 90, 180 or 270 degrees) */
exteria_status exteria_yuv_nv12_to_i420(const uint8_t *luma, int luma_stride, const uint8_t *chroma, int chroma_stride, int width, int height, int rotation,
                                        int mirror, const exteria_yuv_target *target);

/* an I420 picture as BGRA, scaled to out_width x out_height by nearest sampling (the pictures of the call are
   shown at about their own size); EXTERIA_E_ARG for a picture or sizes that are not usable, EXTERIA_E_LIMIT when
   stride is too small */
exteria_status exteria_yuv_i420_to_bgra(const exteria_i420 *src, uint8_t *out, int out_stride, int out_width, int out_height);

#endif
