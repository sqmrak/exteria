#import "exteria_settings_kit.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_chat_settings.h"
#import "exteria_classic_chrome.h"
#import "exteria_expressive_slider.h"
#import "exteria_platform.h"
#import "exteria_split_controller.h"
#import "exteria_sheet.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"
#import "exteria_wave_background_view.h"

#define BAR_HEIGHT 56.0
#define CARD_INSET 12.0
/* the corner of a card is the one the person chose in the look of the app */
#define CARD_RADIUS ExteriaSectionRadius()
#define INNER_RADIUS 6.0
#define ROW_GAP 2.0
#define ICON_PAD 18.0
#define TILE 36.0
#define TRAILING_SIDE 34.0
#define SESSION_ICON 42.0

#pragma mark tones

static UIColor *ExteriaToneRGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

/* IconBackgroundColors, top and bottom */
static void ExteriaToneEnds(ExteriaSettingsTone tone, uint32_t *top, uint32_t *bottom) {
    static const uint32_t table[][2] = {
        {0x1CA5ED, 0x1488E1}, {0x4F85F6, 0x3568E8}, {0x1BA4ED, 0x1488E1}, {0xF09F1B, 0xE18A11}, {0xEFA612, 0xE77512},
        {0xF28B31, 0xE26314}, {0x55CA47, 0x27B434}, {0xF45255, 0xDF3955}, {0x32C0CE, 0x1D9CC6}, {0xC46EF4, 0x9F55DF}, {0x8699AA, 0x6E8397}
    };
    *top = table[tone][0];
    *bottom = table[tone][1];
}

static UIColor *ExteriaMix(UIColor *color, CGFloat white, CGFloat amount) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [UIColor colorWithRed:r + (white - r) * amount green:g + (white - g) * amount blue:b + (white - b) * amount alpha:1];
}

UIImage *ExteriaSettingsTileImage(ExteriaSymbol symbol, ExteriaSettingsTone tone, CGFloat side) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    BOOL dark = ExteriaThemeIsDark();
    NSString *key = [NSString stringWithFormat:@"%d/%d/%g/%d", (int)symbol, (int)tone, (double)side, dark];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    uint32_t top, bottom;
    ExteriaToneEnds(tone, &top, &bottom);
    UIColor *middle = ExteriaMix(ExteriaToneRGB(top), 0, 0);
    CGFloat r1 = 0, g1 = 0, b1 = 0, r2 = 0, g2 = 0, b2 = 0, a = 0;
    [ExteriaToneRGB(top) getRed:&r1 green:&g1 blue:&b1 alpha:&a];
    [ExteriaToneRGB(bottom) getRed:&r2 green:&g2 blue:&b2 alpha:&a];
    middle = [UIColor colorWithRed:(r1 + r2) / 2 green:(g1 + g2) / 2 blue:(b1 + b2) / 2 alpha:1];
    /* a pale disc with a deep glyph: the tonal pair the M3 list takes from the two colors of the tone */
    UIColor *disc = dark ? ExteriaMix(middle, 1, 0.56) : ExteriaMix(middle, 1, 0.80);
    UIColor *ink = dark ? ExteriaMix(middle, 0, 0.42) : ExteriaMix(middle, 0, 0.12);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [disc setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
    UIImage *glyph = ExteriaSymbolImage(symbol, floor(side * 0.62), ink);
    [glyph drawAtPoint:CGPointMake((side - glyph.size.width) / 2, (side - glyph.size.height) / 2)];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}

/* the outline of the mark, in the units of the vector: absolute M, L, C and Z commands */
static const char ExteriaMarkPath[] =
    "M122.661 123.5L261.364 67.4608C279.286 60.2198 287.945 39.8198 280.704 21.8978C273.463 3.97575 253.064 -4.68325 235.141 2.55775L21.8888 88.7168"
    "C15.0532 91.4785 9.26419 96.3283 5.34756 102.574C1.43092 108.82 -0.413356 116.144 0.0777699 123.5C-0.413356 130.856 1.43092 138.179 5.34756 144.425"
    "C9.26419 150.671 15.0532 155.521 21.8888 158.283L235.141 244.442C253.064 251.683 273.463 243.024 280.704 225.102C287.945 207.179 279.286 186.78 261.364 179.539Z";

/* reads the numbers after a command letter; the path above is fixed text, so a malformed one is a build mistake and ends the walk */
static void ExteriaWalkMarkPath(CGMutablePathRef path, CGAffineTransform place) {
    const char *at = ExteriaMarkPath;
    char command = 0;
    double v[6];
    while (*at) {
        if (*at == 'M' || *at == 'L' || *at == 'C' || *at == 'Z') command = *at++;
        else break;
        int need = command == 'C' ? 6 : (command == 'Z' ? 0 : 2);
        do {
            for (int i = 0; i < need; ++i) {
                char *end = NULL;
                v[i] = strtod(at, &end);
                if (end == at) return;
                at = end;
            }
            if (command == 'M') CGPathMoveToPoint(path, &place, (CGFloat)v[0], (CGFloat)v[1]);
            else if (command == 'L') CGPathAddLineToPoint(path, &place, (CGFloat)v[0], (CGFloat)v[1]);
            else if (command == 'C') CGPathAddCurveToPoint(path, &place, (CGFloat)v[0], (CGFloat)v[1], (CGFloat)v[2], (CGFloat)v[3], (CGFloat)v[4], (CGFloat)v[5]);
            else CGPathCloseSubpath(path);
        } while (need && (*at == '-' || *at == '.' || (*at >= '0' && *at <= '9')));
    }
}

UIImage *ExteriaSettingsMarkTile(CGFloat side) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    NSString *key = [NSString stringWithFormat:@"%g", (double)side];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [[UIColor colorWithRed:0x99 / 255.0 green:0x3C / 255.0 blue:0x38 / 255.0 alpha:1] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
    /* the vector is 24 units wide, and its group moves the mark by 4.5 and 5.477 and shrinks it by 0.052817 */
    CGFloat unit = side / 24.0;
    CGMutablePathRef path = CGPathCreateMutable();
    ExteriaWalkMarkPath(path, CGAffineTransformMake(0.052817 * unit, 0, 0, 0.052817 * unit, 4.5 * unit, 5.477 * unit));
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextAddPath(context, path);
    CGPathRelease(path);
    [[UIColor whiteColor] setFill];
    CGContextFillPath(context);
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}

#pragma mark devices

/* the avatar colors theme, top and bottom */
static void ExteriaDeviceEnds(exteria_session_kind kind, uint32_t *top, uint32_t *bottom) {
    switch (kind) {
    case EXTERIA_SESSION_IPHONE:
    case EXTERIA_SESSION_IPAD:
    case EXTERIA_SESSION_LINUX:
    case EXTERIA_SESSION_UBUNTU:
        *top = 0x5CAFFA; *bottom = 0x408ACF; return;
    case EXTERIA_SESSION_MAC:
    case EXTERIA_SESSION_WINDOWS:
    case EXTERIA_SESSION_DESKTOP:
        *top = 0x5BCBE3; *bottom = 0x359AD4; return;
    case EXTERIA_SESSION_ANDROID:
    case EXTERIA_SESSION_ANDROID_TABLET:
        *top = 0x9AD164; *bottom = 0x46BA43; return;
    default:
        *top = 0xFF8AAC; *bottom = 0xD95574; return;
    }
}

static ExteriaSymbol ExteriaDeviceGlyph(exteria_session_kind kind) {
    switch (kind) {
    case EXTERIA_SESSION_IPHONE: return ExteriaSymbolDeviceIphone;
    case EXTERIA_SESSION_IPAD: return ExteriaSymbolDeviceIpad;
    case EXTERIA_SESSION_MAC: return ExteriaSymbolDeviceMac;
    case EXTERIA_SESSION_WINDOWS: return ExteriaSymbolDeviceWindows;
    case EXTERIA_SESSION_LINUX:
    case EXTERIA_SESSION_UBUNTU:
    case EXTERIA_SESSION_DESKTOP: return ExteriaSymbolDeviceDesktop;
    case EXTERIA_SESSION_ANDROID: return ExteriaSymbolDeviceAndroid;
    case EXTERIA_SESSION_ANDROID_TABLET: return ExteriaSymbolDeviceAndroidTablet;
    case EXTERIA_SESSION_CHROME: return ExteriaSymbolDeviceChrome;
    case EXTERIA_SESSION_SAFARI: return ExteriaSymbolDeviceSafari;
    case EXTERIA_SESSION_EDGE: return ExteriaSymbolDeviceEdge;
    case EXTERIA_SESSION_FIREFOX: return ExteriaSymbolDeviceFirefox;
    case EXTERIA_SESSION_OPERA: return ExteriaSymbolDeviceOpera;
    default: return ExteriaSymbolDeviceWeb;
    }
}

UIImage *ExteriaDeviceIconImage(exteria_session_kind kind, CGFloat side) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    NSString *key = [NSString stringWithFormat:@"%d/%g", (int)kind, (double)side];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    uint32_t top, bottom;
    ExteriaDeviceEnds(kind, &top, &bottom);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, CGRectMake(0, 0, side, side));
    CGContextClip(context);
    CGFloat r1 = 0, g1 = 0, b1 = 0, r2 = 0, g2 = 0, b2 = 0, a = 0;
    [ExteriaToneRGB(top) getRed:&r1 green:&g1 blue:&b1 alpha:&a];
    [ExteriaToneRGB(bottom) getRed:&r2 green:&g2 blue:&b2 alpha:&a];
    CGFloat colors[] = {r1, g1, b1, 1, r2, g2, b2, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, side), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(context);
    UIImage *glyph = ExteriaSymbolImage(ExteriaDeviceGlyph(kind), floor(side * 0.62), [UIColor whiteColor]);
    [glyph drawAtPoint:CGPointMake((side - glyph.size.width) / 2, (side - glyph.size.height) / 2)];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}

UIColor *ExteriaDeviceColor(exteria_session_kind kind) {
    switch (kind) {
    case EXTERIA_SESSION_FIREFOX: return ExteriaToneRGB(0xFF845E);
    case EXTERIA_SESSION_IPHONE:
    case EXTERIA_SESSION_IPAD:
    case EXTERIA_SESSION_LINUX:
    case EXTERIA_SESSION_UBUNTU: return ExteriaToneRGB(0x5CAFFA);
    case EXTERIA_SESSION_MAC:
    case EXTERIA_SESSION_WINDOWS:
    case EXTERIA_SESSION_DESKTOP: return ExteriaToneRGB(0x5BCBE3);
    case EXTERIA_SESSION_ANDROID:
    case EXTERIA_SESSION_ANDROID_TABLET: return ExteriaToneRGB(0x9AD164);
    default: return ExteriaToneRGB(0xFF8AAC);
    }
}

