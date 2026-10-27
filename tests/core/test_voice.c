#include <math.h>

#include <ogg/ogg.h>
#include <opus.h>

#include "test_util.h"
#include "exteria_voice.h"

typedef struct sink {
    uint8_t *data;
    size_t len;
    size_t cap;
    int fail_after;
} sink;

static int collect(void *ctx, const uint8_t *bytes, size_t len) {
    sink *s = ctx;
    if (s->fail_after >= 0 && s->len >= (size_t)s->fail_after) return 1;
    if (s->len + len > s->cap) {
        size_t cap = (s->len + len) * 2;
        uint8_t *grown = realloc(s->data, cap);
        if (!grown) return 1;
        s->data = grown;
        s->cap = cap;
    }
    memcpy(s->data + s->len, bytes, len);
    s->len += len;
    return 0;
}

static void tone(int16_t *out, size_t count, double hz, double amplitude) {
    for (size_t i = 0; i < count; ++i) out[i] = (int16_t)(amplitude * sin(2.0 * 3.14159265358979 * hz * (double)i / EXTERIA_VOICE_RATE));
}

/* the stream is read back with libogg and decoded with libopus, as a player would */
static void check_stream(const sink *s, size_t samples) {
    ogg_sync_state sync;
    ogg_stream_state stream;
    ogg_page page;
    ogg_packet packet;
    int started = 0, packets = 0, eos = 0, pages = 0;
    int64_t last_granule = 0;
    long pre_skip = 0;
    uint64_t decoded = 0;
    double energy = 0;
    OpusDecoder *decoder = opus_decoder_create(EXTERIA_VOICE_RATE, 1, NULL);
    CHECK(decoder != NULL);
    ogg_sync_init(&sync);
    char *buffer = ogg_sync_buffer(&sync, (long)s->len);
    memcpy(buffer, s->data, s->len);
    CHECK_EQ_INT(ogg_sync_wrote(&sync, (long)s->len), 0);
    while (ogg_sync_pageout(&sync, &page) == 1) {
        ++pages;
        if (!started) {
            ogg_stream_init(&stream, ogg_page_serialno(&page));
            started = 1;
            CHECK(ogg_page_bos(&page));
        }
        CHECK_EQ_INT(ogg_stream_pagein(&stream, &page), 0);
        while (ogg_stream_packetout(&stream, &packet) == 1) {
            if (packet.packetno == 0) {
                CHECK(packet.bytes == 19 && !memcmp(packet.packet, "OpusHead", 8));
                CHECK_EQ_INT(packet.packet[9], 1);
                pre_skip = packet.packet[10] | (packet.packet[11] << 8);
                CHECK_EQ_INT(packet.packet[12] | (packet.packet[13] << 8), EXTERIA_VOICE_RATE);
            } else if (packet.packetno == 1) {
                CHECK(packet.bytes >= 12 && !memcmp(packet.packet, "OpusTags", 8));
            } else {
                int16_t frame[960];
                int n = opus_decode(decoder, packet.packet, (opus_int32)packet.bytes, frame, 960, 0);
                CHECK(n > 0);
                for (int i = 0; i < n; ++i) energy += (double)frame[i] * frame[i];
                decoded += (uint64_t)n;
                ++packets;
                /* libogg reports a granule position only for the packet that ends a page */
                if (packet.granulepos != -1) {
                    CHECK(packet.granulepos >= last_granule);
                    last_granule = packet.granulepos;
                }
                if (packet.e_o_s) eos = 1;
            }
        }
    }
    CHECK(started);
    CHECK(eos);
    CHECK(pages >= 3);
    /* the end granule position names the real length, so a player trims the padding of the last frame */
    CHECK_EQ_INT(last_granule, pre_skip + (int64_t)samples * 3);
    CHECK(decoded >= samples);
    CHECK(decoded < samples + 2 * EXTERIA_VOICE_RATE / 50);
    CHECK(energy > 1e6);
    if (started) ogg_stream_clear(&stream);
    ogg_sync_clear(&sync);
    opus_decoder_destroy(decoder);
    CHECK(packets > 0);
}

