#import "exteria_gift_screen.h"
#import "exteria_sticker_library.h"

/* the messages the person bookmarked, newest first, from every chat: a tap opens the chat at the message, a swipe takes the bookmark away */
@interface ExteriaBookmarksController : ExteriaGiftScreen <UITableViewDataSource, UITableViewDelegate>

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

@end
