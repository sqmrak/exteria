#include "exteria_wallpaper_tint.h"
#include "test_util.h"

int main(void) {
    CHECK(exteria_wallpaper_tint(0, 0, 0) == EXTERIA_WALLPAPER_NEUTRAL_HUE);
    CHECK(exteria_wallpaper_tint(286, 0.05f, 0.5f) == EXTERIA_WALLPAPER_NEUTRAL_HUE);
    CHECK(exteria_wallpaper_tint(286, 0.8f, 0.1f) == EXTERIA_WALLPAPER_NEUTRAL_HUE);
    CHECK(exteria_wallpaper_tint(286, 0.12f, 0.15f) == 286);
    CHECK(exteria_wallpaper_tint(0, 1, 1) == 0);
    return test_finish("wallpaper_tint");
}
