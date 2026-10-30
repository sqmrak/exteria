#import "exteria_session.h"
#import "exteria_settings_kit.h"
#import "exteria_media_cache.h"

void ExteriaLoadQuickReactionPicture(ExteriaSession *session, ExteriaMediaCache *media, void (^picture)(void));

@interface ExteriaQuickReactionController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session;
@end
