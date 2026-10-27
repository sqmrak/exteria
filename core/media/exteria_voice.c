#include "exteria_voice.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include <ogg/ogg.h>
#include <opus.h>

#include "exteria_random.h"

/* 20 ms at the voice rate; opus takes 2.5 to 60 ms and 20 ms is the usual size for speech */
#define FRAME_SAMPLES (EXTERIA_VOICE_RATE / 50)
#define PACKET_MAX 1275
#define BITRATE 24000
/* the old cores of the supported phones encode faster at a middle complexity with little loss for speech */
#define COMPLEXITY 5
/* ogg granule positions always count at 48 kHz, whatever the input rate was */
#define GRANULE_PER_SAMPLE (48000 / EXTERIA_VOICE_RATE)

struct exteria_voice_encoder {
    OpusEncoder *opus;
    ogg_stream_state stream;
    int stream_ready;
    exteria_voice_sink sink;
    void *ctx;
    int16_t frame[FRAME_SAMPLES];
    size_t filled;
    uint64_t samples;
    uint64_t frames;
    int64_t pre_skip;
    int64_t last_granule;
    int64_t packet_no;
    uint8_t packet[PACKET_MAX];
    int failed;
};

static void put_u16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xffu);
    p[1] = (uint8_t)(v >> 8);
}

static void put_u32(uint8_t *p, uint32_t v) {
    for (int i = 0; i < 4; ++i) p[i] = (uint8_t)(v >> (8 * i));
}

static exteria_status emit_page(exteria_voice_encoder *e, const ogg_page *page) {
    if (e->sink(e->ctx, page->header, (size_t)page->header_len) || e->sink(e->ctx, page->body, (size_t)page->body_len)) {
        e->failed = 1;
        return EXTERIA_E_IO;
    }
    return EXTERIA_OK;
}

/* flush forces a page boundary, which the two header packets need so players find them at fixed places */
static exteria_status push_packet(exteria_voice_encoder *e, const uint8_t *data, size_t len, int64_t granule, int last, int flush) {
    ogg_packet packet;
    ogg_page page;
    memset(&packet, 0, sizeof(packet));
    packet.packet = (unsigned char *)data;
    packet.bytes = (long)len;
    packet.b_o_s = e->packet_no == 0;
    packet.e_o_s = last;
    packet.granulepos = granule;
    packet.packetno = e->packet_no++;
    if (ogg_stream_packetin(&e->stream, &packet) != 0) return EXTERIA_E_MALFORMED;
    while ((flush ? ogg_stream_flush(&e->stream, &page) : ogg_stream_pageout(&e->stream, &page)) > 0) {
        exteria_status status = emit_page(e, &page);
        if (status != EXTERIA_OK) return status;
    }
    if (last) {
        while (ogg_stream_flush(&e->stream, &page) > 0) {
            exteria_status status = emit_page(e, &page);
            if (status != EXTERIA_OK) return status;
        }
    }
    return EXTERIA_OK;
}

static exteria_status write_headers(exteria_voice_encoder *e) {
    static const char vendor[] = "exteria";
    uint8_t head[19];
    uint8_t tags[8 + 4 + sizeof(vendor) - 1 + 4];
    exteria_status status;
    memcpy(head, "OpusHead", 8);
    head[8] = 1;
    head[9] = 1;
    put_u16(head + 10, (uint16_t)e->pre_skip);
    put_u32(head + 12, EXTERIA_VOICE_RATE);
    put_u16(head + 16, 0);
    head[18] = 0;
    status = push_packet(e, head, sizeof(head), 0, 0, 1);
    if (status != EXTERIA_OK) return status;
    memcpy(tags, "OpusTags", 8);
    put_u32(tags + 8, (uint32_t)(sizeof(vendor) - 1));
    memcpy(tags + 12, vendor, sizeof(vendor) - 1);
    put_u32(tags + 12 + sizeof(vendor) - 1, 0);
    return push_packet(e, tags, sizeof(tags), 0, 0, 1);
}

