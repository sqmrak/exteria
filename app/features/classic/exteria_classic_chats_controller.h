#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the chat list built from the system's own table, search bar, toolbar, segmented control and edit button */
@interface ExteriaClassicChatsController : UITableViewController

/* 0 lists the chats, 1 the archive */
- (id)initWithSession:(ExteriaSession *)session folderId:(int32_t)folderId avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

/* the unread messages of the chats that are not muted, for the badge on the tab */
@property (nonatomic, copy) void (^unreadHandler)(NSInteger total);

@end
