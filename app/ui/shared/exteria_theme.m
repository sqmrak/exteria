#import "exteria_theme.h"

#import <objc/message.h>

#import "exteria_wallpaper.h"
#import "exteria_imported_theme.h"
#include "exteria_wallpaper_tint.h"

#include <math.h>

/* the palette is purple, and the chat wallpaper can turn every hue of it: the turn in degrees, zero for the purple of the app */
static CGFloat ExteriaTintShift = 0;
static BOOL ExteriaNeutralTint = NO;
static BOOL ExteriaDark = NO;
static BOOL ExteriaClassic = NO;
/* how many times the saturation of the palette is multiplied; a color of your own sets it, a wallpaper leaves it at 1 */
static CGFloat ExteriaTintScale = 1;
/* a color of your own is stored: palettes with a seed of their own follow it even when it lands on the hue of the app */
static BOOL ExteriaCustomTint = NO;
/* the hue and the saturation of the light accent in the palette below, which a hue and a saturation of your own are measured from */
#define EXTERIA_PALETTE_HUE 286.0
#define EXTERIA_PALETTE_SATURATION 0.6

void ExteriaRGBToHSV(CGFloat red, CGFloat green, CGFloat blue, CGFloat *hue, CGFloat *saturation, CGFloat *value) {
    CGFloat high = MAX(red, MAX(green, blue)), low = MIN(red, MIN(green, blue));
    CGFloat span = high - low;
    CGFloat h = 0;
    if (span > 0) {
        if (high == red) h = fmod((green - blue) / span, 6);
        else if (high == green) h = (blue - red) / span + 2;
        else h = (red - green) / span + 4;
        h *= 60;
        if (h < 0) h += 360;
    }
    if (hue) *hue = h;
    if (saturation) *saturation = high > 0 ? span / high : 0;
    if (value) *value = high;
}

void ExteriaHSVToRGB(CGFloat hue, CGFloat saturation, CGFloat value, CGFloat *red, CGFloat *green, CGFloat *blue) {
    CGFloat chroma = value * saturation;
    CGFloat sector = fmod(hue, 360) / 60;
    CGFloat x = chroma * (1 - fabs(fmod(sector, 2) - 1));
    CGFloat r = 0, g = 0, b = 0;
    if (sector < 1) { r = chroma; g = x; }
    else if (sector < 2) { r = x; g = chroma; }
    else if (sector < 3) { g = chroma; b = x; }
    else if (sector < 4) { g = x; b = chroma; }
    else if (sector < 5) { r = x; b = chroma; }
    else { r = chroma; b = x; }
    CGFloat match = value - chroma;
    *red = r + match;
    *green = g + match;
    *blue = b + match;
}

/* the color with its hue turned by the shift of the wallpaper; greys stay grey, since the turn leaves the saturation alone */
static UIColor *ExteriaTurnedColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    if (ExteriaNeutralTint) {
        red = green = blue = 0.299f * red + 0.587f * green + 0.114f * blue;
    } else if (ExteriaTintShift != 0 || ExteriaTintScale != 1) {
        CGFloat h, s, v;
        ExteriaRGBToHSV(red, green, blue, &h, &s, &v);
        if (s > 0) {
            ExteriaHSVToRGB(h + ExteriaTintShift + 360, MIN(1, s * ExteriaTintScale), v, &red, &green, &blue);
        }
    }
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

UIColor *ExteriaThemeTinted(UIColor *color) {
    if (ExteriaTintShift == 0 && ExteriaTintScale == 1 && !ExteriaNeutralTint) return color;
    CGColorRef ref = color.CGColor;
    const CGFloat *c = CGColorGetComponents(ref);
    size_t count = CGColorGetNumberOfComponents(ref);
    if (count == 4) return ExteriaTurnedColor(c[0], c[1], c[2], c[3]);
    return color;
}

/* a palette with a seed hue of its own (the Shiro screens) moved to the accent of the app: the seed hue goes to the hue the accent has now, saturation follows a color
   of your own, and neutral tones stay grey. The palette keeps its own colors when nothing has tinted the app */
