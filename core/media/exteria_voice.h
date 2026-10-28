#ifndef EXTERIA_VOICE_H
#define EXTERIA_VOICE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* voice notes are 16 kHz mono; the recorder hands over signed 16 bit samples at that rate */
#define EXTERIA_VOICE_RATE 16000
#define EXTERIA_WAVEFORM_BARS 100
/* five bits per bar, packed as the Telegram clients read them */
#define EXTERIA_WAVEFORM_BYTES ((EXTERIA_WAVEFORM_BARS * 5 + 7) / 8)
/* the longest note the encoder accepts, in seconds, and the length at which the recorder stops by itself so a note is never refused after it was made; keeps the
   sample counters and the upload bounded (about 5 MB of Opus at the most) */
#define EXTERIA_VOICE_SECONDS_MAX 1800

typedef struct exteria_voice_encoder exteria_voice_encoder;

/* receives finished Ogg bytes in file order; a non-zero return aborts the encode */
typedef int (*exteria_voice_sink)(void *ctx, const uint8_t *bytes, size_t len);

/* an Ogg Opus stream: header pages first, then one page about every second of audio */
exteria_status exteria_voice_encoder_new(exteria_voice_encoder **out, exteria_voice_sink sink, void *ctx);
/* any number of samples per call; a partial frame waits for the next call */
exteria_status exteria_voice_encoder_feed(exteria_voice_encoder *e, const int16_t *samples, size_t count);
/* pads the last frame with silence, closes the stream and frees the encoder; also frees it when it fails */
exteria_status exteria_voice_encoder_finish(exteria_voice_encoder *e);
void exteria_voice_encoder_free(exteria_voice_encoder *e);

/* the bars of a recording: the loudest sample of each of EXTERIA_WAVEFORM_BARS equal slices, scaled so the loudest bar
   is 31. out is EXTERIA_WAVEFORM_BYTES long */
exteria_status exteria_waveform_build(const int16_t *samples, size_t count, uint8_t *out, size_t cap);

/* the bars of a voice note's waveform as another client packed them (five bits a bar, least significant bit first,
   as above); any length is taken, because other clients do not all send EXTERIA_WAVEFORM_BARS bars */
exteria_status exteria_waveform_unpack(const uint8_t *packed, size_t len, uint8_t *out, size_t cap, size_t *count);

/* where the samples of a mono 16 bit little endian PCM WAV file lie: byte offset and sample count inside data */
exteria_status exteria_wav_pcm16(const uint8_t *data, size_t len, uint32_t rate, size_t *offset, size_t *count);

/* receives decoded samples, mono signed 16 bit at EXTERIA_VOICE_RATE, in order; a non-zero return aborts the decode */
typedef int (*exteria_voice_pcm_sink)(void *ctx, const int16_t *samples, size_t count);

/* decodes an Ogg Opus voice note (what other clients send; stereo is mixed to mono) to the sink in chunks of at
   most 120 ms, so the caller never holds the whole recording as samples */
exteria_status exteria_voice_decode(const uint8_t *ogg, size_t len, exteria_voice_pcm_sink sink, void *ctx, size_t *total);
#define EXTERIA_VOICE_DECODE_SECONDS_MAX 3600

/* the 44 bytes in front of count mono 16 bit samples at rate, as a WAV file starts */
void exteria_wav_header(uint32_t rate, size_t count, uint8_t out[44]);

#endif
