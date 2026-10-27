#include "exteria_call_screen.h"

#include <math.h>
#include <string.h>

#define PILL_HEIGHT 36.0
#define PILL_GLYPH 25.0
#define PILL_GLYPH_GAP 6.0
#define PILL_PADDING 14.0
#define EMOJI_COUNT 4.0
#define CARD_HEIGHT 132.0
#define CARD_MAX_WIDTH 304.0
#define TITLE_HEIGHT 34.0
#define STATUS_HEIGHT 20.0
#define TEXT_GAP 6.0
#define AVATAR_TITLE_GAP 20.0
#define CAPTION_HEIGHT 16.0
#define CAPTION_GAP 8.0
#define BOTTOM_MARGIN 28.0
#define CONTROL_DIAMETER 52.0
#define ANSWER_DIAMETER 64.0
#define SLOT_MAX 104.0
#define AVATAR_MIN 72.0
#define AVATAR_PHONE_MAX 135.0
#define AVATAR_WIDE_MAX 180.0
#define SIDE_MARGIN 16.0
#define EMOJI_TOP 17.0
#define EMOJI_RESERVE 79.0
#define WIDE_RESERVE 8.0
#define BELOW_AVATAR_GAP 24.0
#define PREVIEW_LONG 120.0
#define PREVIEW_SHORT 90.0
#define PREVIEW_GAP 12.0
#define VIDEO_TITLE_GAP 12.0

static exteria_rect rect(double x, double y, double width, double height) {
    exteria_rect r;
    r.x = x;
    r.y = y;
    r.width = width;
    r.height = height;
    return r;
}

static double clamp(double value, double low, double high) {
    if (value < low) return low;
    return value > high ? high : value;
}

static int finite_metrics(const exteria_call_screen_metrics *m) {
    return isfinite(m->width) && isfinite(m->height) && isfinite(m->top_inset) && isfinite(m->bottom_inset) &&
           m->width > 0 && m->height > 0 && m->top_inset >= 0 && m->bottom_inset >= 0;
}

exteria_status exteria_call_screen_layout_compute(const exteria_call_screen_metrics *metrics,
                                                  exteria_call_screen_layout *out) {
    double diameter, slot, circle_y, free_height, reserve, avatar_d, avatar_y, pill_width, card_width;
    int wide, count, i;

    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!metrics || !finite_metrics(metrics)) return EXTERIA_E_ARG;
    count = metrics->incoming ? 2 : metrics->button_count;
    if (count < 1 || count > EXTERIA_CALL_SCREEN_MAX_BUTTONS) return EXTERIA_E_ARG;

    wide = metrics->width > metrics->height;
    out->title_size = 28;
    out->status_size = 15;
    out->caption_size = 11;

    diameter = metrics->incoming ? ANSWER_DIAMETER : CONTROL_DIAMETER;
    circle_y = metrics->height - metrics->bottom_inset - BOTTOM_MARGIN - CAPTION_HEIGHT - CAPTION_GAP - diameter;
    out->button_count = count;
    if (metrics->incoming) {
        /* the two answer buttons sit toward the sides, as the swipe pair of the reference does */
        double centers[2];
        centers[0] = metrics->width * 0.25;
        centers[1] = metrics->width * 0.75;
        slot = metrics->width * 0.5;
        if (slot > SLOT_MAX * 2) slot = SLOT_MAX * 2;
        for (i = 0; i < 2; ++i) {
            out->buttons[i] = rect(centers[i] - diameter / 2, circle_y, diameter, diameter);
            out->captions[i] = rect(centers[i] - slot / 2, circle_y + diameter + CAPTION_GAP, slot, CAPTION_HEIGHT);
        }
    } else {
        double start;
        slot = metrics->width / count;
        if (slot > SLOT_MAX) slot = SLOT_MAX;
        start = (metrics->width - slot * count) / 2;
        for (i = 0; i < count; ++i) {
            double center = start + slot * i + slot / 2;
            out->buttons[i] = rect(center - diameter / 2, circle_y, diameter, diameter);
            out->captions[i] = rect(center - slot / 2, circle_y + diameter + CAPTION_GAP, slot, CAPTION_HEIGHT);
        }
    }

    /* the avatar takes what is left between the emoji strip and the name, up to a fixed size */
    reserve = wide ? WIDE_RESERVE : EMOJI_RESERVE;
    free_height = circle_y - metrics->top_inset - reserve - (TITLE_HEIGHT + TEXT_GAP + STATUS_HEIGHT + AVATAR_TITLE_GAP) - BELOW_AVATAR_GAP;
    avatar_d = clamp(free_height, AVATAR_MIN, metrics->width >= 600 ? AVATAR_WIDE_MAX : AVATAR_PHONE_MAX);
    if (avatar_d > metrics->width - 2 * SIDE_MARGIN) avatar_d = metrics->width - 2 * SIDE_MARGIN;
    avatar_y = metrics->top_inset + reserve;
    if (free_height > avatar_d) avatar_y += (free_height - avatar_d) / 2;
    out->avatar = rect((metrics->width - avatar_d) / 2, avatar_y, avatar_d, avatar_d);
    out->title = rect(SIDE_MARGIN, avatar_y + avatar_d + AVATAR_TITLE_GAP, metrics->width - 2 * SIDE_MARGIN, TITLE_HEIGHT);
    out->status = rect(SIDE_MARGIN, out->title.y + TITLE_HEIGHT + TEXT_GAP, metrics->width - 2 * SIDE_MARGIN, STATUS_HEIGHT);

    pill_width = EMOJI_COUNT * PILL_GLYPH + (EMOJI_COUNT - 1) * PILL_GLYPH_GAP + 2 * PILL_PADDING;
    if (wide) out->emoji = rect(metrics->width - pill_width - SIDE_MARGIN, metrics->top_inset + WIDE_RESERVE, pill_width, PILL_HEIGHT);
    else out->emoji = rect((metrics->width - pill_width) / 2, metrics->top_inset + EMOJI_TOP, pill_width, PILL_HEIGHT);
    card_width = metrics->width - 2 * SIDE_MARGIN;
    if (card_width > CARD_MAX_WIDTH) card_width = CARD_MAX_WIDTH;
    if (wide) out->card = rect(metrics->width - card_width - SIDE_MARGIN, out->emoji.y + PILL_HEIGHT + 10, card_width, CARD_HEIGHT);
    else out->card = rect((metrics->width - card_width) / 2, out->emoji.y + PILL_HEIGHT + 10, card_width, CARD_HEIGHT);
    if (metrics->video) {
        /* over a picture the name sits at the top: under the emoji pill on a tall screen, left of it on a wide one */
        double top = wide ? metrics->top_inset + WIDE_RESERVE : out->emoji.y + PILL_HEIGHT + VIDEO_TITLE_GAP;
        double width = wide ? out->emoji.x - 2 * SIDE_MARGIN : metrics->width - 2 * SIDE_MARGIN;
        if (width < 0) width = 0;
        out->title = rect(SIDE_MARGIN, top, width, TITLE_HEIGHT);
        out->status = rect(SIDE_MARGIN, top + TITLE_HEIGHT + TEXT_GAP, width, STATUS_HEIGHT);
    }
    {
        double preview_w = wide ? PREVIEW_LONG : PREVIEW_SHORT, preview_h = wide ? PREVIEW_SHORT : PREVIEW_LONG;
        out->preview = rect(metrics->width - SIDE_MARGIN - preview_w, circle_y - PREVIEW_GAP - preview_h, preview_w, preview_h);
    }
    return EXTERIA_OK;
}

