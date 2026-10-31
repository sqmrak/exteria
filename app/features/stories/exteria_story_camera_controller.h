#import <UIKit/UIKit.h>

#include "exteria_stories.h"

/* the screen that makes a story: the live picture of the camera under a back arrow and a grid switch */
@interface ExteriaStoryCameraController : UIViewController

/* whether this device has a camera to show */
+ (BOOL)cameraAvailable;

/* a screen that starts on a photo already in hand (from the library) and only dresses it: no camera, the back arrow closes it */
- (id)initWithPhotoPath:(NSString *)path;

/* runs on the main thread with the path of a temporary jpeg that the receiver deletes (the text laid over the picture is already drawn in), the caption
   (nil for none) and who sees the story; the screen is still up, so the receiver dismisses it */
@property (nonatomic, copy) void (^publishHandler)(NSString *path, NSString *caption, exteria_story_privacy privacy);
/* the person asked for the library instead of the camera; the screen is still up */
@property (nonatomic, copy) void (^galleryHandler)(void);
/* the back arrow; the screen is still up */
@property (nonatomic, copy) void (^closeHandler)(void);

@end
