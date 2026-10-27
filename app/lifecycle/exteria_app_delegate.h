#import <UIKit/UIKit.h>

#import "exteria_login_flow.h"
#import "exteria_main_controller.h"
#import "exteria_phone_controller.h"
#import "exteria_session.h"
#import "exteria_welcome_controller.h"

@interface ExteriaAppDelegate : UIResponder <UIApplicationDelegate, ExteriaWelcomeControllerDelegate,
                                              ExteriaLoginFlowDelegate, ExteriaMainControllerDelegate,
                                              ExteriaSessionDelegate, ExteriaCallDelegate, UINavigationControllerDelegate>
@property (nonatomic, retain) UIWindow *window;
@end
