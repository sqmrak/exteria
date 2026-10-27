#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the screen a community opens into, in the style the app runs in; known are the dialogs of the chat list, closeHandler runs once the
   person leaves it for the list */
UIViewController *ExteriaCommunityScreen(ExteriaSession *session, ExteriaDialog *community, NSArray *known, ExteriaAvatarCache *avatars,
                                         ExteriaMediaCache *media, ExteriaStickerLibrary *stickers, void (^closeHandler)(void));
