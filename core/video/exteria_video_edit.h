#ifndef EXTERIA_VIDEO_EDIT_H
#define EXTERIA_VIDEO_EDIT_H

#include "exteria_status.h"

/* selection is expressed as fractions of the asset duration */
exteria_status exteria_video_edit_range(double duration, double start, double end, double *start_seconds, double *duration_seconds);

/* a centered crop in the oriented picture; zero ratio keeps the whole picture */
exteria_status exteria_video_edit_crop(double width, double height, double ratio, double *x, double *y, double *out_width, double *out_height);
double exteria_video_edit_aspect(unsigned index);

/* a crop of any shape: the rectangle is given as fractions of the oriented picture (x, y, width, height) and comes back in pixels, every number even and the side at least
   EXTERIA_VIDEO_CROP_MIN_SIDE, since the encoder takes nothing odd or tiny. a rectangle that is not a number, lies outside the picture or is smaller than that fails with
   EXTERIA_E_ARG and leaves the outputs zero */
#define EXTERIA_VIDEO_CROP_MIN_SIDE 16
exteria_status exteria_video_edit_crop_rect(double width, double height, double nx, double ny, double nw, double nh, double *x, double *y, double *out_width, double *out_height);

/* a trim handle dragged to value (a fraction of the duration): the start stops min_gap short of the end, the end min_gap past the start, both inside [0, 1]. a value that is
   not a number, or a gap the range cannot hold, leaves the handle where it was (other) */
double exteria_video_edit_handle(int is_end, double value, double other, double min_gap);

#endif
