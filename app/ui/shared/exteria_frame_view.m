#import "exteria_frame_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"

/* the current frame plus the ones about to show; a decoded frame is a quarter megabyte */
#define EXTERIA_FRAME_AHEAD 3
#define EXTERIA_FRAME_INTERVAL 2

static dispatch_queue_t ExteriaFrameQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("exteria.frames", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

/* png files decode on first draw, so the draw happens here and not on the main thread */
static CGImageRef ExteriaDecodeFrame(NSString *path) {
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    CGImageRef source = image.CGImage;
    if (!source) return NULL;
    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!context) return NULL;
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), source);
    CGImageRef decoded = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return decoded;
}

@interface ExteriaFrameView () {
    NSString *_prefix;
    NSUInteger _count;
    double _fps;
    NSLock *_lock;
    NSMutableDictionary *_decoded;
    NSMutableSet *_pending;
    CADisplayLink *_link;
    CFTimeInterval _startTime;
    NSUInteger _shown;
    BOOL _playing;
    BOOL _hasContent;
}
@end

@implementation ExteriaFrameView

- (id)initWithPrefix:(NSString *)prefix count:(NSUInteger)count framesPerSecond:(double)fps {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _prefix = [prefix copy];
    _count = count;
    _fps = fps;
    _lock = [[NSLock alloc] init];
    _decoded = [[NSMutableDictionary alloc] init];
    _pending = [[NSMutableSet alloc] init];
    _shown = NSUIntegerMax;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    self.layer.contentsGravity = kCAGravityResizeAspect;
    return self;
}

- (void)dealloc {
    [_prefix release];
    [_lock release];
    [_decoded release];
    [_pending release];
    [super dealloc];
}

/* the display link retains its target, so it only lives while the view is on screen and has work */
- (void)updateLink {
    BOOL wanted = self.window && _count > 0 && (_playing || !_hasContent);
    if (wanted && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        _link.frameInterval = EXTERIA_FRAME_INTERVAL;
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _startTime = CACurrentMediaTime();
    } else if (!wanted && _link) {
        [_link invalidate];
        _link = nil;
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateLink];
}

- (void)setPlaying:(BOOL)playing {
    playing = playing && !ExteriaReduceMotionEnabled();
    if (playing == _playing) return;
    _playing = playing;
    if (_link) _startTime = CACurrentMediaTime();
    [self updateLink];
}

- (void)requestFrame:(NSUInteger)index {
    NSNumber *key = [NSNumber numberWithUnsignedInteger:index];
    [_lock lock];
    BOOL needed = ![_decoded objectForKey:key] && ![_pending containsObject:key];
    if (needed) [_pending addObject:key];
    [_lock unlock];
    if (!needed) return;
    NSString *path = [[NSBundle mainBundle] pathForResource:[NSString stringWithFormat:@"%@_%03d", _prefix, (int)index]
                                                     ofType:@"png"];
    dispatch_async(ExteriaFrameQueue(), ^{
        CGImageRef image = path ? ExteriaDecodeFrame(path) : NULL;
        [_lock lock];
        [_pending removeObject:key];
        if (image) [_decoded setObject:(id)image forKey:key];
        [_lock unlock];
        if (image) CGImageRelease(image);
        else NSLog(@"exteria: frame %@ %d did not decode", _prefix, (int)index);
    });
}

/* frames behind the playhead are dropped so the cache stays a few frames deep */
- (void)trimAround:(NSUInteger)index {
    [_lock lock];
    for (NSNumber *key in [_decoded allKeys]) {
        NSUInteger frame = [key unsignedIntegerValue];
        NSUInteger distance = (frame + _count - index) % _count;
        if (distance >= EXTERIA_FRAME_AHEAD + 1 && frame != _shown) [_decoded removeObjectForKey:key];
    }
    [_lock unlock];
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    NSUInteger index = 0;
    if (_playing) index = (NSUInteger)((CACurrentMediaTime() - _startTime) * _fps) % _count;
    for (NSUInteger i = 0; i < EXTERIA_FRAME_AHEAD; ++i) [self requestFrame:(index + i) % _count];
    [_lock lock];
    id image = [[_decoded objectForKey:[NSNumber numberWithUnsignedInteger:index]] retain];
    [_lock unlock];
    if (image && index != _shown) {
        self.layer.contents = image;
        _shown = index;
        _hasContent = YES;
    }
    [image release];
    [self trimAround:index];
    if (!_playing && _hasContent) [self updateLink];
}

@end
