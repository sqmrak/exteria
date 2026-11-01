#import <UIKit/UIKit.h>

@class ExteriaLottieView;

/* the laptop of the devices screens is a sticker of the official pack tg_placeholders_android. Its animation is kept in Caches after the first download, so the next
   visit builds it at once instead of asking the server for the pack and downloading the file again */
@interface ExteriaDevicesSticker : NSObject

/* the packed animation of an earlier visit, nil when there is none or it is not a gzip animation */
+ (NSData *)storedData;
+ (void)storeData:(NSData *)data;
/* the animation over the card, with its first frame kept between visits */
+ (ExteriaLottieView *)animationWithData:(NSData *)data;

@end
