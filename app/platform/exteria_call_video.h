#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

/* the camera and the screen of a video call */
@interface ExteriaCallVideo : NSObject

/* frameHandler gets each encoded frame (on a queue of its own, it must not block), whether it is a key frame, and its time on the 90 kHz clock */
- (id)initWithFrameHandler:(void (^)(NSData *frame, BOOL keyFrame, uint32_t timestamp))frameHandler;

/* the live picture of the camera; nil until the camera runs */
@property (nonatomic, readonly) CALayer *previewLayer;
/* called on the main thread with each decoded picture of the other side */
@property (nonatomic, copy) void (^remoteImageHandler)(CGImageRef image);
/* called when the decoder cannot go on without a key frame (any queue) */
@property (nonatomic, copy) void (^keyFrameNeededHandler)(void);
/* one line of what the camera and the codec do, for the log of the call; any queue */
@property (nonatomic, copy) void (^traceHandler)(NSString *line);
@property (nonatomic, readonly) BOOL cameraRunning;
@property (nonatomic, readonly) BOOL usingFrontCamera;

/* NO when the device has no camera or the capture refuses; the reason is logged */
- (BOOL)startCamera;
- (void)stopCamera;
/* the other camera; NO when the device has one only */
- (BOOL)switchCamera;
/* the screen turned: the picture sent stays upright (the size of the encoded picture follows) */
- (void)setInterfaceOrientation:(UIInterfaceOrientation)orientation;
/* the next encoded frame is a key frame */
- (void)requestKeyFrame;

/* one VP8 frame of the other side, as the call hands it over; any thread */
- (void)receiveFrame:(NSData *)frame keyFrame:(BOOL)keyFrame;

/* stops the camera and the decoder and waits for the queues */
- (void)stop;

@end
