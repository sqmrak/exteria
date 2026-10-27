#import "exteria_settings_kit.h"

@class ExteriaSession, ExteriaPerson;

/* the Change Name Color screen, for the name of the person themselves */
@interface ExteriaNameColorController : ExteriaSettingsPageController

/* person is the signed in account, as the settings screen loaded it */
- (id)initWithSession:(ExteriaSession *)session person:(ExteriaPerson *)person;

/* runs on the main thread with the id that was set, so the screen behind can show it */
@property (nonatomic, copy) void (^changedHandler)(NSInteger colorId);

@end