NSString *ExteriaDeviceAnimationName(exteria_session_kind kind) {
    switch (kind) {
    case EXTERIA_SESSION_IPHONE: return @"device_iphone";
    case EXTERIA_SESSION_IPAD: return @"device_ipad";
    case EXTERIA_SESSION_MAC: return @"device_mac";
    case EXTERIA_SESSION_WINDOWS:
    case EXTERIA_SESSION_DESKTOP: return @"device_windows";
    case EXTERIA_SESSION_LINUX: return @"device_linux";
    case EXTERIA_SESSION_UBUNTU: return @"device_ubuntu";
    case EXTERIA_SESSION_ANDROID:
    case EXTERIA_SESSION_ANDROID_TABLET: return @"device_android";
    case EXTERIA_SESSION_CHROME:
    case EXTERIA_SESSION_OTHER: return @"device_chrome";
    case EXTERIA_SESSION_SAFARI: return @"device_safari";
    case EXTERIA_SESSION_EDGE: return @"device_edge";
    case EXTERIA_SESSION_FIREFOX: return @"device_firefox";
    default: return nil;
    }
}

#pragma mark models

@implementation ExteriaSettingsRow

@synthesize hasSymbol = _hasSymbol;
@synthesize symbol = _symbol;
@synthesize tone = _tone;
@synthesize title = _title;
@synthesize subtitle = _subtitle;
@synthesize value = _value;
@synthesize line3 = _line3;
@synthesize picture = _picture;
@synthesize tileImage = _tileImage;
@synthesize trailingImage = _trailingImage;
@synthesize customView = _customView;
@synthesize customHeight = _customHeight;
@synthesize bold = _bold;
@synthesize destructive = _destructive;
@synthesize hasSwitch = _hasSwitch;
@synthesize on = _on;
@synthesize accentLine3 = _accentLine3;
@synthesize checked = _checked;
@synthesize disabled = _disabled;
@synthesize hasLevel = _hasLevel;
@synthesize leftCaption = _leftCaption;
@synthesize rightCaption = _rightCaption;
@synthesize describe = _describe;
@synthesize hasSlider = _hasSlider;
@synthesize sliderValue = _sliderValue;
@synthesize sliderMinimum = _sliderMinimum;
@synthesize sliderMaximum = _sliderMaximum;
@synthesize sliderFormat = _sliderFormat;
@synthesize tap = _tap;
@synthesize toggle = _toggle;
@synthesize slide = _slide;

- (void)dealloc {
    [_describe release];
    [_leftCaption release];
    [_rightCaption release];
    [_sliderFormat release];
    [_slide release];
    [_title release];
    [_subtitle release];
    [_value release];
    [_line3 release];
    [_picture release];
    [_tileImage release];
    [_trailingImage release];
    [_customView release];
    [_customHeight release];
    [_tap release];
    [_toggle release];
    [super dealloc];
}

- (BOOL)isSession { return _picture != nil; }

+ (ExteriaSettingsRow *)rowWithSymbol:(ExteriaSymbol)symbol tone:(ExteriaSettingsTone)tone title:(NSString *)title subtitle:(NSString *)subtitle
                                value:(NSString *)value tap:(void (^)(void))tap {
    ExteriaSettingsRow *row = [[[ExteriaSettingsRow alloc] init] autorelease];
    row->_hasSymbol = YES;
    row->_symbol = symbol;
    row->_tone = tone;
    row->_title = [title copy];
    row->_subtitle = [subtitle copy];
    row->_value = [value copy];
    row->_tap = [tap copy];
    return row;
}

+ (ExteriaSettingsRow *)rowWithTileImage:(UIImage *)image title:(NSString *)title subtitle:(NSString *)subtitle tap:(void (^)(void))tap {
    ExteriaSettingsRow *row = [[[ExteriaSettingsRow alloc] init] autorelease];
    row->_tileImage = [image retain];
    row->_title = [title copy];
    row->_subtitle = [subtitle copy];
    row->_tap = [tap copy];
    return row;
}

+ (ExteriaSettingsRow *)rowWithTitle:(NSString *)title value:(NSString *)value tap:(void (^)(void))tap {
    ExteriaSettingsRow *row = [[[ExteriaSettingsRow alloc] init] autorelease];
    row->_title = [title copy];
    row->_value = [value copy];
    row->_tap = [tap copy];
    return row;
}

+ (ExteriaSettingsRow *)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle value:(NSString *)value tap:(void (^)(void))tap {
    ExteriaSettingsRow *row = [ExteriaSettingsRow rowWithTitle:title value:value tap:tap];
    row->_subtitle = [subtitle copy];
    return row;
}

+ (ExteriaSettingsRow *)checkRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle checked:(BOOL)checked tap:(void (^)(void))tap {
    ExteriaSettingsRow *row = [ExteriaSettingsRow rowWithTitle:title subtitle:subtitle value:nil tap:tap];
    row->_checked = checked;
    return row;
}

+ (ExteriaSettingsRow *)sliderRowWithTitle:(NSString *)title format:(NSString *)format value:(float)value minimum:(float)minimum maximum:(float)maximum
                                    change:(void (^)(float))change {
    ExteriaSettingsRow *row = [[[ExteriaSettingsRow alloc] init] autorelease];
    row->_title = [title copy];
    row->_sliderFormat = [format copy];
    row->_value = [[NSString stringWithFormat:format, (double)value] copy];
    row->_hasSlider = YES;
    row->_sliderValue = value;
    row->_sliderMinimum = minimum;
    row->_sliderMaximum = maximum;
    row->_slide = [change copy];
    return row;
}

+ (ExteriaSettingsRow *)viewRowWithView:(UIView *)view height:(CGFloat (^)(CGFloat))height {
    ExteriaSettingsRow *row = [[[ExteriaSettingsRow alloc] init] autorelease];
    row->_customView = [view retain];
    row->_customHeight = [height copy];
    return row;
}

+ (ExteriaSettingsRow *)levelRowWithTitle:(NSString *)title leftCaption:(NSString *)left rightCaption:(NSString *)right percent:(int)percent
                                  describe:(NSDictionary *(^)(int))describe change:(void (^)(int))change {
    ExteriaSettingsRow *row = [[[ExteriaSettingsRow alloc] init] autorelease];
    row->_title = [title copy];
    row->_leftCaption = [left copy];
    row->_rightCaption = [right copy];
    row->_hasLevel = YES;
    row->_hasSlider = YES;
    row->_sliderValue = (float)percent;
    row->_sliderMinimum = 0;
    row->_sliderMaximum = 100;
    row->_describe = [describe copy];
    void (^report)(int) = [change copy];
    row->_slide = [^(float value) { report((int)(value + 0.5f)); } copy];
    [report release];
    return row;
}

+ (ExteriaSettingsRow *)switchRowWithSymbol:(ExteriaSymbol)symbol tone:(ExteriaSettingsTone)tone title:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on
                                     toggle:(void (^)(BOOL))toggle {
    ExteriaSettingsRow *row = [ExteriaSettingsRow switchRowWithTitle:title subtitle:subtitle on:on toggle:toggle];
    row->_hasSymbol = YES;
    row->_symbol = symbol;
    row->_tone = tone;
    return row;
}

+ (ExteriaSettingsRow *)switchRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on toggle:(void (^)(BOOL))toggle {
    ExteriaSettingsRow *row = [[[ExteriaSettingsRow alloc] init] autorelease];
    row->_title = [title copy];
    row->_subtitle = [subtitle copy];
    row->_hasSwitch = YES;
    row->_on = on;
    row->_toggle = [toggle copy];
    return row;
}

+ (ExteriaSettingsRow *)actionRowWithSymbol:(ExteriaSymbol)symbol title:(NSString *)title destructive:(BOOL)destructive tap:(void (^)(void))tap {
    ExteriaSettingsRow *row = [[[ExteriaSettingsRow alloc] init] autorelease];
    row->_hasSymbol = YES;
    row->_symbol = symbol;
    row->_title = [title copy];
    row->_destructive = destructive;
    row->_tap = [tap copy];
    return row;
}

+ (ExteriaSettingsRow *)sessionRowWithPicture:(UIImage *)picture title:(NSString *)title line2:(NSString *)line2 line3:(NSString *)line3 accentLine3:(BOOL)accent
                                          tap:(void (^)(void))tap {
    ExteriaSettingsRow *row = [[[ExteriaSettingsRow alloc] init] autorelease];
    row->_picture = [picture retain];
    row->_title = [title copy];
    row->_subtitle = [line2 copy];
    row->_line3 = [line3 copy];
    row->_accentLine3 = accent;
    row->_bold = YES;
    row->_tap = [tap copy];
    return row;
}

@end

@implementation ExteriaSettingsSection

@synthesize header = _header;
@synthesize footer = _footer;
@synthesize rows = _rows;
@synthesize centerFooter = _centerFooter;

+ (ExteriaSettingsSection *)sectionWithHeader:(NSString *)header footer:(NSString *)footer rows:(NSArray *)rows {
    ExteriaSettingsSection *section = [[[ExteriaSettingsSection alloc] init] autorelease];
    section->_header = [header copy];
    section->_footer = [footer copy];
    section->_rows = [rows retain];
    return section;
}

- (void)dealloc {
    [_header release];
    [_footer release];
    [_rows release];
    [super dealloc];
}

@end

#pragma mark cell

typedef enum { ExteriaRowPlaceOnly, ExteriaRowPlaceFirst, ExteriaRowPlaceMiddle, ExteriaRowPlaceLast } ExteriaRowPlace;

static UIFont *ExteriaRowTitleFont(ExteriaSettingsRow *row) {
    return row.bold ? ExteriaFontBold(15) : ExteriaFontRegular(16);
}

/* the width of the system switch, which the cell lays the text out beside; 94 points before ios 7 and 51 from it,
   so a measure that took one number cut every title on the other system to "Запятая после упо…" */
static CGFloat ExteriaSwitchWidth(void) {
    static CGFloat width;
    if (width == 0) {
        UISwitch *probe = [[UISwitch alloc] init];
        width = probe.frame.size.width;
        [probe release];
    }
    return width;
}

/* the width the text of a row may take: what is left of the card beside the tile, the value and the switch or check */
static CGFloat ExteriaRowTextWidth(ExteriaSettingsRow *row, CGFloat width) {
    CGFloat left = ICON_PAD;
    if (row.hasSymbol || row.tileImage) left += row.destructive ? 26 + 14 : TILE + 18;
    CGFloat right = ICON_PAD;
    if (row.hasSwitch) right = 16 + ExteriaSwitchWidth() + 8;
    else if (row.checked) right = ICON_PAD + 22 + 8;
    else if (row.value.length) right = ICON_PAD + MIN(ceil(ExteriaStringSize(row.value, ExteriaFontRegular(16)).width) + 4, width * 0.45) + 8;
    else if (row.trailingImage) right = ICON_PAD + TRAILING_SIDE + 10;
    return MAX(0, width - left - right);
}

/* the height of a text wrapped at a width; the table asks for the height of every row at each reload and a cell
   asks again at each layout of a scroll, so the same few hundred measures repeat */
