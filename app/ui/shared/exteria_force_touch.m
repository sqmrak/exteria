#import "exteria_force_touch.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

/* share of the strongest press the screen reports; the system's own peek starts near here */
#define FORCE_RATIO 0.45
/* a finger that travels this far is scrolling, and the press is not wanted */
#define FORCE_SLOP 10.0

/* UITouch.force came with ios 9, which the sdk of the armv7 slice does not name, so it is read by key */
static double ExteriaTouchForceRatio(UITouch *touch) {
    if (![touch respondsToSelector:NSSelectorFromString(@"force")] || ![touch respondsToSelector:NSSelectorFromString(@"maximumPossibleForce")]) return 0;
    double maximum = [[touch valueForKey:@"maximumPossibleForce"] doubleValue];
    if (maximum <= 0) return 0;
    return [[touch valueForKey:@"force"] doubleValue] / maximum;
}

@implementation ExteriaForceTouchRecognizer {
    CGPoint _origin;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([[event touchesForGestureRecognizer:self] count] != 1) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    _origin = [[touches anyObject] locationInView:self.view];
    [self consider:[touches anyObject]];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (self.state == UIGestureRecognizerStateFailed) return;
    UITouch *touch = [touches anyObject];
    if (self.state == UIGestureRecognizerStatePossible) {
        CGPoint at = [touch locationInView:self.view];
        if (hypot(at.x - _origin.x, at.y - _origin.y) > FORCE_SLOP) {
            self.state = UIGestureRecognizerStateFailed;
            return;
        }
    }
    [self consider:touch];
}

- (void)consider:(UITouch *)touch {
    if (self.state != UIGestureRecognizerStatePossible || ExteriaTouchForceRatio(touch) < FORCE_RATIO) return;
    self.state = UIGestureRecognizerStateBegan;
    ExteriaForceTouchTick();
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    (void)touches;
    (void)event;
    self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateEnded;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    (void)touches;
    (void)event;
    self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateCancelled;
}

/* the press is read beside the table's scroll and the row's long press, and neither may hold it back or be held by it, so it needs no delegate */
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {
    (void)other;
    return NO;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other {
    (void)other;
    return NO;
}
@end

void ExteriaForceTouchTick(void) {
    Class generator = NSClassFromString(@"UIImpactFeedbackGenerator");
    if (!generator) return;
    id feedback = [[[generator alloc] init] autorelease];
    if ([feedback respondsToSelector:@selector(impactOccurred)]) [feedback performSelector:@selector(impactOccurred)];
}
