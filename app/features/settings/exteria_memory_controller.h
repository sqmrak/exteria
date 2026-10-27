#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_settings_kit.h"

/* what the app keeps on the phone: the size of the photos of people and of the files of messages, how long the
   files stay, and the way to empty both */
@interface ExteriaMemoryController : ExteriaSettingsPageController

- (id)initWithAvatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

@end
