#import "exteria_animation.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "exteria_platform.h"

#define MOTION_SAMPLES 61

@interface ExteriaMotionCompletion : NSObject {
    void (^_completion)(BOOL);
}
- (id)initWithCompletion:(void (^)(BOOL))completion;
@end

@implementation ExteriaMotionCompletion
- (id)initWithCompletion:(void (^)(BOOL))completion {
    self = [super init];
    if (self) _completion = [completion copy];
    return self;
}
- (void)dealloc {
    [_completion release];
    [super dealloc];
}
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {
    (void)animation;
    if (_completion) _completion(finished);
}
@end

void ExteriaAnimateView(UIView *view, CGAffineTransform transform, CGFloat alpha,
                        exteria_motion_curve curve, void (^completion)(BOOL finished)) {
    ExteriaAnimateViewAfter(view, transform, alpha, curve, 0, completion);
}

void ExteriaAnimateViewAfter(UIView *view, CGAffineTransform transform, CGFloat alpha,
                             exteria_motion_curve curve, NSTimeInterval delay, void (^completion)(BOOL finished)) {
    CALayer *layer = view.layer;
    CALayer *visible = [layer animationForKey:@"exteria.motion"] ? [layer presentationLayer] : nil;
    CGAffineTransform from = visible ? CATransform3DGetAffineTransform(visible.transform) : view.transform;
    CGFloat fromAlpha = visible ? visible.opacity : view.alpha;
    [layer removeAnimationForKey:@"exteria.motion"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    view.transform = transform;
    view.alpha = alpha;
    [CATransaction commit];
    BOOL reduced = ExteriaReduceMotionEnabled();
    if (!view.window || ![UIView areAnimationsEnabled] || (reduced && !(delay > 0 && alpha < fromAlpha))) {
        if (completion) completion(YES);
        return;
    }
    if (reduced) {
        /* keep delayed notices readable when reduce motion disables their fade */
        CABasicAnimation *hold = [CABasicAnimation animationWithKeyPath:@"opacity"];
        hold.fromValue = hold.toValue = [NSNumber numberWithDouble:fromAlpha];
        hold.duration = delay;
        if (completion) hold.delegate = (id)[[[ExteriaMotionCompletion alloc] initWithCompletion:completion] autorelease];
        [layer addAnimation:hold forKey:@"exteria.motion"];
        return;
    }
    NSMutableArray *transforms = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    NSMutableArray *opacities = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    for (NSUInteger i = 0; i < MOTION_SAMPLES; ++i) {
        CGFloat progress = (CGFloat)exteria_motion_progress(curve, (double)i / (MOTION_SAMPLES - 1));
        CGAffineTransform value = CGAffineTransformMake(
            from.a + (transform.a - from.a) * progress, from.b + (transform.b - from.b) * progress,
            from.c + (transform.c - from.c) * progress, from.d + (transform.d - from.d) * progress,
            from.tx + (transform.tx - from.tx) * progress, from.ty + (transform.ty - from.ty) * progress);
        [transforms addObject:[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(value)]];
        CGFloat opacity = fromAlpha + (alpha - fromAlpha) * MIN(1, MAX(0, progress));
        [opacities addObject:[NSNumber numberWithDouble:opacity]];
    }
    /* sampled springs keep the same motion on ios 5, where CASpringAnimation is absent */
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    movement.values = transforms;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = opacities;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.duration = exteria_motion_duration(curve);
    movement.duration = fade.duration = group.duration;
    group.animations = [NSArray arrayWithObjects:movement, fade, nil];
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    if (delay > 0) {
        group.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
        group.fillMode = kCAFillModeBackwards;
    }
    if (completion) group.delegate = (id)[[[ExteriaMotionCompletion alloc] initWithCompletion:completion] autorelease];
    [layer addAnimation:group forKey:@"exteria.motion"];
}

void ExteriaAnimatePosition(UIView *view, CGPoint position, exteria_motion_curve curve) {
    CALayer *layer = view.layer;
    CALayer *visible = [layer animationForKey:@"exteria.position"] ? [layer presentationLayer] : nil;
    CGPoint from = visible ? visible.position : layer.position;
    [layer removeAnimationForKey:@"exteria.position"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.position = position;
    [CATransaction commit];
    if (ExteriaReduceMotionEnabled() || !view.window || ![UIView areAnimationsEnabled]) return;
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    for (NSUInteger i = 0; i < MOTION_SAMPLES; ++i) {
        CGFloat progress = (CGFloat)exteria_motion_progress(curve, (double)i / (MOTION_SAMPLES - 1));
        [values addObject:[NSValue valueWithCGPoint:CGPointMake(from.x + (position.x - from.x) * progress,
                                                               from.y + (position.y - from.y) * progress)]];
    }
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    movement.values = values;
    movement.duration = exteria_motion_duration(curve);
    movement.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:movement forKey:@"exteria.position"];
}

void ExteriaAnimateEnter(UIView *view, CGAffineTransform from, CGFloat fromAlpha, exteria_motion_curve curve) {
    CALayer *layer = view.layer;
    CGAffineTransform to = view.transform;
    CGFloat toAlpha = view.alpha;
    [layer removeAnimationForKey:@"exteria.enter"];
    if (!(view.window || view.superview) || ![UIView areAnimationsEnabled] || ExteriaReduceMotionEnabled()) return;
    NSMutableArray *transforms = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    NSMutableArray *opacities = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    for (NSUInteger i = 0; i < MOTION_SAMPLES; ++i) {
        CGFloat progress = (CGFloat)exteria_motion_progress(curve, (double)i / (MOTION_SAMPLES - 1));
        CGAffineTransform value = CGAffineTransformMake(
            from.a + (to.a - from.a) * progress, from.b + (to.b - from.b) * progress,
            from.c + (to.c - from.c) * progress, from.d + (to.d - from.d) * progress,
            from.tx + (to.tx - from.tx) * progress, from.ty + (to.ty - from.ty) * progress);
        [transforms addObject:[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(value)]];
        /* a spring overshoots, and an opacity past one is clamped by the layer anyway */
        [opacities addObject:[NSNumber numberWithDouble:fromAlpha + (toAlpha - fromAlpha) * MIN(1, MAX(0, progress))]];
    }
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    movement.values = transforms;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = opacities;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.duration = exteria_motion_duration(curve);
    movement.duration = fade.duration = group.duration;
    group.animations = [NSArray arrayWithObjects:movement, fade, nil];
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:group forKey:@"exteria.enter"];
}

