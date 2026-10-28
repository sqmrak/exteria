#import <UIKit/UIKit.h>

/* the question after a crash, on a card of the app over a dimmed screen: the app closed with an error, may the
   report go to the lead developer? */
BOOL ExteriaAskCrashReport(void (^answer)(BOOL send));
