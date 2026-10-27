#import <UIKit/UIKit.h>

/* something falling softly over a screen: snow, the small soft dots of the snow of senko */
@interface ExteriaFallingView : UIView

/* snow */
- (id)initWithFrame:(CGRect)frame;
/* a picture of the bundle, such as boykisser, falling and turning slowly; the name is a png without its extension */
- (id)initWithFrame:(CGRect)frame spriteNamed:(NSString *)name;
- (void)start;
- (void)stop;
- (BOOL)isRunning;

@end
