#import "exteria_theme_busy_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_lottie.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_shiro_style.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define DUCK_SIDE 132.0
#define LABEL_GAP 6.0
/* the duck is drawn once into pictures and played from them by the render server: the screens are made again on the main thread, which stops the display link that
   draws the live animation, and the duck froze at its first frame. every third frame of the 60 a second is kept, 20 pictures a second, to hold the memory to a few megabytes */
#define BAKE_STRIDE 3
#define BAKE_STEP_SECONDS 0.02

@interface ExteriaThemeBusyView () {
    ExteriaLottieView *_duck;
    UILabel *_label;
    BOOL _ready;
    void (^_waiting)(void);
    NSString *_animationName;
    ExteriaLottie *_baker;
    NSMutableArray *_frames;
    NSTimer *_bakeTimer;
    BOOL _bakeInFlight;
    BOOL _baked;
    BOOL _animating;
    NSTimeInterval _bakedDuration;
    CALayer *_bakedLayer;
}
@end

@implementation ExteriaThemeBusyView

- (id)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame animation:@"theme_duck"];
}

- (id)initWithFrame:(CGRect)frame animation:(NSString *)animation {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42f];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.userInteractionEnabled = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = NSLocalizedString(@"theme.applying", nil);
    _animationName = [animation copy];
    _frames = [[NSMutableArray alloc] init];
    _duck = [[ExteriaLottieView alloc] initWithAnimationNamed:animation];
    [self addSubview:_duck];
    /* the animation is parsed when the view is made, long before it is shown: the parse took longer than the darkening, and the duck was missing */
    ExteriaThemeBusyView *me = self;
    _duck.firstFrameHandler = ^{ [me duckReady]; };
    [_duck setLoaded:YES];
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = [UIColor whiteColor];
    _label.textAlignment = ExteriaTextAlignmentCenter;
    _label.font = ExteriaShiroFontBody(17, YES);
    _label.numberOfLines = 2;
    _label.text = NSLocalizedString(@"theme.applying", nil);
    [self addSubview:_label];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [self startBaking];
    return self;
}

- (NSString *)text {
    return _label.text;
}

- (void)setText:(NSString *)text {
    _label.text = text;
    self.accessibilityLabel = text;
    [self setNeedsLayout];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_bakeTimer invalidate];
    [_baker invalidate];
    [_baker release];
    [_frames release];
    [_bakedLayer release];
    [_animationName release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(duckReady) object:nil];
    _duck.firstFrameHandler = nil;
    [_waiting release];
    [_duck release];
    [_label release];
    [super dealloc];
}

- (void)duckReady {
    _ready = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(duckReady) object:nil];
    void (^block)(void) = _waiting;
    _waiting = nil;
    if (block) {
        block();
        [block release];
    }
}

- (void)whenReady:(void (^)(void))block {
    if (_ready) {
        block();
        return;
    }
    [_waiting release];
    _waiting = [block copy];
    /* the first frame may never come (the animation failed to parse), and the work must not wait for it for ever */
    [self performSelector:@selector(duckReady) withObject:nil afterDelay:0.8];
}

#pragma mark baked frames

- (NSUInteger)bakeSide {
    return (NSUInteger)ceil(DUCK_SIDE * ExteriaScreenScale());
}

- (void)startBaking {
    if (_baked || _bakeTimer || ExteriaReduceMotionEnabled()) return;
    if (!_baker) _baker = [[ExteriaLottie animationNamed:_animationName] retain];
    if (!_baker) {
        NSLog(@"exteria: the animation %@ is not in the bundle, so it plays live", _animationName);
        return;
    }
    [_frames removeAllObjects];
    _bakeInFlight = NO;
    _bakeTimer = [NSTimer scheduledTimerWithTimeInterval:BAKE_STEP_SECONDS target:self selector:@selector(bakeStep:) userInfo:nil repeats:YES];
}

- (void)stopBaking {
    [_bakeTimer invalidate];
    _bakeTimer = nil;
    [_baker invalidate];
    [_baker release];
    _baker = nil;
    _bakeInFlight = NO;
}

/* one frame at a time: the renderer admits a single request, and the timer asks again when the picture has come */
- (void)bakeStep:(NSTimer *)timer {
    (void)timer;
    if (_baker.failed) {
        NSLog(@"exteria: the animation %@ did not parse, so it plays live", _animationName);
        [_frames removeAllObjects];
        [self stopBaking];
        return;
    }
    if (!_baker.ready) return;
    CGImageRef image = [_baker copyFinishedFrame];
    if (image) {
        [_frames addObject:(id)image];
        CGImageRelease(image);
        _bakeInFlight = NO;
    }
    NSUInteger next = _frames.count * BAKE_STRIDE;
    if (!_bakeInFlight && next >= _baker.frameCount) {
        _bakedDuration = _baker.duration;
        [self stopBaking];
        _baked = YES;
        if (!_bakedLayer) {
            _bakedLayer = [[CALayer alloc] init];
            _bakedLayer.contentsScale = ExteriaScreenScale();
            _bakedLayer.hidden = YES;
            [self.layer addSublayer:_bakedLayer];
        }
        _bakedLayer.contents = [_frames objectAtIndex:0];
        [self setNeedsLayout];
        if (_animating) [self playBaked];
        return;
    }
    if (!_bakeInFlight && next < _baker.frameCount && [_baker requestFrame:next side:[self bakeSide]]) _bakeInFlight = YES;
}

- (void)playBaked {
    [_duck setPlaying:NO];
    _duck.hidden = YES;
    _bakedLayer.hidden = NO;
    CAKeyframeAnimation *play = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
    play.values = _frames;
    play.calculationMode = kCAAnimationDiscrete;
    play.duration = _bakedDuration;
    play.repeatCount = HUGE_VALF;
    play.removedOnCompletion = NO;
    [_bakedLayer addAnimation:play forKey:@"duck"];
}

/* the pictures are the largest thing here; with the duck not on screen they go, and the next start makes them again */
- (void)memoryWarning {
    if (_animating) return;
    [_bakedLayer removeAllAnimations];
    _bakedLayer.contents = nil;
    _bakedLayer.hidden = YES;
    [_frames removeAllObjects];
    _baked = NO;
    _duck.hidden = NO;
    [self stopBaking];
}

- (void)startAnimating {
    _animating = YES;
    if (_baked) {
        [self playBaked];
        return;
    }
    [self startBaking];
    _duck.hidden = NO;
    [_duck setPlaying:YES];
}

/* the animation stays parsed for the next change; only its playing stops */
- (void)stopAnimating {
    _animating = NO;
    [_bakedLayer removeAnimationForKey:@"duck"];
    [_duck setPlaying:NO];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat textWidth = MIN(size.width - 48, 300);
    CGSize fit = [_label sizeThatFits:CGSizeMake(textWidth, 80)];
    CGFloat total = DUCK_SIDE + LABEL_GAP + fit.height;
    CGFloat top = floor((size.height - total) / 2);
    _duck.frame = CGRectMake(floor((size.width - DUCK_SIDE) / 2), top, DUCK_SIDE, DUCK_SIDE);
    _label.frame = CGRectMake(floor((size.width - textWidth) / 2), top + DUCK_SIDE + LABEL_GAP, textWidth, ceil(fit.height));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _bakedLayer.frame = _duck.frame;
    [CATransaction commit];
}

@end
