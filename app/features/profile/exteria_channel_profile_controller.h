#import "exteria_gift_screen.h"
#import "exteria_sticker_library.h"

/* the profile of a channel, or of a group built on one */
@interface ExteriaChannelProfileController : ExteriaGiftScreen

/* dialog is a chat with a channel (peer kind 3); stickers is for the chat of the discussion group */
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers;

@end
