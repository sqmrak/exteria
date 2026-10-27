#import <UIKit/UIKit.h>

@class ExteriaQrController;

@protocol ExteriaQrControllerDelegate <NSObject>
/* the person chose the phone number instead */
- (void)qrControllerDidChoosePhone:(ExteriaQrController *)controller;
/* the back button: the login is given up */
- (void)qrControllerDidGoBack:(ExteriaQrController *)controller;
/* the retry after a failure, which asks for a new code */
- (void)qrControllerDidRequestRetry:(ExteriaQrController *)controller;
@end

/* the login by QR code: a code on a white card for another device to scan, the three steps to do that, and a way back to the
   phone number */
@interface ExteriaQrController : UIViewController

@property (nonatomic, assign) id<ExteriaQrControllerDelegate> delegate;

/* the address of a login token to draw; a code on screen is replaced with the animation of a new one */
- (void)showUrl:(NSString *)url;
/* no code could be had: the card says why and offers another try */
- (void)showFailure:(NSString *)text;
/* the code is being asked for */
- (void)showLoading;

@end
