#import <UIKit/UIKit.h>

#import "exteria_session_devices.h"

/* the session sheet: a card that rises from the bottom over a dimmed screen with the animated picture of the
   device in a circle of its color, the name, when it was last on */
@interface ExteriaDeviceSheet : UIView

/* switches report the new value; end runs after the person confirmed ending the session, and the sheet has already left */
+ (void)presentInView:(UIView *)host device:(ExteriaDeviceSession *)device
         secretChats:(void (^)(BOOL on))secretChats calls:(void (^)(BOOL on))calls end:(void (^)(void))end;

@end
