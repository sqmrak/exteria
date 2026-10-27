#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_message.h"

/* puts the photo or video of a message into the photo library of the phone, without opening it */
@interface ExteriaGallerySaver : NSObject

/* completion runs on the main thread, with nil once the library has the file and the localization key of the reason otherwise (the person
   refused access, the file did not load, or the format is not one the library takes) */
+ (void)saveMedia:(ExteriaMedia *)media cache:(ExteriaMediaCache *)cache completion:(void (^)(NSString *failureKey))completion;

/* the picture of a photo to the pasteboard, decoded at most 2048 points on a side. completion is the same as above */
+ (void)copyPhotoOfMedia:(ExteriaMedia *)media cache:(ExteriaMediaCache *)cache completion:(void (^)(NSString *failureKey))completion;

@end
