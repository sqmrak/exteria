#import <UIKit/UIKit.h>

@interface ExteriaPageDotsView : UIView

@property (nonatomic, assign) NSInteger pages;
@property (nonatomic, assign) CGFloat diameter;

/* fractional page position, so the active dot follows the finger */
- (void)setProgress:(double)progress;

@end
