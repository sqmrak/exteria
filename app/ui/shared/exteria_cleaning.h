#import <UIKit/UIKit.h>

/* the cleaning of the cache it: the duck of the animated sticker sweeps with its mop over the screen, and a line
   under it says what is being cleaned, "Cleaning “the files of messages”…" */

/* one step: the name of what is cleaned and the work, which runs on the main thread */
@interface ExteriaCleaningStep : NSObject
+ (ExteriaCleaningStep *)stepNamed:(NSString *)name work:(void (^)(void))work;
@end

/* runs the steps one after another over the window; done runs when the screen has faded away */
void ExteriaRunCleaning(NSArray *steps, void (^done)(void));
