#include "exteria_vp8.h"

#include <stdlib.h>
#include <string.h>

#include <vpx/vp8cx.h>
#include <vpx/vp8dx.h>
#include <vpx/vpx_decoder.h>
#include <vpx/vpx_encoder.h>

/* real time speed setting of the encoder: negative values trade quality for speed, -12 keeps a 240p stream under one core of an A5 */
#define ENCODER_CPU_USED (-12)
#define KEY_FRAME_HEADER_LEN 10u
/* the same cap as the depacketizer storage of the call */
#define DECODER_MAX_FRAME (512u * 1024u)

struct exteria_vp8_encoder {
    vpx_codec_ctx_t context;
    vpx_codec_enc_cfg_t config;
    int width;
    int height;
    int need_key;
};

struct exteria_vp8_decoder {
    vpx_codec_ctx_t context;
    size_t max_pixels;
    int has_key;
};

static int even_side(int value) {
    return value >= EXTERIA_VP8_MIN_SIDE && value <= EXTERIA_VP8_MAX_SIDE && value % 2 == 0;
}

exteria_status exteria_vp8_encoder_open(exteria_vp8_encoder **out, int width, int height, int fps, int bitrate_kbps) {
    exteria_vp8_encoder *enc;
    vpx_codec_iface_t *iface;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!even_side(width) || !even_side(height) || fps < 1 || fps > 60 || bitrate_kbps < 16 || bitrate_kbps > 4000) return EXTERIA_E_ARG;
    iface = vpx_codec_vp8_cx();
    if (!iface) return EXTERIA_E_UNSUPPORTED;
    enc = (exteria_vp8_encoder *)calloc(1, sizeof(*enc));
    if (!enc) return EXTERIA_E_NOMEM;
    if (vpx_codec_enc_config_default(iface, &enc->config, 0) != VPX_CODEC_OK) {
        free(enc);
        return EXTERIA_E_UNSUPPORTED;
    }
    enc->config.g_w = (unsigned)width;
    enc->config.g_h = (unsigned)height;
    enc->config.g_timebase.num = 1;
    enc->config.g_timebase.den = fps;
    enc->config.g_threads = 1;
    enc->config.g_lag_in_frames = 0;
    enc->config.g_error_resilient = VPX_ERROR_RESILIENT_DEFAULT;
    enc->config.rc_end_usage = VPX_CBR;
    enc->config.rc_target_bitrate = (unsigned)bitrate_kbps;
    enc->config.rc_dropframe_thresh = 0;
    enc->config.rc_min_quantizer = 4;
    enc->config.rc_max_quantizer = 56;
    /* key frames come on request, a call asks for one with a picture loss indication */
    enc->config.kf_mode = VPX_KF_AUTO;
    enc->config.kf_max_dist = 3000;
    if (vpx_codec_enc_init(&enc->context, iface, &enc->config, 0) != VPX_CODEC_OK) {
        free(enc);
        return EXTERIA_E_UNSUPPORTED;
    }
    if (vpx_codec_control(&enc->context, VP8E_SET_CPUUSED, ENCODER_CPU_USED) != VPX_CODEC_OK) {
        vpx_codec_destroy(&enc->context);
        free(enc);
        return EXTERIA_E_UNSUPPORTED;
    }
    enc->width = width;
    enc->height = height;
    *out = enc;
    return EXTERIA_OK;
}

exteria_status exteria_vp8_encoder_encode(exteria_vp8_encoder *enc, const exteria_i420 *image, int64_t pts, int force_key,
                                          uint8_t *out, size_t capacity, size_t *length, int *key_frame) {
    vpx_image_t wrapper;
    const vpx_codec_cx_pkt_t *packet;
    vpx_codec_iter_t iter = NULL;
    exteria_status status = EXTERIA_OK;
    int i;
    if (length) *length = 0;
    if (key_frame) *key_frame = 0;
    if (!enc || !image || !out || !length || !key_frame) return EXTERIA_E_ARG;
    if (image->width != enc->width || image->height != enc->height) return EXTERIA_E_ARG;
    for (i = 0; i < 3; ++i) {
        int need = i == 0 ? enc->width : enc->width / 2;
        if (!image->plane[i] || image->stride[i] < need) return EXTERIA_E_ARG;
    }
    /* the picture borrows the caller's planes, so it is described by hand: vpx_img_wrap allocates when it is given no storage */
    memset(&wrapper, 0, sizeof(wrapper));
    wrapper.fmt = VPX_IMG_FMT_I420;
    wrapper.bit_depth = 8;
    wrapper.w = wrapper.d_w = (unsigned)enc->width;
    wrapper.h = wrapper.d_h = (unsigned)enc->height;
    wrapper.x_chroma_shift = 1;
    wrapper.y_chroma_shift = 1;
    wrapper.bps = 12;
    for (i = 0; i < 3; ++i) {
        /* libvpx reads the planes and never writes them */
        wrapper.planes[i] = (unsigned char *)(uintptr_t)image->plane[i];
        wrapper.stride[i] = image->stride[i];
    }
    if (vpx_codec_encode(&enc->context, &wrapper, pts, 1, (enc->need_key || force_key) ? VPX_EFLAG_FORCE_KF : 0, VPX_DL_REALTIME) !=
        VPX_CODEC_OK) {
        return EXTERIA_E_IO;
    }
    enc->need_key = 0;
    while ((packet = vpx_codec_get_cx_data(&enc->context, &iter)) != NULL) {
        if (packet->kind != VPX_CODEC_CX_FRAME_PKT) continue;
        if (packet->data.frame.sz > capacity) {
            /* the receiver never saw this frame, so the next one must stand alone */
            enc->need_key = 1;
            status = EXTERIA_E_LIMIT;
            continue;
        }
        memcpy(out, packet->data.frame.buf, packet->data.frame.sz);
        *length = packet->data.frame.sz;
        *key_frame = (packet->data.frame.flags & VPX_FRAME_IS_KEY) ? 1 : 0;
    }
    return status;
}

