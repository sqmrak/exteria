#import <UIKit/UIKit.h>

/* a plain browser of the folders the phone lets the app read, for choosing one file to send: iOS 5 has no document
   picker */
@interface ExteriaFilePicker : UITableViewController

/* nil directory opens the list of locations; the handler receives a chosen file on the main thread */
- (id)initWithDirectory:(NSString *)directory handler:(void (^)(NSString *path))handler cancel:(void (^)(void))cancel;

@end
