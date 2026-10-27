#import <UIKit/UIKit.h>

#import "exteria_session.h"

/* the translation of a message, in a card that rises from the bottom over the chat */
@interface ExteriaTranslateSheet : UIView

/* context holds the lines of the chat before the message for the AI translator, or nil */
+ (void)presentInView:(UIView *)host text:(NSString *)text entities:(NSArray *)entities session:(ExteriaSession *)session context:(NSString *)context;

@end