exteria_status exteria_voice_encoder_new(exteria_voice_encoder **out, exteria_voice_sink sink, void *ctx) {
    exteria_voice_encoder *e;
    uint64_t serial = 0;
    int error = 0, lookahead = 0;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!sink) return EXTERIA_E_ARG;
    e = calloc(1, sizeof(*e));
    if (!e) return EXTERIA_E_NOMEM;
    e->sink = sink;
    e->ctx = ctx;
    status = exteria_random_u64(&serial);
    if (status != EXTERIA_OK) goto fail;
    e->opus = opus_encoder_create(EXTERIA_VOICE_RATE, 1, OPUS_APPLICATION_VOIP, &error);
    if (!e->opus || error != OPUS_OK) { status = EXTERIA_E_UNSUPPORTED; goto fail; }
    if (opus_encoder_ctl(e->opus, OPUS_SET_BITRATE(BITRATE)) != OPUS_OK ||
        opus_encoder_ctl(e->opus, OPUS_SET_COMPLEXITY(COMPLEXITY)) != OPUS_OK ||
        opus_encoder_ctl(e->opus, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE)) != OPUS_OK ||
        opus_encoder_ctl(e->opus, OPUS_GET_LOOKAHEAD(&lookahead)) != OPUS_OK) { status = EXTERIA_E_UNSUPPORTED; goto fail; }
    e->pre_skip = (int64_t)lookahead * GRANULE_PER_SAMPLE;
    if (ogg_stream_init(&e->stream, (int)(serial & 0x7fffffffu)) != 0) { status = EXTERIA_E_NOMEM; goto fail; }
    e->stream_ready = 1;
    status = write_headers(e);
    if (status != EXTERIA_OK) goto fail;
    *out = e;
    return EXTERIA_OK;
fail:
    exteria_voice_encoder_free(e);
    return status;
}

/* the last packet carries the end flag and the granule position that trims the padding the decoder would play */
static exteria_status encode_frame(exteria_voice_encoder *e, const int16_t *frame, int last, int64_t last_granule) {
    int len = opus_encode(e->opus, frame, FRAME_SAMPLES, e->packet, PACKET_MAX);
    int64_t granule;
    if (len < 0) return EXTERIA_E_CRYPTO;
    e->frames++;
    granule = (int64_t)e->frames * FRAME_SAMPLES * GRANULE_PER_SAMPLE;
    if (last && last_granule < granule && last_granule > e->last_granule) granule = last_granule;
    e->last_granule = granule;
    return push_packet(e, e->packet, (size_t)len, granule, last, 0);
}

exteria_status exteria_voice_encoder_feed(exteria_voice_encoder *e, const int16_t *samples, size_t count) {
    if (!e || (!samples && count)) return EXTERIA_E_ARG;
    if (e->failed) return EXTERIA_E_STATE;
    if (e->samples + count > (uint64_t)EXTERIA_VOICE_SECONDS_MAX * EXTERIA_VOICE_RATE) return EXTERIA_E_LIMIT;
    while (count) {
        size_t take = FRAME_SAMPLES - e->filled;
        if (take > count) take = count;
        memcpy(e->frame + e->filled, samples, take * sizeof(int16_t));
        e->filled += take;
        samples += take;
        count -= take;
        e->samples += take;
        if (e->filled == FRAME_SAMPLES) {
            exteria_status status = encode_frame(e, e->frame, 0, 0);
            e->filled = 0;
            if (status != EXTERIA_OK) { e->failed = 1; return status; }
        }
    }
    return EXTERIA_OK;
}

exteria_status exteria_voice_encoder_finish(exteria_voice_encoder *e) {
    exteria_status status;
    if (!e) return EXTERIA_E_ARG;
    if (e->failed) status = EXTERIA_E_STATE;
    else if (!e->samples) status = EXTERIA_E_ARG;
    else {
        /* the closing frame is the partial one padded with silence, or an empty one when the audio ended on a boundary */
        memset(e->frame + e->filled, 0, (FRAME_SAMPLES - e->filled) * sizeof(int16_t));
        status = encode_frame(e, e->frame, 1, e->pre_skip + (int64_t)e->samples * GRANULE_PER_SAMPLE);
    }
    exteria_voice_encoder_free(e);
    return status;
}

void exteria_voice_encoder_free(exteria_voice_encoder *e) {
    if (!e) return;
    if (e->stream_ready) ogg_stream_clear(&e->stream);
    if (e->opus) opus_encoder_destroy(e->opus);
    free(e);
}

exteria_status exteria_waveform_build(const int16_t *samples, size_t count, uint8_t *out, size_t cap) {
    uint32_t peaks[EXTERIA_WAVEFORM_BARS];
    uint32_t loudest = 0;
    size_t bar;
    if (!out || cap < EXTERIA_WAVEFORM_BYTES || (!samples && count)) return EXTERIA_E_ARG;
    memset(out, 0, cap);
    if (!count) return EXTERIA_E_ARG;
    for (bar = 0; bar < EXTERIA_WAVEFORM_BARS; ++bar) {
        size_t from = count * bar / EXTERIA_WAVEFORM_BARS;
        size_t to = count * (bar + 1) / EXTERIA_WAVEFORM_BARS;
        uint32_t peak = 0;
        if (to == from && from < count) to = from + 1;
        for (size_t i = from; i < to && i < count; ++i) {
            int32_t v = samples[i];
            uint32_t magnitude = (uint32_t)(v < 0 ? -v : v);
            if (magnitude > peak) peak = magnitude;
        }
        peaks[bar] = peak;
        if (peak > loudest) loudest = peak;
    }
    for (bar = 0; bar < EXTERIA_WAVEFORM_BARS; ++bar) {
        uint32_t level = loudest ? (peaks[bar] * 31u + loudest / 2u) / loudest : 0;
        size_t bit = bar * 5;
        /* the five bits of a bar start at any bit of a byte and may spill into the next, least significant bit first */
        uint32_t window = level << (bit % 8);
        out[bit / 8] = (uint8_t)(out[bit / 8] | (window & 0xffu));
        if (bit / 8 + 1 < EXTERIA_WAVEFORM_BYTES) out[bit / 8 + 1] = (uint8_t)(out[bit / 8 + 1] | (window >> 8));
    }
    return EXTERIA_OK;
}

