#import <UIKit/UIKit.h>
#import "exteria_media_cache.h"

@interface ExteriaMediaViewer : UIViewController
- (id)initWithMessages:(NSArray *)messages selected:(ExteriaMessage *)message media:(ExteriaMediaCache *)media;
- (id)initWithMessages:(NSArray *)messages selected:(ExteriaMessage *)message media:(ExteriaMediaCache *)media
           senderNames:(NSDictionary *)senderNames chatTitle:(NSString *)chatTitle;
- (id)initWithImage:(UIImage *)image send:(void (^)(UIImage *image, NSString *caption))send;
- (id)initWithVideoURL:(NSURL *)url send:(void (^)(NSString *caption))send;
/* a one-time photo, video or round video of a chat: the viewer has no menu, no forward and no save, tells the owner when the file is on the screen (the moment the
   server must hear that it was opened), and burns away when it is closed after that. closed runs once the viewer is gone, opened or not */
- (id)initWithOneTimeMessage:(ExteriaMessage *)message media:(ExteriaMediaCache *)media opened:(void (^)(void))opened closed:(void (^)(void))closed;
/* the sender looks at their own one-time file before the other side has: the same viewer, but nothing is reported to the server and nothing burns. A file that is
   still going up is read from the copy on this phone */
- (id)initWithOneTimePreviewOfMessage:(ExteriaMessage *)message media:(ExteriaMediaCache *)media;
@property (nonatomic, copy) void (^cancelHandler)(void);
@end
