#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_vp8.h"
#include "exteria_vp8_rtp.h"

static int failures;
static int checks;

#define CHECK(cond) do { \
    ++checks; \
    if (!(cond)) { ++failures; fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond); } \
} while (0)
#define CHECK_EQ(a, b) do { \
    long long va_ = (long long)(a), vb_ = (long long)(b); \
    ++checks; \
    if (va_ != vb_) { ++failures; fprintf(stderr, "%s:%d: %s == %lld, expected %lld\n", __FILE__, __LINE__, #a, va_, vb_); } \
} while (0)

#define W 320
#define H 240

static uint8_t y_plane[W * H], u_plane[W * H / 4], v_plane[W * H / 4];

/* a diagonal gradient with a bright block that moves, so inter frames have real motion to code */
static void paint(int frame, exteria_i420 *image) {
    int x, y;
    for (y = 0; y < H; ++y)
        for (x = 0; x < W; ++x) y_plane[y * W + x] = (uint8_t)((x + y) / 3 + 20);
    for (y = 40; y < 100; ++y)
        for (x = 0; x < 60; ++x) y_plane[y * W + ((x + frame * 4) % (W - 60))] = 230;
    for (y = 0; y < H / 2; ++y)
        for (x = 0; x < W / 2; ++x) {
            u_plane[y * (W / 2) + x] = (uint8_t)(100 + x / 4);
            v_plane[y * (W / 2) + x] = (uint8_t)(140 - y / 4);
        }
    image->plane[0] = y_plane;
    image->plane[1] = u_plane;
    image->plane[2] = v_plane;
    image->stride[0] = W;
    image->stride[1] = W / 2;
    image->stride[2] = W / 2;
    image->width = W;
    image->height = H;
}

static double luma_psnr(const exteria_i420 *a, const exteria_i420 *b) {
    double sum = 0;
    int x, y;
    for (y = 0; y < H; ++y)
        for (x = 0; x < W; ++x) {
            double d = (double)a->plane[0][y * a->stride[0] + x] - (double)b->plane[0][y * b->stride[0] + x];
            sum += d * d;
        }
    sum /= (double)(W * H);
    return sum == 0 ? 99 : 10 * log10(255.0 * 255.0 / sum);
}

static uint8_t frame_buffer[EXTERIA_VP8_MAX_FRAME];
static uint8_t depack_storage[EXTERIA_VP8_MAX_FRAME];

/* encoder to packets to depacketizer to decoder, the way a call carries a picture */
static void round_trip(void) {
    exteria_vp8_encoder *enc = NULL;
    exteria_vp8_decoder *dec = NULL;
    exteria_vp8_depacketizer depack;
    exteria_i420 source, shown;
    int frame, key_frames = 0, decoded = 0;
    double worst = 99;
    uint16_t sequence = 60000;
    CHECK_EQ(exteria_vp8_encoder_open(&enc, W, H, 15, 400), EXTERIA_OK);
    CHECK_EQ(exteria_vp8_decoder_open(&dec, W * H), EXTERIA_OK);
    CHECK_EQ(exteria_vp8_depacketizer_init(&depack, depack_storage, sizeof(depack_storage)), EXTERIA_OK);
    for (frame = 0; frame < 45; ++frame) {
        size_t length = 0;
        int key = 0;
        exteria_vp8_packetizer packetizer;
        uint8_t payload[EXTERIA_VP8_MAX_PAYLOAD];
        size_t payload_len;
        int marker;
        exteria_vp8_frame_info info;
        paint(frame, &source);
        /* the 30th picture asks for a key frame, as a picture loss indication would */
        CHECK_EQ(exteria_vp8_encoder_encode(enc, &source, frame, frame == 30, frame_buffer, sizeof(frame_buffer), &length, &key), EXTERIA_OK);
        CHECK(length > 0);
        if (frame == 0 || frame == 30) CHECK_EQ(key, 1);
        else CHECK_EQ(key, 0);
        key_frames += key;
        CHECK_EQ(exteria_vp8_packetizer_init(&packetizer, frame_buffer, length, 1200, (uint16_t)frame, !key), EXTERIA_OK);
        memset(&info, 0, sizeof(info));
        while (exteria_vp8_packetizer_next(&packetizer, payload, sizeof(payload), &payload_len, &marker) == EXTERIA_OK) {
            CHECK_EQ(exteria_vp8_depacketizer_push(&depack, sequence++, (uint32_t)frame * 6000u, marker, payload, payload_len, &info), EXTERIA_OK);
        }
        CHECK_EQ(info.ready, 1);
        CHECK_EQ(info.key_frame, key);
        CHECK_EQ(info.length, length);
        CHECK(memcmp(depack_storage, frame_buffer, length) == 0);
        CHECK_EQ(exteria_vp8_decoder_decode(dec, depack_storage, info.length, &shown), EXTERIA_OK);
        CHECK_EQ(shown.width, W);
        CHECK_EQ(shown.height, H);
        if (shown.width == W) {
            double psnr = luma_psnr(&source, &shown);
            if (psnr < worst) worst = psnr;
            ++decoded;
        }
    }
    CHECK_EQ(key_frames, 2);
    CHECK_EQ(decoded, 45);
    CHECK_EQ(depack.dropped_frames, 0);
    CHECK(worst > 28.0);
    printf("worst luma psnr %.1f dB\n", worst);
    CHECK_EQ(exteria_vp8_encoder_set_bitrate(enc, 200), EXTERIA_OK);
    CHECK_EQ(exteria_vp8_encoder_set_bitrate(enc, 8), EXTERIA_E_ARG);
    exteria_vp8_encoder_close(enc);
    exteria_vp8_decoder_close(dec);
}

static void encoder_limits(void) {
    exteria_vp8_encoder *enc = NULL;
    exteria_i420 source;
    uint8_t tiny[64];
    size_t length = 0;
    int key = 0;
    CHECK_EQ(exteria_vp8_encoder_open(NULL, W, H, 15, 400), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_encoder_open(&enc, 321, H, 15, 400), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_encoder_open(&enc, 8, H, 15, 400), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_encoder_open(&enc, 1282, H, 15, 400), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_encoder_open(&enc, W, H, 0, 400), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_encoder_open(&enc, W, H, 61, 400), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_encoder_open(&enc, W, H, 15, 15), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_encoder_open(&enc, W, H, 15, 4001), EXTERIA_E_ARG);
    CHECK(enc == NULL);
    CHECK_EQ(exteria_vp8_encoder_open(&enc, W, H, 15, 400), EXTERIA_OK);
    paint(0, &source);
    /* a frame that does not fit is reported, and the picture after it stands alone */
    CHECK_EQ(exteria_vp8_encoder_encode(enc, &source, 0, 0, tiny, sizeof(tiny), &length, &key), EXTERIA_E_LIMIT);
    CHECK_EQ(length, 0);
    paint(1, &source);
    CHECK_EQ(exteria_vp8_encoder_encode(enc, &source, 1, 0, frame_buffer, sizeof(frame_buffer), &length, &key), EXTERIA_OK);
    CHECK_EQ(key, 1);
    /* a picture of another size, a missing plane, a stride that is too short */
    source.width = W - 2;
    CHECK_EQ(exteria_vp8_encoder_encode(enc, &source, 2, 0, frame_buffer, sizeof(frame_buffer), &length, &key), EXTERIA_E_ARG);
    source.width = W;
    source.plane[1] = NULL;
    CHECK_EQ(exteria_vp8_encoder_encode(enc, &source, 2, 0, frame_buffer, sizeof(frame_buffer), &length, &key), EXTERIA_E_ARG);
    paint(2, &source);
    source.stride[2] = 10;
    CHECK_EQ(exteria_vp8_encoder_encode(enc, &source, 2, 0, frame_buffer, sizeof(frame_buffer), &length, &key), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_encoder_encode(NULL, &source, 2, 0, frame_buffer, sizeof(frame_buffer), &length, &key), EXTERIA_E_ARG);
    exteria_vp8_encoder_close(enc);
    exteria_vp8_encoder_close(NULL);
}

static void decoder_refuses_bad_frames(void) {
    exteria_vp8_decoder *dec = NULL;
    exteria_i420 shown;
    uint8_t frame[64];
    CHECK_EQ(exteria_vp8_decoder_open(NULL, 100), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_decoder_open(&dec, 0), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_decoder_open(&dec, (size_t)EXTERIA_VP8_MAX_SIDE * EXTERIA_VP8_MAX_SIDE + 1), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_decoder_open(&dec, W * H), EXTERIA_OK);

    /* an inter frame before any key frame */
    memset(frame, 0, sizeof(frame));
    frame[0] = 0x31;
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 32, &shown), EXTERIA_E_STATE);
    CHECK(shown.plane[0] == NULL);
    /* key frames: no start code, too short, a zero side, a side over the limit, an area over the cap, an area of 4000 by 4000 */
    memset(frame, 0, sizeof(frame));
    frame[0] = 0x10;
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 32, &shown), EXTERIA_E_MALFORMED);
    frame[3] = 0x9D; frame[4] = 0x01; frame[5] = 0x2A;
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 9, &shown), EXTERIA_E_MALFORMED);
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 32, &shown), EXTERIA_E_MALFORMED);
    frame[6] = 64; frame[7] = 0; frame[8] = 0; frame[9] = 0;
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 32, &shown), EXTERIA_E_MALFORMED);
    frame[6] = (uint8_t)(1300 & 0xFF); frame[7] = (uint8_t)(1300 >> 8); frame[8] = 64; frame[9] = 0;
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 32, &shown), EXTERIA_E_LIMIT);
    frame[6] = (uint8_t)(400 & 0xFF); frame[7] = (uint8_t)(400 >> 8); frame[8] = (uint8_t)(300 & 0xFF); frame[9] = (uint8_t)(300 >> 8);
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 32, &shown), EXTERIA_E_LIMIT);
    frame[6] = (uint8_t)(4000 & 0xFF); frame[7] = (uint8_t)(4000 >> 8); frame[8] = (uint8_t)(4000 & 0xFF); frame[9] = (uint8_t)(4000 >> 8);
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 32, &shown), EXTERIA_E_LIMIT);
    /* the upscaling bits in the top of each field do not count toward the size */
    frame[6] = 64; frame[7] = 0xC0; frame[8] = 64; frame[9] = 0xC0;
    CHECK(exteria_vp8_decoder_decode(dec, frame, 32, &shown) != EXTERIA_E_LIMIT);

    CHECK_EQ(exteria_vp8_decoder_decode(dec, NULL, 32, &shown), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 0, &shown), EXTERIA_E_ARG);
    CHECK_EQ(exteria_vp8_decoder_decode(dec, frame, 600000, &shown), EXTERIA_E_LIMIT);
    CHECK_EQ(exteria_vp8_decoder_decode(NULL, frame, 32, &shown), EXTERIA_E_ARG);
    exteria_vp8_decoder_close(dec);
    exteria_vp8_decoder_close(NULL);
}

