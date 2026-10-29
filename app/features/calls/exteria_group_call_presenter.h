#import <UIKit/UIKit.h>

#import "exteria_session.h"

/* shows the group call of a session over whatever is open: the full screen when it begins, the green bar at the top when the person folds it away, and the
   notice of why it ended. the session's delegate for group calls */
@interface ExteriaGroupCallPresenter : NSObject <ExteriaGroupCallDelegate>

/* topController gives the controller a screen is presented from, host the view the bar hangs in */
- (id)initWithTopController:(UIViewController *(^)(void))topController host:(UIView *(^)(void))host;

/* the session whose avatars the screen draws; main thread */
@property (nonatomic, assign) ExteriaSession *session;

/* a call is on screen or folded into the bar */
- (BOOL)callIsShown;

@end
