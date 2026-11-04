#import "exteria_settings_kit.h"
#import "exteria_session.h"

@class ExteriaPerson;
@class ExteriaStoryAudience;

/* the contacts with a mark each, to choose any number of them; the choice goes to the caller when the page is left by its arrow */
@interface ExteriaPeopleSelectController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session title:(NSString *)title chosen:(NSArray *)chosen done:(void (^)(NSArray *people))done;
/* the page in a navigation controller of its own, to be presented over a full screen; the classic theme gets a Close button, which hands the choice over too */
- (UINavigationController *)presentableNavigation;
@end

/* who sees a story, in the words of the app: Everyone, Everyone except, Contacts, Contacts except, Close friends, Selected contacts. the list of people of the
   last three choices is asked for on a page over host. done gets the audience; cancelled runs when nothing was chosen */
void ExteriaChooseStoryAudience(UIViewController *host, ExteriaSession *session, ExteriaStoryAudience *current, void (^done)(ExteriaStoryAudience *audience), void (^cancelled)(void));
/* the line that names an audience: "Everyone except 3", "Selected (5)" */
NSString *ExteriaStoryAudienceTitle(ExteriaStoryAudience *audience);
