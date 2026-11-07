#import "exteria_theme.h"

#import <objc/message.h>

#import "exteria_font_choice.h"
#import "exteria_imported_theme.h"

#include <math.h>

/* the palette is purple, and a color of your own can turn every hue of it: the turn in degrees, zero for the purple of the app */
static CGFloat ExteriaTintShift = 0;
static BOOL ExteriaDark = NO;
/* grows with every change of the palette, so what was made in the colors of an earlier one can be told from what was made in these */
static NSUInteger ExteriaRevision = 1;

NSUInteger ExteriaThemeRevision(void) { return ExteriaRevision; }
static BOOL ExteriaClassic = NO;
/* how many times the saturation of the palette is multiplied; a color of your own sets it */
static CGFloat ExteriaTintScale = 1;
/* a color of your own is stored: palettes with a seed of their own follow it even when it lands on the hue of the app */
static BOOL ExteriaCustomTint = NO;
/* how much of the value of the colors of your own a palette keeps: 1 is the palette, 0 is black. The accents, the screens, the bars, the cards and the bubbles take it (see ExteriaDimRGB); the text colors never do, so the words stay readable */
static CGFloat ExteriaTintBrightness = 1;
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

/* the color with its hue turned to the color of your own; greys stay grey, since the turn leaves the saturation alone */
static UIColor *ExteriaTurnedColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    if (ExteriaTintShift != 0 || ExteriaTintScale != 1) {
        CGFloat h, s, v;
        ExteriaRGBToHSV(red, green, blue, &h, &s, &v);
        if (s > 0) {
            ExteriaHSVToRGB(h + ExteriaTintShift + 360, MIN(1, s * ExteriaTintScale), v, &red, &green, &blue);
        }
    }
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

/* the brightness of a color of your own taken by a surface. A dark color keeps its share of the value, and a light one is dimmed less, down to six tenths of itself, since the
   words on it are dark and a light screen turned dark would hide them. At full brightness it does nothing */
static void ExteriaDimRGB(CGFloat *red, CGFloat *green, CGFloat *blue) {
    if (ExteriaTintBrightness >= 1) return;
    CGFloat h, s, v;
    ExteriaRGBToHSV(*red, *green, *blue, &h, &s, &v);
    CGFloat scale = v > 0.7 ? 0.6 + 0.4 * ExteriaTintBrightness : ExteriaTintBrightness;
    ExteriaHSVToRGB(h, s, v * scale, red, green, blue);
}

/* a surface of the palette: turned to the color of your own, then dimmed by its brightness */
static UIColor *ExteriaSurface(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    UIColor *turned = ExteriaTurnedColor(red, green, blue, alpha);
    if (ExteriaTintBrightness >= 1) return turned;
    const CGFloat *c = CGColorGetComponents(turned.CGColor);
    if (CGColorGetNumberOfComponents(turned.CGColor) != 4) return turned;
    CGFloat r = c[0], g = c[1], b = c[2];
    ExteriaDimRGB(&r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:c[3]];
}

UIColor *ExteriaThemeTinted(UIColor *color) {
    if (ExteriaTintShift == 0 && ExteriaTintScale == 1 && ExteriaTintBrightness >= 1) return color;
    CGColorRef ref = color.CGColor;
    const CGFloat *c = CGColorGetComponents(ref);
    size_t count = CGColorGetNumberOfComponents(ref);
    if (count == 4) return ExteriaSurface(c[0], c[1], c[2], c[3]);
    return color;
}

/* a palette with a seed hue of its own (the Shiro screens) moved to the accent of the app: the seed hue goes to the hue the accent has now, saturation follows a color
   of your own, and a grey accent makes the palette grey. The palette keeps its own colors when no color of your own is stored */
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
    } else if (ExteriaCustomTint) {
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
    /* a palette that follows a color of your own follows its brightness as well, but not that of an imported theme, which has its own */
    if (!imported) ExteriaDimRGB(&red, &green, &blue);
    return [UIColor colorWithRed:red green:green blue:blue alpha:c[3]];
}

