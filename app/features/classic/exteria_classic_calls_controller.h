#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the Calls tab in the classic style: the system table of the calls of the account, newest first */
@interface ExteriaClassicCallsController : UITableViewController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

@end
