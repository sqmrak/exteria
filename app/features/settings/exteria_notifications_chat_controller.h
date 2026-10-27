#import "exteria_media_cache.h"
#import "exteria_notify_ui.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* ProfileNotificationsActivity, as far as it means something on this phone; whether the chat notifies and until
   when, the text of the message in the banner, the stories of a person, the tone, and the way back to the settings
   of its kind */
@interface ExteriaNotificationsChatController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media peerKind:(int32_t)peerKind peerId:(long long)peerId peerHash:(long long)peerHash
              channel:(BOOL)broadcast topic:(int32_t)topic title:(NSString *)title;

@end