UIColor *ExteriaThemeFollowAccent(UIColor *color, CGFloat seedHue) {
    CGColorRef ref = color.CGColor;
    const CGFloat *c = CGColorGetComponents(ref);
    if (CGColorGetNumberOfComponents(ref) != 4) return color;
    CGFloat red = c[0], green = c[1], blue = c[2];
    CGFloat target = 0, scale = 1;
    BOOL grey = NO, follow = NO;
    UIColor *imported = !ExteriaClassic ? ExteriaImportedThemeColor("list.accent") : nil;
    if (imported) {
        const CGFloat *a = CGColorGetComponents(imported.CGColor);
        if (CGColorGetNumberOfComponents(imported.CGColor) == 4) {
            CGFloat s = 0;
            ExteriaRGBToHSV(a[0], a[1], a[2], &target, &s, NULL);
            grey = s < 0.08;
            follow = YES;
        }
    } else if (ExteriaNeutralTint) {
        grey = YES;
        follow = YES;
    } else if (ExteriaTintShift != 0 || ExteriaTintScale != 1 || ExteriaCustomTint) {
        target = fmod(EXTERIA_PALETTE_HUE + ExteriaTintShift + 720, 360);
        scale = ExteriaTintScale;
        follow = YES;
    }
    if (!follow) return color;
    if (grey) {
        CGFloat luma = 0.299f * red + 0.587f * green + 0.114f * blue;
        return [UIColor colorWithRed:luma green:luma blue:luma alpha:c[3]];
    }
    CGFloat h, s, v;
    ExteriaRGBToHSV(red, green, blue, &h, &s, &v);
    if (s <= 0) return color;
    ExteriaHSVToRGB(fmod(h + target - seedHue + 720, 360), MIN(1, s * scale), v, &red, &green, &blue);
    return [UIColor colorWithRed:red green:green blue:blue alpha:c[3]];
}

BOOL ExteriaThemeAccentHue(CGFloat *degrees) {
    if (ExteriaTintShift == 0) return NO;
    if (degrees) *degrees = fmod(EXTERIA_PALETTE_HUE + ExteriaTintShift + 720, 360);
    return YES;
}

static UIColor *ExteriaRGB(CGFloat red, CGFloat green, CGFloat blue) {
    return ExteriaTurnedColor(red / 255.0, green / 255.0, blue / 255.0, 1.0);
}

static NSString *const ExteriaClassicThemeKey = @"ExteriaClassicTheme";
static NSString *const ExteriaDarkThemeKey = @"ExteriaDarkTheme";
static NSString *const ExteriaTintOnKey = @"ExteriaThemeTintOn";
static NSString *const ExteriaTintHueKey = @"ExteriaThemeTintHue";
static NSString *const ExteriaCustomTintOnKey = @"ExteriaThemeCustomTintOn";
static NSString *const ExteriaCustomTintHueKey = @"ExteriaThemeCustomTintHue";
static NSString *const ExteriaCustomTintSaturationKey = @"ExteriaThemeCustomTintSaturation";
NSString *const ExteriaThemeDidChangeNotification = @"ExteriaThemeDidChangeNotification";
NSString *const ExteriaThemeOriginKey = @"origin";

BOOL ExteriaClassicThemeAvailable(void) {
    return [[[UIDevice currentDevice] systemVersion] integerValue] <= 10;
}

BOOL ExteriaThemeStoredClassic(void) {
    return ExteriaClassicThemeAvailable() && [[NSUserDefaults standardUserDefaults] boolForKey:ExteriaClassicThemeKey];
}

void ExteriaThemeStoreClassic(BOOL classic) {
    [[NSUserDefaults standardUserDefaults] setBool:classic && ExteriaClassicThemeAvailable() forKey:ExteriaClassicThemeKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: theme style was not saved");
}

BOOL ExteriaThemeIsClassic(void) { return ExteriaClassic; }

BOOL ExteriaThemeStoredDark(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:ExteriaDarkThemeKey];
}

