#import <UIKit/UIKit.h>

#import "exteria_shiro.h"

@class ExteriaWelcomeController;

@protocol ExteriaWelcomeControllerDelegate <NSObject>
- (void)welcomeControllerDidTapStart:(ExteriaWelcomeController *)controller;
/* the faint link under the button: log in with a QR code, without typing a number */
- (void)welcomeControllerDidRequestQr:(ExteriaWelcomeController *)controller;
@end

@interface ExteriaWelcomeController : UIViewController <UIScrollViewDelegate>

@property (nonatomic, assign) id<ExteriaWelcomeControllerDelegate> delegate;
/* the VPN, whose button stands at the top right: a phone that cannot reach Telegram has to be able to turn it on
   before it signs in */
@property (nonatomic, assign) ExteriaShiro *shiro;

@end
