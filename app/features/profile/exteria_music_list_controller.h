#import "exteria_gift_screen.h"

/* the songs saved on a profile, a page at a time, with the player under them */
@interface ExteriaMusicListController : ExteriaGiftScreen

/* dialog is the chat with the person whose profile it is, or the chat with oneself for one's own; first is the song the profile
   showed, listed at once while the first page loads */
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog first:(ExteriaMedia *)first avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media;

@end
