#import <UIKit/UIKit.h>

/* the screen that makes a story: the live picture of the camera under a back arrow and a grid switch */
@interface ExteriaStoryCameraController : UIViewController

/* whether this device has a camera to show */
+ (BOOL)cameraAvailable;

/* runs on the main thread with the path of a temporary jpeg that the receiver deletes; the screen is still up, so the receiver dismisses it */
@property (nonatomic, copy) void (^publishHandler)(NSString *path);
/* the person asked for the library instead of the camera; the screen is still up */
@property (nonatomic, copy) void (^galleryHandler)(void);
/* the back arrow; the screen is still up */
@property (nonatomic, copy) void (^closeHandler)(void);

@end