/* damaged real frames must come back as an error or a picture, never as a crash; the address sanitizer watches the rest */
static void decoder_survives_damage(void) {
    exteria_vp8_encoder *enc = NULL;
    exteria_vp8_decoder *dec = NULL;
    exteria_i420 source, shown;
    size_t length = 0, cut, i;
    int key = 0;
    unsigned seed = 12345;
    uint8_t key_copy[EXTERIA_VP8_MAX_FRAME];
    CHECK_EQ(exteria_vp8_encoder_open(&enc, W, H, 15, 400), EXTERIA_OK);
    paint(0, &source);
    CHECK_EQ(exteria_vp8_encoder_encode(enc, &source, 0, 1, frame_buffer, sizeof(frame_buffer), &length, &key), EXTERIA_OK);
    memcpy(key_copy, frame_buffer, length);
    for (cut = 10; cut < length; cut += length / 40 + 1) {
        CHECK_EQ(exteria_vp8_decoder_open(&dec, W * H), EXTERIA_OK);
        (void)exteria_vp8_decoder_decode(dec, key_copy, cut, &shown);
        exteria_vp8_decoder_close(dec);
    }
    for (i = 0; i < 200; ++i) {
        size_t at;
        memcpy(frame_buffer, key_copy, length);
        seed = seed * 1103515245u + 12345u;
        /* flips after the 10 byte header, so the size check still passes and libvpx sees the damage */
        at = 10 + (seed >> 8) % (length - 10);
        frame_buffer[at] ^= (uint8_t)(1u << (seed % 8));
        CHECK_EQ(exteria_vp8_decoder_open(&dec, W * H), EXTERIA_OK);
        (void)exteria_vp8_decoder_decode(dec, frame_buffer, length, &shown);
        exteria_vp8_decoder_close(dec);
    }
    exteria_vp8_encoder_close(enc);
}

int main(void) {
    round_trip();
    encoder_limits();
    decoder_refuses_bad_frames();
    decoder_survives_damage();
    if (failures) {
        fprintf(stderr, "test_vp8: %d of %d checks failed\n", failures, checks);
        return 1;
    }
    printf("test_vp8: %d checks passed\n", checks);
    return 0;
}
