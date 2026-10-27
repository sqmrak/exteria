#import <UIKit/UIKit.h>

typedef enum {
    /* a new code is typed twice */
    ExteriaPasscodeFlowSetup,
    /* the code that is set now is asked for, to open the settings of the lock or to take it off */
    ExteriaPasscodeFlowVerify
} ExteriaPasscodeFlowMode;

/* a full screen over the settings where a passcode is typed */
@interface ExteriaPasscodeFlowController : UIViewController
- (id)initWithMode:(ExteriaPasscodeFlowMode)mode completion:(void (^)(BOOL done))completion;
@end
