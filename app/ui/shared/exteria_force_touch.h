#import <UIKit/UIKit.h>

/* recognizes a hard press on a screen with 3d touch (ios 9 and later, iphone 6s and later); on every other screen it never begins */
@interface ExteriaForceTouchRecognizer : UIGestureRecognizer
@end

/* the tap the finger feels when the press is taken (ios 10 and later, where the taptic engine can play it) */
void ExteriaForceTouchTick(void);
