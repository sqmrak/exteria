#import <UIKit/UIKit.h>

/* the app icon built from four layers: the arrow and the two waves move, the base stays */
@interface ExteriaAnimatedIconView : UIView

/* plays the entrance and then loops a slow idle motion; reduced motion shows the still icon */
- (void)startAnimating;
- (void)stopAnimating;

@end
