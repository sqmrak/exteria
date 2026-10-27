#import <UIKit/UIKit.h>

#import "exteria_dialog.h"
#import "exteria_session.h"

/* the report of a user, group or channel: a list of reasons, a line of words when the reason is "other" */
@interface ExteriaReportFlow : NSObject

/* host is the screen the list rises over; done runs on the main thread after a report was sent, and not on a cancel or a failure */
+ (void)startForDialog:(ExteriaDialog *)dialog session:(ExteriaSession *)session host:(UIViewController *)host done:(void (^)(void))done;

@end
