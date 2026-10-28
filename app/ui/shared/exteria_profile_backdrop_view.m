#import "exteria_profile_backdrop_view.h"

@implementation ExteriaProfileBackdropView

@synthesize centerColor = _centerColor;
@synthesize edgeColor = _edgeColor;
@synthesize focus = _focus;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.opaque = NO;
    return self;
}

- (void)dealloc {
    [_centerColor release];
    [_edgeColor release];
    [super dealloc];
}

- (void)setCenterColor:(UIColor *)color {
    if (color == _centerColor) return;
    [_centerColor release];
    _centerColor = [color retain];
    [self setNeedsDisplay];
}

- (void)setEdgeColor:(UIColor *)color {
    if (color == _edgeColor) return;
    [_edgeColor release];
    _edgeColor = [color retain];
    [self setNeedsDisplay];
}

- (void)setFocus:(CGPoint)focus {
    if (CGPointEqualToPoint(focus, _focus)) return;
    _focus = focus;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_centerColor || !_edgeColor) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    [_edgeColor setFill];
    CGContextFillRect(context, bounds);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CFArrayRef colors = (CFArrayRef)[NSArray arrayWithObjects:(id)_centerColor.CGColor, (id)_edgeColor.CGColor, nil];
    CGFloat locations[2] = {0, 1};
    CGGradientRef gradient = CGGradientCreateWithColors(space, colors, locations);
    /* the blend reaches the far corner of the header, so the edge color is only at its borders */
    CGFloat radius = MAX(bounds.size.width * 0.9, hypot(MAX(_focus.x, bounds.size.width - _focus.x), MAX(0, bounds.size.height - _focus.y)) * 0.8);
    CGContextDrawRadialGradient(context, gradient, _focus, 0, _focus, radius, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

@end
