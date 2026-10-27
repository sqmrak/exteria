#import "exteria_settings_kit.h"

@class ExteriaSession;

/* the More page of the Exteria settings: the reports of failures, AyuMoments, the local Premium, the boykissers
   that fall in place of the waves */
@interface ExteriaMoreSettingsController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session;
@end
