#import "exteria_media_cache.h"

#import "exteria_image_decoder.h"
#import "exteria_lottie.h"
#import "exteria_dialog.h"
#import "exteria_message.h"
#import "exteria_remote_file.h"
#import "exteria_session_actions.h"
#include "exteria_id3.h"
#include "exteria_mt_files.h"

#include <stdio.h>

/* about two screens of stickers and photos at the sizes the app shows them */
#define MEMORY_BYTES (10 * 1024 * 1024)
#define RETRY_AFTER_SECONDS 300.0
/* the first look at the head of a music file; a tag that does not fit asks for a second one, as large as the tag and a power of two for the server */
#define COVER_HEAD_BYTES (64 * 1024)
/* each prepared picture takes the single decode queue for its turn, so only a few wait there ahead of the visible ones */
#define PREPARE_IN_FLIGHT_MAX 4
/* what the disk cache holds per file; larger files are not fetched by the part limit anyway */
#define FILE_BYTES_MAX EXTERIA_REMOTE_FILE_PART
/* the disk copies stay between runs; past this size the oldest go first, down to four fifths of it */
#define DISK_BYTES_MAX (150ull * 1024 * 1024)
/* path downloads use one part in memory and cannot exceed the disk cache budget */
#define PATH_BYTES_MAX ((long long)DISK_BYTES_MAX)
/* divides a mebibyte, as the server demands of a part */
#define PATH_PART (512 * 1024)
/* files remembered with the message they came from; the table is dropped whole past this, since an old entry is only a chance to refresh a reference */
#define ORIGINS_MAX 4000

static void ExteriaRemovePartial(NSString *path) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:path error:&error] &&
        !([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileNoSuchFileError))
        NSLog(@"exteria: cannot remove partial %@: %@", path, error);
    [pool drain];
}

/* cache instances share one directory: cleanup must run before any instance can create a partial */
static dispatch_queue_t ExteriaMediaWorkQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("exteria.media", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static NSMutableSet *ExteriaMediaCleanedDirectories(void) {
    static NSMutableSet *directories;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ directories = [[NSMutableSet alloc] init]; });
    return directories;
}

@interface ExteriaMediaCache () {
    NSString *_directory;
    NSCache *_memory;
    /* both below are touched on the main thread only */
    NSMutableDictionary *_imageWaiters;
    NSMutableDictionary *_dataWaiters;
    NSMutableDictionary *_failures;
    NSUInteger _preparing;
    /* by file key: who waits for a whole file, and which loop is the current one for it */
    NSMutableDictionary *_pathWaiters;
    NSMutableDictionary *_pathTokens;
    NSMutableDictionary *_pathRequestKeys;
    NSUInteger _pathCounter;
    /* file key to (dialog, message id), main thread only */
    NSMutableDictionary *_origins;
    /* work queue only, writes consume the free space measured by the last trim */
    unsigned long long _diskBytesUntilTrim;
    dispatch_queue_t _work;
}
@end

@implementation ExteriaMediaCache

- (id)initWithSession:(ExteriaSession *)session directory:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _directory = [[directory stringByStandardizingPath] copy];
    _memory = [[NSCache alloc] init];
    _memory.totalCostLimit = MEMORY_BYTES;
    _imageWaiters = [[NSMutableDictionary alloc] init];
    _dataWaiters = [[NSMutableDictionary alloc] init];
    _failures = [[NSMutableDictionary alloc] init];
    _pathWaiters = [[NSMutableDictionary alloc] init];
    _pathTokens = [[NSMutableDictionary alloc] init];
    _pathRequestKeys = [[NSMutableDictionary alloc] init];
    _origins = [[NSMutableDictionary alloc] init];
    /* one decode at a time: old devices have one or two cores and the main thread needs the other */
    _work = ExteriaMediaWorkQueue();
    dispatch_retain(_work);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: cannot create %@: %@", _directory, error);
    }
    NSMutableSet *directories = ExteriaMediaCleanedDirectories();
    @synchronized(directories) {
        BOOL first = ![directories containsObject:_directory];
        if (first) [directories addObject:_directory];
        dispatch_async(_work, ^{ [self trimDiskKeepingPath:nil removePartials:first]; });
    }
    return self;
}

- (void)dealloc {
    dispatch_release(_work);
    [_session release];
    [_directory release];
    [_memory release];
    [_imageWaiters release];
    [_dataWaiters release];
    [_failures release];
    [_pathWaiters release];
    [_pathTokens release];
    [_pathRequestKeys release];
    [_origins release];
    [super dealloc];
}

