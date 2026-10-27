#import <UIKit/UIKit.h>

/* the pill that rises under the last message while the list is pulled up past its end */
@interface ExteriaNextChatHint : UIView

- (void)setTitle:(NSString *)title unread:(NSInteger)unread;
@property (nonatomic, assign) CGFloat progress;

+ (CGFloat)pullDistance;

@end
