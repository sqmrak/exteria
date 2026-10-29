#import "exteria_wallpaper.h"

#include <math.h>

#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_wave.h"
#import <Accelerate/Accelerate.h>

NSString *const ExteriaWallpaperDidChangeNotification = @"ExteriaWallpaperDidChange";

static NSString *const ExteriaWallpaperKindKey = @"exteria.wallpaper.kind";
static NSString *const ExteriaWallpaperTopKey = @"exteria.wallpaper.top";
static NSString *const ExteriaWallpaperBottomKey = @"exteria.wallpaper.bottom";
static NSString *const ExteriaWallpaperAngleKey = @"exteria.wallpaper.angle";
static NSString *const ExteriaWallpaperPatternKey = @"exteria.wallpaper.pattern";
static NSString *const ExteriaWallpaperIntensityKey = @"exteria.wallpaper.intensity";
static NSString *const ExteriaWallpaperBlurKey = @"exteria.wallpaper.blur";
static NSString *const ExteriaWallpaperDimKey = @"exteria.wallpaper.dim";

/* the longest side of a stored photo, in pixels: the 4s shows a wallpaper at 960, and a bigger one would only cost memory */
#define PHOTO_SIDE_MAX 1280.0
/* the pattern is darkened or lightened up to this much at full intensity */
#define PATTERN_ALPHA_MAX 0.55
/* blur a quarter-size image to keep the temporary buffers small on ios 5 */
#define BLUR_DIVISOR 4.0
#define DIM_ALPHA_MAX 0.8

#pragma mark storage

static NSInteger ExteriaStoredInteger(NSString *key, NSInteger fallback) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : fallback;
}

static NSInteger ExteriaClampInt(NSInteger value, NSInteger low, NSInteger high) {
    return value < low ? low : (value > high ? high : value);
}

/* each tone keeps its own wallpaper: the night keys carry a suffix, the day ones are the keys the app always had */
static NSString *ExteriaToneKey(NSString *key, BOOL dark) {
    return dark ? [key stringByAppendingString:@".dark"] : key;
}

static BOOL ExteriaToneHasKey(NSString *key, BOOL dark) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:ExteriaToneKey(key, dark)] != nil;
}

static NSInteger ExteriaToneInteger(NSString *key, BOOL dark, NSInteger fallback) {
    return ExteriaStoredInteger(ExteriaToneKey(key, dark), fallback);
}

/* how light a gradient is, 0 to 1, by the middle of its two colors */
static CGFloat ExteriaColorsLightness(uint32_t top, uint32_t bottom) {
    CGFloat sum = 0;
    uint32_t colors[2] = {top, bottom};
    for (int i = 0; i < 2; ++i) {
        sum += (0.299 * ((colors[i] >> 16) & 0xFF) + 0.587 * ((colors[i] >> 8) & 0xFF) + 0.114 * (colors[i] & 0xFF)) / 255.0;
    }
    return sum / 2;
}

/* a gradient that does not belong to the tone, a dark one by day or a light one by night, is not the wallpaper of that tone */
static BOOL ExteriaColorsFitTone(uint32_t top, uint32_t bottom, BOOL dark) {
    CGFloat lightness = ExteriaColorsLightness(top, bottom);
    return dark ? lightness <= 0.45 : lightness >= 0.4;
}

