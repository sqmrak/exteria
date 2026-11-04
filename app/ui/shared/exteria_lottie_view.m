#import "exteria_lottie_view.h"
#import "exteria_animation.h"

#import <QuartzCore/QuartzCore.h>

#include <ctype.h>

#import "exteria_lottie.h"
#import "exteria_video_sticker.h"
#import "exteria_image_decoder.h"
#import "exteria_platform.h"

@interface ExteriaLottieView () {
    NSString *_name;
    NSData *_packed;
    id<ExteriaFrameAnimation> _animation;
    CADisplayLink *_link;
    NSInteger _linkRate;
    NSUInteger _side;
    NSUInteger _requestedFrame;
    CFTimeInterval _startTime;
    BOOL _clockStarted;
    BOOL _playing;
    BOOL _once;
    BOOL _finishPending;
    NSUInteger _lastFrame;
    BOOL _needsPoster;
    BOOL _posterRequested;
    BOOL _loadFailed;
    BOOL _cachesPoster;
    /* the frame in flight is the first one, not a frame of the play that follows */
    BOOL _posterFrameInFlight;
    void (^_firstFrameHandler)(void);
    void (^_finishHandler)(void);
}
@end

@implementation ExteriaLottieView

@synthesize lastFrame = _lastFrame;
@synthesize firstFrameHandler = _firstFrameHandler;
@synthesize finishHandler = _finishHandler;
@synthesize cachesPoster = _cachesPoster;

static NSMutableDictionary *ExteriaPosterMemory(void) {
    static NSMutableDictionary *memory;
    if (!memory) memory = [[NSMutableDictionary alloc] init];
    return memory;
}

/* the name is a file key or an animation name, so only letters and digits are kept in the file name */
- (NSString *)posterKey {
    NSMutableString *key = [NSMutableString string];
    for (NSUInteger i = 0; i < _name.length && key.length < 80; ++i) {
        unichar c = [_name characterAtIndex:i];
        [key appendFormat:@"%C", (unichar)(isalnum(c) ? c : '_')];
    }
    return [NSString stringWithFormat:@"%@@%lu", key, (unsigned long)_side];
}