exteria_status exteria_waveform_unpack(const uint8_t *packed, size_t len, uint8_t *out, size_t cap, size_t *count) {
    size_t bars, bar;
    if (!count) return EXTERIA_E_ARG;
    *count = 0;
    if (!out || (!packed && len)) return EXTERIA_E_ARG;
    bars = len * 8 / 5;
    if (bars > cap) bars = cap;
    for (bar = 0; bar < bars; ++bar) {
        size_t bit = bar * 5;
        uint32_t window = packed[bit / 8];
        /* the last bar of a stream can sit entirely inside the final byte, so the next byte is only read when it is there */
        if (bit / 8 + 1 < len) window |= (uint32_t)packed[bit / 8 + 1] << 8;
        out[bar] = (uint8_t)((window >> (bit % 8)) & 31u);
    }
    *count = bars;
    return EXTERIA_OK;
}

static uint32_t get_u32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint16_t get_u16(const uint8_t *p) {
    return (uint16_t)(p[0] | p[1] << 8);
}

exteria_status exteria_wav_pcm16(const uint8_t *data, size_t len, uint32_t rate, size_t *offset, size_t *count) {
    size_t at = 12;
    int have_format = 0;
    if (!offset || !count) return EXTERIA_E_ARG;
    *offset = 0;
    *count = 0;
    if (!data || len < 12 || memcmp(data, "RIFF", 4) || memcmp(data + 8, "WAVE", 4)) return EXTERIA_E_MALFORMED;
    while (at + 8 <= len) {
        uint32_t size = get_u32(data + at + 4);
        size_t body = at + 8;
        if (!memcmp(data + at, "fmt ", 4)) {
            if (size < 16 || body + 16 > len) return EXTERIA_E_MALFORMED;
            if (get_u16(data + body) != 1 || get_u16(data + body + 2) != 1 || get_u32(data + body + 4) != rate ||
                get_u16(data + body + 14) != 16) return EXTERIA_E_UNSUPPORTED;
            have_format = 1;
        } else if (!memcmp(data + at, "data", 4)) {
            size_t available = len - body, bytes = size;
            if (!have_format) return EXTERIA_E_MALFORMED;
            if (bytes > available) bytes = available;
            if (bytes < 2) return EXTERIA_E_EOF;
            *offset = body;
            *count = bytes / 2;
            return EXTERIA_OK;
        }
        /* chunks are padded to an even size */
        if (size > len - body) return EXTERIA_E_MALFORMED;
        at = body + size + (size & 1u);
    }
    return EXTERIA_E_MALFORMED;
}

void exteria_wav_header(uint32_t rate, size_t count, uint8_t out[44]) {
    uint32_t bytes = (uint32_t)(count * 2u);
    memcpy(out, "RIFF", 4);
    put_u32(out + 4, 36u + bytes);
    memcpy(out + 8, "WAVEfmt ", 8);
    put_u32(out + 16, 16u);
    put_u16(out + 20, 1u);
    put_u16(out + 22, 1u);
    put_u32(out + 24, rate);
    put_u32(out + 28, rate * 2u);
    put_u16(out + 32, 2u);
    put_u16(out + 34, 16u);
    memcpy(out + 36, "data", 4);
    put_u32(out + 40, bytes);
}

/* the longest frame opus makes is 120 ms */
#define DECODE_FRAME_MAX (EXTERIA_VOICE_RATE / 1000 * 120)
#define DECODE_INPUT_CHUNK 4096
/* damaged packets in a row after which the stream is given up on; isolated damage only costs its own audio */
#define DECODE_BAD_RUN 50

