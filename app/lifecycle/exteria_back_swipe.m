#import "exteria_back_swipe.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_platform.h"

#include "exteria_motion.h"

/* a finger that starts inside this width always pulls the screen back; further in, only where nothing under it takes a rightward drag itself */
#define EDGE_WIDTH 24.0
#define PARALLAX 0.3

@interface ExteriaBackSwipe () <UIGestureRecognizerDelegate> {
    UINavigationController *_navigation;
    UIPanGestureRecognizer *_pan;
    UIView *_top;
    UIView *_below;
    UIView *_dim;
    UIView *_belowHost;
    NSUInteger _belowIndex;
    CGRect _belowBounds;
    CGPoint _belowCenter;
    CGAffineTransform _belowTransform;
    CGAffineTransform _topTransform;
    CGColorRef _shadowColor;
    CGPathRef _shadowPath;
    float _shadowOpacity;
    CGFloat _shadowRadius;
    CGSize _shadowOffset;
    UIGestureRecognizer *_systemPan;
    BOOL _systemPanEnabled;
    CGFloat _width;
    BOOL _active;
}
@end

@implementation ExteriaBackSwipe

- (id)initWithNavigationController:(UINavigationController *)navigation {
    self = [super init];
    if (!self) return nil;
    _navigation = navigation;
    /* ios 7's recognizer must not move the same screens alongside this ios 5 transition */
    if ([navigation respondsToSelector:NSSelectorFromString(@"interactivePopGestureRecognizer")]) {
        _systemPan = [[navigation valueForKey:@"interactivePopGestureRecognizer"] retain];
        _systemPanEnabled = _systemPan.enabled;
        _systemPan.enabled = NO;
    }
    _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    _pan.delegate = self;
    _pan.maximumNumberOfTouches = 1;
    [navigation.view addGestureRecognizer:_pan];
    return self;
}

- (void)dealloc {
    _pan.delegate = nil;
    [_pan.view removeGestureRecognizer:_pan];
    [_pan release];
    if (_active) [self finishPopping:NO];
    _systemPan.enabled = _systemPanEnabled;
    [_systemPan release];
    [super dealloc];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture != _pan || _active || _navigation.viewControllers.count < 2 || _navigation.presentedViewController) return NO;
    UIViewController *top = _navigation.topViewController;
    if (!top.isViewLoaded || !top.view.window) return NO;
    /* a push still moving its content container must finish before a drag takes ownership */
    for (UIView *view = top.view; view; view = view.superview) {
        if (view.layer.animationKeys.count) return NO;
        if (view == _navigation.view) break;
    }
    CGPoint velocity = [_pan velocityInView:_navigation.view];
    return velocity.x > 0 && fabs(velocity.x) > fabs(velocity.y);
}

/* whether the view takes a rightward drag for itself: a slider, a swipe to the right (emoji pages, photo paging), or a horizontal scroll view that is not at its left end */
static BOOL ExteriaViewTakesRightwardDrag(UIView *view) {
    if ([view isKindOfClass:[UISlider class]]) return YES;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (!recognizer.enabled || ![recognizer isKindOfClass:[UISwipeGestureRecognizer class]]) continue;
        if (((UISwipeGestureRecognizer *)recognizer).direction & UISwipeGestureRecognizerDirectionRight) return YES;
    }
    if (![view isKindOfClass:[UIScrollView class]]) return NO;
    UIScrollView *scroll = (UIScrollView *)view;
    return scroll.scrollEnabled && scroll.contentSize.width > scroll.bounds.size.width + 1 && scroll.contentOffset.x > -scroll.contentInset.left + 1;
}

/* the place of the touch is judged where it lands, since by the first movement the finger has left it */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    (void)gesture;
    if ([touch locationInView:_navigation.view].x < EDGE_WIDTH) return YES;
    for (UIView *view = touch.view; view && view != _navigation.view; view = view.superview) {
        if (ExteriaViewTakesRightwardDrag(view)) return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gesture;
    (void)other;
    return NO;
}

