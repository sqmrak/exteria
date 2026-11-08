#include "exteria_video_edit.h"

#include <math.h>

double exteria_video_edit_aspect(unsigned index) {
    static const double ratios[] = {0, 1, 4.0 / 3, 3.0 / 4, 16.0 / 9, 9.0 / 16};
    return index < sizeof(ratios) / sizeof(ratios[0]) ? ratios[index] : -1;
}

exteria_status exteria_video_edit_range(double duration, double start, double end, double *start_seconds, double *duration_seconds) {
    if (start_seconds) *start_seconds = 0;
    if (duration_seconds) *duration_seconds = 0;
    if (!start_seconds || !duration_seconds || !isfinite(duration) || !isfinite(start) || !isfinite(end) ||
        duration <= 0 || duration > 86400 || start < 0 || end > 1 || start >= end || (end - start) * duration < 0.05)
        return EXTERIA_E_ARG;
    *start_seconds = duration * start;
    *duration_seconds = duration * (end - start);
    return EXTERIA_OK;
}

exteria_status exteria_video_edit_crop(double width, double height, double ratio, double *x, double *y, double *out_width, double *out_height) {
    if (x) *x = 0;
    if (y) *y = 0;
    if (out_width) *out_width = 0;
    if (out_height) *out_height = 0;
    if (!x || !y || !out_width || !out_height || !isfinite(width) || !isfinite(height) || !isfinite(ratio) ||
        width < 2 || height < 2 || width > 4096 || height > 4096 || ratio < 0 || (ratio > 0 && (ratio < 0.1 || ratio > 10))) return EXTERIA_E_ARG;
    double w = width, h = height;
    if (ratio > 0) {
        if (width / height > ratio) w = height * ratio;
        else h = width / ratio;
    }
    if (w < 2 || h < 2) return EXTERIA_E_ARG;
    *x = (width - w) / 2;
    *y = (height - h) / 2;
    *out_width = w;
    *out_height = h;
    return EXTERIA_OK;
}

exteria_status exteria_video_edit_crop_rect(double width, double height, double nx, double ny, double nw, double nh, double *x, double *y, double *out_width, double *out_height) {
    if (x) *x = 0;
    if (y) *y = 0;
    if (out_width) *out_width = 0;
    if (out_height) *out_height = 0;
    if (!x || !y || !out_width || !out_height || !isfinite(width) || !isfinite(height) || !isfinite(nx) || !isfinite(ny) || !isfinite(nw) || !isfinite(nh) ||
        width < 2 || height < 2 || width > 4096 || height > 4096 || nx < 0 || ny < 0 || nw <= 0 || nh <= 0 || nx > 1 || ny > 1 || nx + nw > 1 + 1e-6 || ny + nh > 1 + 1e-6)
        return EXTERIA_E_ARG;
    /* the edges are cut to even pixels, the far one never past the picture */
    double left = floor(nx * width / 2) * 2, top = floor(ny * height / 2) * 2;
    double right = floor(fmin(nx + nw, 1) * width / 2) * 2, bottom = floor(fmin(ny + nh, 1) * height / 2) * 2;
    if (right - left < EXTERIA_VIDEO_CROP_MIN_SIDE || bottom - top < EXTERIA_VIDEO_CROP_MIN_SIDE) return EXTERIA_E_ARG;
    *x = left;
    *y = top;
    *out_width = right - left;
    *out_height = bottom - top;
    return EXTERIA_OK;
}

double exteria_video_edit_handle(int is_end, double value, double other, double min_gap) {
    if (!isfinite(value) || !isfinite(other) || !isfinite(min_gap) || min_gap < 0 || min_gap >= 1 || other < 0 || other > 1) return other;
    if (is_end) {
        double low = other + min_gap;
        if (low > 1) return other;
        return value < low ? low : (value > 1 ? 1 : value);
    }
    double high = other - min_gap;
    if (high < 0) return other;
    return value > high ? high : (value < 0 ? 0 : value);
}
