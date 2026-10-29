#ifndef EXTERIA_MOTION_H
#define EXTERIA_MOTION_H

typedef enum exteria_motion_curve {
    EXTERIA_MOTION_ENTER,
    EXTERIA_MOTION_EXIT,
    EXTERIA_MOTION_SPRING,
    EXTERIA_MOTION_NAVIGATION,
    EXTERIA_MOTION_LIST_MOVE,
    /* a card or a menu that goes away: it starts to leave at once and settles, where EXIT starts slowly and the card seems to hang for a moment */
    EXTERIA_MOTION_DISMISS
} exteria_motion_curve;

double exteria_motion_duration(exteria_motion_curve curve);
/* normalized time, with exact endpoints and bounded spring overshoot */
double exteria_motion_progress(exteria_motion_curve curve, double time);
/* callback frequency must not change playback speed or count time spent paused */
double exteria_motion_elapsed(double elapsed, double previous, double now, int paused);
/* one outgoing screen stays under the next one, at most four MiB of pixels */
double exteria_motion_snapshot_scale(double width, double height, double display_scale);
/* only a predominantly leftward gesture starts a reply; a reversed drag has no pull */
int exteria_motion_reply_swipe_begins(double velocity_x, double velocity_y);
double exteria_motion_reply_swipe_pull(double translation_x);

typedef struct exteria_motion_swipe {
    double progress;
    double duration;
    int completes;
} exteria_motion_swipe;

/* finish from the finger's bounded position, with a fast reversal cancelling the pop */
exteria_motion_swipe exteria_motion_back_swipe(double width, double translation, double velocity, int ended);

/* absolute media time keeps ambient wave motion continuous across view rebuilds */
double exteria_motion_alternating(double time, double seconds);

#endif
