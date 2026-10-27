#import <UIKit/UIKit.h>

#import "exteria_shiro.h"

/* the VPN button of the top bar */
@interface ExteriaShiroButton : UIButton

/* host is the controller that carries the button; the mini app opens over the main screen it belongs to */
- (id)initWithShiro:(ExteriaShiro *)shiro host:(UIViewController *)host;

/* the size the pill wants, for a bar that places it */
- (CGSize)preferredSize;

@end

/* the classic one is a bar button item of the system, the same bordered button as Edit beside it, with the word
   VPN */
@interface ExteriaShiroBarItem : UIBarButtonItem

- (id)initWithShiro:(ExteriaShiro *)shiro host:(UIViewController *)host;

@end