static CGFloat ExteriaWrappedHeight(NSString *text, UIFont *font, CGFloat width) {
    if (!text.length) return 0;
    static NSCache *cache;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 600;
    }
    NSString *key = [NSString stringWithFormat:@"%.1f|%@ %.1f|%@", (double)width, font.fontName, (double)font.pointSize, text];
    NSNumber *known = [cache objectForKey:key];
    if (known) return (CGFloat)[known doubleValue];
    CGFloat height = ceil(ExteriaStringSizeIn(text, font, CGSizeMake(width, 2000)).height);
    [cache setObject:[NSNumber numberWithDouble:(double)height] forKey:key];
    return height;
}

/* a row lets its title and the line under it wrap for as many lines as they need, since a text cut to "Подписи авт…" says nothing */
static void ExteriaRowTextHeights(ExteriaSettingsRow *row, CGFloat width, CGFloat *title, CGFloat *subtitle) {
    CGFloat room = ExteriaRowTextWidth(row, width);
    *title = ExteriaWrappedHeight(row.title, ExteriaRowTitleFont(row), room);
    *subtitle = ExteriaWrappedHeight(row.subtitle, ExteriaFontRegular(13), room);
}

static CGFloat ExteriaRowContentHeight(ExteriaSettingsRow *row, CGFloat width) {
    if (row.customView) return row.customHeight(width);
    if (row.isSession) return 76;
    if (row.hasLevel) return 112;
    if (row.hasSlider) return 78;
    CGFloat base = row.subtitle.length ? (row.hasSymbol || row.tileImage ? 64 : 60) : 52;
    if (!row.subtitle.length) {
        /* a title alone is as tall as its lines, with the same room above and below as the one-line row */
        CGFloat title, subtitle;
        ExteriaRowTextHeights(row, width, &title, &subtitle);
        return MAX(base, 16 + title + 16);
    }
    CGFloat title, subtitle;
    ExteriaRowTextHeights(row, width, &title, &subtitle);
    return MAX(base, 14 + title + 4 + subtitle + 14);
}

/* a rectangle with one radius on its two upper corners and another on its two lower ones */
static UIBezierPath *ExteriaCardPath(CGRect rect, CGFloat top, CGFloat bottom) {
    CGFloat l = CGRectGetMinX(rect), r = CGRectGetMaxX(rect), t = CGRectGetMinY(rect), b = CGRectGetMaxY(rect);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(l + top, t)];
    [path addLineToPoint:CGPointMake(r - top, t)];
    [path addArcWithCenter:CGPointMake(r - top, t + top) radius:top startAngle:(CGFloat)(-M_PI_2) endAngle:0 clockwise:YES];
    [path addLineToPoint:CGPointMake(r, b - bottom)];
    [path addArcWithCenter:CGPointMake(r - bottom, b - bottom) radius:bottom startAngle:0 endAngle:(CGFloat)M_PI_2 clockwise:YES];
    [path addLineToPoint:CGPointMake(l + bottom, b)];
    [path addArcWithCenter:CGPointMake(l + bottom, b - bottom) radius:bottom startAngle:(CGFloat)M_PI_2 endAngle:(CGFloat)M_PI clockwise:YES];
    [path addLineToPoint:CGPointMake(l, t + top)];
    [path addArcWithCenter:CGPointMake(l + top, t + top) radius:top startAngle:(CGFloat)M_PI endAngle:(CGFloat)(M_PI + M_PI_2) clockwise:YES];
    [path closePath];
    return path;
}

/* the card is stretched by CALayer.contentsCenter: ios 6 crashes in _UIImageViewPretiledImageWrapper dealloc when resized UIImageView cards are reused */
static UIImage *ExteriaCardImage(CGFloat top, CGFloat bottom) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    UIColor *color = ExteriaColorCard();
    NSString *key = [NSString stringWithFormat:@"%g/%g/%@", (double)top, (double)bottom, color];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    CGFloat side = 2 * CARD_RADIUS + 2;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [color setFill];
    [ExteriaCardPath(CGRectMake(0, 0, side, side), top, bottom) fill];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}

/* the big corners sit on the ends of the card and the small ones on the inner joints, so each row reads as a pill cut from the card */
static void ExteriaCardRadii(ExteriaRowPlace place, CGFloat *top, CGFloat *bottom) {
    *top = (place == ExteriaRowPlaceOnly || place == ExteriaRowPlaceFirst) ? CARD_RADIUS : INNER_RADIUS;
    *bottom = (place == ExteriaRowPlaceOnly || place == ExteriaRowPlaceLast) ? CARD_RADIUS : INNER_RADIUS;
}

/* the cell of a row that holds a view of its own (a preview, a list of cards) */
@interface ExteriaSettingsViewCell : UITableViewCell {
    ExteriaSettingsRow *_row;
}
@property (nonatomic, retain) ExteriaSettingsRow *row;
@end

@implementation ExteriaSettingsViewCell

@synthesize row = _row;

- (void)dealloc {
    [_row release];
    [super dealloc];
}

- (void)setRow:(ExteriaSettingsRow *)row {
    if (row == _row) return;
    for (UIView *old in [[self.contentView.subviews copy] autorelease]) [old removeFromSuperview];
    [_row release];
    _row = [row retain];
    if (_row.customView) [self.contentView addSubview:_row.customView];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width - 2 * CARD_INSET;
    /* never taller than the row the table gave it, so a view that measures more than the table did stays inside its own row */
    CGFloat height = MIN(_row.customHeight(width), self.contentView.bounds.size.height);
    _row.customView.frame = CGRectMake(CARD_INSET, 0, width, height);
}

@end

/* the cell of a row with a slider in the classic grouped table */
@interface ExteriaClassicSliderCell : UITableViewCell {
    UIView *_slider;
}
@property (nonatomic, assign) UIView *slider;
@end

@implementation ExteriaClassicSliderCell

@synthesize slider = _slider;

/* the title and the value on the first line, and the slider under them from the left edge of the title to the right edge of the value, with room above and
   below it */
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGRect title = self.textLabel.frame;
    title.origin.y = 10;
    self.textLabel.frame = title;
    CGRect value = self.detailTextLabel.frame;
    value.origin.y = title.origin.y + floor((title.size.height - value.size.height) / 2);
    self.detailTextLabel.frame = value;
    CGFloat left = title.origin.x;
    _slider.frame = CGRectMake(left, CGRectGetMaxY(title) + 10, MAX(0, width - 2 * left), 30);
}

@end

/* the cell of a row with a view of its own in the classic grouped table */
@interface ExteriaSettingsClassicViewCell : UITableViewCell {
    ExteriaSettingsRow *_row;
    UIRectCorner _corners;
    CAShapeLayer *_cut;
}
@property (nonatomic, retain) ExteriaSettingsRow *row;
@property (nonatomic, assign) UIRectCorner corners;
@end

@implementation ExteriaSettingsClassicViewCell

@synthesize row = _row;
@synthesize corners = _corners;

- (void)dealloc {
    [_row release];
    [_cut release];
    [super dealloc];
}

- (void)setRow:(ExteriaSettingsRow *)row {
    if (row == _row) return;
    for (UIView *old in [[self.contentView.subviews copy] autorelease]) [old removeFromSuperview];
    [_row release];
    _row = [row retain];
    if (_row.customView) [self.contentView addSubview:_row.customView];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIView *view = _row.customView;
    view.frame = self.contentView.bounds;
    view.layer.cornerRadius = 0;
    BOOL systemRounds = [UIViewController instancesRespondToSelector:NSSelectorFromString(@"preferredStatusBarStyle")];
    if (systemRounds || !_corners) {
        self.contentView.layer.mask = nil;
        [CATransaction commit];
        return;
    }
    if (!_cut) _cut = [[CAShapeLayer alloc] init];
    _cut.frame = self.contentView.bounds;
    _cut.path = [UIBezierPath bezierPathWithRoundedRect:self.contentView.bounds byRoundingCorners:_corners cornerRadii:CGSizeMake(10, 10)].CGPath;
    self.contentView.layer.mask = _cut;
    [CATransaction commit];
}

@end

@interface ExteriaSettingsCell : UITableViewCell {
    UIView *_card;
    CALayer *_shape;
    UIImageView *_tile;
    UIImageView *_trailing;
    UILabel *_title;
    UILabel *_subtitle;
    UILabel *_line3;
    UILabel *_value;
    UISwitch *_switch;
    UIImageView *_check;
    ExteriaExpressiveSlider *_slider;
    UILabel *_levelBadge;
    UILabel *_leftLabel;
    UILabel *_rightLabel;
    UILabel *_middle;
    UIImageView *_battery;
    int _lastPercent;
    ExteriaSettingsRow *_row;
    ExteriaRowPlace _place;
}
- (void)configureWithRow:(ExteriaSettingsRow *)row place:(ExteriaRowPlace)place;
@end

@implementation ExteriaSettingsCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.contentView.clipsToBounds = YES;
    _card = [[UIView alloc] init];
    [self.contentView addSubview:_card];
    _shape = [[CALayer alloc] init];
    CGFloat side = 2 * CARD_RADIUS + 2;
    _shape.contentsCenter = CGRectMake(CARD_RADIUS / side, CARD_RADIUS / side, 2 / side, 2 / side);
    [_card.layer addSublayer:_shape];
    _tile = [[UIImageView alloc] init];
    [_card addSubview:_tile];
    _trailing = [[UIImageView alloc] init];
    _trailing.layer.masksToBounds = YES;
    _trailing.layer.cornerRadius = TRAILING_SIDE * 0.225;
    [_card addSubview:_trailing];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.numberOfLines = 1;
    [_card addSubview:_title];
    _subtitle = [[UILabel alloc] init];
    _subtitle.backgroundColor = [UIColor clearColor];
    _subtitle.numberOfLines = 1;
    [_card addSubview:_subtitle];
    _line3 = [[UILabel alloc] init];
    _line3.backgroundColor = [UIColor clearColor];
    [_card addSubview:_line3];
    _value = [[UILabel alloc] init];
    _value.backgroundColor = [UIColor clearColor];
    _value.textAlignment = ExteriaTextAlignmentRight;
    [_card addSubview:_value];
    _switch = [[UISwitch alloc] init];
    [_switch addTarget:self action:@selector(switched) forControlEvents:UIControlEventValueChanged];
    [_card addSubview:_switch];
    _check = [[UIImageView alloc] init];
    [_card addSubview:_check];
    _slider = [[ExteriaExpressiveSlider alloc] init];
    [_slider addTarget:self action:@selector(slid) forControlEvents:UIControlEventValueChanged];
    [_card addSubview:_slider];
    _levelBadge = [[UILabel alloc] init];
    _levelBadge.textAlignment = ExteriaTextAlignmentCenter;
    _levelBadge.layer.cornerRadius = 4;
    _levelBadge.layer.masksToBounds = YES;
    [_card addSubview:_levelBadge];
    _leftLabel = [[UILabel alloc] init];
    _leftLabel.backgroundColor = [UIColor clearColor];
    [_card addSubview:_leftLabel];
    _rightLabel = [[UILabel alloc] init];
    _rightLabel.backgroundColor = [UIColor clearColor];
    _rightLabel.textAlignment = ExteriaTextAlignmentRight;
    [_card addSubview:_rightLabel];
    _middle = [[UILabel alloc] init];
    _middle.backgroundColor = [UIColor clearColor];
    [_card addSubview:_middle];
    _battery = [[UIImageView alloc] init];
    [_card addSubview:_battery];
    return self;
}

