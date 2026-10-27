#import "exteria_settings_kit.h"

/* passcode Lock: the switch that sets or takes off the code, the change of it, and the time away after which the
   app asks again; not offered */
@interface ExteriaPasscodeSettingsController : ExteriaSettingsPageController
- (id)init;

/* the way into the page from a list: the code is asked first when one is set, and the page opens over host once it was right */
+ (void)openFrom:(UIViewController *)host push:(void (^)(UIViewController *page))push;
@end
