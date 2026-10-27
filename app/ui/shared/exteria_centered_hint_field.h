#import <UIKit/UIKit.h>

/* a text field whose hint stands in the middle of the view that holds it, the way a search bar shows it, while the
   words typed start at the left edge of the field */
@interface ExteriaCenteredHintField : UITextField {
    BOOL _leftAligned;
}
/* the hint starts where the typed words do, vertically centered like them, instead of standing in the middle */
@property (nonatomic, assign) BOOL leftAligned;
@end
