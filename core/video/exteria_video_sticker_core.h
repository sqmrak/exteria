#ifndef EXTERIA_VIDEO_STICKER_CORE_H
#define EXTERIA_VIDEO_STICKER_CORE_H
#include <stddef.h>
#include <stdint.h>
/* premultiplied bgra, valid during the callback; 1 continues, 0 accepts a poster, -1 fails */
typedef int (*exteria_video_sticker_frame)(void *context, const uint8_t *pixels, int width, int height);
int exteria_video_sticker_decode(const void *data, size_t length, int max_side, double target_fps,
                                exteria_video_sticker_frame callback, void *context, double *duration);
#endif
