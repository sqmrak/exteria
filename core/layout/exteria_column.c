#include "exteria_column.h"

#include <math.h>

exteria_status exteria_column_place(double width, double left_inset, double right_inset, double max_width, exteria_column *out) {
    double room, column, x;
    if (!out) return EXTERIA_E_ARG;
    out->x = 0;
    out->width = 0;
    if (!isfinite(width) || !isfinite(left_inset) || !isfinite(right_inset) || !isfinite(max_width)) return EXTERIA_E_ARG;
    if (width <= 0 || left_inset < 0 || right_inset < 0) return EXTERIA_E_ARG;
    room = width - left_inset - right_inset;
    if (room <= 0) return EXTERIA_E_ARG;
    column = (max_width > 0 && max_width < room) ? max_width : room;
    x = (width - column) / 2;
    if (x < left_inset) x = left_inset;
    if (x > width - right_inset - column) x = width - right_inset - column;
    out->x = x;
    out->width = column;
    return EXTERIA_OK;
}
