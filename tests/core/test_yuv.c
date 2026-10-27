#include "exteria_yuv.h"
#include "test_util.h"

/* the camera frames below are small enough to write out by hand: 4 wide and 2 high, each luma value its own number */
static void make_target(exteria_yuv_target *t, int w, int h, uint8_t *y, uint8_t *u, uint8_t *v) {
    t->plane[0] = y;
    t->plane[1] = u;
    t->plane[2] = v;
    t->stride[0] = w;
    t->stride[1] = w / 2;
    t->stride[2] = w / 2;
    t->width = w;
    t->height = h;
    memset(y, 0xEE, (size_t)w * (size_t)h);
    memset(u, 0xEE, (size_t)w * (size_t)h / 4);
    memset(v, 0xEE, (size_t)w * (size_t)h / 4);
}

static void identity_and_turns(void) {
    /* luma 10..17 in two rows of four, chroma U 100,101 and V 200,201 in one row of two pairs */
    static const uint8_t luma[8] = {10, 11, 12, 13, 14, 15, 16, 17};
    static const uint8_t chroma[4] = {100, 200, 101, 201};
    exteria_yuv_target t;
    uint8_t y[8], u[2], v[2];
    make_target(&t, 4, 2, y, u, v);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 4, chroma, 4, 4, 2, 0, 0, &t), EXTERIA_OK);
    CHECK_MEM(y, luma, 8);
    CHECK(u[0] == 100 && u[1] == 101);
    CHECK(v[0] == 200 && v[1] == 201);
    /* mirrored: each row is reversed, and so is the chroma */
    make_target(&t, 4, 2, y, u, v);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 4, chroma, 4, 4, 2, 0, 1, &t), EXTERIA_OK);
    CHECK_MEM(y, "\x0D\x0C\x0B\x0A\x11\x10\x0F\x0E", 8);
    CHECK(u[0] == 101 && u[1] == 100);
    /* 180 degrees: everything reversed */
    make_target(&t, 4, 2, y, u, v);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 4, chroma, 4, 4, 2, 180, 0, &t), EXTERIA_OK);
    CHECK_MEM(y, "\x11\x10\x0F\x0E\x0D\x0C\x0B\x0A", 8);
    CHECK(u[0] == 101 && u[1] == 100);
    /* 90 degrees clockwise: the picture becomes 2 wide and 4 high, the left column read from the bottom up becomes the top row */
    {
        uint8_t y2[8], u2[2], v2[2];
        make_target(&t, 2, 4, y2, u2, v2);
        CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 4, chroma, 4, 4, 2, 90, 0, &t), EXTERIA_OK);
        CHECK_MEM(y2, "\x0E\x0A\x0F\x0B\x10\x0C\x11\x0D", 8);
        make_target(&t, 2, 4, y2, u2, v2);
        CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 4, chroma, 4, 4, 2, 270, 0, &t), EXTERIA_OK);
        CHECK_MEM(y2, "\x0D\x11\x0C\x10\x0B\x0F\x0A\x0E", 8);
    }
}

static void camera_orientation(void) {
    static const int fallback[] = {90, 270, 180, 0};
    int turn = -1;
    for (int i = 0; i < 4; ++i) {
        CHECK_EQ_INT(exteria_yuv_capture_rotation((exteria_capture_orientation)i, 0, &turn), EXTERIA_OK);
        CHECK_EQ_INT(turn, fallback[i]);
        CHECK_EQ_INT(exteria_yuv_capture_rotation((exteria_capture_orientation)i, 1, &turn), EXTERIA_OK);
        CHECK_EQ_INT(turn, 0);
    }
    CHECK_EQ_INT(exteria_yuv_capture_rotation((exteria_capture_orientation)4, 0, &turn), EXTERIA_E_ARG);
    CHECK_EQ_INT(turn, 0);
    CHECK_EQ_INT(exteria_yuv_capture_rotation(EXTERIA_CAPTURE_PORTRAIT, 0, NULL), EXTERIA_E_ARG);
}

static void scaling(void) {
    /* a 4 by 4 frame in two columns of equal blocks scales down to 2 by 2 with the block values, and a gradient halves as an average */
    uint8_t luma[16], chroma[16], y[4], u[1], v[1];
    exteria_yuv_target t;
    int i;
    for (i = 0; i < 16; ++i) luma[i] = (uint8_t)((i % 4) < 2 ? 40 : 200);
    for (i = 0; i < 16; i += 2) {
        chroma[i] = 90;
        chroma[i + 1] = 160;
    }
    make_target(&t, 2, 2, y, u, v);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 4, chroma, 4, 4, 4, 0, 0, &t), EXTERIA_OK);
    /* the centre of each output pixel sits between four source samples, two of each block at the edges: the blend is exact at the block middles */
    CHECK(y[0] >= 40 && y[0] <= 120);
    CHECK(y[1] >= 120 && y[1] <= 200);
    CHECK(y[0] < y[1] && y[2] == y[0] && y[3] == y[1]);
    CHECK(u[0] == 90 && v[0] == 160);
    /* upscaling keeps the ends and stays between them */
    {
        uint8_t big_y[16 * 16], big_u[64], big_v[64], src_y[4] = {0, 255, 0, 255}, src_c[2] = {128, 128};
        exteria_yuv_target b;
        make_target(&b, 16, 16, big_y, big_u, big_v);
        CHECK_EQ_INT(exteria_yuv_nv12_to_i420(src_y, 2, src_c, 2, 2, 2, 0, 0, &b), EXTERIA_OK);
        CHECK_EQ_INT(big_y[0], 0);
        CHECK_EQ_INT(big_y[15], 255);
        for (i = 1; i < 16; ++i) CHECK(big_y[i] >= big_y[i - 1]);
        CHECK_EQ_INT(big_u[0], 128);
    }
}

