#import "exteria_avatar_cache.h"

#import "exteria_image_decoder.h"
#import "exteria_platform.h"
#import "exteria_remote_file.h"

#define MEMORY_LIMIT 400
/* decoded bitmaps count by size: 512 MB devices (iphone 4, 4s, ipad 2) get a third of the budget of the rest */
#define MEMORY_BYTES_OLD (12 * 1024 * 1024)
#define MEMORY_BYTES_NEW (32 * 1024 * 1024)
/* a photo that did not come is asked for again after this: a link that was down for a moment must not leave a blank for five minutes */
#define RETRY_AFTER_SECONDS 30.0
/* larger avatars exhausted the cache and caused repeated decodes while scrolling */
#define AVATAR_DECODE_POINTS 96.0
/* a photo that decodes to nothing is not worth keeping, and a file this large is not a profile photo */
#define PHOTO_BYTES_MAX (2 * 1024 * 1024)

@interface ExteriaAvatarCache () {
    ExteriaSession *_session;
    NSString *_directory;
    NSCache *_memory;
    NSMutableDictionary *_waiters;
    NSMutableDictionary *_failures;
    NSString *_pinnedKey;
    UIImage *_pinnedImage;
    /* clear bumps it; a result from before the bump is dropped instead of filling the emptied cache */
    NSUInteger _generation;
    /* serial, so a file write queued before clear is removed by it, never after */
    dispatch_queue_t _work;
    CGFloat _decodeSide;
}
@end

@implementation ExteriaAvatarCache

- (id)initWithSession:(ExteriaSession *)session directory:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _directory = [directory copy];
    _memory = [[NSCache alloc] init];
    _memory.countLimit = MEMORY_LIMIT;
    _memory.totalCostLimit = [[NSProcessInfo processInfo] physicalMemory] <= 512ull * 1024 * 1024
        ? MEMORY_BYTES_OLD : MEMORY_BYTES_NEW;
    _decodeSide = AVATAR_DECODE_POINTS * ExteriaScreenScale();
    _waiters = [[NSMutableDictionary alloc] init];
    _failures = [[NSMutableDictionary alloc] init];
    _work = dispatch_queue_create("exteria.avatars", DISPATCH_QUEUE_SERIAL);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: cannot create %@: %@", _directory, error);
    }
    return self;
}

- (void)dealloc {
    dispatch_release(_work);
    [_session release];
    [_directory release];
    [_memory release];
    [_waiters release];
    [_failures release];
    [_pinnedKey release];
    [_pinnedImage release];
    [super dealloc];
}

- (NSString *)pathForPhoto:(ExteriaPhoto *)photo {
    return [_directory stringByAppendingPathComponent:[photo.key stringByAppendingString:@".jpg"]];
}

- (UIImage *)cachedImageForPhoto:(ExteriaPhoto *)photo {
    if (!photo.key) return nil;
    if (_pinnedImage && [photo.key isEqualToString:_pinnedKey]) return _pinnedImage;
    return [_memory objectForKey:photo.key];
}

- (void)pinPhoto:(ExteriaPhoto *)photo {
    NSString *key = photo.key;
    if (!key) {
        [_pinnedKey release];
        _pinnedKey = nil;
        [_pinnedImage release];
        _pinnedImage = nil;
        return;
    }
    if ([key isEqualToString:_pinnedKey]) return;
    [_pinnedKey release];
    _pinnedKey = [key copy];
    [_pinnedImage release];
    _pinnedImage = nil;
    [self retain];
    [self loadImageForPhoto:photo completion:^(UIImage *image) {
        [self autorelease];
        if (image && [key isEqualToString:_pinnedKey]) _pinnedImage = [image retain];
    }];
}

- (void)completeKey:(NSString *)key image:(UIImage *)image generation:(NSUInteger)generation {
    if (generation != _generation) return;
    if (image) {
        CGImageRef bitmap = image.CGImage;
        NSUInteger cost = bitmap ? (NSUInteger)CGImageGetBytesPerRow(bitmap) * CGImageGetHeight(bitmap) : 0;
        [_memory setObject:image forKey:key cost:cost];
        [_failures removeObjectForKey:key];
    } else {
        [_failures setObject:[NSDate date] forKey:key];
    }
    NSArray *done = [[_waiters objectForKey:key] retain];
    [_waiters removeObjectForKey:key];
    for (void (^waiter)(UIImage *) in done) waiter(image);
    [done release];
}

