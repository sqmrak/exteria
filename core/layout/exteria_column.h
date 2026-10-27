#ifndef EXTERIA_COLUMN_H
#define EXTERIA_COLUMN_H

#include "exteria_status.h"

typedef struct exteria_column {
    double x;
    double width;
} exteria_column;

/* the strip of a screen that content stands in */
exteria_status exteria_column_place(double width, double left_inset, double right_inset, double max_width, exteria_column *out);

#endif
