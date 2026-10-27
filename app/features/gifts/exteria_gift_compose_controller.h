#import "exteria_gift_screen.h"
#import "exteria_star_gift.h"

/* one gift for one person: the note, whether to hide the name, and the payment in stars */
@interface ExteriaGiftComposeController : ExteriaGiftScreen

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog gift:(ExteriaStarGift *)gift
              avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

/* runs on the main thread after the payment went through */
@property (nonatomic, copy) void (^sentHandler)(void);

@end
