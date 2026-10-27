#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the search of the chat list in the classic style: the system's search field in the navigation bar, a scrolling
   strip of the ten kinds of results, system rows, and the duck when a query finds nothing */
@interface ExteriaClassicSearchController : UIViewController

/* dialogs is the loaded chat list, newest first */
- (id)initWithSession:(ExteriaSession *)session dialogs:(NSArray *)dialogs avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

@end