static NSString *ExteriaImageKey(ExteriaRemoteFile *file, CGFloat maxSide) {
    return [NSString stringWithFormat:@"%@@%d", file.key, (int)maxSide];
}

- (NSString *)pathForFile:(ExteriaRemoteFile *)file {
    return [_directory stringByAppendingPathComponent:file.key];
}

- (UIImage *)cachedImageForFile:(ExteriaRemoteFile *)file maxSide:(CGFloat)maxSide {
    if (!file) return nil;
    return [_memory objectForKey:ExteriaImageKey(file, maxSide)];
}

- (BOOL)recentlyFailed:(NSString *)key {
    NSDate *failedAt = [_failures objectForKey:key];
    return failedAt && -[failedAt timeIntervalSinceNow] < RETRY_AFTER_SECONDS;
}

#pragma mark file references

static BOOL ExteriaReferenceExpired(NSString *errorName) {
    return [errorName hasPrefix:@"FILE_REFERENCE"];
}

- (void)noteMessages:(NSArray *)messages ofDialog:(ExteriaDialog *)dialog {
    if (!dialog) return;
    if (_origins.count > ORIGINS_MAX) [_origins removeAllObjects];
    for (ExteriaMessage *message in messages) {
        ExteriaMedia *media = message.media;
        if (!media || message.messageId <= 0) continue;
        /* every change of the chat hands the whole page over again, so a message that is noted already costs one lookup */
        ExteriaRemoteFile *main = media.file;
        NSArray *known = main.key ? [_origins objectForKey:main.key] : nil;
        if (known && [known objectAtIndex:0] == dialog && [[known objectAtIndex:1] intValue] == message.messageId) continue;
        NSArray *origin = [NSArray arrayWithObjects:dialog, [NSNumber numberWithInt:message.messageId], nil];
        NSMutableArray *files = [NSMutableArray array];
        if (main) [files addObject:main];
        if (media.previewFile) [files addObject:media.previewFile];
        if (media.fullPhotoFile) [files addObject:media.fullPhotoFile];
        for (ExteriaRemoteFile *file in files) if (file.key) [_origins setObject:origin forKey:file.key];
    }
}

/* reads the message of a file again and takes the new reference from it; completion on main, NO when the message is gone or does not carry the file */
- (void)refreshReferenceOfFile:(ExteriaRemoteFile *)file completion:(void (^)(BOOL refreshed))completion {
    NSArray *origin = [_origins objectForKey:file.key];
    if (!origin) {
        completion(NO);
        return;
    }
    NSString *key = file.key;
    void (^done)(BOOL) = [completion copy];
    [_session loadMessagesWithIds:[NSArray arrayWithObject:[origin objectAtIndex:1]] ofDialog:[origin objectAtIndex:0] completion:^(NSArray *messages, NSString *errorName) {
        BOOL refreshed = NO;
        for (ExteriaMessage *message in messages) {
            ExteriaMedia *media = message.media;
            NSMutableArray *candidates = [NSMutableArray array];
            if (media.file) [candidates addObject:media.file];
            if (media.previewFile) [candidates addObject:media.previewFile];
            if (media.fullPhotoFile) [candidates addObject:media.fullPhotoFile];
            for (ExteriaRemoteFile *fresh in candidates) {
                if ([fresh.key isEqualToString:key] && [file adoptReferenceOf:fresh]) refreshed = YES;
            }
        }
        if (!refreshed) NSLog(@"exteria: file %@ has no new reference: %@", key, errorName ? errorName : @"message not found");
        done(refreshed);
        [done release];
    }];
}

/* a whole small file from the network; a reference the server let expire is renewed once before the request is given up */
- (void)downloadWhole:(ExteriaRemoteFile *)file refreshed:(BOOL)refreshed completion:(void (^)(NSData *data, NSString *errorName))completion {
    void (^done)(NSData *, NSString *) = [completion copy];
    [_session downloadFile:file completion:^(NSData *data, NSString *errorName) {
        if (data || refreshed || !ExteriaReferenceExpired(errorName)) {
            done(data, errorName);
            [done release];
            return;
        }
        [self refreshReferenceOfFile:file completion:^(BOOL ok) {
            if (ok) [self downloadWhole:file refreshed:YES completion:done];
            else done(nil, errorName);
            [done release];
        }];
    }];
}

