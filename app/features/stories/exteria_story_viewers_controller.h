#import "exteria_settings_kit.h"
#import "exteria_session.h"
#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"

/* the people who looked at one of our stories, newest first, with when; opened from the count of views under the story */
@interface ExteriaStoryViewersController : ExteriaSettingsPageController
/* a tap on a row opens the profile of the person; their reaction stands at the right end of it. views and reactions are the counts the story carried, which the first page corrects */
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog storyId:(int32_t)storyId views:(int32_t)views reactions:(int32_t)reactions
              avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
/* the page in a navigation controller of its own, ready to be presented over the story; the classic theme gets a Close button in its bar */
- (UINavigationController *)presentableNavigation;
@end
