#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_call_state.h"
#import "exteria_photo.h"
#import "exteria_session.h"

/* the full screen of one voice call: who it is, how it stands, the four emoji of the key, and the buttons the
   phase allows */
@interface ExteriaCallController : UIViewController

- (id)initWithSession:(ExteriaSession *)session;

/* the picture of the other person when the caller already has it */
@property (nonatomic, retain) ExteriaPhoto *photo;
@property (nonatomic, retain) ExteriaAvatarCache *avatars;

/* main thread only */
- (void)updateWithCall:(ExteriaCall *)call;

/* the call the screen shows, 0 before its first snapshot */
@property (nonatomic, readonly) long long callId;
/* the call has ended and the screen is on its way out: a call that begins now needs a screen of its own, after this one is gone */
@property (nonatomic, readonly) BOOL finishing;

/* the person pressed the arrow that folds the screen away: the call goes on and the owner shows the way back */
@property (nonatomic, copy) void (^onMinimize)(void);

/* called once the screen is off the window, to let the owner drop it */
@property (nonatomic, copy) void (^onFinish)(void);

@end
