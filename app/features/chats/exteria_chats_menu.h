#import <UIKit/UIKit.h>

@class ExteriaSession, ExteriaAvatarCache, ExteriaMediaCache, ExteriaStickerLibrary;

/* the menu behind the three dots of the main list: night and day, a new group or channel, the favorites, the bookmarks and the proxies. The modern and the classic list both
   show it, so the entries and what they do live here once */
@interface ExteriaChatsMenu : NSObject <UIAlertViewDelegate>

/* host is the controller the screens are pushed from, and refresh asks its list to load again (a group was made, or a chat was left) */
- (id)initWithSession:(ExteriaSession *)session host:(UIViewController *)host avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers refresh:(void (^)(void))refresh;
/* the card hangs from anchor, a point in the coordinates of view, which the card covers while it is open */
- (void)showInView:(UIView *)view anchor:(CGPoint)anchor;

@end
