#import <UIKit/UIKit.h>

@class ExteriaRemoteFile;
@class ExteriaMediaCache;

@interface ExteriaInviteSheet : UIView
+ (void)showInView:(UIView *)host title:(NSString *)title subtitle:(NSString *)subtitle about:(NSString *)about
             photo:(ExteriaRemoteFile *)photo media:(ExteriaMediaCache *)media requestNeeded:(BOOL)requestNeeded join:(void (^)(void))join;
@end
