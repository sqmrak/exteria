#import <UIKit/UIKit.h>

/* the shapes of the customization as a grid of cells: the chosen one stands on a tonal plate in the accent, the others rest in plain ink. the first cell is the rounded square,
   drawn with the corner the person set */
@interface ExteriaShapeGridView : UIView
@property (nonatomic, assign) NSInteger selectedShape;
/* runs on the main thread when the person taps a shape */
@property (nonatomic, copy) void (^chooseHandler)(NSInteger shape);
+ (CGFloat)heightForWidth:(CGFloat)width;
@end

/* what the choices of the customization look like together: a row of the chat list with its picture, a message bubble and the send button */
@interface ExteriaCustomPreviewView : UIView
/* draws the settings again, after any of them moved */
- (void)refresh;
/* the picture of the person the preview shows; nil brings the initials back */
- (void)setPicture:(UIImage *)picture;
+ (CGFloat)height;
@end

/* the classic counterpart: a bar of the chosen material and gloss, a strip of the chat with its texture, a glossy button and a picture, and two rows with the chosen lines between */
@interface ExteriaClassicPreviewView : UIView
- (void)refresh;
- (void)setPicture:(UIImage *)picture;
+ (CGFloat)height;
@end
