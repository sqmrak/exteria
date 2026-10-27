#import <UIKit/UIKit.h>

#import "exteria_symbol.h"

/* the strip over the message field that says what the next send does: whose message it answers, or which message
   it changes */
@interface ExteriaComposeContext : UIView

@property (nonatomic, copy) void (^closeHandler)(void);

+ (CGFloat)height;
/* a glyph, a line in the accent color above and one line of the message under it */
- (void)showSymbol:(ExteriaSymbol)symbol title:(NSString *)title text:(NSString *)text;

@end
