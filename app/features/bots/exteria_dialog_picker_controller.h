#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

#import "exteria_dialog.h"

/* the chats of the person in the cards of the settings, each with its picture, narrowed by a rule, for a place to
   send something to or to hand to a bot */
@interface ExteriaDialogPickerController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
@property (nonatomic, copy) NSString *screenTitle;
@property (nonatomic, assign) BOOL forwarding;
/* decides which chats are listed; nil lists every chat the person can open */
@property (nonatomic, copy) BOOL (^filter)(ExteriaDialog *dialog);
/* how many chats may be picked, at least 1 */
@property (nonatomic, assign) NSUInteger limit;
/* the picked chats, once; not called when the person goes back */
@property (nonatomic, copy) void (^pickHandler)(NSArray *dialogs);

@end
