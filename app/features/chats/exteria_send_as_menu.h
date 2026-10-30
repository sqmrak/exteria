#import <UIKit/UIKit.h>
#import "exteria_avatar_cache.h"

@interface ExteriaSendAsMenu : UIView
- (id)initWithOptions:(NSArray *)options selected:(NSUInteger)selected avatars:(ExteriaAvatarCache *)avatars handler:(void (^)(NSUInteger))handler;
- (void)showInView:(UIView *)host anchor:(CGRect)anchor;
@end
