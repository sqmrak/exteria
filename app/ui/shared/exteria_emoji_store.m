#import "exteria_emoji_store.h"

#import "exteria_image_decoder.h"
#import <CoreText/CoreText.h>

#define PACK_NAME @"emoji"
#define PACK_EXTENSION @"pack"
#define PACK_HEADER 12u

/* the picture pack stays mapped, so its 7 MB cost no memory until a picture is read */
static NSData *ExteriaEmojiPack(void) {
    static NSData *pack;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:PACK_NAME ofType:PACK_EXTENSION];
        NSData *data = path ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:NULL] : nil;
        const uint8_t *bytes = data.bytes;
        uint32_t count = 0;
        if (data.length >= PACK_HEADER && !memcmp(bytes, "EXEM", 4)) memcpy(&count, bytes + 4, 4);
        /* the pack and the table are generated together, so a different count is a stale file */
        if (count == exteria_emoji_image_count && data.length >= PACK_HEADER + 8u * count) pack = [data retain];
        else NSLog(@"exteria: emoji picture pack is missing or does not match the table");
    });
    return pack;
}

static NSCache *ExteriaEmojiCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 500;
    });
    return cache;
}

static const exteria_emoji_entry *ExteriaEmojiEntry(size_t index) {
    if (index >= exteria_emoji_entry_count) return NULL;
    const exteria_emoji_entry *entry = &exteria_emoji_entries[index];
    return entry->image == EXTERIA_EMOJI_NO_IMAGE ? NULL : entry;
}

/* the webp bytes of a picture inside the pack, nil when the record points outside the file */
static NSData *ExteriaEmojiBytes(uint16_t image) {
    NSData *pack = ExteriaEmojiPack();
    if (!pack) return nil;
    uint32_t offset, length;
    const uint8_t *bytes = pack.bytes;
    memcpy(&offset, bytes + PACK_HEADER + 8u * image, 4);
    memcpy(&length, bytes + PACK_HEADER + 8u * image + 4, 4);
    if ((uint64_t)offset + length > pack.length) return nil;
    return [NSData dataWithBytesNoCopy:(void *)(bytes + offset) length:length freeWhenDone:NO];
}

/* a picture whose bytes do not decode is not asked for again, or every redraw would queue it again */
static NSMutableSet *ExteriaEmojiFailed(void) {
    static NSMutableSet *failed;
    if (!failed) failed = [[NSMutableSet alloc] init];
    return failed;
}

BOOL ExteriaEmojiHasPicture(size_t index) {
    const exteria_emoji_entry *entry = ExteriaEmojiEntry(index);
    if (!entry || !ExteriaEmojiPack()) return NO;
    return ![ExteriaEmojiFailed() containsObject:[NSNumber numberWithUnsignedShort:entry->image]];
}

static NSMutableArray *sWaiting;
static NSMutableSet *sPending;
static NSUInteger sLoadedSinceRedraw;
static NSUInteger sMisses;

static void ExteriaEmojiRedrawWaiting(void) {
    NSArray *views = [sWaiting copy];
    [sWaiting removeAllObjects];
    sLoadedSinceRedraw = 0;
    for (UIView *view in views) [view setNeedsDisplay];
    [views release];
}

static void ExteriaEmojiDecoded(NSNumber *key, UIImage *image) {
    if (image) [ExteriaEmojiCache() setObject:image forKey:key];
    else {
        NSLog(@"exteria: emoji picture %@ does not decode", key);
        [ExteriaEmojiFailed() addObject:key];
    }
    [sPending removeObject:key];
    ++sLoadedSinceRedraw;
    /* the redraw waits for the queue to run dry, so a screenful of emoji repaints its views once and not per picture */
    if (!sPending.count || sLoadedSinceRedraw >= 16) ExteriaEmojiRedrawWaiting();
}

/* font bitmaps have different transparent margins, so fit their visible bounds to one square */
static UIImage *ExteriaDecodeEmoji(NSData *data, uint8_t group) {
    UIImage *image = ExteriaDecodeImage(data, 128);
    /* cropping would enlarge small squares, square flags and kneeling figures beyond their font metrics */
    if (group == 1 || group >= 7) return image;
    return ExteriaFitEmojiImage(image);
}

static void ExteriaEmojiSchedule(NSNumber *key, NSData *data, uint8_t group) {
    static dispatch_queue_t queue;
    if (!queue) {
        queue = dispatch_queue_create("exteria.emoji.decode", DISPATCH_QUEUE_SERIAL);
        sPending = [[NSMutableSet alloc] init];
        sWaiting = [[NSMutableArray alloc] init];
    }
    if ([sPending containsObject:key]) return;
    [sPending addObject:key];
    dispatch_async(queue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *image = ExteriaDecodeEmoji(data, group);
        dispatch_async(dispatch_get_main_queue(), ^{ ExteriaEmojiDecoded(key, image); });
        [pool drain];
    });
}

UIImage *ExteriaEmojiImage(size_t index) {
    const exteria_emoji_entry *entry = ExteriaEmojiEntry(index);
    if (!entry) return nil;
    NSNumber *key = [NSNumber numberWithUnsignedShort:entry->image];
    UIImage *image = [ExteriaEmojiCache() objectForKey:key];
    if (image || [ExteriaEmojiFailed() containsObject:key]) return image;
    NSData *data = ExteriaEmojiBytes(entry->image);
    if (!data) return nil;
    ExteriaEmojiSchedule(key, data, entry->group);
    ++sMisses;
    return nil;
}