- (void)dealloc {
    [_card release];
    [_shape release];
    [_tile release];
    [_trailing release];
    [_title release];
    [_subtitle release];
    [_line3 release];
    [_value release];
    [_switch release];
    [_check release];
    [_slider release];
    [_levelBadge release];
    [_leftLabel release];
    [_rightLabel release];
    [_middle release];
    [_battery release];
    [_row release];
    [super dealloc];
}

/* a small battery, outlined, with its charge filled in from the left; it stands after the words that name a level */
static UIImage *ExteriaBatteryImage(float fill, UIColor *color) {
    CGSize size = CGSizeMake(22, 12);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGRect body = CGRectMake(0.75, 0.75, 18.5, 10.5);
    [color setStroke];
    UIBezierPath *outline = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:2.5];
    outline.lineWidth = 1.5;
    [outline stroke];
    [color setFill];
    CGFloat charge = MAX(0, MIN(1, fill));
    if (charge > 0) [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2.5, 2.5, 15 * charge, 7) cornerRadius:1] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(19.8, 3.8, 2, 4.4) cornerRadius:1] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the texts of a level: its words in the middle, the badge at the title, the two ends lit when one of them is the level */
- (void)showLevel:(int)percent {
    NSDictionary *info = _row.describe ? _row.describe(percent) : nil;
    _middle.text = [info objectForKey:@"line"];
    NSString *badge = [info objectForKey:@"badge"];
    _levelBadge.hidden = badge.length == 0;
    _levelBadge.text = badge;
    NSNumber *fill = [info objectForKey:@"fill"];
    _battery.hidden = fill == nil;
    _battery.image = fill ? ExteriaBatteryImage([fill floatValue], ExteriaColorAccent()) : nil;
    _leftLabel.textColor = [[info objectForKey:@"left"] boolValue] ? ExteriaColorAccent() : ExteriaColorSecondary();
    _rightLabel.textColor = [[info objectForKey:@"right"] boolValue] ? ExteriaColorAccent() : ExteriaColorSecondary();
    [self setNeedsLayout];
}

- (void)slid {
    if (_row.hasLevel) {
        int percent = (int)(_slider.value + 0.5f);
        if (percent == _lastPercent) return;
        _lastPercent = percent;
        /* the row keeps the value, because the table builds the cell again from it when the row scrolls back into view */
        _row.sliderValue = (float)percent;
        [self showLevel:percent];
        if (_row.slide) _row.slide((float)percent);
        return;
    }
    _row.sliderValue = _slider.value;
    _value.text = [NSString stringWithFormat:_row.sliderFormat, (double)_slider.value];
    if (_row.slide) _row.slide(_slider.value);
}

- (void)switched {
    _row.on = _switch.on;
    if (_row.toggle) _row.toggle(_switch.on);
}

- (void)configureWithRow:(ExteriaSettingsRow *)row place:(ExteriaRowPlace)place {
    /* the new row is kept before the old one goes, since a cell configured again with its own row would free it first */
    [row retain];
    [_row release];
    _row = row;
    _place = place;
    /* the picture of the card depends on the place and the colors only, so a scroll that lays the cell out again does not look it up again */
    CGFloat top, bottom;
    ExteriaCardRadii(place, &top, &bottom);
    UIImage *shape = ExteriaCardImage(top, bottom);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shape.contents = (id)shape.CGImage;
    _shape.contentsScale = shape.scale;
    [CATransaction commit];
    BOOL tappable = row.tap != nil;
    _card.backgroundColor = [UIColor clearColor];
    UIColor *textColor = row.destructive ? ExteriaColorBadgeRed() : ExteriaColorTitle();
    _title.text = row.title;
    _title.textColor = textColor;
    _title.font = ExteriaRowTitleFont(row);
    /* a title and the line under it wrap for as many lines as they need, so "Terminate All Other Sessions" reads whole (the session rows keep one line each,
       their height is fixed) */
    _title.numberOfLines = row.isSession ? 1 : 0;
    _subtitle.numberOfLines = row.isSession ? 1 : 0;
    _subtitle.text = row.subtitle;
    _subtitle.font = ExteriaFontRegular(row.isSession ? 14 : 13);
    _subtitle.textColor = row.isSession ? ExteriaColorTitle() : ExteriaColorSecondary();
    _subtitle.hidden = row.subtitle.length == 0;
    _line3.text = row.line3;
    _line3.font = ExteriaFontRegular(13);
    _line3.textColor = row.accentLine3 ? ExteriaColorAccent() : ExteriaColorSecondary();
    _line3.hidden = row.line3.length == 0;
    _value.text = row.value;
    _value.font = ExteriaFontRegular(16);
    _value.textColor = ExteriaColorAccent();
    _value.hidden = row.value.length == 0;
    _switch.hidden = !row.hasSwitch;
    _switch.on = row.on;
    _check.hidden = !row.checked;
    _check.image = row.checked ? ExteriaSymbolImage(ExteriaSymbolCheck, 22, ExteriaColorAccent()) : nil;
    _slider.hidden = !row.hasSlider;
    BOOL level = row.hasLevel;
    _levelBadge.hidden = _leftLabel.hidden = _rightLabel.hidden = _middle.hidden = _battery.hidden = !level;
    if (level) {
        _lastPercent = (int)(row.sliderValue + 0.5f);
        _title.font = ExteriaFontSemibold(15);
        _title.textColor = ExteriaColorAccent();
        _leftLabel.font = ExteriaFontRegular(13);
        _leftLabel.text = row.leftCaption;
        _rightLabel.font = ExteriaFontRegular(13);
        _rightLabel.text = row.rightCaption;
        _middle.font = ExteriaFontMedium(13);
        _middle.textColor = ExteriaColorAccent();
        _levelBadge.font = ExteriaFontBold(12);
        _levelBadge.textColor = ExteriaColorAccent();
        _levelBadge.backgroundColor = [ExteriaColorAccent() colorWithAlphaComponent:0.15];
        [self showLevel:_lastPercent];
    }
    if (row.hasSlider) {
        _slider.minimumValue = row.sliderMinimum;
        _slider.maximumValue = row.sliderMaximum;
        _slider.value = row.sliderValue;
        /* the number follows the position, whatever text the row was made with */
        if (!level && row.sliderFormat) {
            _value.text = [NSString stringWithFormat:row.sliderFormat, (double)row.sliderValue];
            _value.hidden = NO;
        }
    }
    if (row.isSession) {
        _tile.image = row.picture;
    } else if (row.tileImage) {
        _tile.image = row.tileImage;
    } else if (row.hasSymbol && row.destructive) {
        _tile.image = ExteriaSymbolImage(row.symbol, 26, textColor);
    } else if (row.hasSymbol) {
        _tile.image = ExteriaSettingsTileImage(row.symbol, row.tone, TILE);
    } else {
        _tile.image = nil;
    }
    _tile.hidden = _tile.image == nil;
    _trailing.image = row.trailingImage;
    _trailing.hidden = row.trailingImage == nil;
    CGFloat dim = row.disabled ? 0.5 : 1;
    _tile.alpha = _title.alpha = _subtitle.alpha = _switch.alpha = dim;
    _switch.userInteractionEnabled = !row.disabled;
    self.accessibilityLabel = row.title;
    self.accessibilityTraits = tappable ? UIAccessibilityTraitButton : UIAccessibilityTraitNone;
    [self setNeedsLayout];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (_row.tap) _card.alpha = highlighted ? 0.7 : 1;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width - 2 * CARD_INSET;
    /* the plate takes the height the table gave the row (minus the gap under a joint), so it cannot run into the row below when the two measures differ */
    BOOL last = _place == ExteriaRowPlaceOnly || _place == ExteriaRowPlaceLast;
    CGFloat height = MAX(0, self.contentView.bounds.size.height - (last ? 0 : ROW_GAP));
    _card.frame = CGRectMake(CARD_INSET, 0, width, height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shape.frame = _card.bounds;
    [CATransaction commit];
    BOOL session = _row.isSession;
    CGFloat iconSide = session ? SESSION_ICON : TILE;
    CGFloat left = ICON_PAD;
    if (!_tile.hidden) {
        _tile.frame = CGRectMake(ICON_PAD, session ? 9 : (height - iconSide) / 2, iconSide, iconSide);
        left = CGRectGetMaxX(_tile.frame) + (session ? 14 : 18);
        /* the glyph of an action row has no circle around it, so its text sits closer */
        if (_row.destructive) {
            _tile.frame = CGRectMake(ICON_PAD, (height - 26) / 2, 26, 26);
            left = CGRectGetMaxX(_tile.frame) + 14;
        }
    }
    CGFloat right = ICON_PAD;
    if (!_switch.hidden) {
        CGSize size = _switch.frame.size;
        _switch.frame = CGRectMake(width - 16 - size.width, (height - size.height) / 2, size.width, size.height);
        right = 16 + size.width + 8;
    }
    if (!_trailing.hidden) {
        _trailing.frame = CGRectMake(width - ICON_PAD - TRAILING_SIDE, (height - TRAILING_SIDE) / 2, TRAILING_SIDE, TRAILING_SIDE);
        right = ICON_PAD + TRAILING_SIDE + 10;
    }
    if (!_check.hidden) {
        _check.frame = CGRectMake(width - ICON_PAD - 22, (height - 22) / 2, 22, 22);
        right = ICON_PAD + 22 + 8;
    }
    if (_row.hasLevel) {
        _title.frame = CGRectMake(ICON_PAD, 16, MAX(0, width - 2 * ICON_PAD), 20);
        if (!_levelBadge.hidden) {
            CGFloat titleWidth = ceil(ExteriaStringSize(_title.text, _title.font).width);
            CGFloat badgeWidth = ceil(ExteriaStringSize(_levelBadge.text, _levelBadge.font).width) + 11;
            _levelBadge.frame = CGRectMake(ICON_PAD + titleWidth + 6, 17, badgeWidth, 18);
        }
        _leftLabel.frame = CGRectMake(ICON_PAD, 46, 80, 20);
        _rightLabel.frame = CGRectMake(width - ICON_PAD - 80, 46, 80, 20);
        CGFloat room = MAX(0, width - 2 * ICON_PAD - 170);
        CGFloat textWidth = MIN(room, ceil(ExteriaStringSize(_middle.text, _middle.font).width));
        CGFloat group = textWidth + (_battery.hidden ? 0 : 28);
        CGFloat x = floor((width - group) / 2);
        _middle.frame = CGRectMake(x, 46, textWidth, 20);
        _battery.frame = CGRectMake(x + textWidth + 6, 50, 22, 12);
        _slider.frame = CGRectMake(ICON_PAD - 6, 72, width - 2 * ICON_PAD + 12, 30);
        return;
    }
    if (!_slider.hidden) {
        _title.frame = CGRectMake(left, 10, MAX(0, width - left - ICON_PAD - 90), 22);
        _value.frame = CGRectMake(width - ICON_PAD - 90, 10, 90, 22);
        _slider.frame = CGRectMake(left, 40, MAX(0, width - left - ICON_PAD), 28);
        return;
    }
    CGFloat valueWidth = 0;
    if (!_value.hidden) {
        valueWidth = MIN(ceil(ExteriaStringSize(_value.text, _value.font).width) + 4, width * 0.45);
        _value.frame = CGRectMake(width - ICON_PAD - valueWidth, 0, valueWidth, height);
        right = ICON_PAD + valueWidth + 8;
    }
    CGFloat textWidth = MAX(0, width - left - right);
    if (session) {
        _title.frame = CGRectMake(left, 6, textWidth, 20);
        _subtitle.frame = CGRectMake(left, 28, textWidth, 18);
        _line3.frame = CGRectMake(left, 46, textWidth, 18);
    } else if (!_subtitle.hidden) {
        CGFloat titleHeight, subtitleHeight;
        ExteriaRowTextHeights(_row, width, &titleHeight, &subtitleHeight);
        CGFloat textTop = floor((height - (titleHeight + 4 + subtitleHeight)) / 2);
        _title.frame = CGRectMake(left, textTop, textWidth, titleHeight);
        _subtitle.frame = CGRectMake(left, textTop + titleHeight + 4, textWidth, subtitleHeight);
    } else {
        _title.frame = CGRectMake(left, 0, textWidth, height);
    }
}

@end

#pragma mark page

/* a field whose hint is drawn in the muted color of the bar; attributedPlaceholder, which would do it, came with ios 6 */
@interface ExteriaSettingsSearchField : UITextField
@end

@implementation ExteriaSettingsSearchField

- (void)drawPlaceholderInRect:(CGRect)rect {
    [ExteriaColorMuted() setFill];
    ExteriaDrawStringIn(self.placeholder, self.font, rect, ExteriaStringTailTruncate, ExteriaTextAlignmentLeft);
}

@end

/* a reused cell starts at its old width; laying out its label here avoids a second autoresize beyond the right margin */
@interface ExteriaSettingsTextCell : UITableViewCell
@end

@implementation ExteriaSettingsTextCell
- (void)layoutSubviews {
    [super layoutSubviews];
    UILabel *label = (UILabel *)[self.contentView viewWithTag:1];
    CGRect bounds = self.contentView.bounds;
    label.frame = CGRectMake(CARD_INSET + ICON_PAD, 10, MAX(0, bounds.size.width - 2 * (CARD_INSET + ICON_PAD)),
                             MAX(0, bounds.size.height - 20));
}
@end

@interface ExteriaSettingsPageController () {
    NSString *_pageTitle;
    NSArray *_sections;
    NSArray *_flat;
    UIView *_headerView;
    UITableView *_table;
    BOOL _showsBack;
    CGFloat _bottomInset;
    NSArray *_barViews;
    CGFloat _titleAlpha;
    BOOL _contentUnderBar;
    CGFloat _barFill;
    BOOL _searchable;
    BOOL _searching;
    NSString *_query;
    NSArray *_searchSections;
    UIView *_barBackground;
    ExteriaWaveBackgroundView *_backdrop;
    UIButton *_back;
    UILabel *_titleLabel;
    UIButton *_searchButton;
    UITextField *_searchField;
    UILabel *_emptyLabel;
    BOOL _classic;
    ExteriaClassicSearchInput *_classicSearch;
    UIView *_classicHead;
    /* the classic search sits in the navigation bar while it is open, and what it replaced waits here */
    BOOL _classicSearchOpen;
    UIView *_savedTitleView;
    NSArray *_savedLeftItems;
    NSArray *_savedRightItems;
    NSMutableIndexSet *_footerDirty;
    BOOL _sliding;
    CGPoint _selectPoint;
}
@end

@implementation ExteriaSettingsPageController

@synthesize table = _table;
@synthesize showsBack = _showsBack;
@synthesize bottomInset = _bottomInset;
@synthesize contentUnderBar = _contentUnderBar;

@synthesize searchable = _searchable;
@synthesize searching = _searching;

- (CGFloat)titleAlpha { return _titleAlpha; }
- (void)setTitleAlpha:(CGFloat)alpha {
    _titleAlpha = alpha;
    _titleLabel.alpha = alpha;
}

- (CGFloat)barFill { return _barFill; }
- (void)setBarFill:(CGFloat)fill {
    _barFill = fill;
    _barBackground.alpha = _searching ? 1 : fill;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _showsBack = YES;
    _titleAlpha = 1;
    _barFill = 1;
    _classic = ExteriaThemeIsClassic();
    _footerDirty = [[NSMutableIndexSet alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeNotified:) name:ExteriaThemeDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyThemeInPlace) object:nil];
    _table.delegate = nil;
    _table.dataSource = nil;
    _searchField.delegate = nil;
    _classicSearch.changeHandler = nil;
    [_pageTitle release];
    [_sections release];
    [_flat release];
    [_headerView release];
    [_table release];
    [_barViews release];
    [_backdrop release];
    [_back release];
    [_titleLabel release];
    [_barBackground release];
    [_searchButton release];
    [_searchField release];
    [_emptyLabel release];
    [_classicSearch release];
    [_classicHead release];
    [_savedTitleView release];
    [_savedLeftItems release];
    [_savedRightItems release];
    [_footerDirty release];
    [_query release];
    [_searchSections release];
    [super dealloc];
}