static ExteriaWallpaperSetting ExteriaWallpaperStoredForTone(BOOL dark) {
    ExteriaWallpaperSetting setting;
    /* the night had no keys of its own before: what the day keys hold stands for it when it is a dark gradient */
    BOOL own = dark ? ExteriaToneHasKey(ExteriaWallpaperKindKey, YES) : YES;
    BOOL keysDark = dark && own;
    NSInteger kind = own ? ExteriaToneInteger(ExteriaWallpaperKindKey, keysDark, ExteriaWallpaperStandard) : ExteriaStoredInteger(ExteriaWallpaperKindKey, ExteriaWallpaperStandard);
    setting.kind = kind == ExteriaWallpaperColors || kind == ExteriaWallpaperPhoto ? (ExteriaWallpaperKind)kind : ExteriaWallpaperStandard;
    BOOL source = keysDark;
    setting.top = (uint32_t)(ExteriaToneInteger(ExteriaWallpaperTopKey, source, 0xD6E2EE) & 0xFFFFFF);
    setting.bottom = (uint32_t)(ExteriaToneInteger(ExteriaWallpaperBottomKey, source, 0xC1D2E7) & 0xFFFFFF);
    setting.angle = (int)ExteriaClampInt(ExteriaToneInteger(ExteriaWallpaperAngleKey, source, 45), 0, 359);
    setting.pattern = ExteriaToneInteger(ExteriaWallpaperPatternKey, source, 1) ? 1 : 0;
    setting.intensity = (int)ExteriaClampInt(ExteriaToneInteger(ExteriaWallpaperIntensityKey, source, 50), 0, 100);
    setting.blur = ExteriaToneInteger(ExteriaWallpaperBlurKey, source, 0) ? 1 : 0;
    setting.dim = (int)ExteriaClampInt(ExteriaToneInteger(ExteriaWallpaperDimKey, source, 0), 0, 100);
    if (setting.kind == ExteriaWallpaperColors && !ExteriaColorsFitTone(setting.top, setting.bottom, dark)) setting.kind = ExteriaWallpaperStandard;
    /* the photo of the day is the one the app always kept; the night has a file of its own, so legacy keys never lend a photo to it */
    if (setting.kind == ExteriaWallpaperPhoto && dark && !own) setting.kind = ExteriaWallpaperStandard;
    return setting;
}

ExteriaWallpaperSetting ExteriaWallpaperStored(void) {
    return ExteriaWallpaperStoredForTone(ExteriaThemeIsDark());
}

void ExteriaWallpaperStore(ExteriaWallpaperSetting setting) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL dark = ExteriaThemeIsDark();
    [defaults setInteger:setting.kind forKey:ExteriaToneKey(ExteriaWallpaperKindKey, dark)];
    [defaults setInteger:setting.top & 0xFFFFFF forKey:ExteriaToneKey(ExteriaWallpaperTopKey, dark)];
    [defaults setInteger:setting.bottom & 0xFFFFFF forKey:ExteriaToneKey(ExteriaWallpaperBottomKey, dark)];
    [defaults setInteger:ExteriaClampInt(setting.angle, 0, 359) forKey:ExteriaToneKey(ExteriaWallpaperAngleKey, dark)];
    [defaults setInteger:setting.pattern ? 1 : 0 forKey:ExteriaToneKey(ExteriaWallpaperPatternKey, dark)];
    [defaults setInteger:ExteriaClampInt(setting.intensity, 0, 100) forKey:ExteriaToneKey(ExteriaWallpaperIntensityKey, dark)];
    [defaults setInteger:setting.blur ? 1 : 0 forKey:ExteriaToneKey(ExteriaWallpaperBlurKey, dark)];
    [defaults setInteger:ExteriaClampInt(setting.dim, 0, 100) forKey:ExteriaToneKey(ExteriaWallpaperDimKey, dark)];
    ExteriaDefaultsSaveSoon();
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaWallpaperDidChangeNotification object:nil];
}

static NSString *ExteriaWallpaperPhotoPathForTone(BOOL dark) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [[[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:dark ? @"wallpaper-dark.jpg" : @"wallpaper.jpg"];
}

static NSString *ExteriaWallpaperPhotoPath(void) {
    return ExteriaWallpaperPhotoPathForTone(ExteriaThemeIsDark());
}

BOOL ExteriaWallpaperUsePhotoAtPath(NSString *path) {
    UIImage *photo = [UIImage imageWithContentsOfFile:path];
    if (!photo) return NO;
    /* a photo from the library is shrunk once, to what any screen shows, and kept as a jpeg */
    CGFloat longest = MAX(photo.size.width, photo.size.height);
    CGFloat factor = longest > PHOTO_SIDE_MAX ? PHOTO_SIDE_MAX / longest : 1;
    UIImage *kept = photo;
    if (factor < 1) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(floor(photo.size.width * factor), floor(photo.size.height * factor)), YES, 1);
        [photo drawInRect:CGRectMake(0, 0, floor(photo.size.width * factor), floor(photo.size.height * factor))];
        kept = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    NSData *data = UIImageJPEGRepresentation(kept, 0.85);
    NSString *target = ExteriaWallpaperPhotoPath();
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[target stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!data || ![data writeToFile:target options:NSDataWritingAtomic error:&error]) {
        NSLog(@"exteria: the wallpaper photo was not kept: %@", error);
        return NO;
    }
    ExteriaWallpaperSetting setting = ExteriaWallpaperStored();
    setting.kind = ExteriaWallpaperPhoto;
    setting.blur = 0;
    setting.dim = 0;
    ExteriaWallpaperStore(setting);
    return YES;
}

