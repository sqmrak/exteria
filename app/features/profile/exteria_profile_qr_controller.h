#import "exteria_gift_screen.h"
#import "exteria_person.h"
#import "exteria_session_channels.h"

/* the QR code of a t.me link with the picture of its owner in its middle, and the ways to copy or share the link */
@interface ExteriaProfileQrController : ExteriaGiftScreen

- (id)initWithSession:(ExteriaSession *)session person:(ExteriaPerson *)person avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
/* a channel or group; a channel with no link the account can see shows a line that says so in place of the code */
- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

@end
