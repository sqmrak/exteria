#import <UIKit/UIKit.h>

/* the slider of the modern settings, in the Material 3 Expressive manner; main thread only */
@interface ExteriaExpressiveSlider : UIControl

@property (nonatomic, assign) float minimumValue;
@property (nonatomic, assign) float maximumValue;
@property (nonatomic, assign) float value;

@end
