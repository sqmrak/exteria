#import "exteria_gift_screen.h"
#import "exteria_profile_feed.h"

/* our pinned or archived stories as tiles; a tap plays them in the story viewer */
@interface ExteriaStoryFeedController : ExteriaGiftScreen

/* kind is ExteriaFeedPinnedStories or ExteriaFeedArchivedStories; owner is the chat with oneself */
- (id)initWithSession:(ExteriaSession *)session kind:(ExteriaProfileFeedKind)kind owner:(ExteriaDialog *)owner avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media;

@end
