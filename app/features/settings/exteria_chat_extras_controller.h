#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* what Exteria adds to the chat screens beyond the settings of the original client; playback, how messages look
   and answer a tap, the entries of the menu of a message, the questions asked before an action, and how times,
   numbers and names are written */
@interface ExteriaChatExtrasController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session;
@end
