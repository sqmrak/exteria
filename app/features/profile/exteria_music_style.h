#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

/* what the music card and the mini player of a profile share */

/* the card behind the controls, and the stronger tone of the covers, handles and quiet keys */
UIColor *ExteriaMusicSurfaceColor(void);
UIColor *ExteriaMusicTonalColor(void);
/* a quick rise past the target and a settle back */
CAMediaTimingFunction *ExteriaMusicSpring(void);

/* a button that rests in a pill or a rounded square: its corners tighten under the finger and spring open on release, and a change of the resting
   radius morphs with the same spring */
@interface ExteriaMusicKey : UIButton {
    CGFloat _restRadius;
}
- (void)setRestRadius:(CGFloat)radius animated:(BOOL)animated;
@end
