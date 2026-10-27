#include "exteria_video_sticker_core.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct { int count, stop, alpha; } frames_seen;
static int frame(void *context, const uint8_t *pixels, int width, int height) {
    frames_seen *seen = context;
    assert(width == 96 && height == 48);
    ++seen->count;
    for (int i = 0; i < width * height; ++i) {
        unsigned a = pixels[i * 4 + 3];
        assert(pixels[i * 4] <= a && pixels[i * 4 + 1] <= a && pixels[i * 4 + 2] <= a);
        if (a > 0 && a < 255) seen->alpha = 1;
        assert(pixels[i * 4] < 4 && pixels[i * 4 + 1] < 4);
        assert(abs((int)pixels[i * 4 + 2] - (int)a) <= 2);
    }
    return seen->stop;
}
static uint8_t *read_file(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb"); assert(file);
    assert(fseek(file, 0, SEEK_END) == 0);
    long size = ftell(file); assert(size > 0 && size < 512 * 1024);
    rewind(file);
    uint8_t *bytes = malloc((size_t)size); assert(bytes);
    assert(fread(bytes, 1, (size_t)size, file) == (size_t)size);
    assert(fclose(file) == 0); *length = (size_t)size; return bytes;
}
int main(int argc, char **argv) {
    assert(argc == 4);
    size_t length;
    uint8_t *bytes = read_file(argv[1], &length);
    frames_seen seen = {0, 1, 0}; double duration = -1;
    int count = exteria_video_sticker_decode(bytes, length, 96, 15, frame, &seen, &duration);
    assert(count == seen.count && count >= 14 && count <= 16 && seen.alpha);
    assert(duration > 0.95 && duration <= 1.05);
    seen = (frames_seen){0, 0, 0};
    assert(exteria_video_sticker_decode(bytes, length, 96, 15, frame, &seen, &duration) == 1);
    assert(seen.count == 1 && seen.alpha);
    seen = (frames_seen){0, -1, 0};
    assert(exteria_video_sticker_decode(bytes, length, 96, 15, frame, &seen, &duration) == 0);
    assert(duration == 0);
    assert(exteria_video_sticker_decode(bytes, 64, 96, 15, frame, &seen, &duration) == 0);
    assert(exteria_video_sticker_decode(NULL, length, 96, 15, frame, &seen, &duration) == 0);
    assert(exteria_video_sticker_decode(bytes, 512 * 1024 + 1, 96, 15, frame, &seen, &duration) == 0);
    assert(exteria_video_sticker_decode(bytes, length, 193, 15, frame, &seen, &duration) == 0);
    assert(exteria_video_sticker_decode(bytes, length, 96, NAN, frame, &seen, &duration) == 0);
    assert(exteria_video_sticker_decode(bytes, length, 96, 31, frame, &seen, &duration) == 0);
    assert(exteria_video_sticker_decode(bytes, length, 96, 15, frame, &seen, NULL) == 0);
    free(bytes);
    for (int i = 2; i < argc; ++i) {
        bytes = read_file(argv[i], &length); seen = (frames_seen){0, 1, 0};
        assert(exteria_video_sticker_decode(bytes, length, 96, 15, frame, &seen, &duration) == 0);
        assert(seen.count == 0 && duration == 0); free(bytes);
    }
    puts("video stickers: alpha, cadence, poster, cancellation, truncation, codec and bounds passed");
    return 0;
}
