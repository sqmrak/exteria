#import "exteria_session_channels.h"
#import "exteria_session_invites.h"
#import "exteria_settings_kit.h"

/* the form of one invite link: its name, how long it lives, how many people it takes in and whether an admin has to accept them. invite is nil for a new link;
   saved runs on the main thread with the link as the server made it, and the screen goes back */
@interface ExteriaChannelInviteEditController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel invite:(ExteriaInvite *)invite saved:(void (^)(ExteriaInvite *saved))saved;

@end
