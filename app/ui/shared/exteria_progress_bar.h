#import <UIKit/UIKit.h>

/* the bar that shows how much of a file has come, in the look of the sliders of the app; main thread only */
@interface ExteriaProgressBar : UIView

/* 0 to 1 */
@property (nonatomic, assign) float progress;
@property (nonatomic, retain) UIColor *fillColor;

@end
