#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the topics of a forum in the classic style: the system table with a row each, pinned first */
@interface ExteriaClassicTopicsController : UITableViewController

- (id)initWithSession:(ExteriaSession *)session forum:(ExteriaDialog *)forum avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

/* runs once when the person leaves for the list, so the list can show what reading changed */
@property (nonatomic, copy) void (^closeHandler)(void);

@end
