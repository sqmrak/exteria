#import <UIKit/UIKit.h>

/* posted on the main thread when the phone is shaken: the shake reaches the window through the responder chain from whatever is focused, a text field included */
extern NSString *const ExteriaDeviceDidShakeNotification;

/* the window of the app: it tells of a shake, and a tap on bare ground closes the keyboard on every screen */
@interface ExteriaWindow : UIWindow <UIGestureRecognizerDelegate>
@end