exteria_status exteria_vp8_encoder_set_bitrate(exteria_vp8_encoder *enc, int bitrate_kbps) {
    if (!enc || bitrate_kbps < 16 || bitrate_kbps > 4000) return EXTERIA_E_ARG;
    enc->config.rc_target_bitrate = (unsigned)bitrate_kbps;
    return vpx_codec_enc_config_set(&enc->context, &enc->config) == VPX_CODEC_OK ? EXTERIA_OK : EXTERIA_E_IO;
}

void exteria_vp8_encoder_close(exteria_vp8_encoder *enc) {
    if (!enc) return;
    vpx_codec_destroy(&enc->context);
    free(enc);
}

exteria_status exteria_vp8_decoder_open(exteria_vp8_decoder **out, size_t max_pixels) {
    exteria_vp8_decoder *dec;
    vpx_codec_dec_cfg_t config;
    vpx_codec_iface_t *iface;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (max_pixels < 1 || max_pixels > (size_t)EXTERIA_VP8_MAX_SIDE * EXTERIA_VP8_MAX_SIDE) return EXTERIA_E_ARG;
    iface = vpx_codec_vp8_dx();
    if (!iface) return EXTERIA_E_UNSUPPORTED;
    dec = (exteria_vp8_decoder *)calloc(1, sizeof(*dec));
    if (!dec) return EXTERIA_E_NOMEM;
    memset(&config, 0, sizeof(config));
    config.threads = 1;
    if (vpx_codec_dec_init(&dec->context, iface, &config, 0) != VPX_CODEC_OK) {
        free(dec);
        return EXTERIA_E_UNSUPPORTED;
    }
    dec->max_pixels = max_pixels;
    *out = dec;
    return EXTERIA_OK;
}

/* a key frame announces its size in the 14 bit fields after the start code; libvpx allocates for that size before
   it checks anything else, so the area is checked first */
static exteria_status check_key_frame(const exteria_vp8_decoder *dec, const uint8_t *data, size_t length) {
    unsigned width, height;
    if (length < KEY_FRAME_HEADER_LEN || data[3] != 0x9D || data[4] != 0x01 || data[5] != 0x2A) return EXTERIA_E_MALFORMED;
    width = (unsigned)(data[6] | (data[7] << 8)) & 0x3FFFu;
    height = (unsigned)(data[8] | (data[9] << 8)) & 0x3FFFu;
    if (width == 0 || height == 0) return EXTERIA_E_MALFORMED;
    if (width > EXTERIA_VP8_MAX_SIDE || height > EXTERIA_VP8_MAX_SIDE || (size_t)width * height > dec->max_pixels) return EXTERIA_E_LIMIT;
    return EXTERIA_OK;
}

exteria_status exteria_vp8_decoder_decode(exteria_vp8_decoder *dec, const uint8_t *data, size_t length, exteria_i420 *image) {
    const vpx_image_t *picture;
    vpx_codec_iter_t iter = NULL;
    exteria_status status;
    int i;
    if (image) memset(image, 0, sizeof(*image));
    if (!dec || !data || !image || length == 0) return EXTERIA_E_ARG;
    if (length > DECODER_MAX_FRAME) return EXTERIA_E_LIMIT;
    if (!(data[0] & 1)) {
        status = check_key_frame(dec, data, length);
        if (status != EXTERIA_OK) return status;
        dec->has_key = 1;
    } else if (!dec->has_key) {
        return EXTERIA_E_STATE;
    }
    if (vpx_codec_decode(&dec->context, data, (unsigned)length, NULL, 0) != VPX_CODEC_OK) return EXTERIA_E_MALFORMED;
    picture = vpx_codec_get_frame(&dec->context, &iter);
    if (!picture) return EXTERIA_OK;
    if (picture->fmt != VPX_IMG_FMT_I420 || picture->d_w == 0 || picture->d_h == 0 || (size_t)picture->d_w * picture->d_h > dec->max_pixels) {
        return EXTERIA_E_LIMIT;
    }
    for (i = 0; i < 3; ++i) {
        image->plane[i] = picture->planes[i];
        image->stride[i] = picture->stride[i];
    }
    image->width = (int)picture->d_w;
    image->height = (int)picture->d_h;
    return EXTERIA_OK;
}

void exteria_vp8_decoder_close(exteria_vp8_decoder *dec) {
    if (!dec) return;
    vpx_codec_destroy(&dec->context);
    free(dec);
}
