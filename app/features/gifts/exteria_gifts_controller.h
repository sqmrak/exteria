#import "exteria_gift_screen.h"
#import "exteria_sticker_library.h"

/* the gifts on one profile as tiles; on our own profile they can be opened to hide, convert, upgrade or hand on;
   on someone else's the bar offers a gift of ours */
@interface ExteriaGiftsController : ExteriaGiftScreen

/* dialog is the owner of the profile, as a chat with them; mine says it is the signed in person */
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog mine:(BOOL)mine avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media;

/* handed on to the profile of a gift's sender, where a chat can be opened */
@property (nonatomic, retain) ExteriaStickerLibrary *stickers;

@end
