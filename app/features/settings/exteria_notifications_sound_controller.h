#import "exteria_media_cache.h"
#import "exteria_notify_ui.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* NotificationsSoundActivity: the tone of a kind of chat or of one chat */
@interface ExteriaNotificationsSoundController : ExteriaSettingsPageController

/* current is an NSValue of the exteria_notify_sound that stands now, nil for the default one. apply gets every tone the person picks, on the main thread */
- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media title:(NSString *)title current:(NSValue *)current
                apply:(void (^)(exteria_notify_sound sound))apply;

@end