/* the bytes of a file: the disk copy, else the network, which also writes the copy */
- (void)fetchDataForFile:(ExteriaRemoteFile *)file completion:(void (^)(NSData *data))completion {
    NSString *key = file.key;
    NSMutableArray *waiting = [_dataWaiters objectForKey:key];
    if (waiting) {
        [waiting addObject:[[completion copy] autorelease]];
        return;
    }
    if ([self recentlyFailed:key]) {
        completion(nil);
        return;
    }
    waiting = [NSMutableArray arrayWithObject:[[completion copy] autorelease]];
    [_dataWaiters setObject:waiting forKey:key];
    NSString *path = [self pathForFile:file];
    void (^finish)(NSData *) = ^(NSData *data) {
        if (data) [_failures removeObjectForKey:key];
        else [_failures setObject:[NSDate date] forKey:key];
        NSArray *done = [[_dataWaiters objectForKey:key] retain];
        [_dataWaiters removeObjectForKey:key];
        for (void (^waiter)(NSData *) in done) waiter(data);
        [done release];
    };
    void (^finishCopy)(NSData *) = [finish copy];
    dispatch_async(_work, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSData *stored = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
        if (stored.length && stored.length < FILE_BYTES_MAX) {
            dispatch_async(dispatch_get_main_queue(), ^{ finishCopy(stored); [finishCopy release]; });
            [pool drain];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self downloadWhole:file refreshed:NO completion:^(NSData *data, NSString *errorName) {
                if (data.length && data.length < FILE_BYTES_MAX) {
                    dispatch_async(_work, ^{
                        NSAutoreleasePool *writePool = [[NSAutoreleasePool alloc] init];
                        if (![data writeToFile:path atomically:YES]) NSLog(@"exteria: cannot cache file %@", key);
                        else if (data.length <= _diskBytesUntilTrim) _diskBytesUntilTrim -= data.length;
                        else [self trimDiskKeepingPath:path removePartials:NO];
                        [writePool drain];
                    });
                } else {
                    NSLog(@"exteria: file %@ not loaded: %@", key, errorName ? errorName : @"empty");
                    data = nil;
                }
                finishCopy(data);
                [finishCopy release];
            }];
        });
        [pool drain];
    });
}

- (void)loadDataForFile:(ExteriaRemoteFile *)file completion:(void (^)(NSData *data))completion {
    if (!file) {
        completion(nil);
        return;
    }
    [self fetchDataForFile:file completion:completion];
}

- (void)loadImageForFile:(ExteriaRemoteFile *)file maxSide:(CGFloat)maxSide completion:(void (^)(UIImage *image))completion {
    if (!file) {
        completion(nil);
        return;
    }
    NSString *imageKey = ExteriaImageKey(file, maxSide);
    UIImage *cached = [_memory objectForKey:imageKey];
    if (cached) {
        completion(cached);
        return;
    }
    NSMutableArray *waiting = [_imageWaiters objectForKey:imageKey];
    if (waiting) {
        [waiting addObject:[[completion copy] autorelease]];
        return;
    }
    waiting = [NSMutableArray arrayWithObject:[[completion copy] autorelease]];
    [_imageWaiters setObject:waiting forKey:imageKey];
    [self fetchDataForFile:file completion:^(NSData *data) {
        void (^deliver)(UIImage *) = ^(UIImage *image) {
            if (image) {
                CGImageRef bitmap = image.CGImage;
                [_memory setObject:image forKey:imageKey cost:CGImageGetBytesPerRow(bitmap) * CGImageGetHeight(bitmap)];
            }
            NSArray *done = [[_imageWaiters objectForKey:imageKey] retain];
            [_imageWaiters removeObjectForKey:imageKey];
            for (void (^waiter)(UIImage *) in done) waiter(image);
            [done release];
        };
        void (^deliverCopy)(UIImage *) = [deliver copy];
        if (!data) {
            deliverCopy(nil);
            [deliverCopy release];
            return;
        }
        dispatch_async(_work, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            if (ExteriaFileFormatOfData(data) == ExteriaFileFormatGzip) {
                ExteriaLottie *animation = [ExteriaLottie animationWithPackedData:data key:file.key];
                if (animation) {
                    [animation renderStillAtSide:(NSUInteger)MAX(8, MIN(512, maxSide)) completion:^(CGImageRef frame) {
                        deliverCopy(frame ? [UIImage imageWithCGImage:frame] : nil);
                        [animation invalidate]; [deliverCopy release];
                    }];
                    [pool drain]; return;
                }
            }
            UIImage *image = ExteriaDecodeImage(data, maxSide);
            dispatch_async(dispatch_get_main_queue(), ^{ deliverCopy(image); [deliverCopy release]; });
            [pool drain];
        });
    }];
}

