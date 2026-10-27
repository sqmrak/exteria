#import "exteria_centered_hint_field.h"

#import "exteria_string_drawing.h"

@implementation ExteriaCenteredHintField

@synthesize leftAligned = _leftAligned;

- (void)drawPlaceholderInRect:(CGRect)rect {
    [[self.textColor colorWithAlphaComponent:0.6] set];
    CGFloat height = ceil(self.font.lineHeight);
    rect.origin.y += floor((rect.size.height - height) / 2);
    rect.size.height = height;
    ExteriaDrawStringIn(self.placeholder, self.font, rect, ExteriaStringTailTruncate, _leftAligned ? 0 : 1);
}

/* one line tall and centered, where the hint stands: the field starts its typed text at the top of the rect it is
   given, so the rect is one line and in the middle */
- (CGRect)lineRectForBounds:(CGRect)bounds {
    CGFloat line = ceil(self.font.lineHeight);
    CGFloat inset = self.leftViewMode == UITextFieldViewModeAlways ? self.leftView.bounds.size.width : 0;
    return CGRectMake(bounds.origin.x + inset, bounds.origin.y + floor((bounds.size.height - line) / 2), MAX(0, bounds.size.width - inset), line);
}

- (CGRect)textRectForBounds:(CGRect)bounds {
    return _leftAligned ? [self lineRectForBounds:bounds] : [super textRectForBounds:bounds];
}

- (CGRect)editingRectForBounds:(CGRect)bounds {
    return _leftAligned ? [self lineRectForBounds:bounds] : [super editingRectForBounds:bounds];
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    /* where the typed text starts, so the hint and the text share one left edge */
    if (_leftAligned) {
        /* a hint is drawn from the top of its rect, so the rect is one line tall and centered, where the typed
           text sits */
        CGFloat line = ceil(self.font.lineHeight);
        CGFloat inset = self.leftViewMode == UITextFieldViewModeAlways ? self.leftView.bounds.size.width : 0;
        return CGRectMake(bounds.origin.x + inset, floor((bounds.size.height - line) / 2), MAX(0, bounds.size.width - inset), line);
    }
    CGFloat width = ceil(ExteriaStringSize(self.placeholder, self.font).width) + 4;
    /* the middle of the field that holds this one, so a field that stops short of a button on its right still has its hint in the middle of the whole row */
    CGFloat middle = bounds.size.width / 2;
    if (self.superview) middle = [self convertPoint:CGPointMake(CGRectGetMidX(self.superview.bounds), 0) fromView:self.superview].x;
    CGFloat x = MAX(14, floor(middle - width / 2));
    return CGRectMake(x, 0, MAX(0, MIN(width, bounds.size.width - x)), bounds.size.height);
}

@end
