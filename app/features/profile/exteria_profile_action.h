#import <UIKit/UIKit.h>

#import "exteria_symbol.h"

/* a card with a symbol over a caption, as on the profile of the signed in person; dims when it cannot be used */
@interface ExteriaUserAction : UIControl {
    UIImageView *_icon;
    UILabel *_caption;
    ExteriaSymbol _symbol;
    UIColor *_ink;
    UIView *_blur;
    BOOL _blurred;
}
- (id)initWithSymbol:(ExteriaSymbol)symbol title:(NSString *)title;
/* the symbol and the caption of the same card, for one that flips between two states such as sound on and off */
- (void)setSymbol:(ExteriaSymbol)symbol title:(NSString *)title;
/* the card stands on a colored ground: a dark veil for its plate and the given ink for the symbol and the caption; nil puts the usual colors back */
- (void)setInk:(UIColor *)ink;
/* the card over a wide photo: a dark blur of what is behind it where the system has one (ios 8 and later, found by class so the older slices never link it),
   and a darker veil elsewhere */
- (void)setBlurred:(BOOL)blurred;
@property (nonatomic, readonly) ExteriaSymbol symbol;
@property (nonatomic, readonly) NSString *captionText;
@end

/* puts the cards in rows of equal width: at most four to a row, and the rows as even as they can be (five make
   three and two), so a caption keeps room on a 320 point screen */
CGFloat ExteriaLayoutActions(NSArray *actions, CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat gap);
