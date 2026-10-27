#import "exteria_gift_screen.h"
#import "exteria_session_channels.h"

typedef enum {
    ExteriaChannelFieldTitle,
    ExteriaChannelFieldAbout,
    /* the public name of the channel: only what a name can hold goes in, and the server is asked whether it is free while the person types */
    ExteriaChannelFieldUsername,
    /* the title an admin shows next to the name */
    ExteriaChannelFieldRank
} ExteriaChannelFieldKind;

/* one text field on a card with a line of explanation under it, and the action that saves it; the screen goes back
   after a save that worked and shows the error otherwise */
@interface ExteriaChannelFieldController : ExteriaGiftScreen <UITextFieldDelegate>

/* dialog is the channel whose name is being checked, needed for the username kind only */
- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media kind:(ExteriaChannelFieldKind)kind
                 text:(NSString *)text dialog:(ExteriaDialog *)dialog save:(void (^)(NSString *text, void (^done)(NSString *errorName)))save;

@end
