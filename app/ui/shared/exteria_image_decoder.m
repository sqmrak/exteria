#import "exteria_image_decoder.h"

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>

#include "src/webp/decode.h"
#include "exteria_video_sticker_core.h"
#include "exteria_emoji.h"

/* no sticker or thumbnail is near this; it stops a crafted header from asking for gigabytes */
#define EXTERIA_DECODE_PIXELS_MAX (4096 * 4096)

ExteriaFileFormat ExteriaFileFormatOfData(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length >= 12 && !memcmp(bytes, "RIFF", 4) && !memcmp(bytes + 8, "WEBP", 4)) return ExteriaFileFormatWebP;
    if (length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) return ExteriaFileFormatGzip;
    if (length >= 4 && bytes[0] == 0x1a && bytes[1] == 0x45 && bytes[2] == 0xdf && bytes[3] == 0xa3) return ExteriaFileFormatMatroska;
    if (length >= 12 && !memcmp(bytes + 4, "ftyp", 4)) return ExteriaFileFormatMP4;
    return ExteriaFileFormatUnknown;
}

static void ExteriaReleasePixels(void *info, const void *data, size_t size) {
    (void)info;
    (void)size;
    free((void *)data);
}

static UIImage *ExteriaDecodeWebP(NSData *data, CGFloat maxSide) {
    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig(&config)) return nil;
    if (WebPGetFeatures(data.bytes, data.length, &config.input) != VP8_STATUS_OK) return nil;
    int width = config.input.width, height = config.input.height;
    if (width <= 0 || height <= 0 || (int64_t)width * height > EXTERIA_DECODE_PIXELS_MAX) return nil;
    CGFloat longest = width > height ? width : height;
    if (maxSide >= 1 && longest > maxSide) {
        CGFloat scale = maxSide / longest;
        int scaledWidth = (int)(width * scale + 0.5), scaledHeight = (int)(height * scale + 0.5);
        width = scaledWidth < 1 ? 1 : scaledWidth;
        height = scaledHeight < 1 ? 1 : scaledHeight;
        config.options.use_scaling = 1;
        config.options.scaled_width = width;
        config.options.scaled_height = height;
    }
    size_t stride = (size_t)width * 4;
    uint8_t *pixels = calloc((size_t)height, stride);
    if (!pixels) return nil;
    /* premultiplied bgra is little endian alpha first, the layout CoreGraphics draws without a conversion */
    config.output.colorspace = MODE_bgrA;
    config.output.is_external_memory = 1;
    config.output.u.RGBA.rgba = pixels;
    config.output.u.RGBA.stride = (int)stride;
    config.output.u.RGBA.size = stride * (size_t)height;
    VP8StatusCode status = WebPDecode(data.bytes, data.length, &config);
    WebPFreeDecBuffer(&config.output);
    if (status != VP8_STATUS_OK) {
        NSLog(@"exteria: webp decode failed, status %d", (int)status);
        free(pixels);
        return nil;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, stride * (size_t)height, ExteriaReleasePixels);
    if (!provider) {
        free(pixels);
        return nil;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate((size_t)width, (size_t)height, 8, 32, stride, space,
                                     kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, provider, NULL, false,
                                     kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    if (!image) return nil;
    UIImage *result = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    return result;
}

static UIImage *ExteriaDecodeWithImageIO(NSData *data, CGFloat maxSide) {
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    if (!source) return nil;
    UIImage *result = nil;
    if (CGImageSourceGetCount(source) > 0) {
        NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool:YES], (id)kCGImageSourceCreateThumbnailFromImageAlways,
            [NSNumber numberWithBool:YES], (id)kCGImageSourceCreateThumbnailWithTransform,
            [NSNumber numberWithDouble:maxSide >= 1 ? maxSide : 2048], (id)kCGImageSourceThumbnailMaxPixelSize, nil];
        CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)options);
        if (image) {
            result = [UIImage imageWithCGImage:image];
            CGImageRelease(image);
        }
    }
    CFRelease(source);
    return result;
}

static int sticker_poster(void *context, const uint8_t *pixels, int width, int height) {
    CFDataRef bytes = CFDataCreate(NULL, pixels, width * height * 4);
    CGDataProviderRef provider = bytes ? CGDataProviderCreateWithCFData(bytes) : NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = provider && space ? CGImageCreate(width, height, 8, 32, width * 4, space,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, provider, NULL, false, kCGRenderingIntentDefault) : NULL;
    if (provider) CGDataProviderRelease(provider);
    if (space) CGColorSpaceRelease(space);
    if (bytes) CFRelease(bytes);
    *(CGImageRef *)context = image;
    return image ? 0 : -1;
}

static UIImage *ExteriaDecodeVideoPoster(NSData *data, CGFloat maxSide) {
    CGImageRef poster = NULL;
    double duration = 0;
    int side = (int)MAX(8, MIN(192, maxSide >= 1 ? maxSide : 128));
    int frames = exteria_video_sticker_decode(data.bytes, data.length, side, 1, sticker_poster, &poster, &duration);
    UIImage *image = frames > 0 && poster ? [UIImage imageWithCGImage:poster] : nil;
    if (poster) CGImageRelease(poster);
    return image;
}

/* Telegram stores some gifs with no picture of the right size, only a small clip of the animation; its first
   picture stands in the bubble */
