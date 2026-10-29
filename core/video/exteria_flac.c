#include "exteria_flac.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libswresample/swresample.h>

/* the temporary WAV stays bounded on devices with little free storage */
#define WAV_BYTES_MAX (512u * 1024u * 1024u)
#define PCM_FRAMES_MAX 262144

static void little16(uint8_t *p, uint16_t n) { p[0] = (uint8_t)n; p[1] = (uint8_t)(n >> 8); }
static void little32(uint8_t *p, uint32_t n) { little16(p, (uint16_t)n); little16(p + 2, (uint16_t)(n >> 16)); }

static void wav_header(uint8_t *h, uint32_t rate, uint16_t channels, uint32_t bytes) {
    memset(h, 0, 44);
    memcpy(h, "RIFF", 4); little32(h + 4, 36 + bytes);
    memcpy(h + 8, "WAVEfmt ", 8); little32(h + 16, 16); little16(h + 20, 1);
    little16(h + 22, channels); little32(h + 24, rate); little32(h + 28, rate * channels * 2);
    little16(h + 32, (uint16_t)(channels * 2)); little16(h + 34, 16);
    memcpy(h + 36, "data", 4); little32(h + 40, bytes);
}

static exteria_status write_frame(SwrContext *resampler, const AVFrame *frame, FILE *file, int channels, uint32_t *total) {
    int count = swr_get_out_samples(resampler, frame ? frame->nb_samples : 0);
    uint8_t *samples = NULL;
    size_t bytes;
    int got;
    if (count < 0 || count > PCM_FRAMES_MAX) return EXTERIA_E_LIMIT;
    if (!count) return EXTERIA_OK;
    samples = malloc((size_t)count * (size_t)channels * 2);
    if (!samples) return EXTERIA_E_NOMEM;
    got = swr_convert(resampler, &samples, count, frame ? (const uint8_t **)frame->extended_data : NULL, frame ? frame->nb_samples : 0);
    if (got < 0) { free(samples); return EXTERIA_E_MALFORMED; }
    bytes = (size_t)got * (size_t)channels * 2;
    if (bytes > WAV_BYTES_MAX - *total) { free(samples); return EXTERIA_E_LIMIT; }
    if (fwrite(samples, 1, bytes, file) != bytes) { free(samples); return EXTERIA_E_IO; }
    *total += (uint32_t)bytes;
    free(samples);
    return EXTERIA_OK;
}

