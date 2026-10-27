#import "exteria_gift_screen.h"
#import "exteria_sticker_library.h"
#import "exteria_star_gift.h"

/* one gift on a profile: the picture, who sent it with what note, and for its owner what can be done with it */
@interface ExteriaGiftDetailController : ExteriaGiftScreen

/* mine says the gift is on our own profile, where it can be hidden, turned into stars, upgraded or handed on */
- (id)initWithSession:(ExteriaSession *)session gift:(ExteriaSavedGift *)gift mine:(BOOL)mine avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media;

/* where a chat opened from the sender's profile gets its stickers */
@property (nonatomic, retain) ExteriaStickerLibrary *stickers;

/* who owns a unique gift when the gift itself does not say, as the profile it was found on knows the name */
@property (nonatomic, copy) NSString *ownerName;

/* the profile the gift is on, for a gift of ours: with it the screen offers to put the gift in a folder of that profile */
@property (nonatomic, retain) ExteriaDialog *folderDialog;

/* runs on the main thread after anything changed on the server, so the list can load again */
@property (nonatomic, copy) void (^changedHandler)(void);

/* shows the detail in a bottom sheet owned by the host */
- (void)showInViewController:(UIViewController *)host;

@end
