#include "exteria_wallpaper_tint.h"

float exteria_wallpaper_tint(float hue, float saturation, float value) {
    return saturation < 0.12f || value < 0.15f ? EXTERIA_WALLPAPER_NEUTRAL_HUE : hue;
}