#pragma mark presets

typedef struct {
    uint32_t top, bottom;
    int angle;
} ExteriaPreset;

/* the grounds the white theme offers: pale and soft ones, a plain white to close them */
static const ExteriaPreset ExteriaLightPresets[] = {
    {0xD6E2EE, 0xC1D2E7, 45}, {0xDBDDBB, 0x6BA587, 45}, {0xE6EBEE, 0xC8D4DA, 90}, {0xFFE0B2, 0xF8B195, 45},
    {0xE1BEE7, 0xB39DDB, 45}, {0xF8BBD0, 0xCE93D8, 45}, {0xB2EBF2, 0x80DEEA, 90}, {0xC5E1A5, 0x9CCC65, 45},
    {0xFFF59D, 0xFFCC80, 45}, {0x90A4AE, 0x546E7A, 90}, {0xFAD0C4, 0xFF9A9E, 45}, {0xA1C4FD, 0xC2E9FB, 90},
    {0xD4FC79, 0x96E6A1, 45}, {0xE0C3FC, 0x8EC5FC, 45}, {0xF5F7FA, 0xB8C6DB, 90}, {0xFFECD2, 0xFCB69F, 45},
    {0xFF9A9E, 0xFECFEF, 45}, {0xC1DFC4, 0xDEECDD, 90}, {0xFBC2EB, 0xA6C1EE, 45}, {0xD299C2, 0xFEF9D7, 45},
    {0xB5FFFC, 0xFFDEE9, 45}, {0xF6D365, 0xFDA085, 45}, {0xCFD9DF, 0xE2EBF0, 90}, {0xC9FFBF, 0xFFAFBD, 45},
    {0xA8EDEA, 0xFED6E3, 45}, {0xFFDDE1, 0xEE9CA7, 45}, {0xBDE0FE, 0xA2D2FF, 90}, {0xFFC8DD, 0xCDB4DB, 45},
    {0xCAF0F8, 0x90E0EF, 45}, {0xFFE5D9, 0xD8E2DC, 90}, {0xE9EDC9, 0xCCD5AE, 90}, {0xFEC89A, 0xF9DCC4, 45},
    {0xE7C6FF, 0xC8B6FF, 45}, {0xB9FBC0, 0x98F5E1, 45}, {0xFBF8CC, 0xFDE4CF, 45}, {0xFFFFFF, 0xFFFFFF, 90},
};

/* the grounds the dark theme offers: deep ones, a plain black to close them */
static const ExteriaPreset ExteriaDarkPresets[] = {
    {0x3E3A54, 0x1B1830, 45}, {0x0F2027, 0x2C5364, 45}, {0x232526, 0x414345, 90}, {0x1E2A44, 0x3B4F7A, 45},
    {0x41295A, 0x2F0743, 45}, {0x2C3E50, 0x4CA1AF, 45}, {0x141E30, 0x243B55, 45}, {0x0F0C29, 0x302B63, 45},
    {0x1F1C2C, 0x4B4668, 45}, {0x373B44, 0x4286F4, 45}, {0x200122, 0x6F0000, 45}, {0x2B5876, 0x4E4376, 45},
    {0x134E5E, 0x2F6B4F, 45}, {0x3A1C71, 0x8E3B6B, 45}, {0x16222A, 0x3A6073, 45}, {0x42275A, 0x734B6D, 45},
    {0x1E3C72, 0x2A5298, 45}, {0x3C3B3F, 0x605C3C, 45}, {0x1D4350, 0x2B2B3A, 45}, {0x4B1D3F, 0x1B1B2F, 45},
    {0x0B3D2E, 0x1B1B2F, 90}, {0x2D1B4E, 0x0F172A, 90}, {0x101820, 0x101820, 90}, {0x000000, 0x000000, 90},
};

