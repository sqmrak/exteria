#import "exteria_gift_screen.h"
#import "exteria_sticker_library.h"

/* the profile of another person: photo and name, whether they are on line, the buttons for a gift and for their
   stories, their phone, bio, username and birthday when they share them */
@interface ExteriaUserProfileController : ExteriaGiftScreen

/* dialog is a chat with a user; stickers is for the chat of their personal channel */
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers;

@end