static void test_roundtrip(void) {
    const size_t total = EXTERIA_VOICE_RATE * 2 + 123;
    int16_t *pcm = malloc(total * sizeof(int16_t));
    sink s = {NULL, 0, 0, -1};
    exteria_voice_encoder *e = NULL;
    CHECK(pcm != NULL);
    tone(pcm, total, 440.0, 12000.0);
    CHECK_EQ_INT(exteria_voice_encoder_new(&e, collect, &s), EXTERIA_OK);
    /* odd chunk sizes: a frame is never aligned with the calls */
    for (size_t at = 0; at < total;) {
        size_t n = 777;
        if (at + n > total) n = total - at;
        CHECK_EQ_INT(exteria_voice_encoder_feed(e, pcm + at, n), EXTERIA_OK);
        at += n;
    }
    CHECK_EQ_INT(exteria_voice_encoder_finish(e), EXTERIA_OK);
    check_stream(&s, total);
    free(s.data);
    free(pcm);
}

static void test_boundaries(void) {
    sink s = {NULL, 0, 0, -1};
    exteria_voice_encoder *e = NULL;
    int16_t pcm[320];
    memset(pcm, 0, sizeof(pcm));
    CHECK_EQ_INT(exteria_voice_encoder_new(NULL, collect, &s), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_voice_encoder_new(&e, NULL, &s), EXTERIA_E_ARG);
    CHECK(e == NULL);
    CHECK_EQ_INT(exteria_voice_encoder_new(&e, collect, &s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_voice_encoder_feed(e, NULL, 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_voice_encoder_feed(e, pcm, 0), EXTERIA_OK);
    /* nothing was recorded: no empty note */
    CHECK_EQ_INT(exteria_voice_encoder_finish(e), EXTERIA_E_ARG);
    free(s.data);

    /* one exact frame ends on a boundary and still closes the stream */
    memset(&s, 0, sizeof(s));
    s.fail_after = -1;
    CHECK_EQ_INT(exteria_voice_encoder_new(&e, collect, &s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_voice_encoder_feed(e, pcm, 320), EXTERIA_OK);
    CHECK_EQ_INT(exteria_voice_encoder_finish(e), EXTERIA_OK);
    CHECK(s.len > 50);
    free(s.data);
}

static void test_sink_failure(void) {
    sink s = {NULL, 0, 0, 0};
    exteria_voice_encoder *e = NULL;
    /* a sink that refuses the very first page fails the constructor and leaks nothing */
    CHECK_EQ_INT(exteria_voice_encoder_new(&e, collect, &s), EXTERIA_E_IO);
    CHECK(e == NULL);
    s.fail_after = 100;
    free(s.data);
    memset(&s, 0, sizeof(s));
    s.fail_after = 90;
    CHECK_EQ_INT(exteria_voice_encoder_new(&e, collect, &s), EXTERIA_OK);
    {
        int16_t pcm[16000];
        exteria_status status = EXTERIA_OK;
        memset(pcm, 0x20, sizeof(pcm));
        for (int i = 0; i < 8 && status == EXTERIA_OK; ++i) status = exteria_voice_encoder_feed(e, pcm, 16000);
        CHECK_EQ_INT(status, EXTERIA_E_IO);
        CHECK_EQ_INT(exteria_voice_encoder_feed(e, pcm, 10), EXTERIA_E_STATE);
        CHECK_EQ_INT(exteria_voice_encoder_finish(e), EXTERIA_E_STATE);
    }
    free(s.data);
}

static void test_limit(void) {
    sink s = {NULL, 0, 0, -1};
    exteria_voice_encoder *e = NULL;
    static int16_t chunk[EXTERIA_VOICE_RATE];
    exteria_status status = EXTERIA_OK;
    int seconds = 0;
    CHECK_EQ_INT(exteria_voice_encoder_new(&e, collect, &s), EXTERIA_OK);
    while (status == EXTERIA_OK && seconds <= EXTERIA_VOICE_SECONDS_MAX + 1) {
        status = exteria_voice_encoder_feed(e, chunk, EXTERIA_VOICE_RATE);
        ++seconds;
    }
    CHECK_EQ_INT(status, EXTERIA_E_LIMIT);
    CHECK_EQ_INT(seconds, EXTERIA_VOICE_SECONDS_MAX + 1);
    exteria_voice_encoder_free(e);
    free(s.data);
}

static int bar(const uint8_t *packed, int index) {
    int bit = index * 5, value = 0;
    for (int i = 0; i < 5; ++i) value |= ((packed[(bit + i) / 8] >> ((bit + i) % 8)) & 1) << i;
    return value;
}

static void test_waveform(void) {
    int16_t pcm[1000];
    uint8_t out[EXTERIA_WAVEFORM_BYTES];
    CHECK_EQ_INT(EXTERIA_WAVEFORM_BYTES, 63);
    CHECK_EQ_INT(exteria_waveform_build(NULL, 1, out, sizeof(out)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_waveform_build(pcm, 0, out, sizeof(out)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_waveform_build(pcm, 10, out, EXTERIA_WAVEFORM_BYTES - 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_waveform_build(pcm, 10, NULL, sizeof(out)), EXTERIA_E_ARG);

    /* silence stays silent and never divides by zero */
    memset(pcm, 0, sizeof(pcm));
    CHECK_EQ_INT(exteria_waveform_build(pcm, 1000, out, sizeof(out)), EXTERIA_OK);
    for (int i = 0; i < EXTERIA_WAVEFORM_BARS; ++i) CHECK_EQ_INT(bar(out, i), 0);

    /* a rising ramp: the last bar is the loudest, the first is near silence, and the bars never fall */
    for (int i = 0; i < 1000; ++i) pcm[i] = (int16_t)(i * 30);
    CHECK_EQ_INT(exteria_waveform_build(pcm, 1000, out, sizeof(out)), EXTERIA_OK);
    CHECK_EQ_INT(bar(out, 99), 31);
    CHECK(bar(out, 0) <= 1);
    for (int i = 1; i < EXTERIA_WAVEFORM_BARS; ++i) CHECK(bar(out, i) >= bar(out, i - 1));

    /* negative samples count by magnitude; fewer samples than bars still fills every bar */
    for (int i = 0; i < 10; ++i) pcm[i] = (int16_t)(i == 3 ? -32768 : 100);
    CHECK_EQ_INT(exteria_waveform_build(pcm, 10, out, sizeof(out)), EXTERIA_OK);
    CHECK_EQ_INT(bar(out, 30), 31);
    CHECK_EQ_INT(bar(out, 0), 0);
}

static size_t wav(uint8_t *out, uint32_t rate, uint16_t format, uint16_t channels, uint16_t bits, int extra_chunk, uint32_t claimed, size_t samples) {
    size_t n = 0;
    memcpy(out, "RIFF\0\0\0\0WAVE", 12);
    n = 12;
    if (extra_chunk) {
        memcpy(out + n, "FLLR", 4);
        out[n + 4] = 3; out[n + 5] = 0; out[n + 6] = 0; out[n + 7] = 0;
        memset(out + n + 8, 0, 4);
        n += 12;
    }
    memcpy(out + n, "fmt ", 4);
    out[n + 4] = 16; out[n + 5] = out[n + 6] = out[n + 7] = 0;
    out[n + 8] = (uint8_t)format; out[n + 9] = (uint8_t)(format >> 8);
    out[n + 10] = (uint8_t)channels; out[n + 11] = 0;
    for (int i = 0; i < 4; ++i) out[n + 12 + i] = (uint8_t)(rate >> (8 * i));
    memset(out + n + 16, 0, 6);
    out[n + 22] = (uint8_t)bits; out[n + 23] = 0;
    n += 24;
    memcpy(out + n, "data", 4);
    for (int i = 0; i < 4; ++i) out[n + 4 + i] = (uint8_t)(claimed >> (8 * i));
    n += 8;
    memset(out + n, 1, samples * 2);
    return n + samples * 2;
}

static void test_wav(void) {
    uint8_t file[512];
    size_t offset = 1, count = 1, len;
    CHECK_EQ_INT(exteria_wav_pcm16(NULL, 0, 16000, &offset, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_wav_pcm16(file, 10, 16000, NULL, &count), EXTERIA_E_ARG);
    len = wav(file, 16000, 1, 1, 16, 0, 40, 20);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_OK);
    CHECK_EQ_INT(offset, 44);
    CHECK_EQ_INT(count, 20);
    /* a chunk before fmt, with the odd size padded */
    len = wav(file, 16000, 1, 1, 16, 1, 40, 20);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_OK);
    CHECK_EQ_INT(offset, 56);
    CHECK_EQ_INT(count, 20);
    /* a recorder that never closed the header leaves a size of zero or a huge one: the file decides */
    len = wav(file, 16000, 1, 1, 16, 0, 0xffffffffu, 30);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 30);
    /* a size smaller than the file wins over the rest */
    len = wav(file, 16000, 1, 1, 16, 0, 10, 30);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 5);
    len = wav(file, 44100, 1, 1, 16, 0, 40, 20);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_E_UNSUPPORTED);
    len = wav(file, 16000, 1, 2, 16, 0, 40, 20);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_E_UNSUPPORTED);
    len = wav(file, 16000, 3, 1, 16, 0, 40, 20);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_E_UNSUPPORTED);
    len = wav(file, 16000, 1, 1, 8, 0, 40, 20);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_E_UNSUPPORTED);
    len = wav(file, 16000, 1, 1, 16, 0, 0, 0);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_E_EOF);
    /* cut inside the headers */
    len = wav(file, 16000, 1, 1, 16, 0, 40, 20);
    for (size_t cut = 0; cut < 44; ++cut) CHECK(exteria_wav_pcm16(file, cut, 16000, &offset, &count) != EXTERIA_OK);
    memcpy(file, "RIFX", 4);
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_E_MALFORMED);
    /* a chunk that claims more than the file holds cannot walk past the end */
    len = wav(file, 16000, 1, 1, 16, 1, 40, 20);
    memcpy(file, "RIFF", 4);
    file[16] = 0xff; file[17] = 0xff; file[18] = 0xff; file[19] = 0x7f;
    CHECK_EQ_INT(exteria_wav_pcm16(file, len, 16000, &offset, &count), EXTERIA_E_MALFORMED);
}