static void bounds(void) {
    uint8_t luma[16 * 16] = {0}, chroma[16 * 16] = {0}, y[16 * 16], u[64], v[64];
    exteria_yuv_target t;
    make_target(&t, 8, 8, y, u, v);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 16, chroma, 16, 16, 16, 45, 0, &t), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 16, chroma, 16, 15, 16, 0, 0, &t), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 16, chroma, 16, 0, 16, 0, 0, &t), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 16, chroma, 16, 4098, 16, 0, 0, &t), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 8, chroma, 16, 16, 16, 0, 0, &t), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 16, chroma, 8, 16, 16, 0, 0, &t), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(NULL, 16, chroma, 16, 16, 16, 0, 0, &t), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 16, chroma, 16, 16, 16, 0, 0, NULL), EXTERIA_E_ARG);
    t.width = 7;
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 16, chroma, 16, 16, 16, 0, 0, &t), EXTERIA_E_ARG);
    t.width = 8;
    t.stride[1] = 3;
    CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 16, chroma, 16, 16, 16, 0, 0, &t), EXTERIA_E_ARG);
    /* the output walks past nothing: every rotation of a non square frame into every target shape fills exactly the target (the guard bytes stay) */
    {
        static const int rotations[4] = {0, 90, 180, 270};
        int r, mirror;
        for (r = 0; r < 4; ++r) {
            for (mirror = 0; mirror < 2; ++mirror) {
                uint8_t guard_y[6 * 4 + 16], guard_u[3 * 2 + 16], guard_v[3 * 2 + 16];
                exteria_yuv_target g;
                memset(guard_y, 0x5A, sizeof(guard_y));
                memset(guard_u, 0x5A, sizeof(guard_u));
                memset(guard_v, 0x5A, sizeof(guard_v));
                g.plane[0] = guard_y;
                g.plane[1] = guard_u;
                g.plane[2] = guard_v;
                g.stride[0] = 6;
                g.stride[1] = 3;
                g.stride[2] = 3;
                g.width = 6;
                g.height = 4;
                CHECK_EQ_INT(exteria_yuv_nv12_to_i420(luma, 16, chroma, 16, 16, 8, rotations[r], mirror, &g), EXTERIA_OK);
                CHECK(memcmp(guard_y + 24, "\x5A\x5A\x5A\x5A", 4) == 0);
                CHECK(memcmp(guard_u + 6, "\x5A\x5A\x5A\x5A", 4) == 0);
                CHECK(memcmp(guard_v + 6, "\x5A\x5A\x5A\x5A", 4) == 0);
            }
        }
    }
}

static void to_bgra(void) {
    /* video range: black, white, mid grey and the primaries */
    uint8_t y[4] = {16, 235, 126, 81}, u[1] = {128}, v[1] = {128}, out[4 * 4 * 2];
    exteria_i420 img;
    img.plane[0] = y;
    img.plane[1] = u;
    img.plane[2] = v;
    img.stride[0] = 2;
    img.stride[1] = 1;
    img.stride[2] = 1;
    img.width = 2;
    img.height = 2;
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, out, 8, 2, 2), EXTERIA_OK);
    CHECK(out[0] == 0 && out[1] == 0 && out[2] == 0 && out[3] == 255);
    CHECK(out[4] == 255 && out[5] == 255 && out[6] == 255 && out[7] == 255);
    CHECK(out[8] >= 126 && out[8] <= 129 && out[8] == out[9] && out[9] == out[10]);
    /* red: Y 81, U 90, V 240 */
    y[0] = 81;
    u[0] = 90;
    v[0] = 240;
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, out, 8, 1, 1), EXTERIA_OK);
    CHECK(out[2] >= 250 && out[1] <= 6 && out[0] <= 6);
    /* blue: Y 41, U 240, V 110 */
    y[0] = 41;
    u[0] = 240;
    v[0] = 110;
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, out, 8, 1, 1), EXTERIA_OK);
    CHECK(out[0] >= 250 && out[2] <= 8);
    /* green: Y 145, U 54, V 34 */
    y[0] = 145;
    u[0] = 54;
    v[0] = 34;
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, out, 8, 1, 1), EXTERIA_OK);
    CHECK(out[1] >= 250 && out[0] <= 8 && out[2] <= 8);
    /* scaling by nearest: 2 by 2 into 4 by 4 repeats each pixel in a block */
    y[0] = 16;
    u[0] = 128;
    v[0] = 128;
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, out, 8, 4, 4), EXTERIA_E_LIMIT);
    {
        uint8_t big[4 * 4 * 4];
        CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, big, 16, 4, 4), EXTERIA_OK);
        CHECK(big[0] == 0 && big[4] == 0 && big[16] == 0);
        CHECK(big[8] == 255 && big[12] == 255);
    }
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(NULL, out, 8, 2, 2), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, NULL, 8, 2, 2), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, out, 8, 0, 2), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, out, 8, 2, 4097), EXTERIA_E_ARG);
    img.stride[0] = 1;
    CHECK_EQ_INT(exteria_yuv_i420_to_bgra(&img, out, 8, 2, 2), EXTERIA_E_ARG);
}

int main(void) {
    identity_and_turns();
    camera_orientation();
    scaling();
    bounds();
    to_bgra();
    return test_finish("test_yuv");
}