static UIColor *ExteriaRGB(CGFloat red, CGFloat green, CGFloat blue) {
    return ExteriaTurnedColor(red / 255.0, green / 255.0, blue / 255.0, 1.0);
}

/* the same for a surface, which takes the brightness */
static UIColor *ExteriaSurfaceRGB(CGFloat red, CGFloat green, CGFloat blue) {
    return ExteriaSurface(red / 255.0, green / 255.0, blue / 255.0, 1.0);
}

static NSString *const ExteriaClassicThemeKey = @"ExteriaClassicTheme";
static NSString *const ExteriaDarkThemeKey = @"ExteriaDarkTheme";
static NSString *const ExteriaCustomTintOnKey = @"ExteriaThemeCustomTintOn";
static NSString *const ExteriaCustomTintHueKey = @"ExteriaThemeCustomTintHue";
static NSString *const ExteriaCustomTintSaturationKey = @"ExteriaThemeCustomTintSaturation";
static NSString *const ExteriaCustomTintBrightnessKey = @"ExteriaThemeCustomTintBrightness";
NSString *const ExteriaThemeDidChangeNotification = @"ExteriaThemeDidChangeNotification";
NSString *const ExteriaThemeOriginKey = @"origin";

NSString *const ExteriaClassicAnywhereKey = @"exteria.developer.classicAnywhere";

BOOL ExteriaClassicThemeAvailable(void) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:ExteriaClassicAnywhereKey]) return YES;
    return [[[UIDevice currentDevice] systemVersion] integerValue] <= 10;
}

/* ios 5 and 6 have no flat ui, so the modern style looks foreign there; until the person picks a style, 6 and older get the classic one */
BOOL ExteriaThemeStoredClassic(void) {
    if (!ExteriaClassicThemeAvailable()) return NO;
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:ExteriaClassicThemeKey];
    if (!stored) return [[[UIDevice currentDevice] systemVersion] integerValue] <= 6;
    return [stored boolValue];
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
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: theme choice was not saved");
}

BOOL ExteriaThemeIsDark(void) { return ExteriaDark; }

BOOL ExteriaThemeStoredCustomTint(float *hue, float *saturation, float *brightness) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:ExteriaCustomTintOnKey]) return NO;
    if (hue) *hue = [defaults floatForKey:ExteriaCustomTintHueKey];
    if (saturation) *saturation = [defaults floatForKey:ExteriaCustomTintSaturationKey];
    if (brightness) *brightness = [defaults objectForKey:ExteriaCustomTintBrightnessKey] ? MIN(1, MAX(0, [defaults floatForKey:ExteriaCustomTintBrightnessKey])) : 1;
    return YES;
}

void ExteriaThemeStoreCustomTint(float hue, float saturation, float brightness) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:ExteriaCustomTintOnKey];
    [defaults setFloat:fmodf(fmodf(hue, 360) + 360, 360) forKey:ExteriaCustomTintHueKey];
    [defaults setFloat:MIN(1, MAX(0, saturation)) forKey:ExteriaCustomTintSaturationKey];
    [defaults setFloat:MIN(1, MAX(0, brightness)) forKey:ExteriaCustomTintBrightnessKey];
    if (![defaults synchronize]) NSLog(@"exteria: the custom color was not saved");
}

UIColor *ExteriaThemeCustomTintColor(float hue, float saturation, float brightness) {
    CGFloat red, green, blue;
    /* the light accent of the palette: value 0.745 */
    ExteriaHSVToRGB(hue, saturation, 0.745 * MIN(1, MAX(0, brightness)), &red, &green, &blue);
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
    ++ExteriaRevision;
    ExteriaDark = dark;
    ExteriaTintShift = 0;
    ExteriaTintScale = 1;
    ExteriaCustomTint = NO;
    ExteriaTintBrightness = 1;
    /* the login keeps its light waves, the signed in root restores the stored style */
    ExteriaClassic = NO;
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarStyle:animated:)]) {
        [application setStatusBarStyle:ExteriaStatusBarStyle(dark) animated:NO];
    }
}

