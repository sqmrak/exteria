#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_remote_file.h"

/* the small rounded picture before the preview text of a chat list row whose last message is a photo or a video */
@interface ExteriaPreviewThumb : UIImageView

/* points on a side, and the room the picture takes with the gap before the text */
+ (CGFloat)side;
+ (CGFloat)room;

/* shows the picture of file once it is loaded, on a plain square until then; nil file or nil cache hides the view */
- (void)showFile:(ExteriaRemoteFile *)file cache:(ExteriaMediaCache *)cache;

@end
