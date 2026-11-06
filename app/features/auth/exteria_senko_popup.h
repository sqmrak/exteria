#import <UIKit/UIKit.h>

/* the thanks for choosing Senko, as a window of its own over the login screen: a dimmed backdrop, a card with the
   picture of the fox, two lines and one button */
@interface ExteriaSenkoPopup : UIView

@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *messageText;
@property (nonatomic, copy) NSString *buttonTitle;
/* the file of the picture over the words, senko_meme.jpg when unset. a picture with its own outline (a sticker) is drawn whole, in a box of at most pictureHeight points, instead
   of filling the width of the card as a photo does */
@property (nonatomic, copy) NSString *pictureName;
@property (nonatomic, assign) CGFloat pictureHeight;
/* runs once, after the card has left */
@property (nonatomic, copy) void (^dismissHandler)(void);

- (void)showInView:(UIView *)host;
- (void)dismiss;
@property (nonatomic, readonly) BOOL isShown;

@end

/* a one-button window with a sticker over the words, shown over the whole screen; it keeps itself until the button is pressed */
void ExteriaShowPicturePopup(NSString *title, NSString *message, NSString *pictureName, CGFloat pictureHeight);