UIImage *ExteriaEmojiImageNow(size_t index) {
    const exteria_emoji_entry *entry = ExteriaEmojiEntry(index);
    if (!entry) return nil;
    NSNumber *key = [NSNumber numberWithUnsignedShort:entry->image];
    UIImage *image = [ExteriaEmojiCache() objectForKey:key];
    if (image) return image;
    NSData *data = ExteriaEmojiBytes(entry->image);
    image = data ? ExteriaDecodeEmoji(data, entry->group) : nil;
    if (image) [ExteriaEmojiCache() setObject:image forKey:key];
    return image;
}

NSUInteger ExteriaEmojiMissCount(void) { return sMisses; }

void ExteriaEmojiRedrawWhenLoaded(UIView *view) {
    if (!sWaiting || !sPending.count) return;
    if ([sWaiting indexOfObjectIdenticalTo:view] == NSNotFound) [sWaiting addObject:view];
}

NSString *ExteriaEmojiString(size_t entry) {
    uint16_t units[32];
    size_t count = exteria_emoji_encode(entry, units, 32);
    return count ? [NSString stringWithCharacters:units length:count] : @"";
}

static UIImage *ExteriaRenderSystemEmoji(NSString *text, size_t side, BOOL *supportedOut) {
    *supportedOut = NO;
    CTFontRef font = CTFontCreateWithName(CFSTR("AppleColorEmoji"), (CGFloat)side * 0.8, NULL);
    if (!font) return nil;
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:(id)font forKey:(id)kCTFontAttributeName];
    NSAttributedString *string = [[[NSAttributedString alloc] initWithString:text attributes:attributes] autorelease];
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)string);
    CFRelease(font);
    if (!line) return nil;
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    BOOL supported = CTLineGetGlyphCount(line) == 1 && CFArrayGetCount(runs) == 1;
    if (supported) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, 0);
        CTFontRef used = (CTFontRef)CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
        CFStringRef name = used ? CTFontCopyPostScriptName(used) : NULL;
        supported = name && CFStringCompare(name, CFSTR("AppleColorEmoji"), 0) == kCFCompareEqualTo;
        if (name) CFRelease(name);
    }
    *supportedOut = supported;
    CGColorSpaceRef colors = supported ? CGColorSpaceCreateDeviceRGB() : NULL;
    CGContextRef context = colors ? CGBitmapContextCreate(NULL, side, side, 8, side * 4, colors,
                                                           kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    if (colors) CGColorSpaceRelease(colors);
    UIImage *image = nil;
    if (context) {
        CGRect bounds = CTLineGetImageBounds(line, context);
        if (!CGRectIsEmpty(bounds) && isfinite(bounds.origin.x) && isfinite(bounds.origin.y) &&
            isfinite(bounds.size.width) && isfinite(bounds.size.height)) {
            CGFloat scale = MIN((CGFloat)side * 0.93 / bounds.size.width, (CGFloat)side * 0.93 / bounds.size.height);
            CGContextScaleCTM(context, scale, scale);
            CGContextSetTextPosition(context, ((CGFloat)side / scale - bounds.size.width) / 2 - bounds.origin.x,
                                     ((CGFloat)side / scale - bounds.size.height) / 2 - bounds.origin.y);
            CTLineDraw(line, context);
            CGImageRef bitmap = CGBitmapContextCreateImage(context);
            if (bitmap) {
                image = [UIImage imageWithCGImage:bitmap];
                CGImageRelease(bitmap);
            }
        }
        CGContextRelease(context);
    }
    CFRelease(line);
    return image;
}

void ExteriaLargeEmojiImage(size_t entry, void (^completion)(UIImage *)) {
    if (!completion) return;
    NSString *emoji = ExteriaEmojiString(entry);
    if (!emoji.length) { completion(nil); return; }
    static NSCache *cache;
    static NSMutableDictionary *pending;
    static NSMutableSet *unsupported;
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 32;
        cache.totalCostLimit = 12 * 1024 * 1024;
        pending = [[NSMutableDictionary alloc] init];
        unsupported = [[NSMutableSet alloc] init];
        queue = dispatch_queue_create("exteria.emoji.large", DISPATCH_QUEUE_SERIAL);
    });
    NSNumber *key = [NSNumber numberWithUnsignedLong:(unsigned long)entry];
    UIImage *cached = [cache objectForKey:key];
    if (cached || [unsupported containsObject:key]) { completion(cached); return; }
    NSMutableArray *waiters = [pending objectForKey:key];
    if (waiters) {
        if (waiters.count < 16) [waiters addObject:[[completion copy] autorelease]];
        else completion(nil);
        return;
    }
    if (pending.count >= 64) { completion(nil); return; }
    waiters = [NSMutableArray arrayWithObject:[[completion copy] autorelease]];
    [pending setObject:waiters forKey:key];
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    size_t side = (size_t)ceil(150 * MAX(1, MIN(3, screenScale)));
    dispatch_async(queue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        BOOL supported = NO;
        UIImage *image = [ExteriaRenderSystemEmoji(emoji, side, &supported) retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (image) [cache setObject:image forKey:key cost:side * side * 4];
            else if (!supported) [unsupported addObject:key];
            else NSLog(@"exteria: could not render system emoji %@", key);
            NSArray *callbacks = [[[pending objectForKey:key] copy] autorelease];
            [pending removeObjectForKey:key];
            for (void (^callback)(UIImage *) in callbacks) callback(image);
            [image release];
        });
        [pool drain];
    });
}

void ExteriaDrawEmoji(size_t entry, CGRect rect) {
    UIImage *image = ExteriaEmojiImage(entry);
    if (image) [image drawInRect:rect];
}