void ExteriaThemeApplyStored(void) {
    ++ExteriaRevision;
    ExteriaThemeApply(ExteriaThemeStoredDark());
    ExteriaImportedThemeReload(ExteriaThemeStoredDark());
    ExteriaClassic = ExteriaThemeStoredClassic();
    ExteriaTintScale = 1;
    float customHue = 0, customSaturation = 0, customBrightness = 1;
    ExteriaCustomTint = ExteriaThemeStoredCustomTint(&customHue, &customSaturation, &customBrightness);
    if (ExteriaCustomTint) {
        ExteriaTintBrightness = customBrightness;
        ExteriaTintShift = (CGFloat)customHue - EXTERIA_PALETTE_HUE;
        ExteriaTintScale = (CGFloat)customSaturation / EXTERIA_PALETTE_SATURATION;
    }
    if (!ExteriaClassic && ExteriaImportedThemeSelected(ExteriaDark)) {
        ExteriaTintShift = 0;
        ExteriaTintScale = 1;
        ExteriaTintBrightness = 1;
    }
    /* the classic bars are dark purple whatever the theme, so the status bar over them is light */
    UIApplication *application = [UIApplication sharedApplication];
    if (ExteriaClassic && [application respondsToSelector:@selector(setStatusBarStyle:animated:)]) [application setStatusBarStyle:(UIStatusBarStyle)1 animated:NO];
    else if ([application respondsToSelector:@selector(setStatusBarStyle:animated:)]) {
        NSString *status = ExteriaImportedThemeStatusBar();
        if (status) [application setStatusBarStyle:ExteriaStatusBarStyle([status isEqualToString:@"white"]) animated:NO];
    }
}

/* an accent color of the palette: turned to the color of your own, then dimmed by its brightness */
static UIColor *ExteriaAccentRGB(CGFloat red, CGFloat green, CGFloat blue) {
    UIColor *turned = ExteriaRGB(red, green, blue);
    if (ExteriaTintBrightness >= 1) return turned;
    const CGFloat *c = CGColorGetComponents(turned.CGColor);
    if (CGColorGetNumberOfComponents(turned.CGColor) != 4) return turned;
    CGFloat h, s, v, r, g, b;
    ExteriaRGBToHSV(c[0], c[1], c[2], &h, &s, &v);
    ExteriaHSVToRGB(h, s, v * ExteriaTintBrightness, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:c[3]];
}

