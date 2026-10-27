#import <UIKit/UIKit.h>

/* the screen that keeps the app shut while a passcode is set; it lives in a window of its own over everything, the
   keyboard of the app included, since a lock drawn in the root view would leave a sheet or an alert above it */
@interface ExteriaPasscodeLock : NSObject

/* the cold start of the app: shut at once, whatever the time away was */
- (void)lockAtLaunch;
/* the app stops being active (a call, the notification center, the switcher): the window covers the screen with a
   plain color, so the snapshot the system takes for the switcher shows no chat */
- (void)cover;
/* the app is in the background now: from this moment the time away is counted */
- (void)noteLeave;
/* the app is active again: a cover that was only a flicker goes, one that followed a long leave turns into the lock */
- (void)evaluateReturn;

@end