#pragma mark music covers

/* the first bytes of a file, from offset 0; a reference the server let expire is renewed once */
- (void)fetchHeadOfFile:(ExteriaRemoteFile *)file limit:(int32_t)limit refreshed:(BOOL)refreshed completion:(void (^)(NSData *data, NSString *errorName))completion {
    void (^done)(NSData *, NSString *) = [completion copy];
    [_session downloadFile:file offset:0 limit:limit completion:^(NSData *data, NSString *errorName) {
        if (data || refreshed || !ExteriaReferenceExpired(errorName)) {
            done(data, errorName);
            [done release];
            return;
        }
        [self refreshReferenceOfFile:file completion:^(BOOL ok) {
            if (ok) [self fetchHeadOfFile:file limit:limit refreshed:YES completion:done];
            else done(nil, errorName);
            [done release];
        }];
    }];
}

/* work queue: the picture of the head bytes, or why there is none. EXTERIA_E_TRUNCATED says the tag goes on past these bytes, with its size in *more */
static exteria_status ExteriaCoverOfHead(NSData *head, NSData **picture, size_t *more) {
    size_t offset = 0, size = 0, tag = 0;
    exteria_status status;
    *picture = nil;
    *more = 0;
    if (head.length < EXTERIA_ID3_HEADER) return EXTERIA_E_NOTFOUND;
    status = exteria_id3_tag_size(head.bytes, head.length, &tag);
    if (status != EXTERIA_OK) return status == EXTERIA_E_NOTFOUND ? status : EXTERIA_E_UNSUPPORTED;
    status = exteria_id3_cover(head.bytes, head.length, &offset, &size);
    if (status == EXTERIA_OK) *picture = [NSData dataWithBytes:(const uint8_t *)head.bytes + offset length:size];
    if (status == EXTERIA_E_TRUNCATED) *more = tag;
    return status;
}

- (void)loadEmbeddedCoverOfFile:(ExteriaRemoteFile *)file maxSide:(CGFloat)maxSide completion:(void (^)(UIImage *image))completion {
    NSString *coverKey = [@"cover-" stringByAppendingString:file.key];
    NSString *imageKey = ExteriaImageKey(file, maxSide);
    imageKey = [@"cover-" stringByAppendingString:imageKey];
    UIImage *cached = [_memory objectForKey:imageKey];
    if (cached) {
        completion(cached);
        return;
    }
    NSMutableArray *waiting = [_imageWaiters objectForKey:imageKey];
    if (waiting) {
        [waiting addObject:[[completion copy] autorelease]];
        return;
    }
    if ([self recentlyFailed:coverKey]) {
        completion(nil);
        return;
    }
    waiting = [NSMutableArray arrayWithObject:[[completion copy] autorelease]];
    [_imageWaiters setObject:waiting forKey:imageKey];
    NSString *path = [_directory stringByAppendingPathComponent:coverKey];
    void (^deliver)(UIImage *, BOOL) = ^(UIImage *image, BOOL failed) {
        if (image) {
            CGImageRef bitmap = image.CGImage;
            [_memory setObject:image forKey:imageKey cost:CGImageGetBytesPerRow(bitmap) * CGImageGetHeight(bitmap)];
        } else if (failed) {
            [_failures setObject:[NSDate date] forKey:coverKey];
        }
        NSArray *done = [[_imageWaiters objectForKey:imageKey] retain];
        [_imageWaiters removeObjectForKey:imageKey];
        for (void (^waiter)(UIImage *) in done) waiter(image);
        [done release];
    };
    void (^deliverCopy)(UIImage *, BOOL) = [deliver copy];
    /* work queue: keeps the picture on disk, an empty file for a track that has none, and decodes it for this size */
    void (^settle)(NSData *) = ^(NSData *picture) {
        dispatch_async(_work, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            if (![(picture ? picture : [NSData data]) writeToFile:path atomically:YES]) NSLog(@"exteria: cannot cache the cover of %@", file.key);
            UIImage *image = picture ? ExteriaDecodeImage(picture, maxSide) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{ deliverCopy(image, NO); [deliverCopy release]; });
            [pool drain];
        });
    };
    void (^settleCopy)(NSData *) = [settle copy];
    dispatch_async(_work, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSData *stored = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
        if (stored) {
            UIImage *image = stored.length ? ExteriaDecodeImage(stored, maxSide) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{ deliverCopy(image, NO); [deliverCopy release]; [settleCopy release]; });
            [pool drain];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self fetchHeadOfFile:file limit:COVER_HEAD_BYTES refreshed:NO completion:^(NSData *head, NSString *errorName) {
                if (!head) {
                    NSLog(@"exteria: the head of %@ was not loaded: %@", file.key, errorName ? errorName : @"empty");
                    deliverCopy(nil, YES);
                    [deliverCopy release];
                    [settleCopy release];
                    return;
                }
                dispatch_async(_work, ^{
                    NSAutoreleasePool *headPool = [[NSAutoreleasePool alloc] init];
                    NSData *picture = nil;
                    size_t tag = 0;
                    exteria_status status = ExteriaCoverOfHead(head, &picture, &tag);
                    if (status == EXTERIA_E_TRUNCATED && head.length >= COVER_HEAD_BYTES && tag > head.length) {
                        uint32_t limit = COVER_HEAD_BYTES;
                        while (limit < tag && limit < EXTERIA_ID3_TAG_MAX) limit *= 2;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self fetchHeadOfFile:file limit:(int32_t)limit refreshed:NO completion:^(NSData *whole, NSString *wholeError) {
                                if (!whole) {
                                    NSLog(@"exteria: the tag of %@ was not loaded: %@", file.key, wholeError ? wholeError : @"empty");
                                    deliverCopy(nil, YES);
                                    [deliverCopy release];
                                    [settleCopy release];
                                    return;
                                }
                                dispatch_async(_work, ^{
                                    NSAutoreleasePool *wholePool = [[NSAutoreleasePool alloc] init];
                                    NSData *found = nil;
                                    size_t again = 0;
                                    ExteriaCoverOfHead(whole, &found, &again);
                                    dispatch_async(dispatch_get_main_queue(), ^{ settleCopy(found); [settleCopy release]; });
                                    [wholePool drain];
                                });
                            }];
                        });
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{ settleCopy(picture); [settleCopy release]; });
                    }
                    [headPool drain];
                });
            }];
        });
        [pool drain];
    });
}

