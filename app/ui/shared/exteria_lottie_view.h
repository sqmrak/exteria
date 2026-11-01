#import <UIKit/UIKit.h>

@interface ExteriaLottieView : UIView
/* consumed after the first rendered frame, so a caller can remove its thumbnail */
@property (nonatomic, copy) void (^firstFrameHandler)(void);

/* keeps the first frame of the animation, by name and size, in memory and in Caches/Exteria/posters, and shows it the moment the view is loaded and laid out, before
   the animation is parsed; for the few animations a screen shows on every visit, not for the stickers of a chat. Set before the view is loaded */
@property (nonatomic, assign) BOOL cachesPoster;

- (id)initWithAnimationNamed:(NSString *)name;
/* a packed sticker held in memory; key only names it in the log */
- (id)initWithPackedData:(NSData *)packed key:(NSString *)key;

/* the parsed animation costs a few megabytes, so only pages next to the visible one hold it */
- (void)setLoaded:(BOOL)loaded;

/* playing implies loaded; the first frame shows without playing, and reduced motion keeps it still */
- (void)setPlaying:(BOOL)playing;

/* the frame that playOnce stops on; zero means the last frame of the animation */
@property (nonatomic, assign) NSUInteger lastFrame;

/* plays once from the first frame and stays on the last; reduced motion keeps the first frame */
- (void)playOnce;
/* back to the first frame, not playing */
- (void)rewind;

@end
