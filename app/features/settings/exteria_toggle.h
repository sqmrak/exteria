#import <UIKit/UIKit.h>

/* the switch of the modern theme, drawn the way Yozora draws it (Material 3): a small thumb at the left when off, a large one at the right when on, travelling on the
   wobble curve. the classic theme keeps the switch of the system, which this control then holds inside itself. on, setOn:animated: and the value changed event are those
   of UISwitch; main thread only */
@interface ExteriaToggle : UIControl

@property (nonatomic, assign, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
/* the size of the switch in the theme of the moment, what a row lays its text out beside */
+ (CGSize)controlSize;

@end