- (void)loadCoverForTrack:(ExteriaMedia *)track maxSide:(CGFloat)maxSide completion:(void (^)(UIImage *image))completion {
    ExteriaRemoteFile *preview = track.previewFile, *audio = track.file;
    void (^done)(UIImage *) = [completion copy];
    void (^embedded)(void) = ^{
        /* a voice message or a round video has no tag to read */
        if (!audio || track.kind != EXTERIA_PREVIEW_AUDIO) {
            done(nil);
            [done release];
            return;
        }
        [self loadEmbeddedCoverOfFile:audio maxSide:maxSide completion:^(UIImage *image) {
            done(image);
            [done release];
        }];
    };
    void (^embeddedCopy)(void) = [embedded copy];
    if (!preview) {
        embeddedCopy();
        [embeddedCopy release];
        return;
    }
    [self loadImageForFile:preview maxSide:maxSide completion:^(UIImage *image) {
        if (image) {
            done(image);
            [done release];
        } else {
            embeddedCopy();
        }
        [embeddedCopy release];
    }];
}

- (void)prepareImageForFile:(ExteriaRemoteFile *)file maxSide:(CGFloat)maxSide {
    if (!file || _preparing >= PREPARE_IN_FLIGHT_MAX) return;
    NSString *imageKey = ExteriaImageKey(file, maxSide);
    if ([_memory objectForKey:imageKey] || [_imageWaiters objectForKey:imageKey] || [self recentlyFailed:file.key]) return;
    ++_preparing;
    [self loadImageForFile:file maxSide:maxSide completion:^(UIImage *image) {
        (void)image;
        --_preparing;
    }];
}

#pragma mark whole files

/* each waiter holds its request number, progress, then completion */
- (void)finishPath:(NSString *)key path:(NSString *)path {
    NSArray *waiting = [[_pathWaiters objectForKey:key] retain];
    [_pathWaiters removeObjectForKey:key];
    [_pathTokens removeObjectForKey:key];
    for (NSArray *waiter in waiting) [_pathRequestKeys removeObjectForKey:[waiter objectAtIndex:0]];
    if (path) [_failures removeObjectForKey:key];
    else [_failures setObject:[NSDate date] forKey:key];
    for (NSArray *waiter in waiting) {
        void (^completion)(NSString *) = [waiter objectAtIndex:2];
        completion(path);
    }
    [waiting release];
}

