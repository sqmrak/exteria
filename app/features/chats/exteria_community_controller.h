#import "exteria_list_controller.h"
#import "exteria_media_cache.h"
#import "exteria_sticker_library.h"

/* a community: a switch that folds it into one entry of the chat list, then the chats it groups, the ones the
   person is in and the ones they can only look at */
@interface ExteriaCommunityController : ExteriaListController

/* known are the dialogs of the chat list, whose last messages the chats of the community take over */
- (id)initWithSession:(ExteriaSession *)session community:(ExteriaDialog *)community known:(NSArray *)known avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

/* runs once when the person leaves for the list, so the list can show what reading changed */
@property (nonatomic, copy) void (^closeHandler)(void);

@end
