#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_person.h"
#import "exteria_settings_kit.h"

/* the contacts in the cards of the settings, each with the picture of the person; a tap hands the chosen one to
   the caller as a chat with that person */
@interface ExteriaContactPickerController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
@property (nonatomic, copy) NSString *screenTitle;
/* when set, the list starts with this person as "this is you"; choosing them hands over the chat with oneself */
@property (nonatomic, retain) ExteriaPerson *selfPerson;
@property (nonatomic, copy) void (^pickHandler)(ExteriaDialog *dialog);

@end