/* main thread: known sizes end on the last byte, unknown sizes on a short reply */
- (void)fetchPart:(long long)offset file:(ExteriaRemoteFile *)file size:(long long)size token:(NSNumber *)token temporary:(NSString *)temporary
            final:(NSString *)final refreshed:(BOOL)refreshed retries:(uint32_t)retries {
    NSString *key = file.key;
    uint32_t limit = 0;
    exteria_status part_status = exteria_file_download_part((uint64_t)offset, PATH_PART, &limit);
    if (part_status != EXTERIA_OK) {
        NSLog(@"exteria: file %@ has an invalid offset %lld: %s", key, offset, exteria_status_name(part_status));
        dispatch_async(_work, ^{ ExteriaRemovePartial(temporary); });
        [self finishPath:key path:nil];
        return;
    }
    [_session downloadFile:file offset:offset limit:(int32_t)limit completion:^(NSData *data, NSString *errorName) {
        if (![[_pathTokens objectForKey:key] isEqual:token]) {
            /* cancelled, or replaced by a newer ask: nobody wants these bytes */
            dispatch_async(_work, ^{ ExteriaRemovePartial(temporary); });
            return;
        }
        if (!data && !refreshed && ExteriaReferenceExpired(errorName)) {
            /* the bytes already on disk stay: the new reference continues the same file from the same offset */
            [self refreshReferenceOfFile:file completion:^(BOOL ok) {
                if (![[_pathTokens objectForKey:key] isEqual:token]) {
                    dispatch_async(_work, ^{ ExteriaRemovePartial(temporary); });
                    return;
                }
                if (ok) {
                    [self fetchPart:offset file:file size:size token:token temporary:temporary final:final refreshed:YES retries:retries];
                    return;
                }
                NSLog(@"exteria: file %@ stopped at %lld: %@", key, offset, errorName);
                dispatch_async(_work, ^{ ExteriaRemovePartial(temporary); });
                [self finishPath:key path:nil];
            }];
            return;
        }
        if (!data) {
            uint32_t delay_ms = 0;
            if (exteria_file_retry_delay(errorName.UTF8String, retries, &delay_ms)) {
                NSLog(@"exteria: file %@ retries part at %lld in %u ms (%u/%u): %@", key, offset, delay_ms,
                      retries + 1, EXTERIA_FILE_RETRIES_MAX, errorName);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay_ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    if ([[_pathTokens objectForKey:key] isEqual:token])
                        [self fetchPart:offset file:file size:size token:token temporary:temporary final:final refreshed:refreshed retries:retries + 1];
                });
                return;
            }
            NSLog(@"exteria: file %@ stopped at %lld: %@", key, offset, errorName);
            dispatch_async(_work, ^{ ExteriaRemovePartial(temporary); });
            [self finishPath:key path:nil];
            return;
        }
        uint64_t end = 0;
        int complete = 0;
        exteria_status status = exteria_file_download_advance((uint64_t)offset, (uint64_t)size, data.length,
                                                            limit, PATH_BYTES_MAX, &end, &complete);
        if (status == EXTERIA_OK && !complete && end % 4096) status = EXTERIA_E_MALFORMED;
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: file %@ rejected at %lld: %s", key, offset, exteria_status_name(status));
            dispatch_async(_work, ^{ ExteriaRemovePartial(temporary); });
            [self finishPath:key path:nil];
            return;
        }
        long long next = (long long)end;
        BOOL last = complete != 0;
        dispatch_async(_work, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:temporary];
            BOOL written = NO;
            if (handle) {
                @try {
                    [handle seekToEndOfFile];
                    [handle writeData:data];
                    written = YES;
                } @catch (NSException *exception) {
                    NSLog(@"exteria: cannot write %@: %@", temporary, exception);
                }
                @try {
                    [handle closeFile];
                } @catch (NSException *exception) {
                    written = NO;
                    NSLog(@"exteria: cannot close %@: %@", temporary, exception);
                }
            }
            if (written && last) {
                /* rename replaces a stale cache copy without leaving the new download behind it */
                written = rename(temporary.fileSystemRepresentation, final.fileSystemRepresentation) == 0;
                if (written) [self trimDiskKeepingPath:final removePartials:NO];
            } else if (written) {
                if (data.length <= _diskBytesUntilTrim) _diskBytesUntilTrim -= data.length;
                else [self trimDiskKeepingPath:nil removePartials:NO];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![[_pathTokens objectForKey:key] isEqual:token]) {
                    /* a finished file is as good for the next ask as for this one */
                    if (!last) [[NSFileManager defaultManager] removeItemAtPath:temporary error:NULL];
                    return;
                }
                if (!written) {
                    NSLog(@"exteria: file %@ not kept (written %d, %lld bytes)", key, written, next);
                    dispatch_async(_work, ^{ ExteriaRemovePartial(temporary); });
                    [self finishPath:key path:nil];
                    return;
                }
                NSArray *waiting = [[_pathWaiters objectForKey:key] copy];
                for (NSArray *waiter in waiting) {
                    NSNumber *request = [waiter objectAtIndex:0];
                    void (^progress)(float) = [waiter objectAtIndex:1];
                    if (size > 0 && [_pathRequestKeys objectForKey:request]) progress((float)next / (float)size > 1 ? 1 : (float)next / (float)size);
                }
                [waiting release];
                if (![[_pathTokens objectForKey:key] isEqual:token]) return;
                if (last) [self finishPath:key path:final];
                else [self fetchPart:next file:file size:size token:token temporary:temporary final:final refreshed:refreshed retries:0];
            });
            [pool drain];
        });
    }];
}

