#import <UIKit/UIKit.h>

#import "exteria_dialog.h"
#import "exteria_session.h"

@class ExteriaAvatarCache, ExteriaMediaCache, ExteriaStickerLibrary;

/* the message button of a profile: the chat the profile was opened from when it is the one right below, so the way
   back does not pile a second copy of the same chat on the stack */
void ExteriaProfileShowChat(UIViewController *profile, ExteriaSession *session, ExteriaDialog *dialog, ExteriaAvatarCache *avatars,
                            ExteriaMediaCache *media, ExteriaStickerLibrary *stickers);
