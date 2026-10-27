#import "exteria_centered_hint_field.h"

#import "exteria_string_drawing.h"

@implementation ExteriaCenteredHintField

@synthesize leftAligned = _leftAligned;

- (void)setLeftAligned:(BOOL)leftAligned {
    _leftAligned = leftAligned;
    self.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    [self setNeedsDisplay];
}

- (void)drawPlaceholderInRect:(CGRect)rect {
    [[self.textColor colorWithAlphaComponent:0.6] set];
    CGFloat height = ceil(self.font.lineHeight);
    rect.origin.y = CGRectGetMinY(self.bounds) + floor((self.bounds.size.height - height) / 2);
    rect.size.height = height;
    ExteriaDrawStringIn(self.placeholder, self.font, rect, ExteriaStringTailTruncate, _leftAligned ? 0 : 1);
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    /* where the typed text starts, so the hint and the text share one left edge */
    if (_leftAligned) {
        CGFloat inset = self.leftViewMode == UITextFieldViewModeAlways ? self.leftView.bounds.size.width : 0;
        return CGRectMake(bounds.origin.x + inset, bounds.origin.y, MAX(0, bounds.size.width - inset), bounds.size.height);
    }
    CGFloat width = ceil(ExteriaStringSize(self.placeholder, self.font).width) + 4;
    /* the middle of the field that holds this one, so a field that stops short of a button on its right still has its hint in the middle of the whole row */
    CGFloat middle = bounds.size.width / 2;
    if (self.superview) middle = [self convertPoint:CGPointMake(CGRectGetMidX(self.superview.bounds), 0) fromView:self.superview].x;
    CGFloat x = MAX(14, floor(middle - width / 2));
    return CGRectMake(x, 0, MAX(0, MIN(width, bounds.size.width - x)), bounds.size.height);
}

@end
