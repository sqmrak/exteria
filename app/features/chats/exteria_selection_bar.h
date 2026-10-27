#import <UIKit/UIKit.h>

/* the bar that takes the place of the message field while messages are picked: Cancel at the left, how many are picked, and the buttons
   that act on all of them */
@interface ExteriaSelectionBar : UIView

@property (nonatomic, copy) void (^cancelHandler)(void);
@property (nonatomic, copy) void (^forwardHandler)(void);
@property (nonatomic, copy) void (^copyHandler)(void);
@property (nonatomic, copy) void (^deleteHandler)(void);
/* picks every message between the first and the last of those picked */
@property (nonatomic, copy) void (^rangeHandler)(void);

+ (CGFloat)height;
/* count of picked messages, and which of the buttons may be used for them */
- (void)setCount:(NSUInteger)count forward:(BOOL)forward copy:(BOOL)copy delete:(BOOL)delete range:(BOOL)range;

@end