exteria_status exteria_voice_decode(const uint8_t *ogg, size_t len, exteria_voice_pcm_sink sink, void *ctx, size_t *total) {
    ogg_sync_state sync;
    ogg_stream_state stream;
    ogg_page page;
    ogg_packet packet;
    OpusDecoder *decoder = NULL;
    int16_t pcm[DECODE_FRAME_MAX];
    size_t at = 0, produced = 0, skip = 0, limit = (size_t)EXTERIA_VOICE_RATE * EXTERIA_VOICE_DECODE_SECONDS_MAX;
    int stream_ready = 0, packet_no = 0, bad_run = 0, damaged = 0;
    long serial = 0;
    exteria_status status = EXTERIA_OK;
    if (!total) return EXTERIA_E_ARG;
    *total = 0;
    if (!ogg || !sink || len == 0) return EXTERIA_E_ARG;
    ogg_sync_init(&sync);
    while (status == EXTERIA_OK) {
        int got = ogg_sync_pageout(&sync, &page);
        if (got == 0) {
            size_t chunk;
            char *room;
            if (at >= len) break;
            chunk = len - at < DECODE_INPUT_CHUNK ? len - at : DECODE_INPUT_CHUNK;
            room = ogg_sync_buffer(&sync, (long)chunk);
            if (!room) {
                status = EXTERIA_E_NOMEM;
                break;
            }
            memcpy(room, ogg + at, chunk);
            at += chunk;
            if (ogg_sync_wrote(&sync, (long)chunk) != 0) status = EXTERIA_E_MALFORMED;
            continue;
        }
        if (got < 0) {
            /* a hole in the stream: the sync layer finds the next page itself */
            ++damaged;
            continue;
        }
        if (!stream_ready) {
            if (!ogg_page_bos(&page)) continue;
            serial = ogg_page_serialno(&page);
            if (ogg_stream_init(&stream, (int)serial) != 0) {
                status = EXTERIA_E_NOMEM;
                break;
            }
            stream_ready = 1;
        } else if (ogg_page_serialno(&page) != (int)serial) {
            /* a chained or multiplexed stream is more than a voice note is */
            status = produced ? EXTERIA_OK : EXTERIA_E_UNSUPPORTED;
            if (ogg_page_bos(&page)) break;
            continue;
        }
        if (ogg_stream_pagein(&stream, &page) != 0) {
            ++damaged;
            continue;
        }
        for (;;) {
            int n;
            got = ogg_stream_packetout(&stream, &packet);
            if (got == 0) break;
            if (got < 0) {
                ++damaged;
                continue;
            }
            if (packet_no == 0) {
                int channels, mapping, error = 0;
                uint16_t pre_skip;
                if (packet.bytes < 19 || memcmp(packet.packet, "OpusHead", 8) || (packet.packet[8] >> 4) != 0) {
                    status = EXTERIA_E_MALFORMED;
                    break;
                }
                channels = packet.packet[9];
                mapping = packet.packet[18];
                if (channels < 1 || channels > 2 || mapping != 0) {
                    status = EXTERIA_E_UNSUPPORTED;
                    break;
                }
                pre_skip = get_u16(packet.packet + 10);
                skip = (size_t)pre_skip / (48000 / EXTERIA_VOICE_RATE);
                /* a stereo stream is asked for one channel, which opus mixes down */
                decoder = opus_decoder_create(EXTERIA_VOICE_RATE, 1, &error);
                if (!decoder || error != OPUS_OK) {
                    status = EXTERIA_E_NOMEM;
                    break;
                }
            } else if (packet_no == 1) {
                if (packet.bytes < 8 || memcmp(packet.packet, "OpusTags", 8)) {
                    status = EXTERIA_E_MALFORMED;
                    break;
                }
            } else {
                const int16_t *out = pcm;
                n = opus_decode(decoder, packet.packet, (opus_int32)packet.bytes, pcm, DECODE_FRAME_MAX, 0);
                if (n < 0) {
                    ++damaged;
                    if (++bad_run >= DECODE_BAD_RUN) {
                        status = EXTERIA_E_MALFORMED;
                        break;
                    }
                    ++packet_no;
                    continue;
                }
                bad_run = 0;
                if (skip) {
                    size_t drop = skip < (size_t)n ? skip : (size_t)n;
                    skip -= drop;
                    out += drop;
                    n -= (int)drop;
                }
                if (n > 0) {
                    if (produced + (size_t)n > limit) {
                        status = EXTERIA_E_ARG;
                        break;
                    }
                    if (sink(ctx, out, (size_t)n)) {
                        status = EXTERIA_E_IO;
                        break;
                    }
                    produced += (size_t)n;
                }
            }
            ++packet_no;
        }
    }
    *total = produced;
    if (decoder) opus_decoder_destroy(decoder);
    if (stream_ready) ogg_stream_clear(&stream);
    ogg_sync_clear(&sync);
    if (status == EXTERIA_OK && !stream_ready) status = EXTERIA_E_MALFORMED;
    if (status == EXTERIA_OK && !produced) status = damaged ? EXTERIA_E_MALFORMED : EXTERIA_E_EOF;
    return status;
}