- (NSString *)pageTitle { return _pageTitle; }
- (void)setPageTitle:(NSString *)title {
    if (title == _pageTitle || [title isEqualToString:_pageTitle]) return;
    [_pageTitle release];
    _pageTitle = [title copy];
    _titleLabel.text = _pageTitle;
    self.title = _pageTitle;
}

- (NSArray *)sections { return _sections; }
- (void)setSections:(NSArray *)sections {
    if (sections == _sections) return;
    [_sections release];
    _sections = [sections retain];
    [self rebuildFlat];
    [_table reloadData];
}

- (UIView *)headerView { return _headerView; }
- (void)setHeaderView:(UIView *)view {
    if (view == _headerView) return;
    [_headerView release];
    _headerView = [view retain];
    if ([self isViewLoaded]) {
        _table.tableHeaderView = _classic ? [self classicTableHeader] : _headerView;
        [self.view setNeedsLayout];
    }
}

- (NSArray *)barViews { return _barViews; }
- (void)setBarViews:(NSArray *)views {
    for (UIView *old in _barViews) [old removeFromSuperview];
    [_barViews release];
    _barViews = [views retain];
    if ([self isViewLoaded]) for (UIView *view in _barViews) [self.view addSubview:view];
    [self.view setNeedsLayout];
}

- (void)setBottomInset:(CGFloat)inset {
    _bottomInset = inset;
    [self.view setNeedsLayout];
}

- (void)goBack {
    if (_searching) {
        [self endSearch];
        return;
    }
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark search

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    (void)query;
    return nil;
}

- (void)searchDidChangeState {
}

- (void)setSearchable:(BOOL)searchable {
    _searchable = searchable;
    _searchButton.hidden = !searchable;
    if (_classic && _classicSearch) _table.tableHeaderView = [self classicTableHeader];
    if ([self isViewLoaded]) [self.view setNeedsLayout];
}

/* the classic style searches as the text is typed: there is no open and close, the text decides */
- (void)classicSearchChanged:(NSString *)text {
    NSString *query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL was = _searching;
    _searching = query.length > 0;
    [_query release];
    _query = [query copy];
    [_searchSections release];
    _searchSections = _searching ? [[self sectionsForSearchQuery:query] retain] : nil;
    [self rebuildFlat];
    [_table reloadData];
    if (was != _searching) [self searchDidChangeState];
    [self refreshEmptyLabel];
}

- (void)focusSearch {
    if (!_searchable) return;
    if (!_classic) {
        [self beginSearch];
        return;
    }
    [self beginClassicSearch];
}

/* old iOS can refuse keyboard focus for a table header during scrolling or before it enters the window */
- (void)beginClassicSearch {
    if (_classicSearchOpen || !_classicSearch) return;
    UINavigationItem *item = self.navigationItem;
    _classicSearchOpen = YES;
    [_savedTitleView release];
    _savedTitleView = [item.titleView retain];
    [_savedLeftItems release];
    _savedLeftItems = [item.leftBarButtonItems copy];
    [_savedRightItems release];
    _savedRightItems = [item.rightBarButtonItems copy];
    CGFloat width = self.navigationController.navigationBar.bounds.size.width;
    _classicSearch.frame = CGRectMake(0, 0, MAX(120, width - 24), 44);
    item.leftBarButtonItems = nil;
    item.rightBarButtonItems = [NSArray arrayWithObject:[[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"picker.cancel", nil)
                                                                                           style:UIBarButtonItemStyleBordered target:self action:@selector(endClassicSearch)] autorelease]];
    item.titleView = _classicSearch;
    /* the bar is in the window after this pass of the run loop, which is when a keyboard can be asked for */
    [self performSelector:@selector(raiseClassicSearchKeyboard) withObject:nil afterDelay:0];
}

- (void)raiseClassicSearchKeyboard {
    if (!_classicSearchOpen) return;
    if (![_classicSearch becomeFirstResponder]) NSLog(@"exteria: the search bar of the settings did not take the keyboard");
}

- (void)endClassicSearch {
    if (!_classicSearchOpen) return;
    _classicSearchOpen = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(raiseClassicSearchKeyboard) object:nil];
    _classicSearch.text = @"";
    [_classicSearch resignFirstResponder];
    UINavigationItem *item = self.navigationItem;
    item.titleView = _savedTitleView;
    item.leftBarButtonItems = _savedLeftItems;
    item.rightBarButtonItems = _savedRightItems;
    [self classicSearchChanged:@""];
}

- (void)beginSearch {
    if (_searching || !_searchable) return;
    _searching = YES;
    _barBackground.hidden = NO;
    _barBackground.alpha = 1;
    _back.hidden = NO;
    _titleLabel.hidden = YES;
    _searchButton.hidden = YES;
    for (UIView *view in _barViews) view.hidden = YES;
    _searchField.text = @"";
    _searchField.hidden = NO;
    [_query release];
    _query = [@"" retain];
    [_searchSections release];
    _searchSections = [[self sectionsForSearchQuery:@""] retain];
    _table.tableHeaderView = nil;
    [self rebuildFlat];
    [_table reloadData];
    [_table setContentOffset:CGPointZero animated:NO];
    [self searchDidChangeState];
    [self.view setNeedsLayout];
    [_searchField becomeFirstResponder];
    [self refreshEmptyLabel];
}

