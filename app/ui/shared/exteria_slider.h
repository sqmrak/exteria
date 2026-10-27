#import <UIKit/UIKit.h>

/* keeps UISlider tracking and accessibility while drawing the modern theme consistently on ios 5 */
@interface ExteriaSlider : UISlider
- (void)setTrackColor:(UIColor *)color;
@end
