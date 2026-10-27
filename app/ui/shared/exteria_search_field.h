#import <UIKit/UIKit.h>

/* the field of the modern style: a magnifier in the left margin, the hint and the typed words on one centered line after it,
   and the clear button at the right edge */
@interface ExteriaSearchField : UITextField
/* a field with the colors, the font and the magnifier of the modern style, as tall as height */
+ (ExteriaSearchField *)fieldWithPlaceholder:(NSString *)placeholder height:(CGFloat)height;
@end
