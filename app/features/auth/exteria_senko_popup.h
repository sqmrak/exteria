#import <UIKit/UIKit.h>

/* the thanks for choosing Senko, as a window of its own over the login screen: a dimmed backdrop, a card with the
   picture of the fox, two lines and one button */
@interface ExteriaSenkoPopup : UIView

@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *messageText;
@property (nonatomic, copy) NSString *buttonTitle;
/* runs once, after the card has left */
@property (nonatomic, copy) void (^dismissHandler)(void);

- (void)showInView:(UIView *)host;
- (void)dismiss;
@property (nonatomic, readonly) BOOL isShown;

@end
