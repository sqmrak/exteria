#import "exteria_gift_screen.h"
#import "exteria_session_profile.h"

/* the screen behind "edit contact": the name the person gives the contact, the private note shown under their username, and the photo for the contact, which
   the person may set for themselves, suggest to the contact, or take away to show the contact's own again */
@interface ExteriaContactEditController : ExteriaGiftScreen

- (id)initWithSession:(ExteriaSession *)session person:(ExteriaPerson *)person fullUser:(ExteriaFullUser *)full avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media;

/* runs on the main thread after anything was changed, so the profile below loads again */
@property (nonatomic, copy) void (^changedHandler)(void);

@end
