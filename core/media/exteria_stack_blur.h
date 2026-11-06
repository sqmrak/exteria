#ifndef EXTERIA_STACK_BLUR_H
#define EXTERIA_STACK_BLUR_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the largest radius: the sums of a line stay inside 32 bits (255 * (radius + 1)^2) */
#define EXTERIA_STACK_BLUR_RADIUS_MAX 254u

/* blurs 8 bit rgba pixels in place with the stack blur of telegram: a triangle of weights radius + 1 - |k| over the 2 * radius + 1 neighbours, the edge pixel
   repeated outside the picture, every channel alike (premultiplied pixels stay premultiplied). capacity is the size of the buffer in bytes. a radius of 0
   leaves the pixels as they are. EXTERIA_E_ARG for a null buffer, an empty picture or a radius above the maximum, EXTERIA_E_LIMIT when the buffer is smaller
   than the picture, EXTERIA_E_NOMEM when the two lines of work do not fit; the pixels are untouched on any error */
exteria_status exteria_stack_blur_rgba(uint8_t *pixels, size_t capacity, uint32_t width, uint32_t height, uint32_t radius);

#endif