#define LIGHT_PRESET_COUNT (sizeof(ExteriaLightPresets) / sizeof(ExteriaLightPresets[0]))
#define DARK_PRESET_COUNT (sizeof(ExteriaDarkPresets) / sizeof(ExteriaDarkPresets[0]))

/* the picker offers the grounds of the theme on screen: the light ones by day, the dark ones by night */
static const ExteriaPreset *ExteriaShownPresets(NSUInteger *count) {
    if (ExteriaThemeIsDark()) {
        *count = DARK_PRESET_COUNT;
        return ExteriaDarkPresets;
    }
    *count = LIGHT_PRESET_COUNT;
    return ExteriaLightPresets;
}

NSUInteger ExteriaWallpaperPresetCount(void) {
    NSUInteger count;
    ExteriaShownPresets(&count);
    return count;
}

ExteriaWallpaperSetting ExteriaWallpaperPreset(NSUInteger index) {
    ExteriaWallpaperSetting setting = ExteriaWallpaperStored();
    NSUInteger count;
    const ExteriaPreset *presets = ExteriaShownPresets(&count);
    if (index >= count) index = 0;
    setting.kind = ExteriaWallpaperColors;
    setting.top = presets[index].top;
    setting.bottom = presets[index].bottom;
    setting.angle = presets[index].angle;
    return setting;
}

#pragma mark drawing

static void ExteriaWallpaperRGB(uint32_t rgb, CGFloat out[4]) {
    out[0] = ((rgb >> 16) & 0xFF) / 255.0;
    out[1] = ((rgb >> 8) & 0xFF) / 255.0;
    out[2] = (rgb & 0xFF) / 255.0;
    out[3] = 1;
}

static CGRect ExteriaFillRect(CGSize source, CGSize target) {
    CGFloat scale = MAX(target.width / source.width, target.height / source.height);
    CGSize fitted = CGSizeMake(source.width * scale, source.height * scale);
    return CGRectMake((target.width - fitted.width) / 2, (target.height - fitted.height) / 2, fitted.width, fitted.height);
}

/* the doodle pattern in one color, as a picture with transparency: the color everywhere, kept only where the pattern has ink */
static UIImage *ExteriaPatternInColor(UIColor *ink) {
    /* the pattern is a 720 by 1280 picture, and a slider that moves the intensity asked for it again at every step; the black and the white one are kept */
    static UIImage *kept[2];
    NSUInteger slot = [ink isEqual:[UIColor blackColor]] ? 0 : 1;
    static BOOL watching;
    if (!watching) {
        watching = YES;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            (void)note;
            for (int i = 0; i < 2; ++i) {
                [kept[i] release];
                kept[i] = nil;
            }
        }];
    }
    if (kept[slot]) return kept[slot];
    UIImage *pattern = [UIImage imageNamed:@"chat_pattern.png"];
    if (!pattern) return nil;
    UIGraphicsBeginImageContextWithOptions(pattern.size, NO, 1);
    CGRect rect = CGRectMake(0, 0, pattern.size.width, pattern.size.height);
    [ink setFill];
    UIRectFill(rect);
    [pattern drawInRect:rect blendMode:kCGBlendModeDestinationIn alpha:1];
    kept[slot] = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return kept[slot];
}

