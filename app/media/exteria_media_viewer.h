#import <UIKit/UIKit.h>
#import "exteria_media_cache.h"

@interface ExteriaMediaViewer : UIViewController
- (id)initWithMessages:(NSArray *)messages selected:(ExteriaMessage *)message media:(ExteriaMediaCache *)media;
- (id)initWithMessages:(NSArray *)messages selected:(ExteriaMessage *)message media:(ExteriaMediaCache *)media
           senderNames:(NSDictionary *)senderNames chatTitle:(NSString *)chatTitle;
- (id)initWithImage:(UIImage *)image send:(void (^)(UIImage *image, NSString *caption))send;
- (id)initWithVideoURL:(NSURL *)url send:(void (^)(NSString *caption))send;
@property (nonatomic, copy) void (^cancelHandler)(void);
@end
