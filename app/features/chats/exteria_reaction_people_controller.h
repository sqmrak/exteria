#import "exteria_settings_kit.h"
#import "exteria_session.h"

@interface ExteriaReactionPeopleController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog messageId:(int32_t)messageId;
@end
