#include "exteria_video_sticker_core.h"
#include <stdio.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const uint8_t *bytes; size_t length, offset; } exteria_sticker_input;
static int read_bytes(void *opaque, uint8_t *buffer, int size) {
    exteria_sticker_input *input = opaque;
    size_t remaining = input->length - input->offset;
    if (size <= 0) return AVERROR(EINVAL);
    if (!remaining) return AVERROR_EOF;
    size_t count = remaining < (size_t)size ? remaining : (size_t)size;
    memcpy(buffer, input->bytes + input->offset, count); input->offset += count;
    return (int)count;
}
static int64_t seek_bytes(void *opaque, int64_t offset, int whence) {
    exteria_sticker_input *input = opaque;
    if (whence == AVSEEK_SIZE) return (int64_t)input->length;
    whence &= ~AVSEEK_FORCE;
    int64_t base = whence == SEEK_SET ? 0 : whence == SEEK_CUR ? (int64_t)input->offset : whence == SEEK_END ? (int64_t)input->length : -1;
    if (base < 0 || offset < -base || offset > (int64_t)input->length - base) return AVERROR(EINVAL);
    input->offset = (size_t)(base + offset); return (int64_t)input->offset;
}
static uint8_t clip_channel(int value) {
    return (uint8_t)(value < 0 ? 0 : value > 255 ? 255 : value);
}

/* telegram vp9 stickers use 8-bit 4:2:0, including a separate full-resolution alpha plane */
static int convert_frame(const AVFrame *frame, uint8_t *pixels, int width, int height) {
    int alpha = frame->format == AV_PIX_FMT_YUVA420P;
    if (!alpha && frame->format != AV_PIX_FMT_YUV420P && frame->format != AV_PIX_FMT_YUVJ420P) return 0;
    for (int plane = 0; plane < (alpha ? 4 : 3); ++plane) {
        int minimum = plane == 1 || plane == 2 ? (frame->width + 1) / 2 : frame->width;
        if (!frame->data[plane] || frame->linesize[plane] < minimum || frame->linesize[plane] > 8192) return 0;
    }
    int full_range = frame->color_range == AVCOL_RANGE_JPEG || frame->format == AV_PIX_FMT_YUVJ420P;
    int hd = frame->colorspace == AVCOL_SPC_BT709;
    for (int y = 0; y < height; ++y) {
        int sy = y * frame->height / height;
        for (int x = 0; x < width; ++x) {
            int sx = x * frame->width / width;
            int luma = frame->data[0][sy * frame->linesize[0] + sx];
            int u = frame->data[1][(sy / 2) * frame->linesize[1] + sx / 2] - 128;
            int v = frame->data[2][(sy / 2) * frame->linesize[2] + sx / 2] - 128;
            int a = alpha ? frame->data[3][sy * frame->linesize[3] + sx] : 255;
            int c = full_range ? 256 * luma : 298 * (luma - 16);
            int r = (c + (full_range ? (hd ? 403 : 359) : (hd ? 459 : 409)) * v + 128) / 256;
            int g = (c - (full_range ? (hd ? 48 : 88) : (hd ? 55 : 100)) * u -
                     (full_range ? (hd ? 120 : 183) : (hd ? 136 : 208)) * v + 128) / 256;
            int b = (c + (full_range ? (hd ? 475 : 454) : (hd ? 541 : 516)) * u + 128) / 256;
            size_t at = ((size_t)y * (size_t)width + (size_t)x) * 4;
            pixels[at] = (uint8_t)((clip_channel(b) * a + 127) / 255);
            pixels[at + 1] = (uint8_t)((clip_channel(g) * a + 127) / 255);
            pixels[at + 2] = (uint8_t)((clip_channel(r) * a + 127) / 255);
            pixels[at + 3] = (uint8_t)a;
        }
    }
    return 1;
}