- (NSString *)cachedPathForFile:(ExteriaRemoteFile *)file size:(long long)size {
    if (!file.key || size < 0 || [_pathWaiters objectForKey:file.key]) return nil;
    NSString *final = [self pathForFile:file];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:final error:NULL];
    unsigned long long stored = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
    return stored > 0 && (size == 0 ? stored > FILE_BYTES_MAX : stored == (unsigned long long)size) ? final : nil;
}

- (NSUInteger)loadPathForFile:(ExteriaRemoteFile *)file size:(long long)size progress:(void (^)(float))progress completion:(void (^)(NSString *))completion {
    /* a nil block would end the waiter array early, and fetchPart reads it by index */
    if (!progress) progress = ^(float fraction) { (void)fraction; };
    /* a person asked for this file, so an earlier failure (a dropped link, a vpn that was off) does not answer for a try that is made now */
    if (!file || size < 0 || size > PATH_BYTES_MAX) {
        completion(nil);
        return 0;
    }
    NSString *key = file.key;
    NSString *final = [self pathForFile:file];
    NSMutableArray *waiting = [_pathWaiters objectForKey:key];
    if (!waiting) {
        /* a finished copy from an earlier ask is the file; one cut short by a crash is not, so only a size match counts */
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:final error:NULL];
        unsigned long long stored = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        if (stored > 0 && (size == 0 ? stored > FILE_BYTES_MAX : stored == (unsigned long long)size)) {
            completion(final);
            return 0;
        }
    }
    NSUInteger requestId = ++_pathCounter;
    NSNumber *request = [NSNumber numberWithUnsignedInteger:requestId];
    NSArray *waiter = [NSArray arrayWithObjects:request, [[progress copy] autorelease], [[completion copy] autorelease], nil];
    [_pathRequestKeys setObject:key forKey:request];
    if (waiting) {
        [waiting addObject:waiter];
        return requestId;
    }
    waiting = [NSMutableArray arrayWithObject:waiter];
    [_pathWaiters setObject:waiting forKey:key];
    NSNumber *token = [NSNumber numberWithUnsignedLongLong:exteria_file_temporary_token()];
    [_pathTokens setObject:token forKey:key];
    /* a loop that was cancelled may still be writing, so each ask keeps its own partial file */
    NSString *temporary = [final stringByAppendingFormat:@".%llu.part", token.unsignedLongLongValue];
    dispatch_async(_work, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSFileManager *files = [NSFileManager defaultManager];
        [files removeItemAtPath:temporary error:NULL];
        BOOL created = [files createFileAtPath:temporary contents:nil attributes:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![[_pathTokens objectForKey:key] isEqual:token]) {
                [files removeItemAtPath:temporary error:NULL];
                return;
            }
            if (!created) {
                NSLog(@"exteria: cannot create %@", temporary);
                [self finishPath:key path:nil];
                return;
            }
            [self fetchPart:0 file:file size:size token:token temporary:temporary final:final refreshed:NO retries:0];
        });
        [pool drain];
    });
    return requestId;
}

- (void)retryFile:(ExteriaRemoteFile *)file {
    if (file.key) [_failures removeObjectForKey:file.key];
}

