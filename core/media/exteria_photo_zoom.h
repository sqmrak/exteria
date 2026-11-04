#ifndef EXTERIA_PHOTO_ZOOM_H
#define EXTERIA_PHOTO_ZOOM_H

#include "exteria_status.h"

#define EXTERIA_PHOTO_ZOOM_MAX 6.0

/* the picture is enlarged by zoom about its own center, and (x, y) is where that center stands, measured from the middle of the area the picture is looked at in.
   a zoom of 1 leaves the picture centered */

/* the offset that keeps the spot under the focal point (also measured from the middle of the area) under it when the zoom changes */
exteria_status exteria_photo_zoom_about(double zoom, double x, double y, double focal_x, double focal_y, double new_zoom, double *new_x, double *new_y);
/* brings zoom into [min_zoom, EXTERIA_PHOTO_ZOOM_MAX] and the offset to where the enlarged picture still covers the area on every axis it is larger than the area on, and
   centers it on the axes where it is not. image is the size of the picture at zoom 1, area the size it is looked at in */
exteria_status exteria_photo_zoom_clamp(double image_width, double image_height, double area_width, double area_height, double min_zoom,
                                      double *zoom, double *x, double *y);

#endif
