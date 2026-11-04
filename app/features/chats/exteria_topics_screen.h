#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the screen a forum opens into, in the style the app runs in; closeHandler runs once the person leaves it for the list */
UIViewController *ExteriaTopicsScreen(ExteriaSession *session, ExteriaDialog *forum, ExteriaAvatarCache *avatars, ExteriaMediaCache *media,
                                      ExteriaStickerLibrary *stickers, void (^closeHandler)(void));

/* the same for a list of chats that is on screen, which a phone shows beside the topics as a column of pictures; archiveHandler opens the archive from its first button, and
   nil leaves the button out */
UIViewController *ExteriaTopicsScreenWithChats(ExteriaSession *session, ExteriaDialog *forum, NSArray *dialogs, ExteriaAvatarCache *avatars, ExteriaMediaCache *media,
                                               ExteriaStickerLibrary *stickers, void (^archiveHandler)(void), void (^closeHandler)(void));
