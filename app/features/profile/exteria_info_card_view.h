#import <UIKit/UIKit.h>

/* a card of rows, each a value over a smaller caption, such as a phone number, a bio or a username; a tap on a row
   copies its value */
@interface ExteriaInfoCardView : UIView

/* each row is an NSArray of the caption and the value; rows with an empty value are left out */
- (void)setRows:(NSArray *)rows;
/* the balance as a picture of the star and the count, shown in a row of its own under the others; nil takes the row away */
- (void)setStarsBalance:(UIImage *)balance caption:(NSString *)caption;
/* the height the card needs at the width; zero when it has no rows */
- (CGFloat)heightForWidth:(CGFloat)width;
/* the row with this caption gets a QR button at its right end; both are set before the rows */
@property (nonatomic, copy) NSString *codeCaption;
@property (nonatomic, copy) void (^codeHandler)(void);
/* runs on the main thread after a value was copied */
@property (nonatomic, copy) void (^copyHandler)(void);

@end
