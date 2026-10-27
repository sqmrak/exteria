#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* the account page of the settings: the name, the surname and the bio, who sees the bio, the personal channel and
   the way out */
@interface ExteriaAccountController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
/* runs on the main thread after the name or the channel changed, so the screen under this one reads the person again */
@property (nonatomic, copy) void (^changedHandler)(void);
/* the row at the bottom: the screen below confirms and signs out */
@property (nonatomic, copy) void (^logoutHandler)(void);
@end
