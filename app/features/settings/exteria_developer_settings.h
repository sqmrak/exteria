#import "exteria_settings_kit.h"

@class ExteriaSession;

/* whether the developer settings are open on this phone: they stay hidden until the lead's picture in the credits is pressed five times */
BOOL ExteriaDeveloperModeEnabled(void);
void ExteriaDeveloperModeSet(BOOL enabled);
/* posted on the main thread when the mode is turned on or off */
extern NSString *const ExteriaDeveloperModeDidChangeNotification;

/* the page of the developer settings: for now, a list of every window of the app that comes up over a screen, each one called by a tap */
@interface ExteriaDeveloperSettingsController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session;
@end