void ExteriaThemeStoreDark(BOOL dark) {
    [[NSUserDefaults standardUserDefaults] setBool:dark forKey:ExteriaDarkThemeKey];
    /* each tone has a wallpaper of its own, and the hue of the client follows the one of the tone it moves to */
    ExteriaWallpaperSyncTintForTone(dark);
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: theme choice was not saved");
}

BOOL ExteriaThemeIsDark(void) { return ExteriaDark; }

BOOL ExteriaThemeStoredTint(float *hue) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:ExteriaTintOnKey]) return NO;
    if (hue) *hue = [defaults floatForKey:ExteriaTintHueKey];
    return YES;
}

void ExteriaThemeStoreTint(BOOL on, float hue) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:on forKey:ExteriaTintOnKey];
    [defaults setFloat:on ? hue : 0 forKey:ExteriaTintHueKey];
    if (![defaults synchronize]) NSLog(@"exteria: the theme tint was not saved");
}

BOOL ExteriaThemeStoredCustomTint(float *hue, float *saturation) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:ExteriaCustomTintOnKey]) return NO;
    if (hue) *hue = [defaults floatForKey:ExteriaCustomTintHueKey];
    if (saturation) *saturation = [defaults floatForKey:ExteriaCustomTintSaturationKey];
    return YES;
}

void ExteriaThemeStoreCustomTint(BOOL on, float hue, float saturation) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:on forKey:ExteriaCustomTintOnKey];
    [defaults setFloat:on ? fmodf(fmodf(hue, 360) + 360, 360) : 0 forKey:ExteriaCustomTintHueKey];
    [defaults setFloat:on ? MIN(1, MAX(0, saturation)) : 0 forKey:ExteriaCustomTintSaturationKey];
    /* the wallpaper of this tone takes the hue back when the color of your own is let go */
    if (!on) ExteriaWallpaperSyncTintForTone(ExteriaThemeStoredDark());
    if (![defaults synchronize]) NSLog(@"exteria: the custom color was not saved");
}

UIColor *ExteriaThemeCustomTintColor(float hue, float saturation) {
    CGFloat red, green, blue;
    /* the light accent of the palette: value 0.745 */
    ExteriaHSVToRGB(hue, saturation, 0.745, &red, &green, &blue);
    return [UIColor colorWithRed:red green:green blue:blue alpha:1];
}

/* ios 13 and later turn the default style into light content when the system is dark, and the app is not told; UIStatusBarStyleDarkContent (3) keeps the text
   black on the light theme. UIWindowScene marks the systems that know the value, older ones keep the default style */
UIStatusBarStyle ExteriaStatusBarStyle(BOOL dark) {
    if (dark) return (UIStatusBarStyle)1;
    return NSClassFromString(@"UIWindowScene") ? (UIStatusBarStyle)3 : UIStatusBarStyleDefault;
}

/* ios 5 to 6 call style 1 black translucent, ios 7 on call it light content; both are light text on a dark bar */
void ExteriaThemeApply(BOOL dark) {
    ExteriaDark = dark;
    ExteriaTintShift = 0;
    ExteriaTintScale = 1;
    ExteriaCustomTint = NO;
    ExteriaNeutralTint = NO;
    /* the login keeps its light waves, the signed in root restores the stored style */
    ExteriaClassic = NO;
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarStyle:animated:)]) {
        [application setStatusBarStyle:ExteriaStatusBarStyle(dark) animated:NO];
    }
}

