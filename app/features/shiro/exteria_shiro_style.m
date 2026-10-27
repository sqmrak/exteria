#import "exteria_shiro_style.h"

#import "exteria_theme.h"

static UIColor *ExteriaShiroFixedHex(unsigned int light, unsigned int dark) {
    unsigned int rgb = ExteriaThemeIsDark() ? dark : light;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

/* the hue of the raspberry seed of the palette (the primary of the day, 0xBC0F52) */
#define SHIRO_SEED_HUE 337.0

/* the palette follows the hue the wallpaper gives the app: its seed goes to the hue of the accent, and every tone
   turns the same way, so the primary of this screen is the accent of the rest */
static UIColor *ExteriaShiroHex(unsigned int light, unsigned int dark) {
    CGFloat accent = 0;
    UIColor *color = ExteriaShiroFixedHex(light, dark);
    return ExteriaThemeAccentHue(&accent) ? ExteriaThemeRotated(color, accent - SHIRO_SEED_HUE) : color;
}

UIColor *ExteriaShiroColorSurface(void) { return ExteriaShiroHex(0xFFF8F8, 0x1A1113); }
UIColor *ExteriaShiroColorSurfaceContainer(void) { return ExteriaShiroHex(0xFBEAEC, 0x271D1F); }
UIColor *ExteriaShiroColorSurfaceHighest(void) { return ExteriaShiroHex(0xF0DFE2, 0x3D3234); }
UIColor *ExteriaShiroColorOnSurface(void) { return ExteriaShiroHex(0x22191B, 0xF0DEE0); }
UIColor *ExteriaShiroColorOnSurfaceVariant(void) { return ExteriaShiroHex(0x524347, 0xD6C2C5); }
UIColor *ExteriaShiroColorOutline(void) { return ExteriaShiroHex(0x847376, 0x9F8C8F); }
UIColor *ExteriaShiroColorPrimary(void) { return ExteriaShiroHex(0xBC0F52, 0xFFB1C6); }
UIColor *ExteriaShiroColorOnPrimary(void) { return ExteriaShiroHex(0xFFFFFF, 0x660030); }
UIColor *ExteriaShiroColorPrimaryContainer(void) { return ExteriaShiroHex(0xFFD9E2, 0x8E0043); }
UIColor *ExteriaShiroColorOnPrimaryContainer(void) { return ExteriaShiroHex(0x3E001D, 0xFFD9E2); }
UIColor *ExteriaShiroColorSecondaryContainer(void) { return ExteriaShiroHex(0xFFD9E1, 0x5B3F46); }
UIColor *ExteriaShiroColorOnSecondaryContainer(void) { return ExteriaShiroHex(0x2B151B, 0xFFD9E1); }
UIColor *ExteriaShiroColorError(void) { return ExteriaShiroFixedHex(0xBA1A1A, 0xFFB4AB); }
UIColor *ExteriaShiroColorErrorContainer(void) { return ExteriaShiroFixedHex(0xFFDAD6, 0x93000A); }
UIColor *ExteriaShiroColorOnErrorContainer(void) { return ExteriaShiroFixedHex(0x410002, 0xFFDAD6); }

NSArray *ExteriaShiroShimmerColors(void) {
    /* raspberry, then the peach and lilac tertiary and secondary tones of the same seed */
    return [NSArray arrayWithObjects:ExteriaShiroHex(0xD81B60, 0xFF8FB1), ExteriaShiroHex(0xF0743C, 0xFFB38A),
            ExteriaShiroHex(0x8E4DD6, 0xCBA6FF), ExteriaShiroHex(0x1E88E5, 0x8CC8FF), nil];
}

/* the faces of the bundle: Rubik-Regular, Rubik-Medium and Rubik-Bold are registered in Info.plist, and ios before 11 reads no variable font axes */
UIFont *ExteriaShiroFontDisplay(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"Rubik-Bold" size:size];
    return font ? font : [UIFont boldSystemFontOfSize:size];
}

UIFont *ExteriaShiroFontBody(CGFloat size, BOOL medium) {
    UIFont *font = [UIFont fontWithName:medium ? @"Rubik-Medium" : @"Rubik-Regular" size:size];
    if (font) return font;
    return medium ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
}

NSString *ExteriaShiroByteText(unsigned long long bytes) {
    static const char *const units[] = {"B", "KB", "MB", "GB", "TB"};
    double value = (double)bytes;
    size_t unit = 0;
    while (value >= 1024.0 && unit + 1 < sizeof(units) / sizeof(units[0])) {
        value /= 1024.0;
        ++unit;
    }
    if (unit == 0) return [NSString stringWithFormat:@"%llu %s", bytes, units[0]];
    return [NSString stringWithFormat:@"%.1f %s", value, units[unit]];
}
