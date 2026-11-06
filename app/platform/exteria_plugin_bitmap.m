#import "exteria_plugin_bitmap.h"

#import <UIKit/UIKit.h>

#import "exteria_image_decoder.h"
#import "exteria_plugins.h"
#include "exteria_stack_blur.h"

#define PICKS_KEPT 4
#define PIXELS_MAX (8u * 1024u * 1024u)
#define BYTES_LIVE_MAX (64u * 1024u * 1024u)

#pragma mark folder of the pictures a person chose

static NSString *const PicksPrefix = @"pick-";
static NSString *const PicksSuffix = @".jpg";

NSString *ExteriaPluginPicksDirectory(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [[roots objectAtIndex:0] stringByAppendingPathComponent:@"exteria-plugin-pictures"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: cannot create %@: %@", directory, error);
    }
    return directory;
}

static BOOL is_pick_name(NSString *name) {
    return [name hasPrefix:PicksPrefix] && [name hasSuffix:PicksSuffix] && name.length > PicksPrefix.length + PicksSuffix.length;
}

/* a path the app may read for a plugin: a regular file (not a link) named like a pick, directly inside the folder. the folder is compared after its links are
   resolved, since the sandbox path of the app has /var and /private/var for the same place */
static BOOL path_is_pick(NSString *path, NSString **failure) {
    if (![path isKindOfClass:[NSString class]] || ![path isAbsolutePath] || !is_pick_name([path lastPathComponent])) {
        if (failure) *failure = @"not a picture the person chose";
        return NO;
    }
    NSString *parent = [[path stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath];
    NSString *root = [ExteriaPluginPicksDirectory() stringByResolvingSymlinksInPath];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (![parent isEqualToString:root] || ![[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeRegular]) {
        if (failure) *failure = @"not a picture the person chose";
        return NO;
    }
    return YES;
}

/* a file a plugin may have decoded: a pick, or a regular file directly or deeper inside the plugin files folder. links are refused, the folder is compared resolved */
static BOOL path_is_readable(NSString *path, NSString **failure) {
    if (path_is_pick(path, NULL)) return YES;
    NSDictionary *attributes = [path isKindOfClass:[NSString class]] && [path isAbsolutePath] ? [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] : nil;
    BOOL regular = [[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeRegular];
    if (!regular || !ExteriaPluginsPathInCache(path) || [[path pathComponents] containsObject:@".."]) {
        if (failure) *failure = @"not a picture of the plugin";
        return NO;
    }
    return YES;
}

/* where an encoded picture may be written: a plain name directly inside the plugin files folder, over nothing or over a regular file */
static BOOL path_is_writable(NSString *path, NSString **failure) {
    NSString *name = [path lastPathComponent];
    NSString *root = [ExteriaPluginsCacheDirectory() stringByResolvingSymlinksInPath];
    NSString *parent = [[path stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    BOOL clean = [path isKindOfClass:[NSString class]] && [path isAbsolutePath] && name.length && ![name hasPrefix:@"."] && ![[path pathComponents] containsObject:@".."];
    BOOL inside = [parent isEqualToString:root] || [parent hasPrefix:[root stringByAppendingString:@"/"]];
    BOOL free = !attributes || [[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeRegular];
    if (!clean || !inside || !free) {
        if (failure) *failure = @"a picture can be written inside the plugin files folder only";
        return NO;
    }
    return YES;
}

NSString *ExteriaPluginPicksAdopt(NSString *path, NSString **failure) {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *directory = ExteriaPluginPicksDirectory();
    NSString *name = [NSString stringWithFormat:@"%@%08x%08x%@", PicksPrefix, arc4random(), arc4random(), PicksSuffix];
    NSString *target = [directory stringByAppendingPathComponent:name];
    NSError *error = nil;
    if (![files moveItemAtPath:path toPath:target error:&error]) {
        NSLog(@"exteria: the picture for a plugin was not kept: %@", error);
        if (failure) *failure = @"the picture could not be kept";
        return nil;
    }
    NSMutableArray *picks = [NSMutableArray array];
    for (NSString *entry in [files contentsOfDirectoryAtPath:directory error:NULL]) {
        if (!is_pick_name(entry)) continue;
        NSDate *date = [[files attributesOfItemAtPath:[directory stringByAppendingPathComponent:entry] error:NULL] objectForKey:NSFileModificationDate];
        [picks addObject:[NSDictionary dictionaryWithObjectsAndKeys:entry, @"name", date ? date : [NSDate distantPast], @"date", nil]];
    }
    [picks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [[b objectForKey:@"date"] compare:[a objectForKey:@"date"]];
    }];
    for (NSUInteger i = PICKS_KEPT; i < picks.count; ++i) {
        NSString *old = [[picks objectAtIndex:i] objectForKey:@"name"];
        if ([old isEqualToString:name]) continue;
        if (![files removeItemAtPath:[directory stringByAppendingPathComponent:old] error:&error]) NSLog(@"exteria: an old picture of a plugin stayed: %@", error);
    }
    return target;
}

#pragma mark pictures kept for python

@interface ExteriaPluginBitmap : NSObject {
@public
    NSMutableData *pixels;
    int width;
    int height;
}
@end

@implementation ExteriaPluginBitmap
- (void)dealloc {
    [pixels release];
    [super dealloc];
}
@end

static NSMutableDictionary *g_bitmaps;
static long long g_next_handle;
static NSUInteger g_live_bytes;

static exteria_status refuse(NSString **failure, NSString *text, exteria_status status) {
    if (failure) *failure = text;
    return status;
}

static ExteriaPluginBitmap *bitmap_for(long long handle) {
    return [g_bitmaps objectForKey:[NSNumber numberWithLongLong:handle]];
}

/* a blank picture of the size, or nil with the reason: sizes are bounded so a plugin cannot ask for the memory of the phone */
static ExteriaPluginBitmap *make_bitmap(int width, int height, exteria_status *status, NSString **failure) {
    if (width < 1 || height < 1 || width > EXTERIA_PLUGIN_BITMAP_SIDE_MAX || height > EXTERIA_PLUGIN_BITMAP_SIDE_MAX || (unsigned long long)width * (unsigned long long)height > PIXELS_MAX) {
        *status = refuse(failure, [NSString stringWithFormat:@"a picture of %dx%d is too large", width, height], EXTERIA_E_LIMIT);
        return nil;
    }
    NSUInteger bytes = (NSUInteger)width * (NSUInteger)height * 4;
    if (g_bitmaps.count >= EXTERIA_PLUGIN_BITMAP_LIVE_MAX || g_live_bytes + bytes > BYTES_LIVE_MAX) {
        *status = refuse(failure, @"too many pictures are held, let go of one first", EXTERIA_E_LIMIT);
        return nil;
    }
    ExteriaPluginBitmap *bitmap = [[[ExteriaPluginBitmap alloc] init] autorelease];
    bitmap->pixels = [[NSMutableData alloc] initWithLength:bytes];
    if (!bitmap->pixels) {
        *status = refuse(failure, @"not enough memory for the picture", EXTERIA_E_NOMEM);
        return nil;
    }
    bitmap->width = width;
    bitmap->height = height;
    return bitmap;
}

static NSDictionary *keep(ExteriaPluginBitmap *bitmap) {
    if (!g_bitmaps) g_bitmaps = [[NSMutableDictionary alloc] init];
    long long handle = ++g_next_handle;
    [g_bitmaps setObject:bitmap forKey:[NSNumber numberWithLongLong:handle]];
    g_live_bytes += bitmap->pixels.length;
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:handle], @"handle", [NSNumber numberWithInt:bitmap->width], @"w",
            [NSNumber numberWithInt:bitmap->height], @"h", nil];
}

static void release_pixels(void *info, const void *data, size_t size) {
    (void)data;
    (void)size;
    [(NSData *)info release];
}

/* pixels are premultiplied rgba, the format a bitmap context draws in */
static const CGBitmapInfo PixelFormat = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;

CGImageRef ExteriaPluginBitmapCreateImage(long long handle) {
    ExteriaPluginBitmap *bitmap = bitmap_for(handle);
    if (!bitmap) return NULL;
    NSData *copy = [bitmap->pixels copy];
    CGDataProviderRef provider = CGDataProviderCreateWithData(copy, copy.bytes, copy.length, release_pixels);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate((size_t)bitmap->width, (size_t)bitmap->height, 8, 32, (size_t)bitmap->width * 4, space, PixelFormat, provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

/* draws a picture into a new bitmap of the given size */
static ExteriaPluginBitmap *draw_into_bitmap(CGImageRef image, int width, int height, exteria_status *status, NSString **failure) {
    ExteriaPluginBitmap *bitmap = make_bitmap(width, height, status, failure);
    if (!bitmap) return nil;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(bitmap->pixels.mutableBytes, (size_t)width, (size_t)height, 8, (size_t)width * 4, space, PixelFormat);
    CGColorSpaceRelease(space);
    if (!context) {
        *status = refuse(failure, @"the picture could not be drawn", EXTERIA_E_NOMEM);
        return nil;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    *status = EXTERIA_OK;
    return bitmap;
}

exteria_status ExteriaPluginBitmapDecode(NSString *path, int side, NSDictionary **reply, NSString **failure) {
    if (side < 1 || side > EXTERIA_PLUGIN_BITMAP_SIDE_MAX) return refuse(failure, @"the side of a picture is 1 to 4096", EXTERIA_E_ARG);
    if (!path_is_readable(path, failure)) return EXTERIA_E_SECURITY;
    UIImage *image = ExteriaDecodeImageAtURL([NSURL fileURLWithPath:path], (CGFloat)side);
    CGImageRef source = image.CGImage;
    if (!source) return refuse(failure, @"not a picture the app can decode", EXTERIA_E_MALFORMED);
    exteria_status status = EXTERIA_OK;
    ExteriaPluginBitmap *bitmap = draw_into_bitmap(source, (int)CGImageGetWidth(source), (int)CGImageGetHeight(source), &status, failure);
    if (!bitmap) return status;
    *reply = keep(bitmap);
    return EXTERIA_OK;
}

exteria_status ExteriaPluginBitmapScale(long long handle, int width, int height, NSDictionary **reply, NSString **failure) {
    ExteriaPluginBitmap *from = bitmap_for(handle);
    if (!from) return refuse(failure, @"no such picture", EXTERIA_E_NOTFOUND);
    CGImageRef image = ExteriaPluginBitmapCreateImage(handle);
    if (!image) return refuse(failure, @"the picture could not be read", EXTERIA_E_NOMEM);
    exteria_status status = EXTERIA_OK;
    ExteriaPluginBitmap *bitmap = draw_into_bitmap(image, width, height, &status, failure);
    CGImageRelease(image);
    if (!bitmap) return status;
    *reply = keep(bitmap);
    return EXTERIA_OK;
}

exteria_status ExteriaPluginBitmapCrop(long long handle, int x, int y, int width, int height, NSDictionary **reply, NSString **failure) {
    ExteriaPluginBitmap *from = bitmap_for(handle);
    if (!from) return refuse(failure, @"no such picture", EXTERIA_E_NOTFOUND);
    if (x < 0 || y < 0 || width < 1 || height < 1 || (long long)x + width > from->width || (long long)y + height > from->height) return refuse(failure, @"the rectangle is not inside the picture", EXTERIA_E_ARG);
    CGImageRef whole = ExteriaPluginBitmapCreateImage(handle);
    CGImageRef part = whole ? CGImageCreateWithImageInRect(whole, CGRectMake(x, y, width, height)) : NULL;
    if (whole) CGImageRelease(whole);
    if (!part) return refuse(failure, @"the picture could not be cut", EXTERIA_E_NOMEM);
    exteria_status status = EXTERIA_OK;
    ExteriaPluginBitmap *bitmap = draw_into_bitmap(part, width, height, &status, failure);
    CGImageRelease(part);
    if (!bitmap) return status;
    *reply = keep(bitmap);
    return EXTERIA_OK;
}

exteria_status ExteriaPluginBitmapEncode(long long handle, BOOL png, int quality, NSString *path, NSString **failure) {
    if (!bitmap_for(handle)) return refuse(failure, @"no such picture", EXTERIA_E_NOTFOUND);
    if (quality < 1 || quality > 100) return refuse(failure, @"the quality is 1 to 100", EXTERIA_E_ARG);
    if (!path_is_writable(path, failure)) return EXTERIA_E_SECURITY;
    CGImageRef image = ExteriaPluginBitmapCreateImage(handle);
    if (!image) return refuse(failure, @"the picture could not be read", EXTERIA_E_NOMEM);
    UIImage *picture = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    NSData *data = png ? UIImagePNGRepresentation(picture) : UIImageJPEGRepresentation(picture, quality / 100.0f);
    NSError *error = nil;
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"exteria: a plugin picture was not written: %@", error);
        return refuse(failure, @"the picture could not be written", EXTERIA_E_IO);
    }
    return EXTERIA_OK;
}

exteria_status ExteriaPluginBitmapCopy(long long handle, NSDictionary **reply, NSString **failure) {
    ExteriaPluginBitmap *from = bitmap_for(handle);
    if (!from) return refuse(failure, @"no such picture", EXTERIA_E_NOTFOUND);
    exteria_status status = EXTERIA_OK;
    ExteriaPluginBitmap *bitmap = make_bitmap(from->width, from->height, &status, failure);
    if (!bitmap) return status;
    [bitmap->pixels setData:from->pixels];
    *reply = keep(bitmap);
    return EXTERIA_OK;
}

exteria_status ExteriaPluginBitmapBlur(long long handle, int radius, NSString **failure) {
    ExteriaPluginBitmap *bitmap = bitmap_for(handle);
    if (!bitmap) return refuse(failure, @"no such picture", EXTERIA_E_NOTFOUND);
    if (radius < 0 || (unsigned)radius > EXTERIA_STACK_BLUR_RADIUS_MAX) return refuse(failure, @"the blur radius is 0 to 254", EXTERIA_E_ARG);
    exteria_status status = exteria_stack_blur_rgba(bitmap->pixels.mutableBytes, bitmap->pixels.length, (uint32_t)bitmap->width, (uint32_t)bitmap->height, (uint32_t)radius);
    if (status != EXTERIA_OK) return refuse(failure, [NSString stringWithFormat:@"the picture could not be blurred (%s)", exteria_status_name(status)], status);
    return EXTERIA_OK;
}

void ExteriaPluginBitmapRelease(long long handle) {
    NSNumber *key = [NSNumber numberWithLongLong:handle];
    ExteriaPluginBitmap *bitmap = [g_bitmaps objectForKey:key];
    if (!bitmap) return;
    g_live_bytes -= bitmap->pixels.length;
    [g_bitmaps removeObjectForKey:key];
}
