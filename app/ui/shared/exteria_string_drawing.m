#import "exteria_string_drawing.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

CGSize ExteriaStringSize(NSString *string, UIFont *font) {
    return [string sizeWithFont:font];
}

CGSize ExteriaStringSizeIn(NSString *string, UIFont *font, CGSize constraint) {
    return [string sizeWithFont:font constrainedToSize:constraint];
}

void ExteriaDrawStringAt(NSString *string, UIFont *font, CGPoint point) {
    [string drawAtPoint:point withFont:font];
}

void ExteriaDrawStringIn(NSString *string, UIFont *font, CGRect rect, ExteriaStringBreak mode, NSInteger alignment) {
    [string drawInRect:rect withFont:font lineBreakMode:(int)mode alignment:(int)alignment];
}

void ExteriaLabelFitToWidth(UILabel *label, CGFloat minimum) {
    /* minimumFontSize is the call that ios 5 has; the scale factor of ios 6 does not exist there, and the old one still works on the newest systems */
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumFontSize = minimum;
}

#pragma clang diagnostic pop
