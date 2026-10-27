#import <UIKit/UIKit.h>

/* records the front camera and the microphone into a square mp4, the way a round video message is made */
@interface ExteriaRoundRecorder : NSObject

/* the live picture, to be shown in a circle by the caller */
@property (nonatomic, readonly) CALayer *previewLayer;
/* NO when there is no camera or microphone to use; the preview runs from here on and recording begins with it */
- (BOOL)start;
/* why the last start failed, when the system gave a reason */
@property (nonatomic, readonly) NSString *failure;
@property (nonatomic, readonly) NSTimeInterval elapsed;
/* stops and closes the file; the completion runs on the main thread; the path is nil when the clip was too short
   or the writer failed */
- (void)finishWithCompletion:(void (^)(NSString *path, int32_t durationMs, int32_t side))completion;
- (void)cancel;
/* swaps between the front and the back camera while the clip keeps running */
- (void)switchCameraWithCompletion:(void (^)(BOOL switched))completion;

@property (nonatomic, readonly) BOOL canUseTorch;
@property (nonatomic, readonly) BOOL torchOn;
- (void)setTorchOn:(BOOL)on completion:(void (^)(BOOL success))completion;

/* the zoom of the camera that is on, 1 for none; a camera that cannot zoom (the zoom of the lens came with ios 7)
   says YES to canZoom as NO */
@property (nonatomic, readonly) BOOL canZoom;
@property (nonatomic, readonly) CGFloat zoom;
/* clamped to what the lens allows and to a few times, so the picture of a small circle stays sharp */
- (void)setZoom:(CGFloat)zoom;

@end
