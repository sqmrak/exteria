#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"

/* the full screen story viewer: the stories of one poster after another and then of the next poster in the strip,
   a bar of segments on top, taps on the sides to step, a hold to pause */
@interface ExteriaStoryViewerController : UIViewController

/* peers are ExteriaStoryPeer items in strip order and index is where to start */
- (id)initWithSession:(ExteriaSession *)session peers:(NSArray *)peers index:(NSUInteger)index avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media;

/* the same viewer over stories already in hand, such as pinned or archived ones; it starts at index and ends after the last */
- (id)initWithSession:(ExteriaSession *)session owner:(ExteriaDialog *)owner stories:(NSArray *)stories index:(NSUInteger)index
              avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

/* runs on the main thread once the viewer is gone, so the strip can show what was seen */
@property (nonatomic, copy) void (^closeHandler)(void);

@end
