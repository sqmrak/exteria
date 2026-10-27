#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* the Stickers and Emoji screen of the settings */
@interface ExteriaStickersSettingsController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media;

@end