typedef struct pcm {
    int16_t *data;
    size_t len;
    size_t cap;
    int refuse_after;
    size_t largest_chunk;
} pcm;

static int take_pcm(void *ctx, const int16_t *samples, size_t count) {
    pcm *p = ctx;
    if (p->refuse_after >= 0 && p->len >= (size_t)p->refuse_after) return 1;
    if (count > p->largest_chunk) p->largest_chunk = count;
    if (p->len + count > p->cap) {
        size_t cap = (p->len + count) * 2;
        int16_t *grown = realloc(p->data, cap * sizeof(int16_t));
        if (!grown) return 1;
        p->data = grown;
        p->cap = cap;
    }
    memcpy(p->data + p->len, samples, count * sizeof(int16_t));
    p->len += count;
    return 0;
}

static void encode_tone(sink *s, size_t samples, double hz) {
    exteria_voice_encoder *e = NULL;
    int16_t *wave = malloc(samples * sizeof(int16_t));
    CHECK(wave != NULL);
    tone(wave, samples, hz, 12000);
    memset(s, 0, sizeof(*s));
    s->fail_after = -1;
    CHECK_EQ_INT(exteria_voice_encoder_new(&e, collect, s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_voice_encoder_feed(e, wave, samples), EXTERIA_OK);
    CHECK_EQ_INT(exteria_voice_encoder_finish(e), EXTERIA_OK);
    free(wave);
}

/* a stream of the given packets, each on a page of its own, so a test can write a head the encoder never would */
static void build_stream(sink *s, const uint8_t *head, size_t head_len, int with_tags) {
    ogg_stream_state stream;
    ogg_packet packet;
    ogg_page page;
    static const uint8_t tags[] = {'O', 'p', 'u', 's', 'T', 'a', 'g', 's', 0, 0, 0, 0, 0, 0, 0, 0};
    memset(s, 0, sizeof(*s));
    s->fail_after = -1;
    ogg_stream_init(&stream, 7);
    memset(&packet, 0, sizeof(packet));
    packet.packet = (unsigned char *)head;
    packet.bytes = (long)head_len;
    packet.b_o_s = 1;
    ogg_stream_packetin(&stream, &packet);
    while (ogg_stream_flush(&stream, &page)) {
        collect(s, page.header, (size_t)page.header_len);
        collect(s, page.body, (size_t)page.body_len);
    }
    if (with_tags) {
        memset(&packet, 0, sizeof(packet));
        packet.packet = (unsigned char *)tags;
        packet.bytes = sizeof(tags);
        packet.packetno = 1;
        ogg_stream_packetin(&stream, &packet);
        while (ogg_stream_flush(&stream, &page)) {
            collect(s, page.header, (size_t)page.header_len);
            collect(s, page.body, (size_t)page.body_len);
        }
    }
    ogg_stream_clear(&stream);
}

static void test_waveform_unpack(void) {
    int16_t wave[EXTERIA_VOICE_RATE];
    uint8_t packed[EXTERIA_WAVEFORM_BYTES], bars[EXTERIA_WAVEFORM_BARS + 8];
    size_t count = 99;
    for (size_t i = 0; i < EXTERIA_VOICE_RATE; ++i) wave[i] = (int16_t)(i < EXTERIA_VOICE_RATE / 2 ? 3000 : 12000);
    CHECK_EQ_INT(exteria_waveform_build(wave, EXTERIA_VOICE_RATE, packed, sizeof(packed)), EXTERIA_OK);
    /* what the recorder packs, the player reads back: the quiet half and the loud half, the loudest bar at the top of the scale */
    CHECK_EQ_INT(exteria_waveform_unpack(packed, sizeof(packed), bars, sizeof(bars), &count), EXTERIA_OK);
    CHECK_EQ_INT(count, EXTERIA_WAVEFORM_BYTES * 8 / 5);
    CHECK(count >= EXTERIA_WAVEFORM_BARS);
    CHECK_EQ_INT(bars[0], 8);
    CHECK_EQ_INT(bars[EXTERIA_WAVEFORM_BARS - 1], 31);
    for (size_t i = 0; i < count; ++i) CHECK(bars[i] <= 31);
    /* the room of the caller cuts the list, a note without a waveform has no bars, and the arguments are checked */
    CHECK_EQ_INT(exteria_waveform_unpack(packed, sizeof(packed), bars, 10, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 10);
    CHECK_EQ_INT(exteria_waveform_unpack(packed, 0, bars, sizeof(bars), &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    {
        /* one byte holds one whole bar and three bits of the next, which is not a bar */
        static const uint8_t one[1] = {0xe9};
        CHECK_EQ_INT(exteria_waveform_unpack(one, 1, bars, sizeof(bars), &count), EXTERIA_OK);
        CHECK_EQ_INT(count, 1);
        CHECK_EQ_INT(bars[0], 0xe9 & 31);
    }
    CHECK_EQ_INT(exteria_waveform_unpack(packed, sizeof(packed), bars, sizeof(bars), NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_waveform_unpack(packed, sizeof(packed), NULL, sizeof(bars), &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_waveform_unpack(NULL, 4, bars, sizeof(bars), &count), EXTERIA_E_ARG);
}

static void test_decode(void) {
    sink encoded;
    pcm out = {0};
    size_t total = 99;
    double energy = 0;
    uint8_t header[44], head[19] = {'O', 'p', 'u', 's', 'H', 'e', 'a', 'd', 1, 1, 0x38, 1, 0x80, 0xbb, 0, 0, 0, 0, 0};
    size_t offset, count;
    out.refuse_after = -1;

    /* a second of tone comes back as a second of tone, within the padding of the last frame, and in chunks no longer than a frame */
    encode_tone(&encoded, EXTERIA_VOICE_RATE, 440);
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len, take_pcm, &out, &total), EXTERIA_OK);
    CHECK_EQ_INT(total, out.len);
    CHECK(out.len >= EXTERIA_VOICE_RATE - EXTERIA_VOICE_RATE / 50 && out.len <= EXTERIA_VOICE_RATE + EXTERIA_VOICE_RATE / 10);
    CHECK(out.largest_chunk <= EXTERIA_VOICE_RATE / 1000 * 120);
    for (size_t i = out.len / 4; i < out.len / 2; ++i) energy += (double)out.data[i] * (double)out.data[i];
    CHECK(energy / (double)(out.len / 4) > 1.0e6);

    /* the samples go to a WAV file the player can read back */
    exteria_wav_header(EXTERIA_VOICE_RATE, out.len, header);
    {
        uint8_t *file = malloc(sizeof(header) + out.len * 2);
        CHECK(file != NULL);
        memcpy(file, header, sizeof(header));
        for (size_t i = 0; i < out.len; ++i) {
            file[sizeof(header) + 2 * i] = (uint8_t)((uint16_t)out.data[i] & 0xffu);
            file[sizeof(header) + 2 * i + 1] = (uint8_t)((uint16_t)out.data[i] >> 8);
        }
        CHECK_EQ_INT(exteria_wav_pcm16(file, sizeof(header) + out.len * 2, EXTERIA_VOICE_RATE, &offset, &count), EXTERIA_OK);
        CHECK_EQ_INT(offset, 44);
        CHECK_EQ_INT(count, out.len);
        free(file);
    }

    /* a sink that refuses stops the decode */
    free(out.data);
    memset(&out, 0, sizeof(out));
    out.refuse_after = 3000;
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len, take_pcm, &out, &total), EXTERIA_E_IO);
    CHECK(total > 0 && total < EXTERIA_VOICE_RATE);

    /* a cut file gives the pages that are whole; garbage is not a stream; nothing at all is an argument error; the
       encoder closes a page about each second, so a few seconds make several */
    free(encoded.data);
    encode_tone(&encoded, 4 * EXTERIA_VOICE_RATE, 330);
    free(out.data);
    memset(&out, 0, sizeof(out));
    out.refuse_after = -1;
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len / 4 * 3, take_pcm, &out, &total), EXTERIA_OK);
    CHECK(total > 0 && total < 4 * EXTERIA_VOICE_RATE);
    {
        uint8_t noise[600];
        for (size_t i = 0; i < sizeof(noise); ++i) noise[i] = (uint8_t)(i * 31u + 7u);
        CHECK_EQ_INT(exteria_voice_decode(noise, sizeof(noise), take_pcm, &out, &total), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(total, 0);
    }
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, 0, take_pcm, &out, &total), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len, NULL, &out, &total), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len, take_pcm, &out, NULL), EXTERIA_E_ARG);
    /* damage in the middle costs that audio and not the rest */
    {
        uint8_t *damaged = malloc(encoded.len);
        size_t before = out.len;
        CHECK(damaged != NULL);
        memcpy(damaged, encoded.data, encoded.len);
        for (size_t i = encoded.len / 2; i < encoded.len / 2 + 40; ++i) damaged[i] ^= 0xa5u;
        CHECK_EQ_INT(exteria_voice_decode(damaged, encoded.len, take_pcm, &out, &total), EXTERIA_OK);
        CHECK(total > 0 && out.len > before);
        free(damaged);
    }
    free(encoded.data);

    /* the heads: a mono head with no audio has none to give, and other mappings, channel counts and magic are refused */
    build_stream(&encoded, head, sizeof(head), 1);
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len, take_pcm, &out, &total), EXTERIA_E_EOF);
    free(encoded.data);
    head[18] = 1;
    build_stream(&encoded, head, sizeof(head), 1);
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len, take_pcm, &out, &total), EXTERIA_E_UNSUPPORTED);
    free(encoded.data);
    head[18] = 0;
    head[9] = 6;
    build_stream(&encoded, head, sizeof(head), 1);
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len, take_pcm, &out, &total), EXTERIA_E_UNSUPPORTED);
    free(encoded.data);
    head[9] = 1;
    head[0] = 'X';
    build_stream(&encoded, head, sizeof(head), 1);
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len, take_pcm, &out, &total), EXTERIA_E_MALFORMED);
    free(encoded.data);
    head[0] = 'O';
    build_stream(&encoded, head, sizeof(head), 0);
    CHECK_EQ_INT(exteria_voice_decode(encoded.data, encoded.len, take_pcm, &out, &total), EXTERIA_E_EOF);
    free(encoded.data);
    free(out.data);
}

int main(void) {
    test_wav();
    test_roundtrip();
    test_boundaries();
    test_sink_failure();
    test_limit();
    test_waveform();
    test_decode();
    test_waveform_unpack();
    if (g_failures) {
        fprintf(stderr, "test_voice: %d of %d checks failed\n", g_failures, g_checks);
        return 1;
    }
    printf("test_voice: %d checks passed\n", g_checks);
    return 0;
}
