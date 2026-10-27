#import "exteria_animated_icon_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_welcome_icon_geometry.h"

#define ENTRANCE_DURATION 0.7
#define ARROW_DRIFT 0.025
#define TOP_TURN_SECONDS 24.0
#define BOTTOM_TURN_SECONDS 30.0

@interface ExteriaAnimatedIconView () {
    CALayer *_back;
    CALayer *_clip;
    CALayer *_fillTop;
    CALayer *_fillBottom;
    CALayer *_holderTop;
    CALayer *_holderBottom;
    CALayer *_diskTop;
    CALayer *_diskBottom;
    CALayer *_arrow;
}
@end

@implementation ExteriaAnimatedIconView

static CALayer *ExteriaIconLayer(NSString *name) {
    CALayer *layer = [CALayer layer];
    layer.contents = (id)[UIImage imageNamed:name].CGImage;
    return layer;
}

/* each wave is a fill image seen through a scalloped disk; the disk turns, the fill stays put */
static CALayer *ExteriaWaveFill(NSString *fillName, NSString *diskName, CALayer **holder, CALayer **disk) {
    CALayer *fill = ExteriaIconLayer(fillName);
    *holder = [[CALayer layer] retain];
    *disk = [ExteriaIconLayer(diskName) retain];
    [*holder addSublayer:*disk];
    fill.mask = *holder;
    return fill;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.isAccessibilityElement = NO;
    _back = [ExteriaIconLayer(@"welcome_icon_back") retain];
    _clip = [[CALayer layer] retain];
    /* the waves swell past the icon outline, so the base shape cuts them off */
    CALayer *mask = [CALayer layer];
    mask.contents = _back.contents;
    _clip.mask = mask;
    _fillTop = [ExteriaWaveFill(@"welcome_icon_wave_top_fill", @"welcome_icon_wave_top_disk",
                                &_holderTop, &_diskTop) retain];
    _fillBottom = [ExteriaWaveFill(@"welcome_icon_wave_bottom_fill", @"welcome_icon_wave_bottom_disk",
                                   &_holderBottom, &_diskBottom) retain];
    _arrow = [ExteriaIconLayer(@"welcome_icon_arrow") retain];
    [_clip addSublayer:_fillTop];
    [_clip addSublayer:_fillBottom];
    [_clip addSublayer:_arrow];
    [self.layer addSublayer:_back];
    [self.layer addSublayer:_clip];
    return self;
}

- (void)dealloc {
    [_back release];
    [_clip release];
    [_fillTop release];
    [_fillBottom release];
    [_holderTop release];
    [_holderBottom release];
    [_diskTop release];
    [_diskBottom release];
    [_arrow release];
    [super dealloc];
}

/* the entrance scales a wave about its disk centre, so the holder gets that anchor before its frame */
static void ExteriaPlaceWave(CALayer *holder, CALayer *disk, CGRect bounds,
                             CGFloat centerX, CGFloat centerY, CGFloat side) {
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    holder.anchorPoint = CGPointMake(centerX, centerY);
    holder.frame = bounds;
    disk.bounds = CGRectMake(0, 0, side * w, side * h);
    disk.position = CGPointMake(centerX * w, centerY * h);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect bounds = self.bounds;
    _back.frame = bounds;
    _clip.frame = bounds;
    _clip.mask.frame = _clip.bounds;
    _fillTop.frame = _clip.bounds;
    _fillBottom.frame = _clip.bounds;
    _arrow.frame = _clip.bounds;
    ExteriaPlaceWave(_holderTop, _diskTop, _clip.bounds, EXTERIA_ICON_WAVE_TOP_CENTER_X,
                     EXTERIA_ICON_WAVE_TOP_CENTER_Y, EXTERIA_ICON_WAVE_TOP_SIDE);
    ExteriaPlaceWave(_holderBottom, _diskBottom, _clip.bounds, EXTERIA_ICON_WAVE_BOTTOM_CENTER_X,
                     EXTERIA_ICON_WAVE_BOTTOM_CENTER_Y, EXTERIA_ICON_WAVE_BOTTOM_SIDE);
    [CATransaction commit];
}