void ExteriaThemeApplyStored(void) {
    ExteriaThemeApply(ExteriaThemeStoredDark());
    ExteriaImportedThemeReload(ExteriaThemeStoredDark());
    /* the hue is that of the wallpaper of the tone that is stored now, whatever the other tone left behind */
    ExteriaWallpaperSyncTintForTone(ExteriaThemeStoredDark());
    ExteriaClassic = ExteriaThemeStoredClassic();
    float hue = 0;
    BOOL tinted = ExteriaThemeStoredTint(&hue);
    ExteriaNeutralTint = tinted && hue == EXTERIA_WALLPAPER_NEUTRAL_HUE;
    ExteriaTintShift = tinted && !ExteriaNeutralTint ? (CGFloat)hue - EXTERIA_PALETTE_HUE : 0;
    ExteriaTintScale = 1;
    float customHue = 0, customSaturation = 0;
    ExteriaCustomTint = ExteriaThemeStoredCustomTint(&customHue, &customSaturation);
    if (ExteriaCustomTint) {
        ExteriaNeutralTint = NO;
        ExteriaTintShift = (CGFloat)customHue - EXTERIA_PALETTE_HUE;
        ExteriaTintScale = (CGFloat)customSaturation / EXTERIA_PALETTE_SATURATION;
    }
    if (!ExteriaClassic && ExteriaImportedThemeSelected(ExteriaDark)) {
        ExteriaTintShift = 0;
        ExteriaTintScale = 1;
        ExteriaNeutralTint = NO;
    }
    /* the classic bars are dark purple whatever the theme, so the status bar over them is light */
    UIApplication *application = [UIApplication sharedApplication];
    if (ExteriaClassic && [application respondsToSelector:@selector(setStatusBarStyle:animated:)]) [application setStatusBarStyle:(UIStatusBarStyle)1 animated:NO];
    else if ([application respondsToSelector:@selector(setStatusBarStyle:animated:)]) {
        NSString *status = ExteriaImportedThemeStatusBar();
        if (status) [application setStatusBarStyle:ExteriaStatusBarStyle([status isEqualToString:@"white"]) animated:NO];
    }
}