void ExteriaCancelEnter(UIView *view) {
    [view.layer removeAnimationForKey:@"exteria.enter"];
}

#define BOUNCE_PRESS_SECONDS 0.06
#define BOUNCE_RELEASE_SECONDS 0.35
#define BOUNCE_OVERSHOOT 5.0
static NSString *const ExteriaBounceKey = @"exteria.bounce";

@interface ExteriaBounceTarget : NSObject
+ (ExteriaBounceTarget *)shared;
- (void)press:(UIControl *)control;
- (void)lift:(UIControl *)control;
@end

/* the scale the layer shows at this moment, which is where a new bounce starts from */
static CGFloat ExteriaBounceShownScale(CALayer *layer) {
    CALayer *shown = [layer animationForKey:ExteriaBounceKey] ? [layer presentationLayer] : nil;
    NSNumber *scale = shown ? [shown valueForKeyPath:@"transform.scale"] : nil;
    return scale ? (CGFloat)scale.doubleValue : 1;
}

@implementation ExteriaBounceTarget

+ (ExteriaBounceTarget *)shared {
    static ExteriaBounceTarget *target;
    if (!target) target = [[ExteriaBounceTarget alloc] init];
    return target;
}

- (BOOL)animates:(UIControl *)control {
    return control.window && [UIView areAnimationsEnabled] && !ExteriaReduceMotionEnabled();
}

- (void)press:(UIControl *)control {
    if (![self animates:control]) return;
    CALayer *layer = control.layer;
    CGFloat depth = [objc_getAssociatedObject(control, &ExteriaBounceKey) doubleValue];
    CABasicAnimation *shrink = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    shrink.fromValue = [NSNumber numberWithDouble:ExteriaBounceShownScale(layer)];
    shrink.toValue = [NSNumber numberWithDouble:1 - depth];
    shrink.duration = BOUNCE_PRESS_SECONDS;
    shrink.fillMode = kCAFillModeForwards;
    shrink.removedOnCompletion = NO;
    /* CubicBezierInterpolator.DEFAULT */
    shrink.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.25f:0.1f:0.25f:1];
    [layer addAnimation:shrink forKey:ExteriaBounceKey];
}

- (void)lift:(UIControl *)control {
    CALayer *layer = control.layer;
    if (![layer animationForKey:ExteriaBounceKey]) return;
    CGFloat from = ExteriaBounceShownScale(layer);
    if (![self animates:control]) {
        [layer removeAnimationForKey:ExteriaBounceKey];
        return;
    }
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    for (NSUInteger i = 0; i < MOTION_SAMPLES; ++i) {
        double t = (double)i / (MOTION_SAMPLES - 1) - 1;
        double overshoot = t * t * ((BOUNCE_OVERSHOOT + 1) * t + BOUNCE_OVERSHOOT) + 1;
        [values addObject:[NSNumber numberWithDouble:from + (1 - from) * overshoot]];
    }
    CAKeyframeAnimation *spring = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    spring.values = values;
    spring.duration = BOUNCE_RELEASE_SECONDS;
    spring.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:spring forKey:ExteriaBounceKey];
}

@end

void ExteriaAttachBounce(UIControl *control, CGFloat depth) {
    ExteriaBounceTarget *target = [ExteriaBounceTarget shared];
    objc_setAssociatedObject(control, &ExteriaBounceKey, [NSNumber numberWithDouble:depth], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control addTarget:target action:@selector(press:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [control addTarget:target action:@selector(lift:)
      forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
}
