#import "exteria_gift_screen.h"

/* the gifts for sale as tiles; a tap opens the screen that writes the note and pays */
@interface ExteriaGiftCatalogController : ExteriaGiftScreen

/* the user the gift goes to, as a chat with them */
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

/* runs on the main thread once a gift was paid for, so the screen below can refresh */
@property (nonatomic, copy) void (^sentHandler)(void);

@end
