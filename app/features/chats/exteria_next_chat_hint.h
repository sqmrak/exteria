#import <UIKit/UIKit.h>

@class ExteriaDialog;

/* what the pull past the end of a channel or of a topic shows in the space that opens under the last message: a plate with an arrow that grows with the finger, and once
   the pull is far enough the picture of the next chat springs up out of it with its name and its count, as the android client draws it. the view lives in the list at
   the end of its content, so the space it fills is the one the list opens by itself */
@interface ExteriaNextChatHint : UIView

/* the picture is nil until the photo arrives, and the first letter of the title stands in for it */
- (void)setTitle:(NSString *)title unread:(NSInteger)unread icon:(UIImage *)icon;
- (void)setIcon:(UIImage *)icon;
/* zero to one, the pull in terms of pullDistance; one starts the release state, anything lower takes it back */
@property (nonatomic, assign) CGFloat progress;

+ (CGFloat)pullDistance;

/* the next topic of a forum with unread messages after the current one, in the order of the list the person came from; seen holds the topics already gone through, since the
   list is only read again once the person is back on it, and the current one is added to it */
+ (ExteriaDialog *)nextUnreadTopicIn:(NSArray *)topics after:(ExteriaDialog *)current seen:(NSMutableSet *)seen;

@end
