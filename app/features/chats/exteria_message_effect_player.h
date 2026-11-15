#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_session.h"

/* the animation of a message effect over the chat, once: the lottie of the effect, or its sticker when it has none, as large as the width of the screen and centered. one plays at a time,
   a new one ends the one before, and nothing plays with reduced motion */
@interface ExteriaMessageEffectPlayer : NSObject
+ (void)playEffect:(ExteriaMessageEffect *)effect inView:(UIView *)host media:(ExteriaMediaCache *)media;
+ (void)dismiss;
@end
