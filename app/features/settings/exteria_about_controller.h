#import "exteria_avatar_cache.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* the screen behind the Exteria row of the settings; the pictures of the people are the ones bundled until the
   current profile photo of each @name has been fetched */
@interface ExteriaAboutController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars;
@end
