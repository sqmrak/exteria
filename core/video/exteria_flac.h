#ifndef EXTERIA_FLAC_H
#define EXTERIA_FLAC_H

#include "exteria_status.h"

/* decodes a local FLAC to a bounded 16-bit PCM WAV, removing incomplete output on failure */
exteria_status exteria_flac_to_wav(const char *input, const char *output, int (*cancelled)(void *), void *context);

#endif
