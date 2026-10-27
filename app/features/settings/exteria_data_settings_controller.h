#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* the Data and Memory screen, as far as the app has something behind each row: the memory the app takes and how
   long files stay, the network the app used, and the drafts the account keeps on the server */
@interface ExteriaDataSettingsController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

@end
