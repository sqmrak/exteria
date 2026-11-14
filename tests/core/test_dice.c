#include <string.h>

#include "exteria_dice.h"
#include "test_util.h"

static void test_plans(void) {
    exteria_slots_plan plan;
    exteria_slots_idle_plan(&plan);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_BACK], 1);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 8);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_CENTER], 14);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_RIGHT], 20);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEVER], 2);
    CHECK_EQ_INT(plan.win, 0);

    /* value 1 is bar, bar, bar */
    CHECK_EQ_INT(exteria_slots_result_plan(1, &plan), EXTERIA_OK);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 5);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_CENTER], 11);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_RIGHT], 17);
    CHECK_EQ_INT(plan.win, 0);
    /* value 2: the left reel shows berries, the others stay on bar */
    CHECK_EQ_INT(exteria_slots_result_plan(2, &plan), EXTERIA_OK);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 6);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_CENTER], 11);
    /* value 3 lemon and 4 seven on the left, 5 berries on the center */
    CHECK_EQ_INT(exteria_slots_result_plan(3, &plan), EXTERIA_OK);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 7);
    CHECK_EQ_INT(exteria_slots_result_plan(4, &plan), EXTERIA_OK);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 4);
    CHECK_EQ_INT(exteria_slots_result_plan(5, &plan), EXTERIA_OK);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 5);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_CENTER], 12);
    /* 22 is 21 = 1,1,1 in two bits each: berries on all three */
    CHECK_EQ_INT(exteria_slots_result_plan(22, &plan), EXTERIA_OK);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 6);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_CENTER], 12);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_RIGHT], 18);
    CHECK_EQ_INT(plan.win, 0);
    /* 43 is 42 = 2,2,2: lemons */
    CHECK_EQ_INT(exteria_slots_result_plan(43, &plan), EXTERIA_OK);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_RIGHT], 19);
    /* 64 is 63 = 3,3,3: three sevens, the win animations */
    CHECK_EQ_INT(exteria_slots_result_plan(64, &plan), EXTERIA_OK);
    CHECK_EQ_INT(plan.win, 1);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 3);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_CENTER], 9);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_RIGHT], 15);
    /* two sevens are no win: 63 is 62 = 2,3,3 would be left lemon; 60 is 59 = 3,2,3 */
    CHECK_EQ_INT(exteria_slots_result_plan(60, &plan), EXTERIA_OK);
    CHECK_EQ_INT(plan.win, 0);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 4);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_CENTER], 13);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_RIGHT], 16);

    /* every value of the range yields documents inside the set of the machine */
    for (int32_t v = 1; v <= 64; ++v) {
        CHECK_EQ_INT(exteria_slots_result_plan(v, &plan), EXTERIA_OK);
        for (int i = 0; i < EXTERIA_SLOTS_LAYERS; ++i) CHECK(plan.doc[i] >= 1 && plan.doc[i] <= 20);
    }
    /* out of range leaves a zeroed plan */
    CHECK_EQ_INT(exteria_slots_result_plan(0, &plan), EXTERIA_E_ARG);
    CHECK_EQ_INT(plan.doc[EXTERIA_SLOTS_LEFT], 0);
    CHECK_EQ_INT(exteria_slots_result_plan(65, &plan), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_slots_result_plan(-1, &plan), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_slots_result_plan(1, NULL), EXTERIA_E_ARG);
}

static void test_frames(void) {
    exteria_slots_plan plain, win;
    /* machine 200 frames, reels 120, 130, 140, lever 90 */
    const uint32_t counts[EXTERIA_SLOTS_LAYERS] = {200, 120, 130, 140, 90};
    uint32_t frames[EXTERIA_SLOTS_LAYERS];
    CHECK_EQ_INT(exteria_slots_result_plan(1, &plain), EXTERIA_OK);
    CHECK_EQ_INT(exteria_slots_result_plan(64, &win), EXTERIA_OK);

    CHECK_EQ_INT(exteria_slots_result_total(&plain, counts), 140);
    /* the win animation starts 100 frames before the left reel ends, at 20, and runs 200 frames */
    CHECK_EQ_INT(exteria_slots_result_total(&win, counts), 220);

    CHECK_EQ_INT(exteria_slots_result_frames(&plain, counts, 0, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_BACK], 0);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_LEFT], 0);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_LEVER], 0);
    CHECK_EQ_INT(exteria_slots_result_frames(&plain, counts, 125, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_LEFT], 119);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_CENTER], 125);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_RIGHT], 125);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_LEVER], 89);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_BACK], 0);
    /* the last frame of the throw is the last frame of every reel */
    CHECK_EQ_INT(exteria_slots_result_frames(&plain, counts, 139, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_RIGHT], 139);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_CENTER], 129);

    CHECK_EQ_INT(exteria_slots_result_frames(&win, counts, 19, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_BACK], 0);
    CHECK_EQ_INT(exteria_slots_result_frames(&win, counts, 20, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_BACK], 0);
    CHECK_EQ_INT(exteria_slots_result_frames(&win, counts, 50, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_BACK], 30);
    CHECK_EQ_INT(exteria_slots_result_frames(&win, counts, 219, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_BACK], 199);
    /* past its end the machine is back on its first frame */
    CHECK_EQ_INT(exteria_slots_result_frames(&win, counts, 220, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_BACK], 0);
    /* a short left reel starts the win animation at the first frame */
    {
        const uint32_t short_reel[EXTERIA_SLOTS_LAYERS] = {50, 60, 70, 80, 10};
        CHECK_EQ_INT(exteria_slots_result_total(&win, short_reel), 80);
        CHECK_EQ_INT(exteria_slots_result_frames(&win, short_reel, 10, frames), EXTERIA_OK);
        CHECK_EQ_INT(frames[EXTERIA_SLOTS_BACK], 10);
    }

    /* an unknown count refuses and leaves the output alone */
    {
        const uint32_t missing[EXTERIA_SLOTS_LAYERS] = {200, 0, 130, 140, 90};
        memset(frames, 0xAB, sizeof(frames));
        CHECK_EQ_INT(exteria_slots_result_frames(&plain, missing, 5, frames), EXTERIA_E_ARG);
        CHECK_EQ_INT(frames[0], 0xABABABABu);
        CHECK_EQ_INT(exteria_slots_result_total(&plain, missing), 0);
        CHECK_EQ_INT(exteria_slots_idle_frames(missing, 5, frames), EXTERIA_E_ARG);
    }
    CHECK_EQ_INT(exteria_slots_result_frames(NULL, counts, 0, frames), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_slots_result_frames(&plain, NULL, 0, frames), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_slots_result_frames(&plain, counts, 0, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_slots_result_total(NULL, counts), 0);

    /* the waiting machine: reels loop on their own length, the lever holds its last frame */
    CHECK_EQ_INT(exteria_slots_idle_frames(counts, 125, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_BACK], 0);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_LEFT], 5);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_CENTER], 125);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_RIGHT], 125);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_LEVER], 89);
    CHECK_EQ_INT(exteria_slots_idle_frames(counts, 0, frames), EXTERIA_OK);
    CHECK_EQ_INT(frames[EXTERIA_SLOTS_LEVER], 0);
}

int main(void) {
    test_plans();
    test_frames();
    return test_finish("test_dice");
}
