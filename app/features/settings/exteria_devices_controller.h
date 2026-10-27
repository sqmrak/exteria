#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

/* the Devices screen, in the modern theme */
@interface ExteriaDevicesController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media;

@end
