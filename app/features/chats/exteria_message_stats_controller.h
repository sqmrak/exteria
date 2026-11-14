#import "exteria_settings_kit.h"
#import "exteria_session.h"

@class ExteriaAvatarCache;
@class ExteriaMessage;

/* the statistics of one post of a channel the account administers: the counts, the graph of views and shares, the graph of reactions by
   emotion, and the public channels that forwarded the post */
@interface ExteriaMessageStatsController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog message:(ExteriaMessage *)message avatars:(ExteriaAvatarCache *)avatars;
@end
