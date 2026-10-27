#import <UIKit/UIKit.h>

#import "exteria_shiro_power_button.h"

/* what the Shiro screen shows, laid out as the home screen of senko over falling foxes */
@interface ExteriaShiroHomeView : UIView

@property (nonatomic, readonly) ExteriaShiroPowerButton *power;
@property (nonatomic, readonly) UILabel *stateLabel;
@property (nonatomic, readonly) UILabel *cardTitle;
@property (nonatomic, readonly) UILabel *cardSubtitle;
/* the plate takes taps only when the controller turns them on, such as for the Turn off action after a failure */
@property (nonatomic, readonly) UIControl *card;

- (void)applyTheme;

@end
