#import <UIKit/UIKit.h>

/* plays numbered png files, prefix_000.png and on, in a loop */
@interface ExteriaFrameView : UIView

- (id)initWithPrefix:(NSString *)prefix count:(NSUInteger)count framesPerSecond:(double)fps;

/* the first frame shows without playing; reduced motion keeps it still */
- (void)setPlaying:(BOOL)playing;

@end