- (void)endSearch {
    if (!_searching) return;
    if (_classic) {
        [self endClassicSearch];
        return;
    }
    [_searchField resignFirstResponder];
    _searching = NO;
    _searchField.hidden = YES;
    _titleLabel.hidden = NO;
    _searchButton.hidden = !_searchable;
    for (UIView *view in _barViews) view.hidden = NO;
    _back.hidden = !_showsBack;
    _barBackground.hidden = !_contentUnderBar;
    _barBackground.alpha = _barFill;
    [_searchSections release];
    _searchSections = nil;
    [_query release];
    _query = nil;
    _table.tableHeaderView = _headerView;
    [self rebuildFlat];
    [_table reloadData];
    [self searchDidChangeState];
    [self.view setNeedsLayout];
    [self refreshEmptyLabel];
}

- (void)reloadSearchResults {
    if (!_searching) return;
    [_searchSections release];
    _searchSections = [[self sectionsForSearchQuery:_query ? _query : @""] retain];
    [self rebuildFlat];
    [_table reloadData];
    [self refreshEmptyLabel];
}

- (void)searchTextChanged {
    NSString *query = [_searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([query isEqualToString:_query]) return;
    [_query release];
    _query = [query copy];
    [_searchSections release];
    _searchSections = [[self sectionsForSearchQuery:query] retain];
    [self rebuildFlat];
    [_table reloadData];
    [_table setContentOffset:CGPointZero animated:NO];
    [self refreshEmptyLabel];
}

/* a query that matched nothing says so in the middle of the empty table */
- (void)refreshEmptyLabel {
    BOOL empty = _searching && _query.length && _searchSections && _flat.count == 0;
    _emptyLabel.hidden = !empty;
}


- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

/* the waves under the rows hold still while the table moves; their animated masks are drawn again by the render
   server on every frame, which a long page of rows on an iPhone 4S cannot afford next to its own scroll */
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    (void)scrollView;
    _backdrop.scrolling = YES;
    if (_searching) [_searchField resignFirstResponder];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    (void)scrollView;
    if (!decelerate) _backdrop.scrolling = NO;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    (void)scrollView;
    _backdrop.scrolling = NO;
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    (void)scrollView;
    _backdrop.scrolling = NO;
}

/* a row that changes height animates its cell, while a view of its own inside it (the preview) takes the new size
   at once and for a moment spills over the rows beside it */
- (void)updateRowHeights {
    BOOL animated = [UIView areAnimationsEnabled];
    [UIView setAnimationsEnabled:NO];
    [_table beginUpdates];
    [_table endUpdates];
    [UIView setAnimationsEnabled:animated];
}

- (void)reloadSettings {
    [_table reloadData];
}

/* the head of the classic table: the block of a page that has one (the identity of the settings), and under it the
   search bar of a searchable page; with both they share one container */
- (UIView *)classicTableHeader {
    /* the search lives in the navigation bar now, so the head of the table is the page's own block alone */
    UIView *search = nil;
    if (!_headerView || !search) return _headerView ? _headerView : search;
    for (UIView *old in [[_classicHead.subviews copy] autorelease]) [old removeFromSuperview];
    [_classicHead release];
    CGFloat width = _table.bounds.size.width, head = _headerView.bounds.size.height;
    _classicHead = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, head + search.bounds.size.height)];
    _classicHead.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _headerView.frame = CGRectMake(0, 0, width, head);
    _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    search.frame = CGRectMake(0, head, width, search.bounds.size.height);
    search.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_classicHead addSubview:_headerView];
    [_classicHead addSubview:search];
    return _classicHead;
}

/* the classic style: the system's grouped table under the navigation bar of its tab, with the search in a bar at the head of the table */
- (void)loadClassicView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    _table = [[UITableView alloc] initWithFrame:root.bounds style:UITableViewStyleGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.delegate = self;
    _table.dataSource = self;
    ExteriaClassicStyleTable(_table);
    [root addSubview:_table];
    _classicSearch = [[ExteriaClassicSearchInput alloc] initWithFrame:CGRectMake(0, 0, root.bounds.size.width, 44) placeholder:NSLocalizedString(@"settings.search", nil)];
    ExteriaWeakReference *searchWeak = [ExteriaWeakReference referenceTo:self];
    _classicSearch.changeHandler = ^(NSString *text) { [(ExteriaSettingsPageController *)searchWeak.target classicSearchChanged:text]; };
    _table.tableHeaderView = [self classicTableHeader];
    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 120, root.bounds.size.width - 48, 24)];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.textColor = ExteriaThemeIsDark() ? ExteriaColorSecondary() : [UIColor grayColor];
    _emptyLabel.textAlignment = ExteriaTextAlignmentCenter;
    _emptyLabel.text = NSLocalizedString(@"settings.search.empty", nil);
    _emptyLabel.hidden = YES;
    [root addSubview:_emptyLabel];
    self.title = _pageTitle;
}

/* everything the modern page draws around its rows; it is made again when the colors change */
- (void)buildModernChromeInRoot:(UIView *)root {
    _backdrop = [[ExteriaWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.plain = YES;
    _backdrop.animated = YES;
    /* the table is made once and stays through every change of colors; only its rows are drawn again */
    if (_table) {
        [root insertSubview:_backdrop atIndex:0];
    } else {
        [root addSubview:_backdrop];
        _table = [[UITableView alloc] initWithFrame:root.bounds style:UITableViewStylePlain];
        ExteriaScrollViewOwnsInsets(_table);
        _table.backgroundColor = [UIColor clearColor];
        _table.separatorStyle = UITableViewCellSeparatorStyleNone;
        _table.showsVerticalScrollIndicator = NO;
        _table.delegate = self;
        _table.dataSource = self;
        _table.tableHeaderView = _headerView;
        [root addSubview:_table];
    }
    _barBackground = [[UIView alloc] init];
    _barBackground.backgroundColor = [ExteriaColorScreen() colorWithAlphaComponent:0.94];
    _barBackground.alpha = _barFill;
    _barBackground.hidden = !_contentUnderBar;
    [root addSubview:_barBackground];
    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.textColor = ExteriaColorSecondary();
    _emptyLabel.textAlignment = ExteriaTextAlignmentCenter;
    _emptyLabel.text = NSLocalizedString(@"settings.search.empty", nil);
    _emptyLabel.hidden = YES;
    [root addSubview:_emptyLabel];
    _back = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_back setImage:ExteriaSymbolImage(ExteriaSymbolBack, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    _back.accessibilityLabel = NSLocalizedString(@"story.close", nil);
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    _back.hidden = !_showsBack;
    [root addSubview:_back];
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textColor = ExteriaColorTitle();
    _titleLabel.text = _pageTitle;
    _titleLabel.alpha = _titleAlpha;
    [root addSubview:_titleLabel];
    for (UIView *view in _barViews) [root addSubview:view];
    _searchButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_searchButton setImage:ExteriaSymbolImage(ExteriaSymbolMagnifier, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    _searchButton.accessibilityLabel = NSLocalizedString(@"settings.search", nil);
    [_searchButton addTarget:self action:@selector(beginSearch) forControlEvents:UIControlEventTouchUpInside];
    _searchButton.frame = CGRectMake(0, 0, 44, 44);
    _searchButton.hidden = !_searchable;
    [root addSubview:_searchButton];
    _searchField = [[ExteriaSettingsSearchField alloc] init];
    _searchField.backgroundColor = [UIColor clearColor];
    _searchField.textColor = ExteriaColorTitle();
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.delegate = self;
    _searchField.placeholder = NSLocalizedString(@"settings.search", nil);
    _searchField.hidden = YES;
    [_searchField addTarget:self action:@selector(searchTextChanged) forControlEvents:UIControlEventEditingChanged];
    [root addSubview:_searchField];
}

/* the views of the page go, except its table; the old views are kept for a moment before they are let go, since an
   animation that was running on one of them (the waves, a fade of the bar) still reports to it when it ends */
- (void)discardModernChrome {
    _searchField.delegate = nil;
    NSMutableArray *retired = [NSMutableArray array];
    for (UIView *view in [NSArray arrayWithObjects:_backdrop, _barBackground, _emptyLabel, _back, _titleLabel, _searchButton, _searchField, nil]) {
        [view removeFromSuperview];
        [retired addObject:view];
    }
    [_backdrop release];
    _backdrop = nil;
    [_barBackground release];
    _barBackground = nil;
    [_emptyLabel release];
    _emptyLabel = nil;
    [_back release];
    _back = nil;
    [_titleLabel release];
    _titleLabel = nil;
    [_searchButton release];
    _searchButton = nil;
    [_searchField release];
    _searchField = nil;
    [self performSelector:@selector(dropRetiredViews:) withObject:retired afterDelay:1.5];
}

- (void)dropRetiredViews:(NSArray *)views {
    (void)views;
}

/* the colors are read when a view is built, so a page that stays up across a change of the theme makes its own
   views again */
- (void)themeNotified:(NSNotification *)note {
    (void)note;
    [self performSelector:@selector(applyThemeInPlace) withObject:nil afterDelay:0];
}

- (void)applyThemeInPlace {
    ExteriaThemeApplyStored();
    if (_classic || ExteriaThemeIsClassic() || ![self isViewLoaded]) return;
    if (_searching) [self endSearch];
    CGPoint offset = _table.contentOffset;
    UIView *root = self.view;
    [self discardModernChrome];
    root.backgroundColor = ExteriaColorScreen();
    [self buildModernChromeInRoot:root];
    [self themeDidChange];
    [_table reloadData];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    _table.contentOffset = offset;
}

- (void)themeDidChange {
}

- (CGPoint)selectPoint { return _selectPoint; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:!_classic animated:animated];
}

- (void)loadView {
    _classic = ExteriaThemeIsClassic();
    if (_classic) {
        [self loadClassicView];
        return;
    }
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    [self buildModernChromeInRoot:root];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate { return YES; }

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations { return ExteriaOrientationMask(); }
#pragma clang diagnostic pop

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_classic) return;
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = insets.top;
    /* the bar, the rows and the cards share one column: the wave and the bar fill stay full width behind it */
    CGRect column = ExteriaContentColumn(size, insets, EXTERIA_COLUMN_PAGE);
    CGFloat left = column.origin.x, edge = CGRectGetMaxX(column);
    _backdrop.frame = self.view.bounds;
    _back.frame = CGRectMake(left + 6, top + 6, 44, 44);
    _titleLabel.font = ExteriaFontSemibold(22);
    CGFloat right = edge - 8;
    for (UIView *view in [_barViews reverseObjectEnumerator]) {
        CGRect frame = view.frame;
        frame.origin = CGPointMake(right - frame.size.width, top + (BAR_HEIGHT - frame.size.height) / 2);
        view.frame = frame;
        right = frame.origin.x - 4;
    }
    if (_searchable) {
        _searchButton.frame = CGRectMake(right - 44, top + (BAR_HEIGHT - 44) / 2, 44, 44);
        right = _searchButton.frame.origin.x - 4;
    }
    /* the only page of the right pane of a tablet has no left pane to go back to */
    BOOL arrow = _searching || (_showsBack && !ExteriaIsDetailRoot(self));
    _back.hidden = !arrow;
    CGFloat titleLeft = arrow ? left + 62 : left + 20;
    _titleLabel.frame = CGRectMake(titleLeft, top, MAX(0, right - titleLeft), BAR_HEIGHT);
    _searchField.font = ExteriaFontRegular(18);
    _searchField.frame = CGRectMake(titleLeft, top + (BAR_HEIGHT - 32) / 2, MAX(0, edge - 12 - titleLeft), 32);
    CGFloat tableTop = (_contentUnderBar && !_searching) ? top : top + BAR_HEIGHT;
    _emptyLabel.font = ExteriaFontRegular(16);
    _emptyLabel.frame = CGRectMake(left + 24, tableTop + 60, MAX(0, column.size.width - 48), 24);
    _barBackground.frame = CGRectMake(0, 0, size.width, top + BAR_HEIGHT);
    _table.frame = CGRectMake(left, tableTop, column.size.width, size.height - tableTop);
    _table.contentInset = UIEdgeInsetsMake(0, 0, MAX(_bottomInset, insets.bottom) + 16, 0);
    if (_headerView) {
        CGRect frame = _headerView.frame;
        if (frame.size.width != column.size.width) {
            frame.size.width = column.size.width;
            _headerView.frame = frame;
            _table.tableHeaderView = _headerView;
        }
    }
}

#pragma mark table

/* the headers and footers of the sections are rows of the one section of the table, so they scroll away with the
   cards */
enum { ExteriaFlatHeader, ExteriaFlatRow, ExteriaFlatFooter, ExteriaFlatSpace };

- (void)rebuildFlat {
    [_flat release];
    NSMutableArray *flat = [NSMutableArray array];
    NSUInteger sectionIndex = 0;
    BOOL afterView = NO;
    for (ExteriaSettingsSection *section in [self shownSections]) {
        NSNumber *mine = [NSNumber numberWithUnsignedInteger:sectionIndex++];
        /* a header under a card that is a picture (a preview, a list of cards) sat too close to its corners, so it gets a gap of its own */
        if (afterView && section.header.length) [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:ExteriaFlatSpace], @"kind", mine, @"section", nil]];
        afterView = [section.rows.lastObject customView] != nil;
        if (section.header.length) [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:ExteriaFlatHeader], @"kind", section.header, @"text", mine, @"section", nil]];
        else [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:ExteriaFlatSpace], @"kind", mine, @"section", nil]];
        NSUInteger count = section.rows.count;
        for (NSUInteger i = 0; i < count; ++i) {
            ExteriaRowPlace place = count == 1 ? ExteriaRowPlaceOnly : (i == 0 ? ExteriaRowPlaceFirst : (i == count - 1 ? ExteriaRowPlaceLast : ExteriaRowPlaceMiddle));
            [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:ExteriaFlatRow], @"kind", [section.rows objectAtIndex:i], @"row",
                             [NSNumber numberWithInt:place], @"place", mine, @"section", nil]];
        }
        if (section.footer.length) [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:ExteriaFlatFooter], @"kind", section.footer, @"text",
                             [NSNumber numberWithBool:section.centerFooter], @"center", mine, @"section", nil]];
    }
    _flat = [flat retain];
}

