#include "exteria_dice.h"

#include <string.h>

/* the documents of the slot machine set: 1 the machine, 2 the lever, then for each reel the spin and one stop animation for each face */
#define DOC_BACK 1
#define DOC_LEVER 2
#define WIN_LEAD_FRAMES 100

static const int32_t spin_doc[3] = {8, 14, 20};
/* bar, berries, lemon, seven, seven in a win, for the left, center and right reel */
static const int32_t stop_doc[3][5] = {{5, 6, 7, 4, 3}, {11, 12, 13, 10, 9}, {17, 18, 19, 16, 15}};

void exteria_slots_idle_plan(exteria_slots_plan *out) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    out->doc[EXTERIA_SLOTS_BACK] = DOC_BACK;
    for (int i = 0; i < 3; ++i) out->doc[EXTERIA_SLOTS_LEFT + i] = spin_doc[i];
    out->doc[EXTERIA_SLOTS_LEVER] = DOC_LEVER;
}

exteria_status exteria_slots_result_plan(int32_t value, exteria_slots_plan *out) {
    int32_t faces[3];
    if (out) memset(out, 0, sizeof(*out));
    if (!out || value < 1 || value > 64) return EXTERIA_E_ARG;
    value -= 1;
    faces[0] = value & 3;
    faces[1] = (value >> 2) & 3;
    faces[2] = (value >> 4) & 3;
    out->win = faces[0] == 3 && faces[1] == 3 && faces[2] == 3;
    out->doc[EXTERIA_SLOTS_BACK] = DOC_BACK;
    for (int i = 0; i < 3; ++i) out->doc[EXTERIA_SLOTS_LEFT + i] = stop_doc[i][out->win ? 4 : faces[i]];
    out->doc[EXTERIA_SLOTS_LEVER] = DOC_LEVER;
    return EXTERIA_OK;
}

static int counts_known(const uint32_t counts[EXTERIA_SLOTS_LAYERS]) {
    for (int i = 0; i < EXTERIA_SLOTS_LAYERS; ++i) {
        if (counts[i] == 0) return 0;
    }
    return 1;
}

/* the frame at which the machine starts its own animation: the last 100 frames of the left reel */
static uint32_t win_start(const uint32_t counts[EXTERIA_SLOTS_LAYERS]) {
    uint32_t reel = counts[EXTERIA_SLOTS_LEFT];
    return reel > WIN_LEAD_FRAMES ? reel - WIN_LEAD_FRAMES : 0;
}

uint32_t exteria_slots_result_total(const exteria_slots_plan *plan, const uint32_t counts[EXTERIA_SLOTS_LAYERS]) {
    uint32_t total = 0;
    if (!plan || !counts || !counts_known(counts)) return 0;
    for (int i = EXTERIA_SLOTS_LEFT; i < EXTERIA_SLOTS_LAYERS; ++i) {
        if (counts[i] > total) total = counts[i];
    }
    if (plan->win && win_start(counts) + counts[EXTERIA_SLOTS_BACK] > total) total = win_start(counts) + counts[EXTERIA_SLOTS_BACK];
    return total;
}

static uint32_t hold(uint32_t frame, uint32_t count) {
    return frame < count ? frame : count - 1;
}

exteria_status exteria_slots_result_frames(const exteria_slots_plan *plan, const uint32_t counts[EXTERIA_SLOTS_LAYERS], uint32_t frame, uint32_t out[EXTERIA_SLOTS_LAYERS]) {
    uint32_t start;
    if (!plan || !counts || !out || !counts_known(counts)) return EXTERIA_E_ARG;
    start = win_start(counts);
    out[EXTERIA_SLOTS_BACK] = 0;
    if (plan->win && frame >= start && frame - start < counts[EXTERIA_SLOTS_BACK]) out[EXTERIA_SLOTS_BACK] = frame - start;
    for (int i = EXTERIA_SLOTS_LEFT; i < EXTERIA_SLOTS_LAYERS; ++i) out[i] = hold(frame, counts[i]);
    return EXTERIA_OK;
}

exteria_status exteria_slots_idle_frames(const uint32_t counts[EXTERIA_SLOTS_LAYERS], uint32_t frame, uint32_t out[EXTERIA_SLOTS_LAYERS]) {
    if (!counts || !out || !counts_known(counts)) return EXTERIA_E_ARG;
    out[EXTERIA_SLOTS_BACK] = 0;
    for (int i = EXTERIA_SLOTS_LEFT; i <= EXTERIA_SLOTS_RIGHT; ++i) out[i] = frame % counts[i];
    out[EXTERIA_SLOTS_LEVER] = hold(frame, counts[EXTERIA_SLOTS_LEVER]);
    return EXTERIA_OK;
}