/* the reference palettes: mesh backgrounds of the android call screen, light set for the modern theme */
static const uint32_t moods[EXTERIA_CALL_MOOD_COUNT][2][4] = {
    {{0xB456D8, 0x8148EC, 0x20A4D7, 0x3F8BEA}, {0xA736D0, 0x6A2BDD, 0x0F95C9, 0x287AE1}},
    {{0x4576E9, 0x3B7AF1, 0x08B0A3, 0x17AAE4}, {0x2D60D6, 0x2C6ADF, 0x009595, 0x0291C9}},
    {{0xE86958, 0xE7618F, 0xDB904C, 0xDE7238}, {0xE23F29, 0xE6306F, 0xC77616, 0xD75A16}}
};

exteria_status exteria_call_mood_colors(exteria_call_mood mood, int dark, uint32_t out[4]) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, 4 * sizeof(out[0]));
    if ((int)mood < 0 || mood >= EXTERIA_CALL_MOOD_COUNT) return EXTERIA_E_ARG;
    memcpy(out, moods[mood][dark ? 1 : 0], 4 * sizeof(out[0]));
    return EXTERIA_OK;
}

exteria_status exteria_call_mesh_fill(uint8_t *rgba, size_t capacity, int width, int height, const uint32_t colors[4]) {
    int x, y, c;
    if (!rgba || !colors) return EXTERIA_E_ARG;
    if (width < 2 || height < 2 || width > EXTERIA_CALL_MESH_MAX_SIDE || height > EXTERIA_CALL_MESH_MAX_SIDE) return EXTERIA_E_ARG;
    if (capacity < (size_t)width * (size_t)height * 4) return EXTERIA_E_LIMIT;
    for (y = 0; y < height; ++y) {
        double v = (double)y / (double)(height - 1);
        for (x = 0; x < width; ++x) {
            double u = (double)x / (double)(width - 1);
            uint8_t *pixel = rgba + ((size_t)y * (size_t)width + (size_t)x) * 4;
            for (c = 0; c < 3; ++c) {
                int shift = 16 - 8 * c;
                double tl = (double)((colors[0] >> shift) & 0xFF);
                double tr = (double)((colors[1] >> shift) & 0xFF);
                double br = (double)((colors[2] >> shift) & 0xFF);
                double bl = (double)((colors[3] >> shift) & 0xFF);
                double top = tl + (tr - tl) * u;
                double bottom = bl + (br - bl) * u;
                pixel[c] = (uint8_t)(top + (bottom - top) * v + 0.5);
            }
            pixel[3] = 0xFF;
        }
    }
    return EXTERIA_OK;
}
