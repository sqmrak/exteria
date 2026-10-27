#import <UIKit/UIKit.h>

/* how a line that does not fit ends; the numbers are the ones UILineBreakMode and NSLineBreakMode share */
typedef enum {
    ExteriaStringWrap = 0,
    ExteriaStringClip = 2,
    ExteriaStringTailTruncate = 3,
    ExteriaStringMiddleTruncate = 5
} ExteriaStringBreak;

/* plain string measuring and drawing. ios 5 and 6 have only the UIKit methods that ios 7 deprecated, and the
   attribute based ones that replaced them do not exist there */
CGSize ExteriaStringSize(NSString *string, UIFont *font);
CGSize ExteriaStringSizeIn(NSString *string, UIFont *font, CGSize constraint);
void ExteriaDrawStringAt(NSString *string, UIFont *font, CGPoint point);
/* the color is the one already set on the context; alignment is one of the ExteriaTextAlignment values */
void ExteriaDrawStringIn(NSString *string, UIFont *font, CGRect rect, ExteriaStringBreak mode, NSInteger alignment);

/* a one line label whose room is fixed (a date, a time, a last seen line) shrinks its letters, down to minimum points, before it would end in three dots */
void ExteriaLabelFitToWidth(UILabel *label, CGFloat minimum);
