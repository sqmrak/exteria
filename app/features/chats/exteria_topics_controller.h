#import "exteria_list_controller.h"
#import "exteria_media_cache.h"
#import "exteria_sticker_library.h"

/* the topics of a forum: a row each with its icon, the last message and the counts, pinned ones first */
@interface ExteriaTopicsController : ExteriaListController

- (id)initWithSession:(ExteriaSession *)session forum:(ExteriaDialog *)forum avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

/* runs once when the person leaves for the list, so the list can show what reading changed */
@property (nonatomic, copy) void (^closeHandler)(void);

@end
