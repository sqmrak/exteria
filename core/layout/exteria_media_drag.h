#ifndef EXTERIA_MEDIA_DRAG_H
#define EXTERIA_MEDIA_DRAG_H

/* direction is selected before paging or dismissing, so one gesture cannot do both */
typedef enum exteria_media_drag_direction {
    EXTERIA_MEDIA_DRAG_NONE,
    EXTERIA_MEDIA_DRAG_HORIZONTAL,
    EXTERIA_MEDIA_DRAG_VERTICAL
} exteria_media_drag_direction;

exteria_media_drag_direction exteria_media_drag_direction_for(double x, double y);
double exteria_media_drag_progress(double distance, double height);
int exteria_media_drag_should_close(double distance, double height, int ended);

#endif
