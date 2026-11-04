#include "exteria_photo_zoom.h"

#include <math.h>

exteria_status exteria_photo_zoom_about(double zoom, double x, double y, double focal_x, double focal_y, double new_zoom, double *new_x, double *new_y) {
    if (new_x) *new_x = x;
    if (new_y) *new_y = y;
    if (!new_x || !new_y || !isfinite(zoom) || !isfinite(x) || !isfinite(y) || !isfinite(focal_x) || !isfinite(focal_y) || !isfinite(new_zoom) ||
        zoom <= 0 || new_zoom <= 0)
        return EXTERIA_E_ARG;
    double ratio = new_zoom / zoom;
    *new_x = focal_x - (focal_x - x) * ratio;
    *new_y = focal_y - (focal_y - y) * ratio;
    return EXTERIA_OK;
}

static double limit(double image, double area, double zoom) {
    double over = image * zoom - area;
    return over > 0 ? over / 2 : 0;
}

exteria_status exteria_photo_zoom_clamp(double image_width, double image_height, double area_width, double area_height, double min_zoom,
                                      double *zoom, double *x, double *y) {
    if (!zoom || !x || !y || !isfinite(*zoom) || !isfinite(*x) || !isfinite(*y) || !isfinite(image_width) || !isfinite(image_height) ||
        !isfinite(area_width) || !isfinite(area_height) || !isfinite(min_zoom) ||
        image_width <= 0 || image_height <= 0 || area_width <= 0 || area_height <= 0 || min_zoom <= 0 || min_zoom > EXTERIA_PHOTO_ZOOM_MAX)
        return EXTERIA_E_ARG;
    if (*zoom < min_zoom) *zoom = min_zoom;
    if (*zoom > EXTERIA_PHOTO_ZOOM_MAX) *zoom = EXTERIA_PHOTO_ZOOM_MAX;
    double reach_x = limit(image_width, area_width, *zoom), reach_y = limit(image_height, area_height, *zoom);
    if (*x < -reach_x) *x = -reach_x;
    if (*x > reach_x) *x = reach_x;
    if (*y < -reach_y) *y = -reach_y;
    if (*y > reach_y) *y = reach_y;
    return EXTERIA_OK;
}
