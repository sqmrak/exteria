#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@protocol ExteriaFrameAnimation <NSObject>
@property (nonatomic, readonly) BOOL ready;
@property (nonatomic, readonly) BOOL failed;
@property (nonatomic, readonly) NSUInteger frameCount;
@property (nonatomic, readonly) double framesPerSecond;
@property (nonatomic, readonly) NSTimeInterval duration;
- (BOOL)requestFrame:(NSUInteger)frame side:(NSUInteger)side;
- (CGImageRef)copyFinishedFrame;
- (void)invalidate;
@end

/* one parsed animation, rendered one frame at a time on a private queue */
@interface ExteriaLottie : NSObject <ExteriaFrameAnimation>

/* nil when the file is missing, not gzip or over the size limits; parsing runs on the shared render
   queue, so a bad lottie document shows up as failed later */
+ (ExteriaLottie *)animationNamed:(NSString *)name;

/* the same for a sticker that came over the network; key only names it in the log */
+ (ExteriaLottie *)animationWithPackedData:(NSData *)packed key:(NSString *)key;

/* the counts below are valid once ready; failed never turns back to ready */
@property (nonatomic, readonly) BOOL ready;
@property (nonatomic, readonly) BOOL failed;

@property (nonatomic, readonly) NSUInteger frameCount;
@property (nonatomic, readonly) double framesPerSecond;
@property (nonatomic, readonly) NSTimeInterval duration;

/* main thread only; returns NO while the previous frame is still rendering */
- (BOOL)requestFrame:(NSUInteger)frame side:(NSUInteger)side;

/* one picture of the first frame, for a place that shows the animation still (a custom emoji in a line of text);
   the image lives only for the call */
- (void)renderStillAtSide:(NSUInteger)side completion:(void (^)(CGImageRef image))completion;

/* returns a retained image once per finished frame, NULL when nothing new arrived */
- (CGImageRef)copyFinishedFrame;

/* drops the pending image and refuses further requests; safe to call twice */
- (void)invalidate;

@end