static UIImage *ExteriaDecodeClipPoster(NSData *data, CGFloat maxSide) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-poster-%08x%08x.mp4", arc4random(), arc4random()]];
    if (![data writeToFile:path atomically:NO]) {
        NSLog(@"exteria: cannot write the clip for its poster");
        return nil;
    }
    UIImage *result = nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    if (maxSide >= 1) generator.maximumSize = CGSizeMake(maxSide, maxSide);
    NSError *error = nil;
    CGImageRef frame = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:&error];
    if (frame) {
        result = [UIImage imageWithCGImage:frame];
        CGImageRelease(frame);
    } else {
        NSLog(@"exteria: no poster in the clip: %@", error);
    }
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    return result;
}

UIImage *ExteriaDecodeImage(NSData *data, CGFloat maxSide) {
    if (!data.length) return nil;
    switch (ExteriaFileFormatOfData(data)) {
    case ExteriaFileFormatWebP: return ExteriaDecodeWebP(data, maxSide);
    case ExteriaFileFormatGzip: return nil;
    case ExteriaFileFormatMatroska: return ExteriaDecodeVideoPoster(data, maxSide);
    case ExteriaFileFormatMP4: return ExteriaDecodeClipPoster(data, maxSide);
    case ExteriaFileFormatUnknown: break;
    }
    return ExteriaDecodeWithImageIO(data, maxSide);
}

UIImage *ExteriaDecodeImageAtURL(NSURL *url, CGFloat maxSide) {
    if (!url.isFileURL || !isfinite(maxSide) || maxSide < 1 || maxSide > 4096) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
    if (!source) return nil;
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:YES], (id)kCGImageSourceCreateThumbnailFromImageAlways,
        [NSNumber numberWithBool:YES], (id)kCGImageSourceCreateThumbnailWithTransform,
        [NSNumber numberWithDouble:maxSide], (id)kCGImageSourceThumbnailMaxPixelSize, nil];
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)options);
    UIImage *image = thumbnail ? [UIImage imageWithCGImage:thumbnail] : nil;
    if (thumbnail) CGImageRelease(thumbnail);
    CFRelease(source);
    return image;
}

UIImage *ExteriaFitEmojiImage(UIImage *image) {
    CGImageRef original = image.CGImage;
    if (!original) return image;
    size_t width = CGImageGetWidth(original), height = CGImageGetHeight(original);
    if (!width || !height || width > 512 || height > 512) return image;
    size_t stride = width * 4, bounds[4];
    uint8_t *pixels = calloc(height, stride);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = pixels && space ? CGBitmapContextCreate(pixels, width, height, 8, stride, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (!context) { free(pixels); return image; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), original);
    BOOL fitted = exteria_emoji_alpha_bounds(pixels, height * stride, width, height, stride, bounds);
    CGImageRef bitmap = fitted ? CGBitmapContextCreateImage(context) : NULL;
    CGContextRelease(context); free(pixels);
    CGImageRef cropped = bitmap ? CGImageCreateWithImageInRect(bitmap, CGRectMake(bounds[0], bounds[1], bounds[2], bounds[3])) : NULL;
    if (bitmap) CGImageRelease(bitmap);
    if (!cropped) return image;
    CGFloat side = MAX(width, height), scale = side * 0.93 / MAX(bounds[2], bounds[3]);
    CGSize shown = CGSizeMake(bounds[2] * scale, bounds[3] * scale);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 1);
    [[UIImage imageWithCGImage:cropped] drawInRect:CGRectMake((side - shown.width) / 2, (side - shown.height) / 2, shown.width, shown.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext(); CGImageRelease(cropped);
    return result ? result : image;
}

static const char ExteriaRoundKey;

BOOL ExteriaImageIsRound(UIImage *image) {
    if (!image.CGImage) return NO;
    NSNumber *known = objc_getAssociatedObject(image, &ExteriaRoundKey);
    if (known) return known.boolValue;
    enum { SIDE = 24, PATCH = 3 };
    uint8_t pixels[SIDE * SIDE * 4];
    memset(pixels, 0, sizeof(pixels));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = space ? CGBitmapContextCreate(pixels, SIDE, SIDE, 8, SIDE * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (!context) return NO;
    CGContextDrawImage(context, CGRectMake(0, 0, SIDE, SIDE), image.CGImage);
    CGContextRelease(context);
    int empty = 0;
    for (int corner = 0; corner < 4; ++corner) {
        int x0 = corner & 1 ? SIDE - PATCH : 0, y0 = corner & 2 ? SIDE - PATCH : 0;
        int clear = 0;
        for (int y = y0; y < y0 + PATCH; ++y) {
            for (int x = x0; x < x0 + PATCH; ++x) {
                const uint8_t *p = pixels + (y * SIDE + x) * 4;
                /* premultiplied: a see-through pixel has no color left, and a white one has all of it */
                if (p[3] < 40 || (p[0] > 240 && p[1] > 240 && p[2] > 240)) ++clear;
            }
        }
        if (clear >= PATCH * PATCH - 1) ++empty;
    }
    BOOL round = empty >= 3;
    objc_setAssociatedObject(image, &ExteriaRoundKey, [NSNumber numberWithBool:round], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return round;
}