/* the flat rows of one section, as index paths */
- (NSArray *)pathsOfSection:(NSUInteger)index inFlat:(NSArray *)flat footersOnly:(BOOL)footersOnly {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSUInteger i = 0; i < flat.count; ++i) {
        NSDictionary *item = [flat objectAtIndex:i];
        if ([[item objectForKey:@"section"] unsignedIntegerValue] != index) continue;
        if (footersOnly && [[item objectForKey:@"kind"] intValue] != ExteriaFlatFooter) continue;
        [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
    }
    return paths;
}

- (void)replaceSectionAtIndex:(NSUInteger)index withSection:(ExteriaSettingsSection *)section {
    if (index >= _sections.count) return;
    NSMutableArray *sections = [NSMutableArray arrayWithArray:_sections];
    [sections replaceObjectAtIndex:index withObject:section];
    [_sections release];
    _sections = [sections copy];
    if (_classic) {
        if (!_searching) [_table reloadSections:[NSIndexSet indexSetWithIndex:index] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
    NSArray *before = [[_flat retain] autorelease];
    [self rebuildFlat];
    if (_searching || _flat.count != before.count) {
        [_table reloadData];
        return;
    }
    NSArray *paths = [self pathsOfSection:index inFlat:_flat footersOnly:NO];
    if (paths.count) [_table reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
}

- (void)setFooter:(NSString *)footer forSectionAtIndex:(NSUInteger)index {
    if (index >= _sections.count) return;
    ExteriaSettingsSection *section = [_sections objectAtIndex:index];
    if ([footer isEqualToString:section.footer]) return;
    BOOL appears = footer.length != section.footer.length && (!footer.length || !section.footer.length);
    section.footer = footer;
    if (_classic) {
        /* the system's own footer is part of the section, which is made again once the finger leaves the slider above it */
        [_footerDirty addIndex:index];
        if (!_sliding) [self flushFooters];
        return;
    }
    NSArray *before = [[_flat retain] autorelease];
    [self rebuildFlat];
    if (appears || _searching || _flat.count != before.count) {
        [_table reloadData];
        return;
    }
    NSArray *paths = [self pathsOfSection:index inFlat:_flat footersOnly:YES];
    if (paths.count) [_table reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
}

- (void)flushFooters {
    if (!_footerDirty.count) return;
    [_table reloadSections:_footerDirty withRowAnimation:UITableViewRowAnimationNone];
    [_footerDirty removeAllIndexes];
}

- (NSArray *)shownSections {
    return (_searching && _searchSections) ? _searchSections : _sections;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return _classic ? (NSInteger)[self shownSections].count : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (_classic) return (NSInteger)[[[[self shownSections] objectAtIndex:(NSUInteger)section] rows] count];
    return (NSInteger)_flat.count;
}

- (NSDictionary *)itemAt:(NSIndexPath *)indexPath {
    return [_flat objectAtIndex:(NSUInteger)indexPath.row];
}

- (CGFloat)sectionTextHeight:(NSString *)text width:(CGFloat)width font:(UIFont *)font minimum:(CGFloat)minimum {
    CGFloat room = MAX(0, width - 2 * (CARD_INSET + ICON_PAD));
    return MAX(minimum, ExteriaWrappedHeight(text, font, room) + 20);
}

#pragma mark classic table

- (ExteriaSettingsRow *)classicRowAt:(NSIndexPath *)indexPath {
    return [[[[self shownSections] objectAtIndex:(NSUInteger)indexPath.section] rows] objectAtIndex:(NSUInteger)indexPath.row];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return _classic ? [[[self shownSections] objectAtIndex:(NSUInteger)section] header] : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return _classic ? [[[self shownSections] objectAtIndex:(NSUInteger)section] footer] : nil;
}

/* the system header text is dark grey, unreadable on the dark grouped background */
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (!_classic || !ExteriaThemeIsDark()) return nil;
    NSString *text = [[[self shownSections] objectAtIndex:(NSUInteger)section] header];
    if (!text.length) return nil;
    return ExteriaClassicGroupedHeader(text, tableView.bounds.size.width, 34, [UIColor whiteColor]);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (!_classic || !ExteriaThemeIsDark()) return nil;
    NSString *text = [[[self shownSections] objectAtIndex:(NSUInteger)section] footer];
    if (!text.length) return nil;
    CGFloat edge = ExteriaClassicGroupedTextInset(tableView.bounds.size.width);
    CGFloat width = MAX(0, tableView.bounds.size.width - 2 * edge);
    CGSize fit = ExteriaStringSizeIn(text, [UIFont systemFontOfSize:14], CGSizeMake(width, 600));
    return ExteriaClassicGroupedFooter(text, tableView.bounds.size.width, fit.height + 12);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (!_classic) return 0;
    NSString *text = [[[self shownSections] objectAtIndex:(NSUInteger)section] header];
    return text.length ? (ExteriaThemeIsDark() ? 34 : UITableViewAutomaticDimension) : 10;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (!_classic) return 0;
    NSString *text = [[[self shownSections] objectAtIndex:(NSUInteger)section] footer];
    if (!text.length) return 10;
    if (!ExteriaThemeIsDark()) return UITableViewAutomaticDimension;
    CGFloat edge = ExteriaClassicGroupedTextInset(tableView.bounds.size.width);
    CGSize fit = ExteriaStringSizeIn(text, [UIFont systemFontOfSize:14], CGSizeMake(MAX(0, tableView.bounds.size.width - 2 * edge), 600));
    return fit.height + 12;
}

- (void)classicSwitched:(UISwitch *)toggle {
    NSInteger tag = toggle.tag - 1;
    NSArray *shown = [self shownSections];
    NSUInteger section = (NSUInteger)(tag / 1000), index = (NSUInteger)(tag % 1000);
    if (section >= shown.count) return;
    NSArray *rows = [[shown objectAtIndex:section] rows];
    if (index >= rows.count) return;
    ExteriaSettingsRow *row = [rows objectAtIndex:index];
    row.on = toggle.on;
    if (row.toggle) row.toggle(toggle.on);
}

- (void)classicSlid:(UISlider *)slider {
    NSInteger tag = slider.tag - 1;
    NSArray *shown = [self shownSections];
    NSUInteger section = (NSUInteger)(tag / 1000), index = (NSUInteger)(tag % 1000);
    if (section >= shown.count) return;
    NSArray *rows = [[shown objectAtIndex:section] rows];
    if (index >= rows.count) return;
    ExteriaSettingsRow *row = [rows objectAtIndex:index];
    UIView *up = slider.superview;
    while (up && ![up isKindOfClass:[UITableViewCell class]]) up = up.superview;
    if (row.hasLevel) {
        int percent = (int)(slider.value + 0.5f);
        NSString *line = [row.describe(percent) objectForKey:@"line"];
        row.sliderValue = (float)percent;
        UILabel *label = [(UITableViewCell *)up detailTextLabel];
        if ([label.text isEqualToString:line]) return;
        label.text = line;
        if (row.slide) row.slide((float)percent);
        return;
    }
    row.sliderValue = slider.value;
    [(UITableViewCell *)up detailTextLabel].text = [NSString stringWithFormat:row.sliderFormat, (double)slider.value];
    if (row.slide) row.slide(slider.value);
}

- (void)classicSlideBegan {
    _sliding = YES;
}

/* a footer that changed under the finger is swapped in now that the finger has left */
- (void)classicSlideEnded {
    _sliding = NO;
    [self flushFooters];
}

/* the classic cell has one line for its title, so "Pause music when recording a video" ended as "Pause music when" */
static CGFloat ExteriaClassicTextWidth(ExteriaSettingsRow *row, CGFloat tableWidth) {
    CGFloat left = 20 + (row.hasSymbol || row.tileImage ? 29 + 10 : 0);
    CGFloat right = 14;
    if (row.hasSwitch) right = 20 + 79 + 8;
    else if (row.trailingImage) right = 20 + 29 + 8;
    else if (row.value.length) right = 20 + MIN(ceil(ExteriaStringSize(row.value, [UIFont systemFontOfSize:17]).width), tableWidth * 0.4) + 8;
    else if (row.tap) right = 40;
    return MAX(40, tableWidth - 20 - left - right);
}

static CGFloat ExteriaClassicRowHeight(ExteriaSettingsRow *row, CGFloat tableWidth) {
    if (row.hasSlider) return 84;
    CGFloat width = ExteriaClassicTextWidth(row, tableWidth);
    CGFloat title = ExteriaStringSizeIn(row.title, [UIFont boldSystemFontOfSize:17], CGSizeMake(width, 600)).height;
    CGFloat detail = row.subtitle.length ? ExteriaStringSizeIn(row.subtitle, [UIFont systemFontOfSize:14], CGSizeMake(width, 600)).height : 0;
    return MAX(44, ceil(title) + ceil(detail) + 22);
}

- (UITableViewCell *)classicCellForRow:(ExteriaSettingsRow *)row at:(NSIndexPath *)indexPath {
    if (row.customView) {
        static NSString *viewIdentifier = @"settings.classic.view";
        ExteriaSettingsClassicViewCell *host = (ExteriaSettingsClassicViewCell *)[_table dequeueReusableCellWithIdentifier:viewIdentifier];
        if (!host) {
            host = [[[ExteriaSettingsClassicViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:viewIdentifier] autorelease];
            host.selectionStyle = UITableViewCellSelectionStyleNone;
            ExteriaClassicStyleCell(host);
        }
        NSUInteger count = [[[[self shownSections] objectAtIndex:(NSUInteger)indexPath.section] rows] count];
        UIRectCorner corners = 0;
        if (indexPath.row == 0) corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
        if ((NSUInteger)indexPath.row + 1 == count) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
        host.corners = corners;
        host.row = row;
        return host;
    }
    /* a slider rides in the cell, so its cells are not shared with the others */
    BOOL subtitle = row.subtitle.length > 0;
    UITableViewCellStyle style = subtitle ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1;
    Class cellClass = row.hasSlider ? [ExteriaClassicSliderCell class] : [UITableViewCell class];
    UITableViewCell *cell = [[[cellClass alloc] initWithStyle:style reuseIdentifier:nil] autorelease];
    ExteriaClassicStyleCell(cell);
    UIView *selection = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
    selection.backgroundColor = ExteriaClassicSelectionColor();
    cell.selectedBackgroundView = selection;
    cell.textLabel.text = row.title;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.lineBreakMode = UILineBreakModeWordWrap;
    cell.detailTextLabel.numberOfLines = subtitle ? 0 : 1;
    if (row.destructive) cell.textLabel.textColor = [UIColor redColor];
    NSInteger tag = indexPath.section * 1000 + indexPath.row + 1;
    if (subtitle) {
        cell.detailTextLabel.text = row.subtitle;
        if (row.value.length) {
            UILabel *value = [[[UILabel alloc] init] autorelease];
            value.backgroundColor = [UIColor clearColor];
            value.font = [UIFont systemFontOfSize:16];
            value.textColor = [UIColor colorWithRed:0.22f green:0.33f blue:0.53f alpha:1];
            value.text = row.value;
            [value sizeToFit];
            cell.accessoryView = value;
        }
    } else {
        cell.detailTextLabel.text = row.value;
    }
    if (row.hasSymbol && !row.destructive) cell.imageView.image = ExteriaSettingsTileImage(row.symbol, row.tone, 29);
    else if (row.tileImage) cell.imageView.image = row.tileImage;
    if (row.trailingImage && !row.hasSwitch && !row.value.length) {
        UIImageView *mark = [[[UIImageView alloc] initWithImage:row.trailingImage] autorelease];
        mark.frame = CGRectMake(0, 0, 29, 29);
        mark.layer.masksToBounds = YES;
        mark.layer.cornerRadius = 29 * 0.225;
        cell.accessoryView = mark;
    }
    if (row.hasSwitch) {
        UISwitch *toggle = [[[UISwitch alloc] init] autorelease];
        toggle.on = row.on;
        toggle.enabled = !row.disabled;
        toggle.tag = tag;
        [toggle addTarget:self action:@selector(classicSwitched:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row.hasSlider) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (row.hasLevel) {
            cell.detailTextLabel.text = [row.describe((int)(row.sliderValue + 0.5f)) objectForKey:@"line"];
            if (!ExteriaThemeIsDark()) cell.textLabel.textColor = [UIColor colorWithRed:0.22f green:0.33f blue:0.53f alpha:1];
        } else {
            /* the row keeps where the slider stands, so a cell made again shows the value and not the one the row was made with */
            cell.detailTextLabel.text = [NSString stringWithFormat:row.sliderFormat, (double)row.sliderValue];
        }
        UISlider *slider = [[[UISlider alloc] initWithFrame:CGRectMake(20, 38, _table.bounds.size.width - 60, 28)] autorelease];
        slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        /* the filled part takes the accent of the style; the grey of the system slider is no part of it */
        slider.minimumTrackTintColor = ExteriaColorAccent();
        slider.minimumValue = row.sliderMinimum;
        slider.maximumValue = row.sliderMaximum;
        slider.value = row.sliderValue;
        slider.tag = tag;
        [slider addTarget:self action:@selector(classicSlid:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(classicSlideBegan) forControlEvents:UIControlEventTouchDown];
        [slider addTarget:self action:@selector(classicSlideEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [cell.contentView addSubview:slider];
        [(ExteriaClassicSliderCell *)cell setSlider:slider];
    } else if (row.checked) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else if (row.tap && !row.value.length && !subtitle) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    if (!row.tap && !row.hasSwitch && !row.hasSlider) cell.selectionStyle = UITableViewCellSelectionStyleNone;
    else if (!row.hasSwitch && !row.hasSlider) cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_classic) {
        ExteriaSettingsRow *row = [self classicRowAt:indexPath];
        /* a grouped cell is narrower than the table by its margins before ios 7 */
        if (row.customView) return row.customHeight(tableView.bounds.size.width - ([UIViewController instancesRespondToSelector:NSSelectorFromString(@"preferredStatusBarStyle")] ? 0 : 20));
        return ExteriaClassicRowHeight(row, tableView.bounds.size.width);
    }
    NSDictionary *item = [self itemAt:indexPath];
    switch ([[item objectForKey:@"kind"] intValue]) {
    case ExteriaFlatHeader: return [self sectionTextHeight:[item objectForKey:@"text"] width:tableView.bounds.size.width font:ExteriaFontSemibold(15) minimum:44];
    case ExteriaFlatSpace: return 14;
    case ExteriaFlatFooter: return [self sectionTextHeight:[item objectForKey:@"text"] width:tableView.bounds.size.width font:ExteriaFontRegular([[item objectForKey:@"center"] boolValue] ? 14 : 13) minimum:0];
    default: {
        ExteriaRowPlace place = (ExteriaRowPlace)[[item objectForKey:@"place"] intValue];
        BOOL last = place == ExteriaRowPlaceLast || place == ExteriaRowPlaceOnly;
        return ExteriaRowContentHeight([item objectForKey:@"row"], tableView.bounds.size.width - 2 * CARD_INSET) + (last ? 0 : ROW_GAP);
    }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_classic) return [self classicCellForRow:[self classicRowAt:indexPath] at:indexPath];
    NSDictionary *item = [self itemAt:indexPath];
    int kind = [[item objectForKey:@"kind"] intValue];
    if (kind == ExteriaFlatRow) {
        ExteriaSettingsRow *shown = [item objectForKey:@"row"];
        if (shown.customView) {
            static NSString *viewIdentifier = @"settings.view";
            ExteriaSettingsViewCell *host = (ExteriaSettingsViewCell *)[tableView dequeueReusableCellWithIdentifier:viewIdentifier];
            if (!host) {
                host = [[[ExteriaSettingsViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:viewIdentifier] autorelease];
                host.backgroundColor = [UIColor clearColor];
                host.selectionStyle = UITableViewCellSelectionStyleNone;
                host.contentView.clipsToBounds = YES;
            }
            host.row = shown;
            return host;
        }
        static NSString *identifier = @"settings";
        ExteriaSettingsCell *cell = (ExteriaSettingsCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) cell = [[[ExteriaSettingsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        [cell configureWithRow:[item objectForKey:@"row"] place:(ExteriaRowPlace)[[item objectForKey:@"place"] intValue]];
        return cell;
    }
    static NSString *textIdentifier = @"text";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:textIdentifier];
    UILabel *label;
    if (!cell) {
        cell = [[[ExteriaSettingsTextCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:textIdentifier] autorelease];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.contentView.clipsToBounds = YES;
        label = [[[UILabel alloc] init] autorelease];
        label.backgroundColor = [UIColor clearColor];
        label.tag = 1;
        [cell.contentView addSubview:label];
    }
    label = (UILabel *)[cell.contentView viewWithTag:1];
    [cell setNeedsLayout];
    NSString *text = [item objectForKey:@"text"];
    label.text = text;
    /* the frame comes from the table, not from a cell that may still hold the width and height of its last use */
    label.frame = CGRectMake(CARD_INSET + ICON_PAD, 10, MAX(0, tableView.bounds.size.width - 2 * (CARD_INSET + ICON_PAD)),
                             MAX(0, [self tableView:tableView heightForRowAtIndexPath:indexPath] - 20));
    label.numberOfLines = 0;
    label.font = kind == ExteriaFlatHeader ? ExteriaFontSemibold(15) : ExteriaFontRegular(13);
    label.textColor = kind == ExteriaFlatHeader ? ExteriaColorAccent() : ExteriaColorSecondary();
    label.hidden = kind == ExteriaFlatSpace;
    BOOL center = [[item objectForKey:@"center"] boolValue];
    label.textAlignment = center ? ExteriaTextAlignmentCenter : ExteriaTextAlignmentLeft;
    if (center) label.font = ExteriaFontRegular(14);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CGRect rowRect = [tableView rectForRowAtIndexPath:indexPath];
    _selectPoint = [tableView convertPoint:CGPointMake(CGRectGetMidX(rowRect), CGRectGetMidY(rowRect)) toView:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (_classic) {
        ExteriaSettingsRow *row = [self classicRowAt:indexPath];
        if (row.tap) row.tap();
        return;
    }
    NSDictionary *item = [self itemAt:indexPath];
    if ([[item objectForKey:@"kind"] intValue] != ExteriaFlatRow) return;
    ExteriaSettingsRow *row = [item objectForKey:@"row"];
    if (row.tap) row.tap();
    else if (row.hasSwitch && row.toggle && !row.disabled) {
        /* a tap anywhere on the row moves its switch */
        row.on = !row.on;
        row.toggle(row.on);
        [tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }
}

@end

void ExteriaSettingsChoose(UIViewController *host, NSString *title, NSArray *options, void (^handler)(NSUInteger index)) {
    if (ExteriaThemeIsClassic() || !host.view) {
        void (^pick)(NSUInteger) = [handler copy];
        ExteriaChoose(title, options, -1, ^(NSInteger index) {
            if (index >= 0 && pick) pick((NSUInteger)index);
        });
        [pick release];
        return;
    }
    [ExteriaSheet presentInView:host.view title:title message:nil options:options destructive:nil cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:handler];
}
