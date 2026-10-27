#import <UIKit/UIKit.h>

typedef enum {
    ExteriaShiroPowerOff = 0,
    /* the shape cycles through the others while the tunnel is made */
    ExteriaShiroPowerWorking,
    ExteriaShiroPowerOn,
    ExteriaShiroPowerFailed
} ExteriaShiroPowerState;

/* the power control as a Material shape: a scallop in a quiet tone when the tunnel is off, the same scallop lit
   and turning slowly over a counter-turning bloom when it carries traffic */
@interface ExteriaShiroPowerButton : UIControl

@property (nonatomic, assign) ExteriaShiroPowerState powerState;
/* repaints in the colors of the current theme */
- (void)applyTheme;

@end