- (NSString *)posterPath {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if (!roots.count) return nil;
    return [[[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria/posters"] stringByAppendingPathComponent:[[self posterKey] stringByAppendingString:@".png"]];
}

/* the first frame of an earlier visit, on the layer before the animation has parsed; the real frame replaces it */
- (void)showCachedPoster {
    if (!_cachesPoster || !_side || self.layer.contents) return;
    NSString *key = [self posterKey];
    UIImage *poster = [ExteriaPosterMemory() objectForKey:key];
    if (!poster) {
        NSString *path = [self posterPath];
        poster = path ? [UIImage imageWithContentsOfFile:path] : nil;
        if (poster) [ExteriaPosterMemory() setObject:poster forKey:key];
    }
    if (poster) self.layer.contents = (id)poster.CGImage;
}

- (void)storePoster:(CGImageRef)image {
    NSString *key = [self posterKey];
    if ([ExteriaPosterMemory() objectForKey:key]) return;
    UIImage *poster = [UIImage imageWithCGImage:image];
    [ExteriaPosterMemory() setObject:poster forKey:key];
    NSString *path = [self posterPath];
    if (!path) return;
    NSData *png = UIImagePNGRepresentation(poster);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error] ||
        !png || ![png writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"exteria: the first frame of %@ was not kept: %@", _name, error);
    }
}

- (id)initWithAnimationNamed:(NSString *)name {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    _name = [name copy];
    _requestedFrame = NSUIntegerMax;
    return self;
}

- (id)initWithPackedData:(NSData *)packed key:(NSString *)key {
    self = [self initWithAnimationNamed:key];
    if (!self) return nil;
    _packed = [packed retain];
    return self;
}

- (void)dealloc {
    [_animation invalidate];
    [_animation release];
    [_name release];
    [_packed release];
    [_firstFrameHandler release];
    [_finishHandler release];
    [super dealloc];
}

- (void)setLoaded:(BOOL)loaded {
    if (loaded && !_animation && !_loadFailed) {
        if (ExteriaFileFormatOfData(_packed) == ExteriaFileFormatMatroska)
            _animation = [[ExteriaVideoSticker animationWithPackedData:_packed key:_name] retain];
        else _animation = [(_packed ? [ExteriaLottie animationWithPackedData:_packed key:_name] : [ExteriaLottie animationNamed:_name]) retain];
        _loadFailed = _animation == nil;
        _needsPoster = _animation != nil;
        _posterRequested = NO;
        _requestedFrame = NSUIntegerMax;
        [self showCachedPoster];
    } else if (!loaded && _animation) {
        _playing = NO;
        _finishPending = NO;
        [_animation invalidate];
        [_animation release];
        _animation = nil;
        self.layer.contents = nil;
    }
    [self updateLink];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat pixels = MAX(self.bounds.size.width, self.bounds.size.height) * ExteriaScreenScale();
    NSUInteger side = (NSUInteger)ceil(pixels);
    if (side == _side) return;
    _side = side;
    _needsPoster = _animation != nil;
    _posterRequested = NO;
    _requestedFrame = NSUIntegerMax;
    [self showCachedPoster];
    [self updateLink];
}

/* the display link retains its target, so it only lives while the view is on screen */
- (void)updateLink {
    BOOL wanted = _animation && self.window && _side >= 8 && (_playing || _needsPoster);
    if (wanted && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        _linkRate = 60;
        ExteriaSetFrameRate(_link, _linkRate);
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _clockStarted = NO;
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
    /* asked to play, the view loops: the stop on the last frame belongs to playOnce alone, and left set it made an animation that was played once by a tap play once on every later start */
    if (playing) { _once = NO; _finishPending = NO; }
    playing = playing && !ExteriaReduceMotionEnabled();
    if (playing) [self setLoaded:YES];
    playing = playing && _animation;
    if (playing) _posterFrameInFlight = NO;
    if (playing == _playing) return;
    _playing = playing;
    _clockStarted = NO;
    [self updateLink];
}

- (void)playOnce {
    if (ExteriaReduceMotionEnabled()) {
        [self rewind];
        return;
    }
    _requestedFrame = NSUIntegerMax;
    [self setPlaying:NO];
    [self setPlaying:YES];
    _once = YES;
}

- (void)rewind {
    _once = NO;
    _finishPending = NO;
    _playing = NO;
    [self setLoaded:YES];
    _needsPoster = _animation != nil;
    _posterRequested = NO;
    _requestedFrame = NSUIntegerMax;
    [self updateLink];
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    if (_animation.failed) {
        _loadFailed = YES;
        [self setLoaded:NO];
        return;
    }
    if (!_animation.ready) return;
    /* requestFrame admits one render at a time, so a slow device drops frames without building a queue */
    NSInteger rate = _animation.framesPerSecond > 30 ? 60 : 30;
    if (rate != _linkRate) {
        _linkRate = rate;
        ExteriaSetFrameRate(_link, rate);
    }
    CGImageRef image = [_animation copyFinishedFrame];
    if (image) {
        self.layer.contents = (id)image;
        if (_cachesPoster && _posterFrameInFlight && !_playing) [self storePoster:image];
        _posterFrameInFlight = NO;
        CGImageRelease(image);
        _needsPoster = NO;
        if (_firstFrameHandler) {
            void (^ready)(void) = _firstFrameHandler;
            _firstFrameHandler = nil;
            ready();
            [ready release];
        }
        if (_finishPending) {
            _finishPending = NO;
            if (_finishHandler) {
                void (^finished)(void) = [_finishHandler autorelease];
                _finishHandler = nil;
                dispatch_async(dispatch_get_main_queue(), finished);
            }
        }
    }
    if (_playing) {
        if (!_clockStarted) {
            /* parsing on the render queue must not consume the start of a one-shot animation */
            _startTime = CACurrentMediaTime();
            _clockStarted = YES;
        }
        double elapsed = CACurrentMediaTime() - _startTime;
        NSUInteger last = _animation.frameCount - 1;
        if (_once && _lastFrame && _lastFrame < last) last = _lastFrame;
        NSUInteger frame = _once ? (NSUInteger)(elapsed * _animation.framesPerSecond)
                                 : (NSUInteger)(fmod(elapsed, _animation.duration) * _animation.framesPerSecond);
        if (_once && frame > last) frame = last;
        if (frame != _requestedFrame && [_animation requestFrame:frame side:_side]) _requestedFrame = frame;
        if (_once && _requestedFrame == last) {
            /* the last frame is in flight; one more tick collects it and drops the link */
            _playing = NO;
            _needsPoster = YES;
            _posterRequested = YES;
            _finishPending = YES;
        }
        return;
    }
    if (!_needsPoster) {
        [self updateLink];
    } else if (!_posterRequested) {
        _posterRequested = [_animation requestFrame:0 side:_side];
        _posterFrameInFlight = _posterRequested;
    }
}

@end
