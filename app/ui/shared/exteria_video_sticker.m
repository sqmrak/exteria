#import "exteria_video_sticker.h"
#import "exteria_video_sticker_core.h"

/* 46 frames at 128 square pixels stay below 3 MiB per visible video sticker */
#define VIDEO_SIDE 128
#define VIDEO_FPS 15.0

@interface ExteriaVideoSticker () {
    NSArray *_frames;
    NSLock *_videoLock;
    NSTimeInterval _length;
    BOOL _decoded;
    BOOL _invalidated;
    BOOL _decodingFailed;
    CGImageRef _finishedImage;
}
- (BOOL)renderingCancelled;
@end

typedef struct { NSMutableArray *frames; ExteriaVideoSticker *video; } video_context;

static int append_frame(void *context, const uint8_t *pixels, int width, int height) {
    video_context *decode = context;
    if ([decode->video renderingCancelled]) return -1;
    NSMutableArray *frames = decode->frames;
    if (frames.count >= 48) return -1;
    CFDataRef bytes = CFDataCreate(NULL, pixels, width * height * 4);
    CGDataProviderRef provider = bytes ? CGDataProviderCreateWithCFData(bytes) : NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = provider && space ? CGImageCreate(width, height, 8, 32, width * 4, space,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, provider, NULL, false, kCGRenderingIntentDefault) : NULL;
    if (image) { [frames addObject:(id)image]; CGImageRelease(image); }
    if (provider) CGDataProviderRelease(provider);
    if (space) CGColorSpaceRelease(space);
    if (bytes) CFRelease(bytes);
    return image ? 1 : -1;
}

@implementation ExteriaVideoSticker
+ (ExteriaVideoSticker *)animationWithPackedData:(NSData *)packed key:(NSString *)key {
    if (!packed.length || packed.length > 512 * 1024) return nil;
    ExteriaVideoSticker *video = [[[self alloc] init] autorelease];
    video->_videoLock = [[NSLock alloc] init];
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("exteria.sticker.video", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        if ([video renderingCancelled]) { [pool drain]; return; }
        NSMutableArray *frames = [NSMutableArray array];
        video_context context = {frames, video};
        double duration = 0;
        int count = exteria_video_sticker_decode(packed.bytes, packed.length, VIDEO_SIDE, VIDEO_FPS, append_frame, &context, &duration);
        if (count <= 0 && ![video renderingCancelled]) NSLog(@"exteria: video sticker %@ could not be decoded", key);
        NSArray *result = count > 0 ? [[frames copy] autorelease] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!video->_invalidated) {
                video->_frames = [result retain];
                video->_length = duration;
                video->_decoded = count > 0;
                video->_decodingFailed = count <= 0;
            }
        });
        [pool drain];
    });
    return video;
}
- (BOOL)renderingCancelled {
    [_videoLock lock]; BOOL cancelled = _invalidated; [_videoLock unlock]; return cancelled;
}
- (BOOL)ready { return _decoded && !_invalidated; }
- (BOOL)failed { return _decodingFailed; }
- (NSUInteger)frameCount { return _frames.count; }
- (double)framesPerSecond { return _length > 0 ? _frames.count / _length : VIDEO_FPS; }
- (NSTimeInterval)duration { return _length; }
- (BOOL)requestFrame:(NSUInteger)frame side:(NSUInteger)side {
    (void)side;
    if (!self.ready || !_frames.count) return NO;
    if (_finishedImage) CGImageRelease(_finishedImage);
    _finishedImage = CGImageRetain((CGImageRef)[_frames objectAtIndex:MIN(frame, _frames.count - 1)]);
    return YES;
}
- (CGImageRef)copyFinishedFrame {
    CGImageRef image = _finishedImage; _finishedImage = NULL; return image;
}
- (void)invalidate {
    [_videoLock lock]; _invalidated = YES; [_videoLock unlock];
    if (_finishedImage) CGImageRelease(_finishedImage);
    _finishedImage = NULL;
    [_frames release]; _frames = nil;
}
- (void)dealloc { [self invalidate]; [_videoLock release]; [super dealloc]; }
@end
