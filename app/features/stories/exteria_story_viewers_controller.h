#import "exteria_settings_kit.h"
#import "exteria_session.h"

/* the people who looked at one of our stories, newest first, with when; opened from the count of views under the story */
@interface ExteriaStoryViewersController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog storyId:(int32_t)storyId views:(int32_t)views;
/* the page in a navigation controller of its own, ready to be presented over the story; the classic theme gets a Close button in its bar */
- (UINavigationController *)presentableNavigation;
@end
