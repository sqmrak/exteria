#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_message.h"

/* what a hold on a reaction of a private chat shows, as in Telegram: the reaction large, and under it a card for each person who put it with the time they did. a tap anywhere takes it away.
   entries are dictionaries with "person" (ExteriaPerson) and "date" (an NSNumber of unix seconds) */
@interface ExteriaReactionTimePopup : UIView
+ (void)presentReaction:(ExteriaReaction *)reaction entries:(NSArray *)entries avatars:(ExteriaAvatarCache *)avatars inView:(UIView *)host;
@end
