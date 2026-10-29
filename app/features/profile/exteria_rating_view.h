#import <UIKit/UIKit.h>
#import "exteria_session_profile.h"

@interface ExteriaRatingBadge : UIControl
@property (nonatomic, assign) int32_t level;
@end

void ExteriaShowRating(UIView *host, ExteriaFullUser *user);
