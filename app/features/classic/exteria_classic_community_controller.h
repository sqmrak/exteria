#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* a community in the classic style: a grouped table with the switch that folds it into one entry of the chat list,
   and the chats it groups in two sections */
@interface ExteriaClassicCommunityController : UITableViewController

- (id)initWithSession:(ExteriaSession *)session community:(ExteriaDialog *)community known:(NSArray *)known avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

/* runs once when the person leaves for the list, so the list can show what reading changed */
@property (nonatomic, copy) void (^closeHandler)(void);

@end
