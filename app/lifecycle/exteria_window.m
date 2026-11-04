#import "exteria_window.h"

NSString *const ExteriaDeviceDidShakeNotification = @"ExteriaDeviceDidShake";

@implementation ExteriaWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)] autorelease];
    tap.delegate = self;
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];
    return self;
}

- (void)dismissKeyboard {
    [self endEditing:YES];
}

/* fields and buttons keep their own taps, so the send button of a chat does not drop the keyboard it types with */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view; view = view.superview) {
        if ([view isKindOfClass:[UIControl class]] || [view conformsToProtocol:@protocol(UIKeyInput)]) return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDeviceDidShakeNotification object:nil];
    [super motionBegan:motion withEvent:event];
}

@end
