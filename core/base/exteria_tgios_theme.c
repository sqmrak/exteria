#include "exteria_tgios_theme.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_tgios_color_keys.inc"

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int valid_text(const uint8_t *data, size_t length) {
    for (size_t i = 0; i < length;) {
        uint8_t c = data[i];
        if (c >= 32 && c < 127) { ++i; continue; }
        if (c < 0xc2 || c > 0xf4) return 0;
        size_t following = c < 0xe0 ? 1u : (c < 0xf0 ? 2u : 3u);
        if (length - i <= following) return 0;
        for (size_t j = 1; j <= following; ++j)
            if ((data[i + j] & 0xc0u) != 0x80u) return 0;
        if (c == 0xe0 && data[i + 1] < 0xa0) return 0;
        if (c == 0xed && data[i + 1] >= 0xa0) return 0;
        if (c == 0xf0 && data[i + 1] < 0x90) return 0;
        if (c == 0xf4 && data[i + 1] >= 0x90) return 0;
        i += following + 1;
    }
    return 1;
}

/* telegram ios reads a leading # on a theme color and none inside a wallpaper line, so only the keys take it */
static int parse_color(const char *value, int allow_hash, uint32_t *argb) {
    if (!value || !argb) return 0;
    size_t length = strlen(value);
    if (length == 5 && (value[0] == 'c' || value[0] == 'C') &&
        (value[1] == 'l' || value[1] == 'L') &&
        (value[2] == 'e' || value[2] == 'E') &&
        (value[3] == 'a' || value[3] == 'A') &&
        (value[4] == 'r' || value[4] == 'R') && value[5] == 0) { *argb = 0; return 1; }
    if (allow_hash && value[0] == '#') {
        ++value;
        --length;
    }
    if (length != 6 && length != 8) return 0;
    uint32_t color = 0;
    for (size_t i = 0; i < length; ++i) {
        int digit = hex_digit(value[i]);
        if (digit < 0) return 0;
        color = (color << 4) | (uint32_t)digit;
    }
    *argb = length == 6 ? color | 0xff000000u : color;
    return 1;
}

int exteria_tgios_color(const char *value, uint32_t *argb) {
    return parse_color(value, 1, argb);
}

int exteria_tgios_parse_wallpaper(const char *value, exteria_tgios_wallpaper *wallpaper) {
    if (!value || !wallpaper) return 0;
    memset(wallpaper, 0, sizeof(*wallpaper));
    wallpaper->rotation = 90;
    wallpaper->intensity = 50;
    if (strcmp(value, "builtin") == 0) return 1;
    uint32_t one_color;
    if (parse_color(value, 0, &one_color)) {
        wallpaper->kind = EXTERIA_TGIOS_WALLPAPER_COLOR;
        wallpaper->colors[0] = one_color;
        wallpaper->color_count = 1;
        return 1;
    }
    size_t length = strlen(value);
    if (!length || length >= 256) return 0;
    char text[256];
    memcpy(text, value, length + 1);
    unsigned numeric_count = 0;
    unsigned tokens = 0;
    char *cursor = text;
    while (*cursor) {
        if (*cursor == ' ') { ++cursor; continue; }
        char *part = cursor;
        while (*cursor && *cursor != ' ') ++cursor;
        char saved = *cursor;
        *cursor = 0;
        if (++tokens > 12) return 0;
        if (strcmp(part, "motion") == 0) wallpaper->motion = 1;
        else if (strcmp(part, "blur") == 0) wallpaper->blur = 1;
        else if (tokens == 1 && strlen(part) > 8) {
            size_t slug_length = strlen(part);
            if (slug_length >= sizeof(wallpaper->slug)) return 0;
            memcpy(wallpaper->slug, part, slug_length + 1);
            wallpaper->kind = EXTERIA_TGIOS_WALLPAPER_FILE;
        } else {
            uint32_t color;
            if (parse_color(part, 0, &color)) {
                if (wallpaper->color_count == 4) return 0;
                wallpaper->colors[wallpaper->color_count++] = color;
            } else {
                char *end = NULL;
                errno = 0;
                long number = strtol(part, &end, 10);
                if (errno || end == part || *end || ++numeric_count > 2) return 0;
                if (wallpaper->kind == EXTERIA_TGIOS_WALLPAPER_FILE && numeric_count == 1) {
                    if (number < -100 || number > 100) return 0;
                    wallpaper->intensity = (int)number;
                } else {
                    if (number < 0 || number >= 360) return 0;
                    wallpaper->rotation = (int)number;
                }
            }
        }
        if (!saved) break;
        *cursor++ = saved;
    }
    if (wallpaper->kind == EXTERIA_TGIOS_WALLPAPER_FILE) return 1;
    if (wallpaper->color_count < 2) return 0;
    wallpaper->kind = EXTERIA_TGIOS_WALLPAPER_GRADIENT;
    return 1;
}

const char *exteria_tgios_get(const exteria_tgios_theme *theme, const char *key) {
    if (!theme || !key) return NULL;
    for (size_t i = 0; i < theme->count; ++i)
        if (strcmp(theme->fields[i].key, key) == 0) return theme->fields[i].value;
    return NULL;
}

exteria_tgios_status exteria_tgios_validate_applicable(const exteria_tgios_theme *theme) {
    return exteria_tgios_validate_applicable_at(theme, NULL);
}