- (void)loadImageForPhoto:(ExteriaPhoto *)photo completion:(void (^)(UIImage *image))completion {
    if (!photo || !photo.key) {
        if (completion) completion(nil);
        return;
    }
    NSString *key = photo.key;
    UIImage *image = [self cachedImageForPhoto:photo];
    if (image) {
        if (completion) completion(image);
        return;
    }
    NSDate *failedAt = [_failures objectForKey:key];
    if (failedAt && -[failedAt timeIntervalSinceNow] < RETRY_AFTER_SECONDS) {
        if (completion) completion(nil);
        return;
    }
    NSMutableArray *waiting = [_waiters objectForKey:key];
    if (waiting) {
        if (completion) [waiting addObject:[[completion copy] autorelease]];
        return;
    }
    waiting = [NSMutableArray array];
    if (completion) [waiting addObject:[[completion copy] autorelease]];
    [_waiters setObject:waiting forKey:key];

    NSUInteger generation = _generation;
    CGFloat decodeSide = _decodeSide;
    NSString *path = [self pathForPhoto:photo];
    ExteriaRemoteFile *remote = [ExteriaRemoteFile fileForPhoto:photo];
    dispatch_async(_work, ^{
        @autoreleasepool {
            NSFileManager *files = [NSFileManager defaultManager];
            NSDictionary *attributes = [files attributesOfItemAtPath:path error:NULL];
            unsigned long long bytes = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
            NSData *data = bytes > 0 && bytes <= PHOTO_BYTES_MAX ? [NSData dataWithContentsOfFile:path] : nil;
            UIImage *stored = data && data.length <= PHOTO_BYTES_MAX ? ExteriaDecodeImage(data, decodeSide) : nil;
            if (attributes && !stored) [files removeItemAtPath:path error:NULL];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != _generation) return;
                if (stored) {
                    [self completeKey:key image:stored generation:generation];
                    return;
                }
                [_session downloadFile:remote completion:^(NSData *downloaded, NSString *errorName) {
                    if (generation != _generation) return;
                    if (!downloaded.length || downloaded.length > PHOTO_BYTES_MAX) {
                        NSLog(@"exteria: photo %@ not loaded: %@", key, errorName ? errorName : @"empty or too large");
                        [self completeKey:key image:nil generation:generation];
                        return;
                    }
                    dispatch_async(_work, ^{
                        @autoreleasepool {
                            UIImage *decoded = ExteriaDecodeImage(downloaded, decodeSide);
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if (generation != _generation) return;
                                if (decoded) {
                                    dispatch_async(_work, ^{
                                        if (![downloaded writeToFile:path atomically:YES])
                                            NSLog(@"exteria: cannot cache photo %@", key);
                                    });
                                } else {
                                    NSLog(@"exteria: photo %@ is not an image", key);
                                }
                                [self completeKey:key image:decoded generation:generation];
                            });
                        }
                    });
                }];
            });
        }
    });
}

- (unsigned long long)diskBytes {
    unsigned long long total = 0;
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *name in [files contentsOfDirectoryAtPath:_directory error:NULL]) {
        NSDictionary *attributes = [files attributesOfItemAtPath:[_directory stringByAppendingPathComponent:name] error:NULL];
        total += [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
    }
    return total;
}

- (void)clear {
    ++_generation;
    [_pinnedKey release];
    _pinnedKey = nil;
    [_pinnedImage release];
    _pinnedImage = nil;
    NSArray *waiting = [[_waiters allValues] retain];
    [_waiters removeAllObjects];
    [_memory removeAllObjects];
    [_failures removeAllObjects];
    for (NSArray *callbacks in waiting) {
        for (void (^callback)(UIImage *) in callbacks) callback(nil);
    }
    [waiting release];
    dispatch_sync(_work, ^{
        NSFileManager *files = [NSFileManager defaultManager];
        for (NSString *name in [files contentsOfDirectoryAtPath:_directory error:NULL]) {
            NSError *error = nil;
            if (![files removeItemAtPath:[_directory stringByAppendingPathComponent:name] error:&error])
                NSLog(@"exteria: cannot remove %@: %@", name, error);
        }
    });
}

@end
