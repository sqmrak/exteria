#import <UIKit/UIKit.h>

/* the bubble that stands at the end of a chat while the other side is typing: a small incoming bubble with three dots that rise one after another, as in the intro of the app */
@interface ExteriaTypingBubble : UIView {
    NSArray *_dots;
}
/* the size the bubble has */
+ (CGSize)size;
/* the colors of the theme are read again */
- (void)applyTheme;
/* the dots begin their beat; the system drops layer animations in the background, so this is asked again when the bubble is on a window */
- (void)startBeat;
@end
