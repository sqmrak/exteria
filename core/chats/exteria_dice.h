#ifndef EXTERIA_DICE_H
#define EXTERIA_DICE_H

#include <stdint.h>

#include "exteria_tl.h"

/* the slot machine is drawn from five animations laid over one another, back to front: the machine, the three reels and the lever. which document of the dice set is which layer, and
   which frame of each is on screen at a frame of the whole throw, is worked out here so it can be tested without an animation renderer */
#define EXTERIA_SLOTS_LAYERS 5
#define EXTERIA_SLOTS_BACK 0
#define EXTERIA_SLOTS_LEFT 1
#define EXTERIA_SLOTS_CENTER 2
#define EXTERIA_SLOTS_RIGHT 3
#define EXTERIA_SLOTS_LEVER 4

typedef struct exteria_slots_plan {
    int32_t doc[EXTERIA_SLOTS_LAYERS];  /* index into the documents of the set */
    uint8_t win;                        /* three sevens: the machine plays its own animation as the reels stop */
} exteria_slots_plan;

/* the layers of a slot machine still waiting for its result: the reels spin */
void exteria_slots_idle_plan(exteria_slots_plan *out);
/* the layers of a throw that ends on value (1 to 64, which holds one of four faces for each reel in two bits each); EXTERIA_E_ARG outside that */
exteria_status exteria_slots_result_plan(int32_t value, exteria_slots_plan *out);

/* the frames of the whole throw: the longest layer, with the win animation of the machine counted from the moment it starts. counts are the frame counts of the five documents of the
   plan, in layer order; zero for one that is not known, which makes the total zero */
uint32_t exteria_slots_result_total(const exteria_slots_plan *plan, const uint32_t counts[EXTERIA_SLOTS_LAYERS]);
/* the frame of each layer at frame of the throw: a reel and the lever hold their last frame when they are done, the machine stays on its first frame until the win animation starts and goes
   back to it when that ends. out is untouched when a count is zero and the call answers EXTERIA_E_ARG */
exteria_status exteria_slots_result_frames(const exteria_slots_plan *plan, const uint32_t counts[EXTERIA_SLOTS_LAYERS], uint32_t frame, uint32_t out[EXTERIA_SLOTS_LAYERS]);
/* the frames of the waiting machine: the reels loop on their own length, the machine stays on its first frame and the lever plays to its last and holds it */
exteria_status exteria_slots_idle_frames(const uint32_t counts[EXTERIA_SLOTS_LAYERS], uint32_t frame, uint32_t out[EXTERIA_SLOTS_LAYERS]);

#endif