exteria_tgios_status exteria_tgios_validate_applicable_at(const exteria_tgios_theme *theme, const exteria_tgios_field **bad_field) {
    if (bad_field) *bad_field = NULL;
    if (!theme) return EXTERIA_TGIOS_MALFORMED;
    const char *base = exteria_tgios_get(theme, "basedOn");
    const char *tone = exteria_tgios_get(theme, "dark");
    if (!base || !tone || (strcmp(tone, "true") && strcmp(tone, "false"))) return EXTERIA_TGIOS_MALFORMED;
    if (strcmp(base, "day") && strcmp(base, "night") && strcmp(base, "nightAccent") && strcmp(base, "dayClassic")) return EXTERIA_TGIOS_MALFORMED;
    const char *status_bar = exteria_tgios_get(theme, "root.statusBar");
    if (status_bar && strcmp(status_bar, "black") && strcmp(status_bar, "white")) return EXTERIA_TGIOS_MALFORMED;
    for (size_t i = 0; i < theme->count; ++i) {
        const exteria_tgios_field *field = &theme->fields[i];
        for (size_t j = 0; j < sizeof(exteria_tgios_color_keys) / sizeof(exteria_tgios_color_keys[0]); ++j) {
            if (strcmp(field->key, exteria_tgios_color_keys[j]) == 0) {
                uint32_t color;
                if (!exteria_tgios_color(field->value, &color)) {
                    if (bad_field) *bad_field = field;
                    return EXTERIA_TGIOS_INVALID_COLOR;
                }
                break;
            }
        }
    }
    const char *wallpaper = exteria_tgios_get(theme, "wallpaper");
    exteria_tgios_wallpaper parsed_wallpaper;
    if (wallpaper && !exteria_tgios_parse_wallpaper(wallpaper, &parsed_wallpaper)) return EXTERIA_TGIOS_INVALID_WALLPAPER;
    return EXTERIA_TGIOS_OK;
}

exteria_tgios_status exteria_tgios_parse(const uint8_t *data, size_t length, exteria_tgios_theme *theme) {
    if (!theme) return EXTERIA_TGIOS_MALFORMED;
    theme->count = 0;
    if (!data || !length) return EXTERIA_TGIOS_EMPTY;
    if (length > EXTERIA_TGIOS_MAX_BYTES) return EXTERIA_TGIOS_TOO_LARGE;
    char parents[16][160] = {{0}};
    size_t position = 0;
    unsigned previous_depth = 0;
    int previous_parent = 0;
    while (position < length) {
        size_t start = position;
        while (position < length && data[position] != '\n') ++position;
        size_t end = position;
        if (position < length) ++position;
        if (end > start && data[end - 1] == '\r') --end;
        if (end == start) continue;
        size_t spaces = 0;
        while (start + spaces < end && data[start + spaces] == ' ') ++spaces;
        if (start + spaces == end || data[start + spaces] == '#') continue;
        if (spaces & 1u) return EXTERIA_TGIOS_MALFORMED;
        unsigned depth = (unsigned)(spaces / 2);
        if (depth >= 16) return EXTERIA_TGIOS_TOO_DEEP;
        if (depth > previous_depth && (depth != previous_depth + 1 || !previous_parent)) return EXTERIA_TGIOS_MALFORMED;
        size_t colon = start + spaces;
        while (colon < end && data[colon] != ':') ++colon;
        if (colon == end || colon == start + spaces) return EXTERIA_TGIOS_MALFORMED;
        for (size_t i = start + spaces; i < colon; ++i) {
            uint8_t c = data[i];
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '_')) return EXTERIA_TGIOS_MALFORMED;
        }
        size_t value = colon + 1;
        while (value < end && data[value] == ' ') ++value;
        while (end > value && data[end - 1] == ' ') --end;
        size_t key_length = colon - start - spaces;
        size_t prefix = depth ? strlen(parents[depth - 1]) : 0;
        if (prefix + (depth ? 1u : 0u) + key_length >= sizeof(parents[0]) || end - value >= sizeof(theme->fields[0].value)) return EXTERIA_TGIOS_MALFORMED;
        char key[160];
        if (depth) { memcpy(key, parents[depth - 1], prefix); key[prefix++] = '.'; }
        memcpy(key + prefix, data + start + spaces, key_length);
        key[prefix + key_length] = 0;
        if (value == end) {
            memcpy(parents[depth], key, prefix + key_length + 1);
            previous_parent = 1;
        } else {
            if (theme->count == EXTERIA_TGIOS_MAX_FIELDS) return EXTERIA_TGIOS_TOO_MANY_FIELDS;
            exteria_tgios_field *field = &theme->fields[theme->count++];
            memcpy(field->key, key, prefix + key_length + 1);
            for (size_t i = 0; i + 1 < theme->count; ++i)
                if (strcmp(theme->fields[i].key, key) == 0) return EXTERIA_TGIOS_MALFORMED;
            if (!valid_text(data + value, end - value)) return EXTERIA_TGIOS_MALFORMED;
            memcpy(field->value, data + value, end - value);
            field->value[end - value] = 0;
            previous_parent = 0;
        }
        previous_depth = depth;
    }
    return theme->count ? EXTERIA_TGIOS_OK : EXTERIA_TGIOS_EMPTY;
}
