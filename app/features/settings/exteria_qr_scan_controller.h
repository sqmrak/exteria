#import <UIKit/UIKit.h>

/* the camera that reads the QR code of another Telegram app, for linking a device */
@interface ExteriaQrScanController : UIViewController

/* whether this device has a camera to read with */
+ (BOOL)scanningAvailable;

/* called once, on the main thread, with the text of the first code that reads as a tg://login address; the screen is still up, so the receiver dismisses it */
@property (nonatomic, copy) void (^scanHandler)(NSString *link);
@property (nonatomic, copy) void (^closeHandler)(void);

@end