exteria_status exteria_flac_to_wav(const char *input, const char *output, int (*cancelled)(void *), void *context) {
    AVFormatContext *format = NULL;
    AVCodecContext *codec = NULL;
    AVPacket *packet = NULL;
    AVFrame *frame = NULL;
    SwrContext *resampler = NULL;
    AVChannelLayout target = {0};
    FILE *file = NULL;
    uint8_t header[44] = {0};
    uint32_t total = 0;
    int64_t input_samples = 0;
    int stream = -1, draining = 0, channels = 0, rate = 0, result, input_rate = 0, input_channels = 0, input_format = -1;
    exteria_status status = EXTERIA_E_MALFORMED;
    if (!input || !output || input[0] != '/' || output[0] != '/' || !strcmp(input, output)) return EXTERIA_E_ARG;
    if (cancelled && cancelled(context)) return EXTERIA_E_RETRY;
    if (avformat_open_input(&format, input, av_find_input_format("flac"), NULL) < 0 || avformat_find_stream_info(format, NULL) < 0) goto done;
    stream = av_find_best_stream(format, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (stream < 0 || format->streams[stream]->codecpar->codec_id != AV_CODEC_ID_FLAC) goto done;
    const AVCodec *decoder = avcodec_find_decoder(AV_CODEC_ID_FLAC);
    if (!decoder) { status = EXTERIA_E_UNSUPPORTED; goto done; }
    codec = avcodec_alloc_context3(decoder);
    packet = av_packet_alloc();
    frame = av_frame_alloc();
    if (!codec || !packet || !frame) { status = EXTERIA_E_NOMEM; goto done; }
    if (avcodec_parameters_to_context(codec, format->streams[stream]->codecpar) < 0 || avcodec_open2(codec, decoder, NULL) < 0) goto done;
    if (codec->sample_rate > 0 && codec->sample_rate <= 655350 && codec->ch_layout.nb_channels > 0 && codec->ch_layout.nb_channels <= 8 &&
        format->streams[stream]->duration > 0 && format->streams[stream]->duration != AV_NOPTS_VALUE) {
        int output_rate = codec->sample_rate > 48000 ? 48000 : codec->sample_rate;
        int output_channels = codec->ch_layout.nb_channels == 1 ? 1 : 2;
        AVRational output_time = {1, output_rate};
        int64_t frames = av_rescale_q_rnd(format->streams[stream]->duration, format->streams[stream]->time_base, output_time, AV_ROUND_UP);
        if (frames < 0 || frames > (int64_t)WAV_BYTES_MAX / (output_channels * 2)) { status = EXTERIA_E_LIMIT; goto done; }
    }
    file = fopen(output, "wb");
    if (!file) { status = EXTERIA_E_IO; goto done; }
    if (fwrite(header, 1, sizeof(header), file) != sizeof(header)) { status = EXTERIA_E_IO; goto done; }
    for (;;) {
        if (cancelled && cancelled(context)) { status = EXTERIA_E_RETRY; goto done; }
        result = avcodec_receive_frame(codec, frame);
        if (result == AVERROR_EOF) break;
        if (result == AVERROR(EAGAIN)) {
            if (draining) goto done;
            for (;;) {
                result = av_read_frame(format, packet);
                if (result < 0 || packet->stream_index == stream) break;
                av_packet_unref(packet);
            }
            if (result == AVERROR_EOF) { draining = 1; result = avcodec_send_packet(codec, NULL); }
            else if (result >= 0) result = avcodec_send_packet(codec, packet);
            av_packet_unref(packet);
            if (result < 0 && result != AVERROR_EOF) goto done;
            continue;
        }
        if (result < 0 || frame->nb_samples <= 0 || frame->nb_samples > PCM_FRAMES_MAX || frame->sample_rate <= 0 || frame->sample_rate > 655350 ||
            frame->ch_layout.nb_channels < 1 || frame->ch_layout.nb_channels > 8) goto done;
        if (input_samples > INT64_MAX - frame->nb_samples) { status = EXTERIA_E_LIMIT; goto done; }
        input_samples += frame->nb_samples;
        if (!resampler) {
            channels = frame->ch_layout.nb_channels == 1 ? 1 : 2;
            rate = frame->sample_rate > 48000 ? 48000 : frame->sample_rate;
            input_rate = frame->sample_rate;
            input_channels = frame->ch_layout.nb_channels;
            input_format = frame->format;
            av_channel_layout_default(&target, channels);
            if (swr_alloc_set_opts2(&resampler, &target, AV_SAMPLE_FMT_S16, rate, &frame->ch_layout, (enum AVSampleFormat)frame->format,
                                    frame->sample_rate, 0, NULL) < 0 || !resampler || swr_init(resampler) < 0) goto done;
        } else if (frame->sample_rate != input_rate || frame->ch_layout.nb_channels != input_channels || frame->format != input_format) goto done;
        status = write_frame(resampler, frame, file, channels, &total);
        av_frame_unref(frame);
        if (status != EXTERIA_OK) goto done;
        status = EXTERIA_E_MALFORMED;
    }
    if (!resampler || !total) goto done;
    if (format->streams[stream]->duration > 0 && format->streams[stream]->duration != AV_NOPTS_VALUE) {
        AVRational samples_time = {1, input_rate};
        int64_t expected = av_rescale_q(format->streams[stream]->duration, format->streams[stream]->time_base, samples_time);
        if (expected > 0 && input_samples != expected) goto done;
    }
    status = write_frame(resampler, NULL, file, channels, &total);
    if (status != EXTERIA_OK) goto done;
    wav_header(header, (uint32_t)rate, (uint16_t)channels, total);
    if (fseek(file, 0, SEEK_SET) != 0 || fwrite(header, 1, sizeof(header), file) != sizeof(header)) { status = EXTERIA_E_IO; goto done; }
    status = EXTERIA_OK;
done:
    if (file && fclose(file) != 0 && status == EXTERIA_OK) status = EXTERIA_E_IO;
    if (file && status != EXTERIA_OK) unlink(output);
    swr_free(&resampler); av_channel_layout_uninit(&target); av_frame_free(&frame); av_packet_free(&packet);
    avcodec_free_context(&codec); avformat_close_input(&format);
    return status;
}
