#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_session_profile.h"

/* the personal channel of a profile as a card: "Channel" with its follower count, the picture, the name, the
   newest line and its time */
@interface ExteriaChannelCard : UIControl

- (void)configureWithChannel:(ExteriaPersonalChannel *)channel avatars:(ExteriaAvatarCache *)avatars;
+ (CGFloat)height;

@end