- (void)cancelPathRequest:(NSUInteger)requestId {
    if (!requestId) return;
    NSNumber *request = [NSNumber numberWithUnsignedInteger:requestId];
    /* removing the waiter and request can release the file that owns this key */
    NSString *key = [[[_pathRequestKeys objectForKey:request] retain] autorelease];
    if (!key) return;
    NSMutableArray *waiting = [_pathWaiters objectForKey:key];
    for (NSUInteger i = 0; i < waiting.count; ++i) {
        if ([[[waiting objectAtIndex:i] objectAtIndex:0] isEqual:request]) {
            [waiting removeObjectAtIndex:i];
            break;
        }
    }
    [_pathRequestKeys removeObjectForKey:request];
    if (waiting.count) return;
    NSNumber *token = [_pathTokens objectForKey:key];
    NSString *temporary = [[_directory stringByAppendingPathComponent:key] stringByAppendingFormat:@".%llu.part", token.unsignedLongLongValue];
    [_pathWaiters removeObjectForKey:key];
    [_pathTokens removeObjectForKey:key];
    dispatch_async(_work, ^{ ExteriaRemovePartial(temporary); });
}

/* runs on the work queue */
- (void)trimDiskKeepingPath:(NSString *)keep removePartials:(BOOL)removePartials {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray *entries = [NSMutableArray array];
    unsigned long long total = 0;
    NSError *scanError = nil;
    NSArray *names = [files contentsOfDirectoryAtPath:_directory error:&scanError];
    if (!names) {
        NSLog(@"exteria: cannot scan cache %@: %@", _directory, scanError);
        _diskBytesUntilTrim = 0;
        [pool drain];
        return;
    }
    for (NSString *name in names) {
        NSString *path = [_directory stringByAppendingPathComponent:name];
        /* a crash can leave parts behind; live parts must stay until their request ends */
        if (removePartials && [name hasSuffix:@".part"]) {
            NSError *error = nil;
            if ([files removeItemAtPath:path error:&error]) continue;
            NSLog(@"exteria: cannot remove partial %@: %@", name, error);
        }
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:NULL];
        if (!attributes) continue;
        total += [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        if ([name hasSuffix:@".part"] || [path isEqualToString:keep]) continue;
        [entries addObject:[NSArray arrayWithObjects:path, [attributes objectForKey:NSFileModificationDate], [attributes objectForKey:NSFileSize], nil]];
    }
    if (total > DISK_BYTES_MAX) {
        [entries sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            return [[a objectAtIndex:1] compare:[b objectAtIndex:1]];
        }];
        for (NSArray *entry in entries) {
            if (total <= DISK_BYTES_MAX / 5 * 4) break;
            NSError *error = nil;
            if ([files removeItemAtPath:[entry objectAtIndex:0] error:&error]) total -= [[entry objectAtIndex:2] unsignedLongLongValue];
            else NSLog(@"exteria: cannot trim %@: %@", [entry objectAtIndex:0], error);
        }
    }
    _diskBytesUntilTrim = total < DISK_BYTES_MAX ? DISK_BYTES_MAX - total : 0;
    [pool drain];
}

- (void)removeFilesOlderThanDays:(NSInteger)days {
    if (days <= 0) return;
    NSString *directory = [[_directory copy] autorelease];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:-(NSTimeInterval)days * 86400];
    dispatch_async(_work, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSFileManager *files = [NSFileManager defaultManager];
        for (NSString *name in [files contentsOfDirectoryAtPath:directory error:NULL]) {
            if ([name hasSuffix:@".part"]) continue;
            NSString *path = [directory stringByAppendingPathComponent:name];
            NSDate *touched = [[files attributesOfItemAtPath:path error:NULL] objectForKey:NSFileModificationDate];
            if (!touched || [touched compare:limit] != NSOrderedAscending) continue;
            NSError *error = nil;
            if (![files removeItemAtPath:path error:&error]) NSLog(@"exteria: cannot remove %@: %@", name, error);
        }
        [pool drain];
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
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *name in [files contentsOfDirectoryAtPath:_directory error:NULL]) {
        if ([name hasSuffix:@".part"]) continue;
        NSError *error = nil;
        if (![files removeItemAtPath:[_directory stringByAppendingPathComponent:name] error:&error]) NSLog(@"exteria: cannot remove %@: %@", name, error);
    }
    [_memory removeAllObjects];
    [_failures removeAllObjects];
}

@end
