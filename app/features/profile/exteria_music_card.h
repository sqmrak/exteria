#import <UIKit/UIKit.h>

/* the player of the modern theme, in the Material 3 Expressive manner */
@interface ExteriaMusicCard : UIView

+ (CGFloat)height;
/* springs the card in from below, for the moment it first shows */
- (void)reveal;

@end