- (void)begin {
    NSArray *stack = _navigation.viewControllers;
    if (stack.count < 2) return;
    UIViewController *top = [stack objectAtIndex:stack.count - 1];
    UIViewController *below = [stack objectAtIndex:stack.count - 2];
    if (!top.isViewLoaded || !top.view.superview || !below.view) return;
    UIView *host = top.view.superview;
    _width = top.view.bounds.size.width;
    if (_width <= 0) return;
    _active = YES;
    _top = [top.view retain];
    _below = [below.view retain];
    _topTransform = _top.transform;
    _belowHost = [_below.superview retain];
    _belowIndex = [_belowHost.subviews indexOfObjectIdenticalTo:_below];
    _belowBounds = _below.bounds;
    _belowCenter = _below.center;
    _belowTransform = _below.transform;
    /* use the content container's size without resetting a table controller's scroll offset */
    _below.transform = CGAffineTransformIdentity;
    CGRect bounds = _belowBounds;
    bounds.size = _top.bounds.size;
    _below.bounds = bounds;
    _below.center = _top.center;
    [host insertSubview:_below belowSubview:_top];
    [_below setNeedsLayout];
    [_below layoutIfNeeded];
    _below.transform = CGAffineTransformMakeTranslation(-_width * PARALLAX, 0);
    _dim = [[UIView alloc] initWithFrame:_top.frame];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25f];
    _dim.userInteractionEnabled = NO;
    [host insertSubview:_dim aboveSubview:_below];
    if (_top.layer.shadowColor) _shadowColor = CGColorRetain(_top.layer.shadowColor);
    if (_top.layer.shadowPath) _shadowPath = CGPathRetain(_top.layer.shadowPath);
    _shadowOpacity = _top.layer.shadowOpacity;
    _shadowRadius = _top.layer.shadowRadius;
    _shadowOffset = _top.layer.shadowOffset;
    _top.layer.shadowColor = [UIColor blackColor].CGColor;
    _top.layer.shadowOpacity = 0.3f;
    _top.layer.shadowRadius = 6;
    _top.layer.shadowOffset = CGSizeZero;
    /* a fixed outline avoids rendering the whole screen into an offscreen shadow on every drag frame */
    _top.layer.shadowPath = [UIBezierPath bezierPathWithRect:_top.bounds].CGPath;
}

- (void)moveTo:(CGFloat)x {
    CGFloat progress = MAX(0, MIN(1, x / _width));
    _top.transform = CGAffineTransformTranslate(_topTransform, progress * _width, 0);
    _below.transform = CGAffineTransformMakeTranslation(-_width * PARALLAX * (1 - progress), 0);
    _dim.alpha = 1 - progress;
}

/* puts every view back as the navigation controller expects to find it, whichever way the swipe ended */
- (void)finishPopping:(BOOL)pops {
    /* detach the outgoing screen before restoring it, so a completed swipe never flashes back to its start */
    BOOL popped = pops && _navigation.topViewController.view == _top;
    if (popped) [_navigation popViewControllerAnimated:NO];
    _top.transform = _topTransform;
    _top.layer.shadowColor = _shadowColor;
    _top.layer.shadowPath = _shadowPath;
    _top.layer.shadowOpacity = _shadowOpacity;
    _top.layer.shadowRadius = _shadowRadius;
    _top.layer.shadowOffset = _shadowOffset;
    if (_shadowColor) CGColorRelease(_shadowColor);
    if (_shadowPath) CGPathRelease(_shadowPath);
    _shadowColor = NULL;
    _shadowPath = NULL;
    [_dim removeFromSuperview];
    if (!popped && _navigation.topViewController.view != _below) {
        [_below removeFromSuperview];
        _below.transform = CGAffineTransformIdentity;
        _below.bounds = _belowBounds;
        _below.center = _belowCenter;
        _below.transform = _belowTransform;
        if (_belowHost) [_belowHost insertSubview:_below atIndex:MIN(_belowIndex, _belowHost.subviews.count)];
    } else if (!popped) {
        _below.transform = CGAffineTransformIdentity;
    }
    [_belowHost release];
    _belowHost = nil;
    [_dim release];
    _dim = nil;
    [_top release];
    _top = nil;
    [_below release];
    _below = nil;
    _active = NO;
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    switch (pan.state) {
    case UIGestureRecognizerStateBegan:
        [self begin];
        if (_active) [self moveTo:[pan translationInView:_navigation.view].x];
        break;
    case UIGestureRecognizerStateChanged:
        if (_active) [self moveTo:[pan translationInView:_navigation.view].x];
        break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed: {
        if (!_active) break;
        CGFloat x = [pan translationInView:_navigation.view].x;
        CGFloat velocity = [pan velocityInView:_navigation.view].x;
        exteria_motion_swipe plan = exteria_motion_back_swipe(_width, x, velocity, pan.state == UIGestureRecognizerStateEnded);
        [self moveTo:(CGFloat)plan.progress * _width];
        if (plan.duration == 0 || ExteriaReduceMotionEnabled()) {
            [self moveTo:plan.completes ? _width : 0];
            [self finishPopping:plan.completes];
            break;
        }
        [UIView animateWithDuration:plan.duration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            [self moveTo:plan.completes ? _width : 0];
        } completion:^(BOOL finished) {
            (void)finished;
            [self finishPopping:plan.completes];
        }];
        break;
    }
    default:
        break;
    }
}

@end
