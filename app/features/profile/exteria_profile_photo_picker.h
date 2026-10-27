#import <UIKit/UIKit.h>

/* picks a picture from the library and hands over a square jpeg ready to become a profile photo */
@interface ExteriaProfilePhotoPicker : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverControllerDelegate>

/* host presents the picker; picked runs on the main thread with the path of a temporary jpeg, which the receiver
   deletes */
+ (void)pickFrom:(UIViewController *)host picked:(void (^)(NSString *path))picked unavailable:(void (^)(void))unavailable;
/* the same for a story: the whole picture is kept, shrunk to at most 1280 points on its long side, and not cut to a square */
+ (void)pickWholeFrom:(UIViewController *)host picked:(void (^)(NSString *path))picked unavailable:(void (^)(void))unavailable;

@end