static UIImage *ExteriaColorsImage(ExteriaWallpaperSetting setting, CGSize size) {
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat colors[8];
    ExteriaWallpaperRGB(setting.top, colors);
    ExteriaWallpaperRGB(setting.bottom, colors + 4);
    /* the gradient runs along its angle through the middle of the picture, and reaches the corners */
    CGFloat radians = setting.angle * M_PI / 180.0;
    CGFloat reach = (fabs(cos(radians)) * size.width + fabs(sin(radians)) * size.height) / 2;
    CGPoint middle = CGPointMake(size.width / 2, size.height / 2);
    CGPoint from = CGPointMake(middle.x - cos(radians) * reach, middle.y - sin(radians) * reach);
    CGPoint to = CGPointMake(middle.x + cos(radians) * reach, middle.y + sin(radians) * reach);
    ExteriaFillGradient(context, from, to, colors, 2);
    if (setting.pattern && setting.intensity > 0) {
        /* black ink on a light ground, white on a dark one, by the brightness of the middle of the gradient */
        CGFloat mid = ((colors[0] + colors[4]) * 0.299 + (colors[1] + colors[5]) * 0.587 + (colors[2] + colors[6]) * 0.114) / 2;
        UIColor *ink = mid > 0.5 ? [UIColor blackColor] : [UIColor whiteColor];
        UIImage *pattern = ExteriaPatternInColor(ink);
        if (pattern) [pattern drawInRect:ExteriaFillRect(pattern.size, size) blendMode:kCGBlendModeNormal alpha:(CGFloat)(setting.intensity / 100.0 * PATTERN_ALPHA_MAX)];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static UIImage *ExteriaPhotoImage(ExteriaWallpaperSetting setting, CGSize size) {
    UIImage *photo = [UIImage imageWithContentsOfFile:ExteriaWallpaperPhotoPath()];
    if (!photo) return nil;
    UIImage *source = photo;
    if (setting.blur) {
        CGSize small = CGSizeMake(MAX(8, floor(size.width / BLUR_DIVISOR)), MAX(8, floor(size.height / BLUR_DIVISOR)));
        size_t width = (size_t)small.width, height = (size_t)small.height, row = width * 4;
        void *pixels = calloc(height, row), *scratch = calloc(height, row);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = pixels && colorSpace ? CGBitmapContextCreate(pixels, width, height, 8, row, colorSpace, kCGImageAlphaPremultipliedLast) : NULL;
        if (colorSpace) CGColorSpaceRelease(colorSpace);
        if (bitmap && scratch) {
            UIGraphicsPushContext(bitmap);
            CGContextTranslateCTM(bitmap, 0, small.height);
            CGContextScaleCTM(bitmap, 1, -1);
            CGContextSetInterpolationQuality(bitmap, kCGInterpolationHigh);
            [photo drawInRect:ExteriaFillRect(photo.size, small)];
            UIGraphicsPopContext();
            vImage_Buffer a = {pixels, height, width, row}, b = {scratch, height, width, row};
            vImage_Error error = vImageBoxConvolve_ARGB8888(&a, &b, NULL, 0, 0, 9, 9, NULL, kvImageEdgeExtend);
            if (error == kvImageNoError) error = vImageBoxConvolve_ARGB8888(&b, &a, NULL, 0, 0, 9, 9, NULL, kvImageEdgeExtend);
            if (error == kvImageNoError) error = vImageBoxConvolve_ARGB8888(&a, &b, NULL, 0, 0, 9, 9, NULL, kvImageEdgeExtend);
            if (error == kvImageNoError) {
                NSData *copy = [NSData dataWithBytes:scratch length:row * height];
                CGDataProviderRef provider = copy ? CGDataProviderCreateWithCFData((CFDataRef)copy) : NULL;
                CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
                CGImageRef blurred = provider && rgb ? CGImageCreate(width, height, 8, 32, row, rgb, (CGBitmapInfo)kCGImageAlphaPremultipliedLast,
                                                                     provider, NULL, true, kCGRenderingIntentDefault) : NULL;
                if (blurred) { source = [UIImage imageWithCGImage:blurred]; CGImageRelease(blurred); }
                else NSLog(@"exteria: blurred wallpaper image could not be made");
                if (provider) CGDataProviderRelease(provider);
                if (rgb) CGColorSpaceRelease(rgb);
            } else NSLog(@"exteria: wallpaper blur failed: %ld", (long)error);
        } else NSLog(@"exteria: wallpaper blur buffers could not be allocated");
        if (bitmap) CGContextRelease(bitmap);
        free(pixels);
        free(scratch);
    }
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [source drawInRect:ExteriaFillRect(source.size, size)];
    if (setting.dim > 0) {
        [[UIColor colorWithWhite:0 alpha:(CGFloat)(setting.dim / 100.0 * DIM_ALPHA_MAX)] setFill];
        UIRectFillUsingBlendMode(CGRectMake(0, 0, size.width, size.height), kCGBlendModeNormal);
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

UIImage *ExteriaWallpaperImage(ExteriaWallpaperSetting setting, CGSize size) {
    if (size.width < 1 || size.height < 1) return nil;
    switch (setting.kind) {
    case ExteriaWallpaperColors: return ExteriaColorsImage(setting, size);
    case ExteriaWallpaperPhoto: return ExteriaPhotoImage(setting, size);
    case ExteriaWallpaperStandard: break;
    }
    return nil;
}

/* the picture of the setting on screen is made once and kept until the setting changes, since a screen of a chat
   asks for it every time it opens */
static UIImage *ExteriaShownWallpaper(void) {
    static UIImage *cached;
    static ExteriaWallpaperSetting cachedSetting;
    static BOOL watching;
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSObject alloc] init]; });
    @synchronized (lock) {
        if (!watching) {
            watching = YES;
            [[NSNotificationCenter defaultCenter] addObserverForName:ExteriaWallpaperDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                (void)note;
                @synchronized (lock) {
                    [cached release];
                    cached = nil;
                }
            }];
        }
        ExteriaWallpaperSetting setting = ExteriaWallpaperStored();
        if (setting.kind == ExteriaWallpaperStandard) return nil;
        if (!cached || memcmp(&setting, &cachedSetting, sizeof(setting)) != 0) {
            [cached release];
            cached = [ExteriaWallpaperImage(setting, [UIScreen mainScreen].bounds.size) retain];
            cachedSetting = setting;
        }
        return [[cached retain] autorelease];
    }
}

