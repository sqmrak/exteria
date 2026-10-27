#import "exteria_lottie_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_lottie.h"
#import "exteria_video_sticker.h"
#import "exteria_image_decoder.h"
#import "exteria_platform.h"

@interface ExteriaLottieView () {
    NSString *_name;
    NSData *_packed;
    id<ExteriaFrameAnimation> _animation;
    CADisplayLink *_link;
    NSUInteger _side;
    NSUInteger _requestedFrame;
    CFTimeInterval _startTime;
    BOOL _clockStarted;
    BOOL _playing;
    BOOL _once;
    NSUInteger _lastFrame;
    BOOL _needsPoster;
    BOOL _posterRequested;
    BOOL _loadFailed;
    void (^_firstFrameHandler)(void);
}
@end

@implementation ExteriaLottieView

@synthesize lastFrame = _lastFrame;
@synthesize firstFrameHandler = _firstFrameHandler;

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
    } else if (!loaded && _animation) {
        _playing = NO;
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
    [self updateLink];
}

/* the display link retains its target, so it only lives while the view is on screen */
- (void)updateLink {
    BOOL wanted = _animation && self.window && _side >= 8 && (_playing || _needsPoster);
    if (wanted && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        _link.frameInterval = 1;
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
    playing = playing && !ExteriaReduceMotionEnabled();
    if (playing) [self setLoaded:YES];
    playing = playing && _animation;
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
    _once = YES;
    _requestedFrame = NSUIntegerMax;
    [self setPlaying:NO];
    [self setPlaying:YES];
}

- (void)rewind {
    _once = NO;
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
    NSInteger interval = _animation.framesPerSecond > 30 ? 1 : 2;
    if (_link.frameInterval != interval) _link.frameInterval = interval;
    CGImageRef image = [_animation copyFinishedFrame];
    if (image) {
        self.layer.contents = (id)image;
        CGImageRelease(image);
        _needsPoster = NO;
        if (_firstFrameHandler) {
            void (^ready)(void) = _firstFrameHandler;
            _firstFrameHandler = nil;
            ready();
            [ready release];
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
        }
        return;
    }
    if (!_needsPoster) {
        [self updateLink];
    } else if (!_posterRequested) {
        _posterRequested = [_animation requestFrame:0 side:_side];
    }
}

@end
