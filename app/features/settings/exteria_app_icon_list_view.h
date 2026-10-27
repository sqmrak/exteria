#import <UIKit/UIKit.h>

/* the icons of the app side by side, the one on the home screen ringed, as the app icon row of ThemeActivity shows
   them: the icon of the app first, then the alternate ones */
@interface ExteriaAppIconListView : UIView

/* runs on the main thread with the name of the alternate icon, nil for the icon of the app; only for an icon that is not the one in use */
@property (nonatomic, copy) void (^chooseHandler)(NSString *name);
/* a picker that cannot be used right now (no jailbreak, or a change in progress) is dimmed and ignores touches */
@property (nonatomic, assign) BOOL enabled;
/* draws the ring again after the icon changed */
- (void)refreshSelection;
+ (CGFloat)height;

@end
