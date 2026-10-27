#import <UIKit/UIKit.h>

#import "exteria_story.h"

/* the colors of the ring of the Telegram story cell */
void ExteriaStoryRingColors(BOOL unseen, BOOL closeFriends, UIColor **from, UIColor **to);

/* the ring that stands round a profile picture while the person has stories: one arc per story, clockwise from the top, the
   seen ones first in thin grey and the unseen ones after them in a thick gradient, as the Telegram avatar draws it; a single
   story is a closed circle */
@interface ExteriaStoryRing : UIView

/* count stories, unseen of them not seen yet (the newest ones) */
- (void)setCount:(NSInteger)count unseen:(NSInteger)unseen closeFriends:(BOOL)closeFriends;
- (void)setPeer:(ExteriaStoryPeer *)peer;
/* how far the ring stands outside the picture it surrounds */
+ (CGFloat)outset;

@end
