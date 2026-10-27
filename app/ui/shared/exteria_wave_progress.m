#import "exteria_wave_progress.h"

#import <QuartzCore/QuartzCore.h>

#include <math.h>

#import "exteria_music_style.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define WAVE_PERIOD 26.0
#define WAVE_AMPLITUDE 3.0
#define WAVE_LINE 4.0
#define WAVE_GAP 6.0
#define PROGRESS_HEIGHT ExteriaWaveProgressHeight
#define PROGRESS_INSET ExteriaWaveProgressInset
#define THUMB_HEIGHT 24.0

static NSString *const ExteriaWavePhaseKey = @"wave.phase";
static NSString *const ExteriaWaveMorphKey = @"wave.morph";

/* a line from 0 to width that rides amplitude above and below the middle; the point count depends on the width alone, so a wave and a flat line
   of one width morph into each other */
static UIBezierPath *ExteriaWaveLine(CGFloat width, CGFloat amplitude, CGFloat mid) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    int count = (int)ceil(width / 3) + 1;
    for (int i = 0; i < count; ++i) {
        CGFloat x = width * i / (count - 1);
        CGPoint point = CGPointMake(x, mid + amplitude * sin(2 * M_PI * x / WAVE_PERIOD));
        if (i == 0) [path moveToPoint:point];
        else [path addLineToPoint:point];
    }
    return path;
}

@implementation ExteriaWaveProgress

@synthesize value = _value;
@synthesize waving = _waving;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.isAccessibilityElement = YES;
    /* UIAccessibilityTraitAdjustable is 1 << 12; the constant is not exported by every runtime this app starts on */
    self.accessibilityTraits = (UIAccessibilityTraits)(1 << 12);
    UIColor *accent = ExteriaColorAccent();
    _rest = [[CAShapeLayer alloc] init];
    _rest.fillColor = nil;
    _rest.strokeColor = [accent colorWithAlphaComponent:0.28f].CGColor;
    _rest.lineWidth = WAVE_LINE;
    _rest.lineCap = kCALineCapRound;
    _rest.anchorPoint = CGPointMake(0, 0.5f);
    [self.layer addSublayer:_rest];
    _clip = [[CALayer alloc] init];
    _clip.masksToBounds = YES;
    _clip.anchorPoint = CGPointMake(0, 0.5f);
    [self.layer addSublayer:_clip];
    _wave = [[CAShapeLayer alloc] init];
    _wave.fillColor = nil;
    _wave.strokeColor = accent.CGColor;
    _wave.lineWidth = WAVE_LINE;
    _wave.lineCap = kCALineCapRound;
    _wave.lineJoin = kCALineJoinRound;
    _wave.anchorPoint = CGPointMake(0, 0.5f);
    [_clip addSublayer:_wave];
    _thumb = [[CALayer alloc] init];
    _thumb.backgroundColor = accent.CGColor;
    _thumb.cornerRadius = 2;
    [self.layer addSublayer:_thumb];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_rest release];
    [_clip release];
    [_wave release];
    [_thumb release];
    [super dealloc];
}

- (CGFloat)trackWidth {
    return MAX(1, self.bounds.size.width - PROGRESS_INSET * 2);
}

- (BOOL)moving {
    return self.window != nil && !ExteriaReduceMotionEnabled() && _laidSize.width > 0;
}

- (UIBezierPath *)wavePath {
    return ExteriaWaveLine([self trackWidth] + WAVE_PERIOD, _waving ? WAVE_AMPLITUDE : 0, PROGRESS_HEIGHT / 2);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (size.width < 1 || CGSizeEqualToSize(size, _laidSize)) return;
    _laidSize = size;
    CGFloat mid = PROGRESS_HEIGHT / 2;
    CGFloat track = [self trackWidth];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _rest.bounds = CGRectMake(0, 0, track, PROGRESS_HEIGHT);
    _rest.position = CGPointMake(PROGRESS_INSET, mid);
    UIBezierPath *line = [UIBezierPath bezierPath];
    [line moveToPoint:CGPointMake(0, mid)];
    [line addLineToPoint:CGPointMake(track, mid)];
    _rest.path = line.CGPath;
    _clip.position = CGPointMake(0, mid);
    _wave.bounds = CGRectMake(0, 0, track + WAVE_PERIOD, PROGRESS_HEIGHT);
    _wave.position = CGPointMake(PROGRESS_INSET, mid);
    _wave.path = [self wavePath].CGPath;
    _thumb.bounds = CGRectMake(0, 0, 4, THUMB_HEIGHT);
    [CATransaction commit];
    [self placeGliding:NO];
    [self syncMotion];
}

