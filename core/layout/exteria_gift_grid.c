#include "exteria_gift_grid.h"
#include <math.h>
#include <limits.h>

void exteria_gift_grid_layout(double width, double limit, int *columns, double *tile, double *margin) {
    if (!isfinite(width) || width < 0) width = 0;
    double content = limit > 0 && limit < width ? limit : width;
    double wanted = floor((content - 8.0) / 104.0);
    int count = wanted > INT_MAX ? INT_MAX : (int)wanted;
    if (count < 2) count = 2;
    double side = (content - 8.0 * ((double)count + 1.0)) / count;
    if (side < 0) side = 0;
    if (side > 128) side = 128;
    if (columns) *columns = count;
    if (tile) *tile = side;
    if (margin) *margin = floor((width - side * count - 8.0 * (count - 1)) / 2.0);
}
