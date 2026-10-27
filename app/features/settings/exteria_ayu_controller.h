#import "exteria_settings_kit.h"

@class ExteriaSession;

/* AyuMoments it: the ghost mode, the filters of messages by a regular expression, and the keeping of what the
   other side deletes or changes */
@interface ExteriaAyuController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session;
@end

/* the three switches of the ghost mode */
@interface ExteriaGhostController : ExteriaSettingsPageController
@end

/* the list of the filters of the person, with the way to add one and to change or remove it */
@interface ExteriaRegexFiltersController : ExteriaSettingsPageController
@end
