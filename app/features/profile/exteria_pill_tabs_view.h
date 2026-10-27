#import <UIKit/UIKit.h>

/* a capsule of text tabs, the chosen one on a raised capsule of its own; the tabs share the width equally */
@interface ExteriaPillTabsView : UIView

- (id)initWithTitles:(NSArray *)titles;

@property (nonatomic, assign) NSUInteger selectedIndex;
/* runs on the main thread when the person taps another tab */
@property (nonatomic, copy) void (^changeHandler)(NSUInteger index);

@end
