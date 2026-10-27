#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* NotificationsSettingsActivity: the kinds of chat (private chats, groups, channels, stories, reactions) with
   their exceptions, the vibration of a call, the number on the icon */
@interface ExteriaNotificationsSettingsController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

@end