static CABasicAnimation *ExteriaBasic(NSString *keyPath, id from, id to, CFTimeInterval duration) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:keyPath];
    animation.fromValue = from;
    animation.toValue = to;
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    return animation;
}

static CAKeyframeAnimation *ExteriaKeyframes(NSString *keyPath, NSArray *values, NSArray *times, CFTimeInterval duration) {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
    animation.values = values;
    animation.keyTimes = times;
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    return animation;
}

static void ExteriaTurn(CALayer *layer, CGFloat direction, CFTimeInterval seconds) {
    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    turn.fromValue = [NSNumber numberWithDouble:0];
    turn.toValue = [NSNumber numberWithDouble:direction * 2 * M_PI];
    turn.duration = seconds;
    turn.repeatCount = HUGE_VALF;
    turn.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:turn forKey:@"turn"];
}

static void ExteriaIdle(CALayer *layer, NSString *key, CABasicAnimation *animation, CFTimeInterval delay) {
    animation.autoreverses = YES;
    animation.repeatCount = HUGE_VALF;
    animation.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
    [layer addAnimation:animation forKey:key];
}

- (void)startAnimating {
    [self stopAnimating];
    if (ExteriaReduceMotionEnabled()) return;
    CGFloat width = self.bounds.size.width;
    NSArray *times = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.6],
                                               [NSNumber numberWithFloat:1], nil];

    [self.layer addAnimation:ExteriaKeyframes(@"transform.scale",
        [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.55], [NSNumber numberWithFloat:1.06],
                                  [NSNumber numberWithFloat:1], nil], times, ENTRANCE_DURATION) forKey:@"entrance"];
    [self.layer addAnimation:ExteriaBasic(@"opacity", [NSNumber numberWithFloat:0], [NSNumber numberWithFloat:1], 0.25)
                      forKey:@"fade"];

    /* the waves open up from their disk centres */
    [_holderTop addAnimation:ExteriaBasic(@"transform.scale", [NSNumber numberWithFloat:0.05],
        [NSNumber numberWithFloat:1], ENTRANCE_DURATION) forKey:@"entrance"];
    [_holderBottom addAnimation:ExteriaBasic(@"transform.scale", [NSNumber numberWithFloat:0.05],
        [NSNumber numberWithFloat:1], ENTRANCE_DURATION) forKey:@"entrance"];
    [_arrow addAnimation:ExteriaKeyframes(@"transform.translation.x",
        [NSArray arrayWithObjects:[NSNumber numberWithFloat:width * 0.25], [NSNumber numberWithFloat:-width * 0.03],
                                  [NSNumber numberWithFloat:0], nil], times, ENTRANCE_DURATION) forKey:@"entrance"];
    [_arrow addAnimation:ExteriaBasic(@"opacity", [NSNumber numberWithFloat:0], [NSNumber numberWithFloat:1], 0.3)
                  forKey:@"fade"];

    ExteriaTurn(_diskTop, 1, TOP_TURN_SECONDS);
    ExteriaTurn(_diskBottom, -1, BOTTOM_TURN_SECONDS);
    ExteriaIdle(_arrow, @"idle", ExteriaBasic(@"transform.translation.x", [NSNumber numberWithFloat:0],
        [NSNumber numberWithFloat:-width * ARROW_DRIFT], 2.6), ENTRANCE_DURATION);
}

- (void)stopAnimating {
    [self.layer removeAllAnimations];
    [_holderTop removeAllAnimations];
    [_holderBottom removeAllAnimations];
    [_diskTop removeAllAnimations];
    [_diskBottom removeAllAnimations];
    [_arrow removeAllAnimations];
}

@end
