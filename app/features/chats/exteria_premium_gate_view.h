#import <UIKit/UIKit.h>

/* where a tap on "Get Premium" leads: the chat with the Premium bot of Telegram, opened inside the app, since Premium cannot be bought here */
void ExteriaOpenPremiumPage(void);

/* the card of a chat with a person who accepts messages only from Premium users: a lock on a speech bubble, a line
   that says so with the name in bold, and the button that leads to Premium */
@interface ExteriaPremiumGateView : UIView

- (id)initWithName:(NSString *)name;
- (CGSize)cardSizeForWidth:(CGFloat)width;

@end
