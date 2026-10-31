#include "exteria_tgios_theme.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void check(const char *text, exteria_tgios_status expected) {
    exteria_tgios_theme *theme = malloc(sizeof(*theme));
    assert(theme);
    assert(exteria_tgios_parse((const uint8_t *)text, strlen(text), theme) == expected);
    free(theme);
}

int main(void) {
    exteria_tgios_theme *theme = malloc(sizeof(*theme));
    assert(theme);
    uint8_t bytes[EXTERIA_TGIOS_MAX_BYTES + 1];
    const char *fixtures[] = {"fixtures/telegram-rich-black.tgios-theme", "fixtures/telegram-claude-light.tgios-theme"};
    const char *names[] = {"Rich Black", "Claude Light"};
    for (size_t i = 0; i < 2; ++i) {
        FILE *file = fopen(fixtures[i], "rb");
        assert(file);
        size_t length = fread(bytes, 1, sizeof(bytes), file);
        assert(!ferror(file));
        assert(fclose(file) == 0);
        assert(exteria_tgios_parse(bytes, length, theme) == EXTERIA_TGIOS_OK);
        assert(exteria_tgios_validate_applicable(theme) == EXTERIA_TGIOS_OK);
        assert(strcmp(exteria_tgios_get(theme, "name"), names[i]) == 0);
    }
    assert(strcmp(exteria_tgios_get(theme, "chat.message.incoming.primaryText"), "2d2a26") == 0);
    uint32_t argb = 0;
    assert(exteria_tgios_color("80aAbBcC", &argb) && argb == 0x80aabbccu);
    assert(exteria_tgios_color("ffffff", &argb) && argb == 0xffffffffu);
    assert(exteria_tgios_color("clear", &argb) && argb == 0);
    assert(exteria_tgios_color("CLEAR", &argb) && argb == 0);
    assert(!exteria_tgios_color("fffff", &argb));
    assert(exteria_tgios_color("#ffffff", &argb) && argb == 0xffffffffu);
    assert(exteria_tgios_color("#80aAbBcC", &argb) && argb == 0x80aabbccu);
    assert(exteria_tgios_color("#clear", &argb) == 0);
    assert(!exteria_tgios_color("##ffffff", &argb));
    assert(!exteria_tgios_color("#fffff", &argb));
    assert(!exteria_tgios_color("#", &argb));
    assert(!exteria_tgios_color("#fffffff", &argb));
    assert(!exteria_tgios_color("gggggg", &argb));
    free(theme);
    check("", EXTERIA_TGIOS_EMPTY);
    check("root:\n  tabBar:\n    background: ffffff\n", EXTERIA_TGIOS_OK);
    check("name: \320\242\320\265\320\274\320\260\n", EXTERIA_TGIOS_OK);
    check("name: \320\242\320\265\320\274\320\260\320", EXTERIA_TGIOS_MALFORMED);
    check("name: \320\242\n", EXTERIA_TGIOS_OK);
    check("root:\n   tabBar: ffffff\n", EXTERIA_TGIOS_MALFORMED);
    check("root:\n    tabBar: ffffff\n", EXTERIA_TGIOS_MALFORMED);
    check("root: value\n  tabBar: ffffff\n", EXTERIA_TGIOS_MALFORMED);
    check("root: value\nroot: other\n", EXTERIA_TGIOS_MALFORMED);
    check("root:\n  tabBar", EXTERIA_TGIOS_MALFORMED);
    check("basedOn: day\ndark: false\nunknownField: kept\n", EXTERIA_TGIOS_OK);
    const char *bad_color = "basedOn: day\ndark: false\nchat:\n  message:\n    incoming:\n      primaryText: zzzzzz\n";
    theme = malloc(sizeof(*theme));
    assert(theme);
    assert(exteria_tgios_parse((const uint8_t *)bad_color, strlen(bad_color), theme) == EXTERIA_TGIOS_OK);
    assert(exteria_tgios_validate_applicable(theme) == EXTERIA_TGIOS_INVALID_COLOR);
    const exteria_tgios_field *bad_field = NULL;
    assert(exteria_tgios_validate_applicable_at(theme, &bad_field) == EXTERIA_TGIOS_INVALID_COLOR);
    assert(bad_field && !strcmp(bad_field->key, "chat.message.incoming.primaryText") && !strcmp(bad_field->value, "zzzzzz"));
    free(theme);
    const char *hash_color = "basedOn: day\ndark: false\nchat:\n  message:\n    incoming:\n      primaryText: #aabbcc\n";
    theme = malloc(sizeof(*theme));
    assert(theme);
    assert(exteria_tgios_parse((const uint8_t *)hash_color, strlen(hash_color), theme) == EXTERIA_TGIOS_OK);
    bad_field = theme->fields;
    assert(exteria_tgios_validate_applicable_at(theme, &bad_field) == EXTERIA_TGIOS_OK && !bad_field);
    free(theme);
    exteria_tgios_wallpaper wallpaper;
    assert(!exteria_tgios_parse_wallpaper("#112233", &wallpaper));
    assert(!exteria_tgios_parse_wallpaper("112233 #445566", &wallpaper));
    assert(exteria_tgios_parse_wallpaper("builtin", &wallpaper) && wallpaper.kind == EXTERIA_TGIOS_WALLPAPER_BUILTIN);
    assert(exteria_tgios_parse_wallpaper("112233", &wallpaper) && wallpaper.kind == EXTERIA_TGIOS_WALLPAPER_COLOR);
    assert(exteria_tgios_parse_wallpaper("112233 445566 778899 aabbcc 90 motion", &wallpaper));
    assert(wallpaper.kind == EXTERIA_TGIOS_WALLPAPER_GRADIENT && wallpaper.color_count == 4 && wallpaper.rotation == 90 && wallpaper.motion);
    assert(exteria_tgios_parse_wallpaper("telegram-pattern 112233 50 445566 blur", &wallpaper));
    assert(wallpaper.kind == EXTERIA_TGIOS_WALLPAPER_FILE && wallpaper.color_count == 2 && wallpaper.intensity == 50 && wallpaper.blur);
    assert(!exteria_tgios_parse_wallpaper("112233 445566 gggggg", &wallpaper));
    assert(!exteria_tgios_parse_wallpaper("112233 445566 778899 aabbcc dddddd", &wallpaper));
    const char *unmapped_bad_color = "basedOn: day\ndark: false\nchat:\n  inputMediaPanel:\n    stickersBg: xyzxyz\n";
    theme = malloc(sizeof(*theme));
    assert(theme);
    assert(exteria_tgios_parse((const uint8_t *)unmapped_bad_color, strlen(unmapped_bad_color), theme) == EXTERIA_TGIOS_OK);
    assert(exteria_tgios_validate_applicable(theme) == EXTERIA_TGIOS_INVALID_COLOR);
    free(theme);
    const char *bad_wallpaper = "basedOn: day\ndark: false\nwallpaper: zzzzzz\n";
    theme = malloc(sizeof(*theme));
    assert(theme);
    assert(exteria_tgios_parse((const uint8_t *)bad_wallpaper, strlen(bad_wallpaper), theme) == EXTERIA_TGIOS_OK);
    assert(exteria_tgios_validate_applicable(theme) == EXTERIA_TGIOS_INVALID_WALLPAPER);
    free(theme);
    check("a:\n  b:\n    c:\n      d:\n        e:\n          f:\n            g:\n              h:\n                i:\n                  j:\n                    k:\n                      l:\n                        m:\n                          n:\n                            o:\n                              p:\n                                q: 1\n", EXTERIA_TGIOS_TOO_DEEP);
    char many[8192];
    size_t used = 0;
    for (unsigned i = 0; i <= EXTERIA_TGIOS_MAX_FIELDS; ++i) {
        int written = snprintf(many + used, sizeof(many) - used, "k%u: 1\n", i);
        assert(written > 0 && (size_t)written < sizeof(many) - used);
        used += (size_t)written;
    }
    theme = malloc(sizeof(*theme));
    assert(theme);
    assert(exteria_tgios_parse((const uint8_t *)many, used, theme) == EXTERIA_TGIOS_TOO_MANY_FIELDS);
    free(theme);
    memset(bytes, 'a', sizeof(bytes));
    assert(exteria_tgios_parse(bytes, sizeof(bytes), theme = malloc(sizeof(*theme))) == EXTERIA_TGIOS_TOO_LARGE);
    free(theme);
    puts("test_tgios_theme: passed");
    return 0;
}