void ExteriaWallpaperWarm(void) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool { (void)ExteriaShownWallpaper(); }
    });
}

/* the preview of the settings asks for a small picture of the same setting at every layout and at every step of a slider, and a step back to a value
   already seen needs no new painting */
static UIImage *ExteriaSizedWallpaper(ExteriaWallpaperSetting setting, CGSize size) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 4;
        [[NSNotificationCenter defaultCenter] addObserverForName:ExteriaWallpaperDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            (void)note;
            [cache removeAllObjects];
        }];
    });
    NSString *key = [NSString stringWithFormat:@"%@|%.1fx%.1f", [[NSData dataWithBytes:&setting length:sizeof(setting)] description], (double)size.width, (double)size.height];
    UIImage *image = [cache objectForKey:key];
    if (!image) {
        image = ExteriaWallpaperImage(setting, size);
        if (image) [cache setObject:image forKey:key];
    }
    return image;
}

#pragma mark applying

void ExteriaApplyChatWallpaper(UIImageView *view, BOOL dark) {
    BOOL classic = ExteriaThemeIsClassic();
    ExteriaApplyWallpaperStyle(view, classic, dark);
    /* the picked wallpaper takes the place of the standard picture, or of the linen in the classic style */
    UIImage *picked = ExteriaShownWallpaper();
    if (picked) view.image = picked;
}

void ExteriaApplyChatWallpaperSized(UIImageView *view, BOOL dark, CGSize size) {
    BOOL classic = ExteriaThemeIsClassic();
    ExteriaApplyWallpaperStyle(view, classic, dark);
    ExteriaWallpaperSetting setting = ExteriaWallpaperStored();
    /* a preview a few hundred points wide does not need the picture of the whole screen, which cost a full repaint of the pattern at every step of a slider */
    if (setting.kind != ExteriaWallpaperStandard) view.image = ExteriaSizedWallpaper(setting, size);
}