/* the wave stops short of the handle and the plain line starts after it, with a gap on both sides */
- (void)placeGliding:(BOOL)gliding {
    CGFloat track = [self trackWidth];
    CGFloat played = _value * track;
    CGFloat waveEnd = played - WAVE_GAP;
    [CATransaction begin];
    if (gliding && !ExteriaReduceMotionEnabled()) {
        [CATransaction setAnimationDuration:0.5];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    } else {
        [CATransaction setDisableActions:YES];
    }
    _clip.bounds = CGRectMake(0, 0, waveEnd > 0 ? PROGRESS_INSET + waveEnd : 0, PROGRESS_HEIGHT);
    _rest.strokeStart = MIN(1, MAX(0, (played + WAVE_GAP) / track));
    _thumb.position = CGPointMake(PROGRESS_INSET + played, PROGRESS_HEIGHT / 2);
    [CATransaction commit];
}

- (void)setValue:(float)value gliding:(BOOL)gliding {
    value = value < 0 ? 0 : (value > 1 ? 1 : value);
    if (value == _value) return;
    _value = value;
    [self placeGliding:gliding && !_dragging];
}

- (void)setValue:(float)value {
    [self setValue:value gliding:NO];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1 : 0.4f;
}

- (NSString *)accessibilityValue {
    return [NSString stringWithFormat:@"%d%%", (int)(_value * 100 + 0.5f)];
}

- (void)stepBy:(float)step {
    [self setValue:_value + step gliding:NO];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)accessibilityIncrement { [self stepBy:0.05f]; }
- (void)accessibilityDecrement { [self stepBy:-0.05f]; }

#pragma mark wave motion

/* backgrounding drops running animations, so they start again when the app is active; a system that asks for reduced motion gets the wave standing still */
- (void)syncMotion {
    if (![self moving] || !_waving) {
        /* a wave that is going flat keeps travelling until the morph is over: the flat line does not show it, and removing it earlier would jump the crests */
        if (![_wave animationForKey:ExteriaWaveMorphKey] || ![self moving]) [_wave removeAnimationForKey:ExteriaWavePhaseKey];
        return;
    }
    if ([_wave animationForKey:ExteriaWavePhaseKey]) return;
    CABasicAnimation *travel = [CABasicAnimation animationWithKeyPath:@"position.x"];
    travel.fromValue = [NSNumber numberWithFloat:(float)(PROGRESS_INSET - WAVE_PERIOD)];
    travel.toValue = [NSNumber numberWithFloat:(float)PROGRESS_INSET];
    travel.duration = 1.3;
    travel.repeatCount = HUGE_VALF;
    travel.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [_wave addAnimation:travel forKey:ExteriaWavePhaseKey];
}

- (void)setWaving:(BOOL)waving {
    if (waving == _waving) return;
    _waving = waving;
    if (_laidSize.width < 1) return;
    CAShapeLayer *shown = (CAShapeLayer *)[_wave presentationLayer];
    CGPathRef from = shown && shown.path ? shown.path : _wave.path;
    CGPathRetain(from);
    [_wave removeAnimationForKey:ExteriaWaveMorphKey];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _wave.path = [self wavePath].CGPath;
    [CATransaction commit];
    if ([self moving] && from) {
        CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"path"];
        morph.fromValue = (id)from;
        morph.toValue = (id)_wave.path;
        morph.duration = 0.45;
        morph.timingFunction = ExteriaMusicSpring();
        morph.delegate = (id)self;
        [_wave addAnimation:morph forKey:ExteriaWaveMorphKey];
    }
    CGPathRelease(from);
    [self syncMotion];
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {
    (void)animation;
    if (finished && !_waving) [_wave removeAnimationForKey:ExteriaWavePhaseKey];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_observing) [center removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    _observing = NO;
    if (self.window) {
        [center addObserver:self selector:@selector(syncMotion) name:UIApplicationDidBecomeActiveNotification object:nil];
        _observing = YES;
    }
    [self syncMotion];
}

#pragma mark touch

- (void)squeezeThumb:(BOOL)squeezed {
    [CATransaction begin];
    if (ExteriaReduceMotionEnabled()) {
        [CATransaction setDisableActions:YES];
    } else {
        [CATransaction setAnimationDuration:0.25];
        [CATransaction setAnimationTimingFunction:ExteriaMusicSpring()];
    }
    _thumb.bounds = CGRectMake(0, 0, squeezed ? 2 : 4, THUMB_HEIGHT);
    [CATransaction commit];
}

- (float)valueForTouch:(UITouch *)touch {
    return (float)(([touch locationInView:self].x - PROGRESS_INSET) / [self trackWidth]);
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    _dragging = YES;
    [self squeezeThumb:YES];
    [self setValue:[self valueForTouch:touch] gliding:NO];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    [self setValue:[self valueForTouch:touch] gliding:NO];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)touch;
    (void)event;
    _dragging = NO;
    [self squeezeThumb:NO];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    (void)event;
    _dragging = NO;
    [self squeezeThumb:NO];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    return CGRectContainsPoint(CGRectInset(self.bounds, -8, -MAX(0, (44 - self.bounds.size.height) / 2)), point);
}

@end
