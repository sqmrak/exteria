#ifndef EXTERIA_GEO_H
#define EXTERIA_GEO_H

#include <stddef.h>
#include <stdint.h>
#include "exteria_status.h"
#include "exteria_tl.h"

#define EXTERIA_MAP_TILE_SIZE 256
#define EXTERIA_MAP_MAX_TILES 64
#define EXTERIA_MAP_MAX_ZOOM 19
#define EXTERIA_MAP_MAX_LATITUDE 85.0511287798066
#define EXTERIA_MAP_TILE_BYTES_MAX (256u * 1024u)

typedef struct exteria_geo_point {
    uint8_t valid;
    uint8_t venue;
    double latitude;
    double longitude;
    double accuracy;
    char title[128];
    char address[256];
    char provider[32];
    char venue_id[128];
    char venue_type[96];
} exteria_geo_point;

typedef struct exteria_map_tile {
    uint32_t x, y;
    uint8_t zoom;
    double left, top, side;
} exteria_map_tile;

int exteria_geo_valid(double latitude, double longitude);
/* check the PNG header before handing bytes to the image decoder */
int exteria_map_png_header(const uint8_t *bytes, size_t length);
/* normalized world coordinates, with mercator's polar limit and longitude wrapping */
exteria_status exteria_map_project(double latitude, double longitude, double *x, double *y);
exteria_status exteria_map_unproject(double x, double y, double *latitude, double *longitude);
exteria_status exteria_map_tiles(double latitude, double longitude, double zoom, double width, double height,
                                exteria_map_tile *tiles, size_t cap, size_t *count);
/* reads GeoPoint plus the optional venue fields of its containing media */
exteria_status exteria_geo_read(const exteria_tl_value *point, const exteria_tl_value *venue, exteria_geo_point *out);
exteria_status exteria_geo_input(exteria_arena *arena, const exteria_geo_point *point, exteria_tl_value **out);

#endif
