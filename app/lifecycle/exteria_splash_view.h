#import <UIKit/UIKit.h>

/* posted by the first signed in list that shows rows, an empty state or an error, so the splash can leave */
extern NSString *const ExteriaFirstScreenReadyNotification;

/* the app icon on the color of the screen that follows, held over the window while the first screen fills */
@interface ExteriaSplashView : UIView

- (id)initWithFrame:(CGRect)frame color:(UIColor *)color;
/* fades out and leaves its superview */
- (void)dismiss;

@end