int exteria_video_sticker_decode(const void *data, size_t length, int max_side, double target_fps,
                        exteria_video_sticker_frame callback, void *context, double *duration) {
    if (duration) *duration = 0;
    if (!data || !length || length > 512 * 1024 || max_side < 1 || max_side > 192 ||
        !isfinite(target_fps) || target_fps < 1 || target_fps > 30 || !callback || !duration) return 0;
    exteria_sticker_input input = {data, length, 0};
    AVFormatContext *format = avformat_alloc_context();
    uint8_t *io_buffer = av_malloc(8192);
    AVIOContext *io = io_buffer ? avio_alloc_context(io_buffer, 8192, 0, &input, read_bytes, NULL, seek_bytes) : NULL;
    AVCodecContext *codec = NULL; AVFrame *frame = NULL; AVPacket *packet = NULL;
    uint8_t *pixels = NULL;
    int emitted = 0, decoded = 0, valid = 0, stream = -1, draining = 0, packets = 0;
    double next_time = 0, end_time = 0, first_time = NAN, source_fps = 30;
    if (!format || !io) goto cleanup;
    format->pb = io; format->flags |= AVFMT_FLAG_CUSTOM_IO;
    /* matroska and libvpx preserve vp9 alpha without probing unrelated formats */
    const AVInputFormat *demuxer = av_find_input_format("matroska");
    if (!demuxer) goto cleanup;
    format->max_streams = 8;
    format->probesize = 512 * 1024;
    format->max_analyze_duration = 3200000;
    if (avformat_open_input(&format, NULL, demuxer, NULL) < 0) goto cleanup;
    for (unsigned i = 0; i < format->nb_streams; i++)
        if (format->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) { stream = (int)i; break; }
    if (stream < 0 || format->streams[stream]->codecpar->codec_id != AV_CODEC_ID_VP9) goto cleanup;
    const AVCodec *decoder = avcodec_find_decoder_by_name("libvpx-vp9");
    if (!decoder) goto cleanup;
    codec = avcodec_alloc_context3(decoder);
    if (!codec || avcodec_parameters_to_context(codec, format->streams[stream]->codecpar) < 0) goto cleanup;
    if (codec->width < 1 || codec->height < 1 || codec->width > 512 || codec->height > 512) goto cleanup;
    codec->max_pixels = 512 * 512;
    codec->thread_count = 1;
    if (avcodec_open2(codec, decoder, NULL) < 0) goto cleanup;
    AVRational rate = av_guess_frame_rate(format, format->streams[stream], NULL);
    if (rate.num > 0 && rate.den > 0) source_fps = av_q2d(rate);
    if (source_fps < 1 || source_fps > 60) goto cleanup;
    frame = av_frame_alloc(); packet = av_packet_alloc();
    if (!frame || !packet) goto cleanup;
    while (decoded <= 192) {
        int result = avcodec_receive_frame(codec, frame);
        if (result == AVERROR_EOF) { valid = 1; break; }
        if (result == AVERROR(EAGAIN)) {
            if (draining) goto cleanup;
            while ((result = av_read_frame(format, packet)) >= 0) {
                if (++packets > 512) goto cleanup;
                if (packet->stream_index == stream) break;
                av_packet_unref(packet);
            }
            if (result < 0) {
                if (result != AVERROR_EOF) goto cleanup;
                draining = 1; result = avcodec_send_packet(codec, NULL);
            } else result = avcodec_send_packet(codec, packet);
            av_packet_unref(packet);
            if (result < 0 && result != AVERROR_EOF) goto cleanup;
            continue;
        }
        if (result < 0) goto cleanup;
        decoded++;
        if (frame->width < 1 || frame->height < 1 || frame->width > 512 || frame->height > 512) goto cleanup;
        double time = frame->best_effort_timestamp == AV_NOPTS_VALUE ? (decoded - 1) / source_fps :
            (double)frame->best_effort_timestamp * av_q2d(format->streams[stream]->time_base);
        if (isnan(first_time)) first_time = time;
        time -= first_time;
        if (!isfinite(time) || time < 0 || time > 3.1) goto cleanup;
        end_time = time + 1 / source_fps;
        /* webm timestamps round to milliseconds */
        if (time + .5 / source_fps >= next_time && emitted < 90) {
            int longest = frame->width > frame->height ? frame->width : frame->height;
            int width = (frame->width * max_side + longest / 2) / longest;
            int height = (frame->height * max_side + longest / 2) / longest;
            width = width > 0 ? width : 1; height = height > 0 ? height : 1;
            free(pixels); pixels = malloc((size_t)width * (size_t)height * 4);
            if (!pixels || !convert_frame(frame, pixels, width, height)) goto cleanup;
            int action = callback(context, pixels, width, height);
            if (action < 0) goto cleanup;
            if (!action) { valid = 1; emitted++; break; }
            emitted++; next_time += 1 / target_fps;
            if (next_time < time) next_time = time + 1 / target_fps;
        }
        av_frame_unref(frame);
    }
cleanup:
    free(pixels);
    av_packet_free(&packet); av_frame_free(&frame); avcodec_free_context(&codec);
    avformat_close_input(&format);
    if (io) { av_freep(&io->buffer); avio_context_free(&io); } else av_free(io_buffer);
    if (!valid || emitted < 1 || end_time <= 0 || end_time > 3.2) return 0;
    *duration = end_time; return emitted;
}
