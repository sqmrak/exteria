#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "exteria_flac.h"

static int cancelled(void *context) { (void)context; return 1; }
static int cancel_after_frames(void *context) { int *calls = context; return ++*calls > 3; }

int main(int argc, char **argv) {
    unsigned char header[44], samples[4096];
    FILE *file;
    size_t count;
    int nonzero = 0;
    int calls = 0;
    int expected_channels, expected_rate;
    if (argc != 7) return 1;
    expected_channels = atoi(argv[4]);
    expected_rate = atoi(argv[5]);
    if (exteria_flac_to_wav(argv[1], argv[3], NULL, NULL) != EXTERIA_OK) return 2;
    file = fopen(argv[3], "rb");
    if (!file || fread(header, 1, sizeof(header), file) != sizeof(header) || memcmp(header, "RIFF", 4) || memcmp(header + 8, "WAVE", 4) ||
        header[22] != expected_channels || header[34] != 16 ||
        ((unsigned)header[24] | (unsigned)header[25] << 8 | (unsigned)header[26] << 16 | (unsigned)header[27] << 24) != (unsigned)expected_rate) return 3;
    count = fread(samples, 1, sizeof(samples), file);
    fclose(file);
    for (size_t i = 0; i < count; ++i) if (samples[i]) nonzero = 1;
    if (!nonzero || count != sizeof(samples)) return 4;
    unlink(argv[3]);
    if (exteria_flac_to_wav(argv[1], argv[3], cancel_after_frames, &calls) != EXTERIA_E_RETRY || access(argv[3], F_OK) == 0) return 8;
    if (exteria_flac_to_wav(argv[2], argv[3], NULL, NULL) == EXTERIA_OK || access(argv[3], F_OK) == 0) return 5;
    if (exteria_flac_to_wav(argv[1], argv[3], cancelled, NULL) != EXTERIA_E_RETRY || access(argv[3], F_OK) == 0) return 6;
    if (exteria_flac_to_wav(argv[1], argv[1], NULL, NULL) != EXTERIA_E_ARG) return 7;
    if (exteria_flac_to_wav(argv[6], argv[3], NULL, NULL) != EXTERIA_E_LIMIT || access(argv[3], F_OK) == 0) return 9;
    puts("test_flac: playback conversion, corrupt input and cancellation passed");
    return 0;
}
