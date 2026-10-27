#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the screen a forum opens into, in the style the app runs in; closeHandler runs once the person leaves it for the list */
UIViewController *ExteriaTopicsScreen(ExteriaSession *session, ExteriaDialog *forum, ExteriaAvatarCache *avatars, ExteriaMediaCache *media,
                                      ExteriaStickerLibrary *stickers, void (^closeHandler)(void));