UIColor *ExteriaColorBackdrop(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.blocksBg"); if (color) return color; } if (ExteriaClassic || ExteriaDark) return ExteriaColorScreen(); return ExteriaRGB(242, 232, 249); }
UIColor *ExteriaColorScreen(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.plainBg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(24, 21, 32) : ExteriaRGB(247, 245, 251); return ExteriaDark ? ExteriaRGB(21, 18, 31) : ExteriaRGB(251, 250, 254); }
UIColor *ExteriaColorField(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.itemInputField.bg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(46, 41, 59) : ExteriaRGB(236, 232, 245); return ExteriaDark ? ExteriaRGB(43, 39, 62) : ExteriaRGB(237, 234, 248); }
UIColor *ExteriaColorCard(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.itemBlocksBg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(34, 30, 44) : [UIColor whiteColor]; return ExteriaDark ? ExteriaRGB(34, 30, 49) : ExteriaRGB(255, 255, 255); }
UIColor *ExteriaColorBar(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("root.navBar.background"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(38, 32, 52) : ExteriaRGB(253, 252, 254); return ExteriaDark ? ExteriaRGB(27, 23, 40) : ExteriaRGB(255, 255, 255); }
UIColor *ExteriaColorHairline(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("list.plainSeparator") : nil; if (color) return color; return ExteriaDark ? [UIColor colorWithWhite:1 alpha:0.09] : [UIColor colorWithWhite:0 alpha:0.1]; }
UIColor *ExteriaColorAccent(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("list.accent") : nil; if (color) return color; return ExteriaDark ? ExteriaRGB(172, 98, 222) : ExteriaRGB(164, 75, 190); }
UIColor *ExteriaColorAccentDark(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("root.navBar.button") : nil; return color ? color : ExteriaRGB(132, 44, 160); }
UIColor *ExteriaColorTitle(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("list.primaryText") : nil; if (color) return color; return ExteriaDark ? ExteriaRGB(240, 238, 248) : ExteriaRGB(34, 34, 38); }
UIColor *ExteriaColorMessage(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("chatList.messageText") : nil; if (color) return color; return ExteriaDark ? ExteriaRGB(176, 170, 196) : ExteriaRGB(86, 86, 92); }
UIColor *ExteriaColorDotOff(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("list.placeholderText") : nil; return color ? color : (ExteriaDark ? ExteriaRGB(84, 78, 104) : ExteriaRGB(208, 204, 212)); }
UIColor *ExteriaColorSecondary(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.secondaryText"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(172, 164, 190) : ExteriaRGB(116, 108, 132); return ExteriaDark ? ExteriaRGB(151, 143, 178) : ExteriaRGB(128, 112, 140); }
UIColor *ExteriaColorMuted(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("chatList.muteIcon"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(130, 122, 150) : ExteriaRGB(156, 148, 172); return ExteriaDark ? ExteriaRGB(108, 101, 134) : ExteriaRGB(176, 166, 186); }
UIColor *ExteriaColorBadgeRed(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("root.tabBar.badgeBackground") : nil; return color ? color : ExteriaRGB(230, 62, 72); }
UIColor *ExteriaColorQrPaper(void) { return ExteriaRGB(244, 236, 251); }
UIColor *ExteriaColorBubbleOut(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("chat.message.outgoing.bubble.withWp.bg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(65, 51, 84) : ExteriaRGB(235, 225, 249); return ExteriaDark ? ExteriaRGB(124, 70, 196) : ExteriaRGB(139, 80, 214); }
UIColor *ExteriaColorBubbleIn(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("chat.message.incoming.bubble.withWp.bg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(54, 47, 68) : [UIColor whiteColor]; return ExteriaDark ? ExteriaTurnedColor(0.14, 0.125, 0.2, 0.94) : [UIColor colorWithWhite:1 alpha:0.96]; }
UIColor *ExteriaColorBubbleCapsule(void) { return ExteriaTurnedColor(0.12, 0.1, 0.18, 0.5); }

void ExteriaThemePreviewColors(BOOL classic, BOOL dark, UIColor **incoming, UIColor **outgoing, UIColor **incomingText, UIColor **outgoingText) {
    BOOL wasClassic = ExteriaClassic, wasDark = ExteriaDark;
    ExteriaClassic = classic;
    ExteriaDark = dark;
    if (incoming) *incoming = ExteriaColorBubbleIn();
    if (outgoing) *outgoing = ExteriaColorBubbleOut();
    if (incomingText) *incomingText = ExteriaColorBubbleText(NO);
    if (outgoingText) *outgoingText = ExteriaColorBubbleText(YES);
    ExteriaClassic = wasClassic;
    ExteriaDark = wasDark;
}

UIColor *ExteriaColorChatBackground(void) {
    UIColor *imported = !ExteriaClassic ? ExteriaImportedThemeColor("chat.defaultWallpaper") : nil;
    if (imported) return imported;
    return ExteriaDark ? ExteriaRGB(25, 29, 36) : ExteriaRGB(218, 225, 233);
}

UIColor *ExteriaColorBubbleText(BOOL outgoing) {
    if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor(outgoing ? "chat.message.outgoing.primaryText" : "chat.message.incoming.primaryText"); if (color) return color; }
    return outgoing && !ExteriaClassic ? [UIColor whiteColor] : ExteriaColorTitle();
}

UIColor *ExteriaColorBubbleLink(BOOL outgoing) {
    if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor(outgoing ? "chat.message.outgoing.linkText" : "chat.message.incoming.linkText"); if (color) return color; }
    return outgoing && !ExteriaClassic ? [UIColor colorWithWhite:1 alpha:0.92] : ExteriaColorAccent();
}

UIColor *ExteriaColorBubbleMeta(BOOL outgoing) {
    if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor(outgoing ? "chat.message.outgoing.secondaryText" : "chat.message.incoming.secondaryText"); if (color) return color; }
    return outgoing && !ExteriaClassic ? [UIColor colorWithWhite:1 alpha:0.78] : ExteriaColorSecondary();
}

void ExteriaClassicBubbleColors(BOOL outgoing, UIColor **top, UIColor **bottom, UIColor **outline) {
    if (ExteriaDark) {
        *top = outgoing ? ExteriaRGB(118, 84, 158) : ExteriaRGB(78, 70, 96);
        *bottom = outgoing ? ExteriaRGB(86, 58, 124) : ExteriaRGB(58, 51, 74);
        *outline = outgoing ? ExteriaRGB(54, 34, 84) : ExteriaRGB(30, 26, 42);
    } else {
        *top = outgoing ? ExteriaRGB(236, 224, 252) : ExteriaRGB(255, 255, 255);
        *bottom = outgoing ? ExteriaRGB(210, 186, 242) : ExteriaRGB(240, 236, 247);
        *outline = outgoing ? ExteriaRGB(148, 116, 190) : ExteriaRGB(188, 178, 206);
    }
}

typedef enum { ExteriaWeightRegular, ExteriaWeightMedium, ExteriaWeightSemibold, ExteriaWeightBold } ExteriaWeight;

/* Apple licenses San Francisco for mock-ups only and bars embedding it, so only the system can supply it */
static UIFont *ExteriaSystemFont(ExteriaWeight weight, CGFloat size) {
    static const CGFloat weights[] = {0.0, 0.23, 0.3, 0.4};
    if (![UIFont respondsToSelector:NSSelectorFromString(@"monospacedDigitSystemFontOfSize:weight:")]) return nil;
    UIFont *(*weighted)(id, SEL, CGFloat, CGFloat) = (UIFont *(*)(id, SEL, CGFloat, CGFloat))objc_msgSend;
    return weighted([UIFont class], NSSelectorFromString(@"systemFontOfSize:weight:"), size, weights[weight]);
}

/* fonts are asked for in every cell layout and every bubble draw, and each lookup resolved the family by name again */
static UIFont *ExteriaFont(ExteriaWeight weight, CGFloat size) {
    static NSString *const names[] = {@"Inter-Regular", @"Inter-Medium", @"Inter-SemiBold", @"Inter-Bold"};
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)(size * 100 + 0.5) * 4 + (unsigned long long)weight];
    UIFont *cached = [[[cache objectForKey:key] retain] autorelease];
    if (cached) return cached;
    UIFont *font = ExteriaSystemFont(weight, size);
    if (!font) font = [UIFont fontWithName:names[weight] size:size];
    if (!font) font = weight == ExteriaWeightRegular ? [UIFont systemFontOfSize:size] : [UIFont boldSystemFontOfSize:size];
    if (font) [cache setObject:font forKey:key];
    return font;
}

UIFont *ExteriaFontRegular(CGFloat size) { return ExteriaFont(ExteriaWeightRegular, size); }
UIFont *ExteriaFontMedium(CGFloat size) { return ExteriaFont(ExteriaWeightMedium, size); }
UIFont *ExteriaFontSemibold(CGFloat size) { return ExteriaFont(ExteriaWeightSemibold, size); }
UIFont *ExteriaFontBold(CGFloat size) { return ExteriaFont(ExteriaWeightBold, size); }

UIColor *ExteriaMixedColor(UIColor *base, UIColor *tint, CGFloat share) {
    CGFloat b[4] = {0, 0, 0, 1}, t[4] = {0, 0, 0, 1};
    if (![base getRed:&b[0] green:&b[1] blue:&b[2] alpha:&b[3]]) {
        CGFloat white;
        if (![base getWhite:&white alpha:&b[3]]) return base;
        b[0] = b[1] = b[2] = white;
    }
    if (![tint getRed:&t[0] green:&t[1] blue:&t[2] alpha:&t[3]]) {
        CGFloat white;
        if (![tint getWhite:&white alpha:&t[3]]) return base;
        t[0] = t[1] = t[2] = white;
    }
    return [UIColor colorWithRed:b[0] + (t[0] - b[0]) * share green:b[1] + (t[1] - b[1]) * share blue:b[2] + (t[2] - b[2]) * share alpha:1];
}

UIColor *ExteriaColorOfRGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f green:((rgb >> 8) & 0xFF) / 255.0f blue:(rgb & 0xFF) / 255.0f alpha:1];
}
