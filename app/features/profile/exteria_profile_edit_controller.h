#import "exteria_gift_screen.h"
#import "exteria_session_profile.h"

/* the profile in cards: the name, the bio with its counter, the phone, the username and the birthday, the personal
   channel and the way out */
@interface ExteriaProfileEditController : ExteriaGiftScreen

- (id)initWithSession:(ExteriaSession *)session person:(ExteriaPerson *)person fullUser:(ExteriaFullUser *)full avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media;

/* runs on the main thread after anything was saved, so the profile below loads again */
@property (nonatomic, copy) void (^changedHandler)(void);
/* the row at the bottom: runs when the person taps it, which is the screen below's to confirm */
@property (nonatomic, copy) void (^logoutHandler)(void);

@end
