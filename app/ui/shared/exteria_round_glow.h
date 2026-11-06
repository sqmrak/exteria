#import <UIKit/UIKit.h>

/* the screen light of the front camera of a video message: a warm glow that grows in from the edges of the screen and leaves the middle clear for the circle */
@interface ExteriaRoundGlow : UIView

/* fades the light in or out, and takes the screen to full brightness while it is on; the brightness the person had comes back when it goes out */
- (void)setLit:(BOOL)lit;

@end
