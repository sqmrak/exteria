#import <UIKit/UIKit.h>

#import "exteria_shiro.h"

/* shiro as a mini app: a card that rises over the signed in app, with a Close button and the name in its header,
   and the senko home screen in it; it is a child of the main controller */
@interface ExteriaShiroController : UIViewController

/* host is any controller on the main screen; the card is put on the main controller above it, or on the top one when there is none */
+ (void)presentWithShiro:(ExteriaShiro *)shiro from:(UIViewController *)host;

@end