void ExteriaApplyWallpaperStyle(UIImageView *view, BOOL classic, BOOL dark) {
    view.image = classic ? nil : [UIImage imageNamed:dark ? @"chat_bg_dark.jpg" : @"chat_bg_light.jpg"];
    /* the classic wallpaper is a linen tile, laid as a pattern so the system repeats it at any size */
    UIImage *linen = classic ? [UIImage imageNamed:dark ? @"chat_linen_dark.png" : @"chat_linen_light.png"] : nil;
    view.backgroundColor = linen ? [UIColor colorWithPatternImage:linen] : ExteriaColorChatBackground();
    view.contentMode = UIViewContentModeScaleAspectFill;
    view.clipsToBounds = YES;
}


#pragma mark tint

/* the hue the picture of a photo wallpaper leans to; NO for a picture without a clear color */
static BOOL ExteriaPhotoHue(UIImage *image, float *hue) {
    enum { Side = 24, Bins = 36 };
    uint8_t pixels[Side * Side * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, Side, Side, 8, Side * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context || !image.CGImage) {
        CGContextRelease(context);
        return NO;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, Side, Side), image.CGImage);
    CGContextRelease(context);
    double weight[Bins] = {0};
    double total = 0;
    for (int i = 0; i < Side * Side; ++i) {
        CGFloat h, s, v;
        ExteriaRGBToHSV(pixels[i * 4] / 255.0, pixels[i * 4 + 1] / 255.0, pixels[i * 4 + 2] / 255.0, &h, &s, &v);
        if (s < 0.2 || v < 0.2) continue;
        weight[(int)(h / (360.0 / Bins)) % Bins] += s * v;
        total += s * v;
    }
    int best = 0;
    for (int i = 1; i < Bins; ++i) {
        if (weight[i] + weight[(i + 1) % Bins] > weight[best] + weight[(best + 1) % Bins]) best = i;
    }
    if (total < Side * Side * 0.05) return NO;
    /* the strongest bin and the one after it, at the middle of each */
    double a = weight[best], b = weight[(best + 1) % Bins];
    double step = 360.0 / Bins;
    double center = (best + 0.5) * step;
    double next = (best + 1.5) * step;
    *hue = (float)fmod((center * a + next * b) / (a + b) , 360);
    return YES;
}

/* the hue of a wallpaper, in degrees, when it has one */
static BOOL ExteriaWallpaperHue(ExteriaWallpaperSetting setting, BOOL dark, float *hue) {
    if (setting.kind == ExteriaWallpaperStandard) return NO;
    if (setting.kind == ExteriaWallpaperPhoto) {
        UIImage *photo = [UIImage imageWithContentsOfFile:ExteriaWallpaperPhotoPathForTone(dark)];
        return photo && ExteriaPhotoHue(photo, hue);
    }
    CGFloat r = (((setting.top >> 16) & 0xFF) + ((setting.bottom >> 16) & 0xFF)) / 510.0;
    CGFloat g = (((setting.top >> 8) & 0xFF) + ((setting.bottom >> 8) & 0xFF)) / 510.0;
    CGFloat b = ((setting.top & 0xFF) + (setting.bottom & 0xFF)) / 510.0;
    CGFloat h, s, v;
    ExteriaRGBToHSV(r, g, b, &h, &s, &v);
    if (s < 0.12 || v < 0.15) return NO;
    *hue = (float)h;
    return YES;
}

void ExteriaWallpaperRetintTheme(CGPoint origin) {
    float hue = 0, was = 0;
    BOOL tinted = ExteriaWallpaperHue(ExteriaWallpaperStored(), ExteriaThemeIsDark(), &hue);
    BOOL wasTinted = ExteriaThemeStoredTint(&was);
    /* a few degrees are not worth a new coat on every screen */
    if (tinted == wasTinted && (!tinted || fabsf(hue - was) < 2)) return;
    ExteriaThemeStoreTint(tinted, hue);
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:origin] forKey:ExteriaThemeOriginKey]];
}

void ExteriaWallpaperSyncTintForTone(BOOL dark) {
    float hue = 0;
    BOOL tinted = ExteriaWallpaperHue(ExteriaWallpaperStoredForTone(dark), dark, &hue);
    float was = 0;
    BOOL wasTinted = ExteriaThemeStoredTint(&was);
    if (tinted == wasTinted && (!tinted || fabsf(hue - was) < 0.5f)) return;
    ExteriaThemeStoreTint(tinted, hue);
}
