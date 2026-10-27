#include "exteria_geo.h"

#include <math.h>
#include <string.h>
#include "exteria_tl_ids.h"

#define PI 3.14159265358979323846

int exteria_geo_valid(double latitude, double longitude) {
    return isfinite(latitude) && isfinite(longitude) && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
}

int exteria_map_png_header(const uint8_t *bytes, size_t length) {
    static const uint8_t signature[] = {137,80,78,71,13,10,26,10};
    static const uint8_t header[] = {0,0,0,13,'I','H','D','R',0,0,1,0,0,0,1,0};
    return bytes && length >= 33 && length <= EXTERIA_MAP_TILE_BYTES_MAX &&
        !memcmp(bytes, signature, sizeof(signature)) && !memcmp(bytes + 8, header, sizeof(header));
}

exteria_status exteria_map_project(double latitude, double longitude, double *x, double *y) {
    if (x) *x = 0;
    if (y) *y = 0;
    if (!x || !y || !exteria_geo_valid(latitude, longitude)) return EXTERIA_E_ARG;
    latitude = fmax(-EXTERIA_MAP_MAX_LATITUDE, fmin(EXTERIA_MAP_MAX_LATITUDE, latitude));
    double radians = latitude * PI / 180;
    *x = (longitude + 180) / 360;
    if (*x == 1) *x = 0;
    *y = fmax(0, fmin(1, (1 - log(tan(radians) + 1 / cos(radians)) / PI) / 2));
    return EXTERIA_OK;
}

exteria_status exteria_map_unproject(double x, double y, double *latitude, double *longitude) {
    if (latitude) *latitude = 0;
    if (longitude) *longitude = 0;
    if (!latitude || !longitude || !isfinite(x) || !isfinite(y)) return EXTERIA_E_ARG;
    x -= floor(x);
    y = fmax(0, fmin(1, y));
    *longitude = x * 360 - 180;
    *latitude = atan(sinh(PI * (1 - 2 * y))) * 180 / PI;
    return EXTERIA_OK;
}

exteria_status exteria_map_tiles(double latitude, double longitude, double zoom, double width, double height,
                                exteria_map_tile *tiles, size_t cap, size_t *count) {
    double x, y;
    if (count) *count = 0;
    if (!tiles || !count || !cap || !isfinite(zoom) || zoom < 0 || zoom > EXTERIA_MAP_MAX_ZOOM ||
        !isfinite(width) || !isfinite(height) || width <= 0 || height <= 0 || width > 4096 || height > 4096 ||
        exteria_map_project(latitude, longitude, &x, &y) != EXTERIA_OK) return EXTERIA_E_ARG;
    unsigned int level = (unsigned int)floor(zoom);
    int32_t world = (int32_t)(1u << level);
    double side = EXTERIA_MAP_TILE_SIZE * pow(2, zoom - level);
    double left = x * world - width / (2 * side), top = y * world - height / (2 * side);
    int32_t first_x = (int32_t)floor(left), last_x = (int32_t)ceil(left + width / side) - 1;
    int32_t first_y = (int32_t)fmax(0, floor(top)), last_y = (int32_t)fmin(world - 1, ceil(top + height / side) - 1);
    size_t needed = (size_t)(last_x - first_x + 1) * (size_t)(last_y - first_y + 1);
    if (needed > cap || needed > EXTERIA_MAP_MAX_TILES) return EXTERIA_E_LIMIT;
    for (int32_t row = first_y; row <= last_y; ++row) {
        for (int32_t column = first_x; column <= last_x; ++column) {
            exteria_map_tile *tile = &tiles[(*count)++];
            tile->x = (uint32_t)((column % world + world) % world);
            tile->y = (uint32_t)row;
            tile->zoom = (uint8_t)level;
            tile->left = (column - left) * side;
            tile->top = (row - top) * side;
            tile->side = side;
        }
    }
    return EXTERIA_OK;
}

static int read_text(const exteria_tl_value *value, const char *key, char *out, size_t cap, int whole) {
    const uint8_t *bytes = NULL;
    size_t len = 0;
    out[0] = 0;
    if (exteria_tl_get_bytes(value, key, &bytes, &len) != EXTERIA_OK || (whole && len >= cap) ||
        (len && (!bytes || memchr(bytes, 0, len)))) return 0;
    if (len >= cap) {
        len = cap - 1;
        /* presentation text may be shortened, but a UTF-8 character must stay whole */
        while (len && (bytes[len] & 0xc0) == 0x80) --len;
    }
    if (len) memcpy(out, bytes, len);
    out[len] = 0;
    return 1;
}

exteria_status exteria_geo_read(const exteria_tl_value *point, const exteria_tl_value *venue, exteria_geo_point *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(point, EXTERIA_TL_ID_geoPoint) ||
        exteria_tl_get_f64(point, "lat", &out->latitude) != EXTERIA_OK ||
        exteria_tl_get_f64(point, "long", &out->longitude) != EXTERIA_OK ||
        !exteria_geo_valid(out->latitude, out->longitude)) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    int32_t accuracy = 0;
    if (exteria_tl_get_i32(point, "accuracy_radius", &accuracy) == EXTERIA_OK && accuracy > 0 && accuracy <= 1500) out->accuracy = accuracy;
    if (venue) {
        if (!read_text(venue, "title", out->title, sizeof(out->title), 0) ||
            !read_text(venue, "address", out->address, sizeof(out->address), 0) ||
            !read_text(venue, "provider", out->provider, sizeof(out->provider), 1) ||
            !read_text(venue, "venue_id", out->venue_id, sizeof(out->venue_id), 1) ||
            !read_text(venue, "venue_type", out->venue_type, sizeof(out->venue_type), 1)) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        out->venue = 1;
    }
    out->valid = 1;
    return EXTERIA_OK;
}

exteria_status exteria_geo_input(exteria_arena *arena, const exteria_geo_point *point, exteria_tl_value **out) {
    if (out) *out = NULL;
    if (!arena || !point || !out || !point->valid || !exteria_geo_valid(point->latitude, point->longitude) ||
        !isfinite(point->accuracy) || point->accuracy < 0 || point->accuracy > 1500) return EXTERIA_E_ARG;
    exteria_tl_value *input = exteria_tl_new_obj(arena, "inputGeoPoint");
    if (!input) return EXTERIA_E_NOMEM;
    exteria_status status = exteria_tl_set_f64(arena, input, "lat", point->latitude);
    if (status == EXTERIA_OK) status = exteria_tl_set_f64(arena, input, "long", point->longitude);
    if (status == EXTERIA_OK && point->accuracy > 0) status = exteria_tl_set_i32(arena, input, "accuracy_radius", (int32_t)ceil(point->accuracy));
    if (status == EXTERIA_OK) *out = input;
    return status;
}
