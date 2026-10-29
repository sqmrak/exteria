#import "exteria_dismiss_pan.h"

#import "exteria_platform.h"
#include <math.h>

@interface ExteriaDismissPan : UIPanGestureRecognizer <UIGestureRecognizerDelegate> {
    id _owner;
    SEL _action;
    UIScrollView *_scroll;
}
- (id)initWithOwner:(id)owner action:(SEL)action;
@end

@implementation ExteriaDismissPan

- (id)initWithOwner:(id)owner action:(SEL)action {
    self = [super initWithTarget:nil action:NULL];
    if (!self) return nil;
    _owner = owner;
    _action = action;
    self.delegate = self;
    [self addTarget:self action:@selector(pulled:)];
    return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    _scroll = nil;
    for (UIView *view = touch.view; view && view != gesture.view; view = view.superview) {
        if ([view isKindOfClass:[UISlider class]] || [view isKindOfClass:[UIDatePicker class]] ||
            [view isKindOfClass:[UITextField class]] || [view isKindOfClass:[UITextView class]]) return NO;
        if (!_scroll && [view isKindOfClass:[UIScrollView class]]) _scroll = (UIScrollView *)view;
    }
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if ([_owner respondsToSelector:@selector(exteriaCanDismissByPan)] && ![(id<ExteriaDismissPanGuard>)_owner exteriaCanDismissByPan]) return NO;
    CGPoint velocity = [self velocityInView:gesture.view];
    return velocity.y > 0 && velocity.y > fabs(velocity.x) &&
           (!_scroll || _scroll.contentOffset.y <= -_scroll.contentInset.top + 0.5);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gesture;
    return _scroll && other == _scroll.panGestureRecognizer;
}

- (void)pulled:(UIPanGestureRecognizer *)pan {
    UIView *card = pan.view;
    CGFloat distance = MAX(0, [pan translationInView:card.superview].y);
    if (pan.state == UIGestureRecognizerStateChanged) {
        if (_scroll && _scroll.contentOffset.y < -_scroll.contentInset.top)
            _scroll.contentOffset = CGPointMake(_scroll.contentOffset.x, -_scroll.contentInset.top);
        card.transform = CGAffineTransformMakeTranslation(0, distance);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (pan.state == UIGestureRecognizerStateEnded && (distance > 80 || [pan velocityInView:card.superview].y > 900)) {
            id owner = _owner;
            SEL action = _action;
            _scroll = nil;
            [owner performSelector:action];
            return;
        } else {
            [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.2 delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                             animations:^{ card.transform = CGAffineTransformIdentity; } completion:nil];
        }
        _scroll = nil;
    }
}

@end

void ExteriaAddDismissPan(UIView *card, id target, SEL action) {
    ExteriaDismissPan *pan = [[[ExteriaDismissPan alloc] initWithOwner:target action:action] autorelease];
    [card addGestureRecognizer:pan];
}
