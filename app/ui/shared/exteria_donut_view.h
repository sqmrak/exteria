#import <UIKit/UIKit.h>

/* the ring of the storage screen: one coloured arc per value, a share written inside every arc that is wide enough, and
   the total with its unit in the middle. a value that changes (a category was unchecked) slides to its new size */
@interface ExteriaDonutView : UIView

/* values are NSNumber byte counts and colors UIColors of the same count; a value of zero has no arc. amount and unit are
   the text in the middle, "2,9" and "GB" */
- (void)setValues:(NSArray *)values colors:(NSArray *)colors amount:(NSString *)amount unit:(NSString *)unit animated:(BOOL)animated;

@end
