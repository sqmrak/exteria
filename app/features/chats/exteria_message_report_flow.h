#import <UIKit/UIKit.h>

#import "exteria_dialog.h"
#import "exteria_session.h"

/* the report of messages, which the server leads step by step: it lists what is wrong, may list more under the
   choice, and may ask for a line of words at the end */
@interface ExteriaMessageReportFlow : NSObject

/* ids are NSNumber message ids of the dialog; host is the screen the choices rise over */
+ (void)startForMessageIds:(NSArray *)ids dialog:(ExteriaDialog *)dialog session:(ExteriaSession *)session host:(UIViewController *)host;

@end
