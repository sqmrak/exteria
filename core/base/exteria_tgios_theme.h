#ifndef EXTERIA_TGIOS_THEME_H
#define EXTERIA_TGIOS_THEME_H

#include <stddef.h>
#include <stdint.h>

#define EXTERIA_TGIOS_MAX_BYTES (256u * 1024u)
#define EXTERIA_TGIOS_MAX_FIELDS 512u

typedef enum {
    EXTERIA_TGIOS_OK = 0,
    EXTERIA_TGIOS_EMPTY,
    EXTERIA_TGIOS_TOO_LARGE,
    EXTERIA_TGIOS_TOO_DEEP,
    EXTERIA_TGIOS_MALFORMED,
    EXTERIA_TGIOS_TOO_MANY_FIELDS,
    EXTERIA_TGIOS_INVALID_COLOR,
    EXTERIA_TGIOS_INVALID_WALLPAPER
} exteria_tgios_status;

typedef struct {
    char key[160];
    char value[256];
} exteria_tgios_field;

typedef struct {
    exteria_tgios_field fields[EXTERIA_TGIOS_MAX_FIELDS];
    size_t count;
} exteria_tgios_theme;

exteria_tgios_status exteria_tgios_parse(const uint8_t *data, size_t length, exteria_tgios_theme *theme);
const char *exteria_tgios_get(const exteria_tgios_theme *theme, const char *key);
/* RRGGBB, AARRGGBB (the alpha first, as telegram ios writes it) or clear, with one # allowed before the digits */
int exteria_tgios_color(const char *value, uint32_t *argb);

typedef enum { EXTERIA_TGIOS_WALLPAPER_BUILTIN, EXTERIA_TGIOS_WALLPAPER_COLOR,
               EXTERIA_TGIOS_WALLPAPER_GRADIENT, EXTERIA_TGIOS_WALLPAPER_FILE } exteria_tgios_wallpaper_kind;
typedef struct {
    exteria_tgios_wallpaper_kind kind;
    uint32_t colors[4];
    unsigned color_count;
    int rotation;
    int intensity;
    int blur;
    int motion;
    char slug[160];
} exteria_tgios_wallpaper;

int exteria_tgios_parse_wallpaper(const char *value, exteria_tgios_wallpaper *wallpaper);
exteria_tgios_status exteria_tgios_validate_applicable(const exteria_tgios_theme *theme);
/* the same, and for EXTERIA_TGIOS_INVALID_COLOR the first field whose value is not a color, so the message can name it; NULL for any other status */
exteria_tgios_status exteria_tgios_validate_applicable_at(const exteria_tgios_theme *theme, const exteria_tgios_field **bad_field);

#endif
