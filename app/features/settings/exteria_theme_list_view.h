#import <UIKit/UIKit.h>

/* the themes of the app side by side, as the color theme row of ThemeActivity shows its themes */
@interface ExteriaThemeListView : UIView

/* runs on the main thread with the style and the tone of the card that was tapped, only for a card that is not the one on screen */
@property (nonatomic, copy) void (^chooseHandler)(BOOL classic, BOOL dark);

/* where the last tapped card is, in window coordinates, which is where the change of colors spreads from */
@property (nonatomic, readonly) CGPoint tapPoint;

/* the height the list takes */
+ (CGFloat)height;

@end
