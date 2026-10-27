#import <UIKit/UIKit.h>

/* a title painted with a gradient that flows through it; a gradient layer twice as wide as the title slides one
   lap under a mask cut from the text, and the colors repeat after one lap so the loop has no seam */
@interface ExteriaShiroShimmerLabel : UIView

@property (nonatomic, copy) NSString *text;
@property (nonatomic, retain) UIFont *font;
/* repaints in the colors of the current theme */
- (void)applyTheme;

@end
