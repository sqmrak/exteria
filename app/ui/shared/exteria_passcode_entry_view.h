#import <UIKit/UIKit.h>

#include "exteria_passcode.h"

/* where a passcode is typed, for the lock screen and for the setting of a code; it only collects the code */
@interface ExteriaPasscodeEntryView : UIView

/* the pad of four digits, or the field of a password; set before the view shows, or the typed part is dropped */
@property (nonatomic, assign) exteria_passcode_type type;
@property (nonatomic, copy) NSString *title;
/* the line under the title: a hint, or why the last try failed */
@property (nonatomic, copy) NSString *message;
/* off while a wait runs: the pad and the field take no input */
/* the height of the bar the owner draws its buttons in; the words start below it, so a button never sits beside the title */
@property (nonatomic, assign) CGFloat topInset;
@property (nonatomic, assign) BOOL inputEnabled;
/* a pin is full, or the person pressed done on a password; main thread */
@property (nonatomic, copy) void (^submit)(NSString *code);

/* drops what was typed */
- (void)reset;
/* the dots shake sideways, and what was typed is dropped */
- (void)rejectCode;
/* the keyboard of a password opens; the pad needs nothing */
- (void)focus;
/* refuses input for this many seconds and counts them down in the line under the title; input comes back by itself */
- (void)holdForSeconds:(NSUInteger)seconds;

@end
