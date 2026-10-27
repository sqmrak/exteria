#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session_channels.h"
#import "exteria_settings_kit.h"

/* the management screen of a channel or group for its creator and admins */
@interface ExteriaChannelManageController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

/* runs on the main thread after the channel changed, with the full channel as the server now has it, so the profile behind can show it */
@property (nonatomic, copy) void (^changedHandler)(ExteriaFullChannel *channel);

@end
