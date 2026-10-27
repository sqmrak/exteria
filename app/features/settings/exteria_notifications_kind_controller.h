#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_notify_ui.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* NotificationsCustomSettingsActivity: one kind of chat; the kind ExteriaNotifyKindAllExceptions lists the
   exceptions of every kind and nothing else */
@interface ExteriaNotificationsKindController : ExteriaSettingsPageController

/* exceptions is what the main page already loaded, nil to ask the server */
- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media kind:(ExteriaNotifyKind)kind exceptions:(NSArray *)exceptions;

@end
