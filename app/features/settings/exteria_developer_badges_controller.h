#import "exteria_settings_kit.h"

@class ExteriaSession;

/* the badges a developer can put on his own name on this phone, to see how each looks in the lists, the chats and the profile: a card with the name as it is drawn at the top, and a row for
   each badge that takes it or gives it back with a tap; nothing is sent to the server and nobody else sees it */
@interface ExteriaDeveloperBadgesController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session;
@end
