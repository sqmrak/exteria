#import "exteria_pill_label.h"

@interface ExteriaPillLabel () {
    UIColor *_fill;
}
@end

@implementation ExteriaPillLabel

- (void)dealloc {
    [_fill release];
    [super dealloc];
}

- (UIColor *)backgroundColor {
    return _fill;
}

- (void)setBackgroundColor:(UIColor *)color {
    if (color == _fill) return;
    [_fill release];
    _fill = [color retain];
    [super setBackgroundColor:[UIColor clearColor]];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (_fill) {
        CGRect bounds = self.bounds;
        [_fill setFill];
        [[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:MIN(bounds.size.width, bounds.size.height) / 2] fill];
    }
    [super drawRect:rect];
}

@end
