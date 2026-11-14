#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the screen a forum opens into on a phone: the chats of the list as a column of round pictures on the left, with the forum marked, and its topics beside them.
   a forum picked in the column shows its topics in place; any other chat opens over this screen */
@interface ExteriaForumController : UIViewController

/* dialogs is the chat list the column is made of, nil or empty for a screen without the column */
- (id)initWithSession:(ExteriaSession *)session forum:(ExteriaDialog *)forum dialogs:(NSArray *)dialogs avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

/* runs once when the person leaves for the list, so the list can show what reading changed */
@property (nonatomic, copy) void (^closeHandler)(void);
/* the archive button on top of the column opens the archive; without the handler the button is not shown */
@property (nonatomic, copy) void (^archiveHandler)(void);

/* whether this screen is the topics of that forum, so a profile opened from it can go back instead of stacking another */
- (BOOL)showsForum:(ExteriaDialog *)forum;

@end