UIColor *ExteriaColorBackdrop(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.blocksBg"); if (color) return color; } if (ExteriaClassic || ExteriaDark) return ExteriaColorScreen(); return ExteriaSurfaceRGB(242, 232, 249); }
UIColor *ExteriaColorScreen(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.plainBg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaSurfaceRGB(24, 21, 32) : ExteriaSurfaceRGB(247, 245, 251); return ExteriaDark ? ExteriaSurfaceRGB(21, 18, 31) : ExteriaSurfaceRGB(251, 250, 254); }
UIColor *ExteriaColorField(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.itemInputField.bg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaSurfaceRGB(46, 41, 59) : ExteriaSurfaceRGB(236, 232, 245); return ExteriaDark ? ExteriaSurfaceRGB(43, 39, 62) : ExteriaSurfaceRGB(237, 234, 248); }
UIColor *ExteriaColorCard(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.itemBlocksBg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaSurfaceRGB(34, 30, 44) : ExteriaSurfaceRGB(255, 255, 255); return ExteriaDark ? ExteriaSurfaceRGB(34, 30, 49) : ExteriaSurfaceRGB(255, 255, 255); }
UIColor *ExteriaColorBar(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("root.navBar.background"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaSurfaceRGB(38, 32, 52) : ExteriaSurfaceRGB(253, 252, 254); return ExteriaDark ? ExteriaSurfaceRGB(27, 23, 40) : ExteriaSurfaceRGB(255, 255, 255); }
UIColor *ExteriaColorHairline(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("list.plainSeparator") : nil; if (color) return color; return ExteriaDark ? [UIColor colorWithWhite:1 alpha:0.09] : [UIColor colorWithWhite:0 alpha:0.1]; }
UIColor *ExteriaColorAccent(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("list.accent") : nil; if (color) return color; return ExteriaDark ? ExteriaAccentRGB(172, 98, 222) : ExteriaAccentRGB(164, 75, 190); }
UIColor *ExteriaColorAccentDark(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("root.navBar.button") : nil; return color ? color : ExteriaAccentRGB(132, 44, 160); }
UIColor *ExteriaColorTitle(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("list.primaryText") : nil; if (color) return color; return ExteriaDark ? ExteriaRGB(240, 238, 248) : ExteriaRGB(34, 34, 38); }
UIColor *ExteriaColorMessage(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("chatList.messageText") : nil; if (color) return color; return ExteriaDark ? ExteriaRGB(176, 170, 196) : ExteriaRGB(86, 86, 92); }
UIColor *ExteriaColorDotOff(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("list.placeholderText") : nil; return color ? color : (ExteriaDark ? ExteriaRGB(84, 78, 104) : ExteriaRGB(208, 204, 212)); }
UIColor *ExteriaColorSecondary(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("list.secondaryText"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(172, 164, 190) : ExteriaRGB(116, 108, 132); return ExteriaDark ? ExteriaRGB(151, 143, 178) : ExteriaRGB(128, 112, 140); }
UIColor *ExteriaColorMuted(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("chatList.muteIcon"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaRGB(130, 122, 150) : ExteriaRGB(156, 148, 172); return ExteriaDark ? ExteriaRGB(108, 101, 134) : ExteriaRGB(176, 166, 186); }
UIColor *ExteriaColorBadgeRed(void) { UIColor *color = !ExteriaClassic ? ExteriaImportedThemeColor("root.tabBar.badgeBackground") : nil; return color ? color : ExteriaRGB(230, 62, 72); }
UIColor *ExteriaColorQrPaper(void) { return ExteriaRGB(244, 236, 251); }
UIColor *ExteriaColorBubbleOut(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("chat.message.outgoing.bubble.withWp.bg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaSurfaceRGB(65, 51, 84) : ExteriaSurfaceRGB(235, 225, 249); return ExteriaDark ? ExteriaAccentRGB(124, 70, 196) : ExteriaAccentRGB(139, 80, 214); }
UIColor *ExteriaColorBubbleIn(void) { if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor("chat.message.incoming.bubble.withWp.bg"); if (color) return color; } if (ExteriaClassic) return ExteriaDark ? ExteriaSurfaceRGB(54, 47, 68) : ExteriaSurfaceRGB(255, 255, 255); return ExteriaDark ? ExteriaSurface(0.14, 0.125, 0.2, 0.94) : ExteriaSurface(1, 1, 1, 0.96); }
UIColor *ExteriaColorBubbleCapsule(void) { return ExteriaSurface(0.12, 0.1, 0.18, 0.5); }

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
    if (outgoing && ExteriaClassic) {
        /* the classic outgoing bubble is lit in the accent, so a link in the accent itself vanished into it; a light tint of the accent stays a color and reads on it */
        return ExteriaMixedColor(ExteriaColorAccent(), [UIColor whiteColor], 0.82);
    }
    return outgoing ? [UIColor colorWithWhite:1 alpha:0.92] : ExteriaColorAccent();
}

UIColor *ExteriaColorBubbleMeta(BOOL outgoing) {
    if (!ExteriaClassic) { UIColor *color = ExteriaImportedThemeColor(outgoing ? "chat.message.outgoing.secondaryText" : "chat.message.incoming.secondaryText"); if (color) return color; }
    return outgoing && !ExteriaClassic ? [UIColor colorWithWhite:1 alpha:0.78] : ExteriaColorSecondary();
}

/* the bubbles are lit from above in the accent of the theme: top is the lit edge, bottom the color the picture is filled with and the light that bounces up from the lower
   edge, outline the dark rim. the colors follow the accent, so a color of the person's own reaches the bubbles */
void ExteriaClassicBubbleColors(BOOL outgoing, UIColor **top, UIColor **bottom, UIColor **outline) {
    UIColor *accent = ExteriaColorAccent();
    UIColor *white = [UIColor whiteColor], *black = [UIColor blackColor];
    if (ExteriaDark) {
        if (outgoing) {
            *top = ExteriaMixedColor(accent, white, 0.10);
            *bottom = ExteriaMixedColor(accent, black, 0.34);
            *outline = ExteriaMixedColor(accent, black, 0.68);
        } else {
            UIColor *grey = [UIColor colorWithWhite:0.3 alpha:1];
            *top = ExteriaMixedColor(grey, accent, 0.16);
            *bottom = ExteriaMixedColor([UIColor colorWithWhite:0.2 alpha:1], accent, 0.14);
            *outline = ExteriaMixedColor([UIColor colorWithWhite:0.06 alpha:1], accent, 0.12);
        }
    } else if (outgoing) {
        *top = ExteriaMixedColor(accent, white, 0.74);
        *bottom = ExteriaMixedColor(accent, white, 0.52);
        *outline = ExteriaMixedColor(accent, black, 0.45);
    } else {
        *top = white;
        *bottom = ExteriaMixedColor([UIColor colorWithWhite:0.9 alpha:1], accent, 0.07);
        *outline = ExteriaMixedColor([UIColor colorWithWhite:0.52 alpha:1], accent, 0.28);
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
static NSCache *ExteriaFontCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    return cache;
}

void ExteriaFontsDidChange(void) {
    [ExteriaFontCache() removeAllObjects];
}

static NSString *const ExteriaInterfaceScaleKey = @"exteria.interface.scale";

NSInteger ExteriaInterfaceScaleStored(void) {
    NSNumber *stored = [[NSUserDefaults standardUserDefaults] objectForKey:ExteriaInterfaceScaleKey];
    if (![stored isKindOfClass:[NSNumber class]]) return 100;
    NSInteger percent = stored.integerValue;
    return percent < EXTERIA_INTERFACE_SCALE_MIN ? EXTERIA_INTERFACE_SCALE_MIN : (percent > EXTERIA_INTERFACE_SCALE_MAX ? EXTERIA_INTERFACE_SCALE_MAX : percent);
}

/* every font and row height asks for the scale, so it is kept in a variable and not read from the defaults each time; zero means not read yet */
static CGFloat ExteriaScaleNow;

void ExteriaInterfaceScaleStore(NSInteger percent) {
    percent = percent < EXTERIA_INTERFACE_SCALE_MIN ? EXTERIA_INTERFACE_SCALE_MIN : (percent > EXTERIA_INTERFACE_SCALE_MAX ? EXTERIA_INTERFACE_SCALE_MAX : percent);
    [[NSUserDefaults standardUserDefaults] setInteger:percent forKey:ExteriaInterfaceScaleKey];
    ExteriaScaleNow = (CGFloat)percent / 100.0f;
}

CGFloat ExteriaInterfaceScale(void) {
    if (ExteriaScaleNow <= 0) ExteriaScaleNow = (CGFloat)ExteriaInterfaceScaleStored() / 100.0f;
    return ExteriaScaleNow;
}

static UIFont *ExteriaFont(ExteriaWeight weight, CGFloat size) {
    static NSString *const names[] = {@"Inter-Regular", @"Inter-Medium", @"Inter-SemiBold", @"Inter-Bold"};
    size *= ExteriaInterfaceScale();
    NSCache *cache = ExteriaFontCache();
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)(size * 100 + 0.5) * 4 + (unsigned long long)weight];
    UIFont *cached = [[[cache objectForKey:key] retain] autorelease];
    if (cached) return cached;
    UIFont *font = ExteriaFontChoiceFont((int)weight, size);
    if (!font) font = ExteriaSystemFont(weight, size);
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
