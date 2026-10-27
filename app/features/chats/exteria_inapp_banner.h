#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"

/* the notice a message of another chat brings while the app is on screen: a card that drops from the top edge with
   the picture and the name of the chat and the start of the message */
@interface ExteriaInAppBanner : UIView

/* shows the card over the key window; tap runs when it is touched, after the card has left. The picture at the left is the avatar of dialog
   (the initials on its colour while the photo loads, or when there is none); a nil dialog leaves the text at the edge */
+ (void)showTitle:(NSString *)title body:(NSString *)body dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars tap:(void (^)(void))tap;

+ (void)showPowerTitle:(NSString *)title body:(NSString *)body;

@end
