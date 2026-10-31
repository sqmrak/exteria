#import "exteria_settings_kit.h"

@class ExteriaSession;

/* hands a file to the share sheet (the open-in menu on systems without one) over the given screen */
void ExteriaShareFile(UIViewController *host, NSString *path);

/* the logs the app keeps on the phone, one row each with its size and its last change: a tap reads it in the colors of the theme, and a row at the top packs them all into
   exteria-[username].zip and hands it to the share sheet */
@interface ExteriaLogsController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session;
@end
