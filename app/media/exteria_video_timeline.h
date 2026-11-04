#import <UIKit/UIKit.h>

/* the strip of the video editor: frames of the video side by side with a handle at each end of the part that is kept, a playhead that runs along it, and a
   bubble with the time over whatever the finger holds. a drag on a handle moves that end, a drag anywhere else moves the playhead. the control sends
   UIControlEventValueChanged while something moves and the usual touch events at the start and the end of a drag; main thread only */
@interface ExteriaVideoTimeline : UIControl
/* seconds; the handles keep at least a tenth of a second between them, and never touch */
@property (nonatomic, assign) double duration;
/* fractions of the duration */
@property (nonatomic, assign) double start;
@property (nonatomic, assign) double end;
@property (nonatomic, assign) double position;
/* 0 while nothing is held, 1 the start handle, 2 the end handle, 3 the playhead */
@property (nonatomic, readonly) NSInteger activeHandle;
/* UIImage for a frame, NSNull for one that could not be taken; the frames fade in one after another */
- (void)setFrames:(NSArray *)frames;
/* the height the strip, its handles and the bubbles over them need */
+ (CGFloat)preferredHeight;
@end

/* m:ss */
NSString *ExteriaVideoTimeText(double seconds);
