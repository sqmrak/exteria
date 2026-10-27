#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_session_privacy.h"
#import "exteria_settings_kit.h"

/* the privacy screen: who the account hides from, the people it blocked, the time after which an idle account is
   deleted, and the rest that the server keeps for the person */
@interface ExteriaPrivacyController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
@end

/* who may see one piece of the account: the three bases as a list of choices, and under them the people who are the exception to the choice */
@interface ExteriaPrivacyRuleController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session rules:(ExteriaPrivacyRules *)rules avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
/* runs on the main thread with the rules as the server holds them after each change */
@property (nonatomic, copy) void (^changedHandler)(ExteriaPrivacyRules *rules);
@end

/* the people the account blocked, with the way to block one more and to let one go */
@interface ExteriaBlockedController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
/* runs on the main thread with how many are blocked after a change */
@property (nonatomic, copy) void (^countHandler)(int32_t total);
@end

/* the row text of a rule: the base and the count of exceptions, such as "Мои контакты (+2, -1)" */
NSString *ExteriaPrivacyValue(ExteriaPrivacyRules *rules);
