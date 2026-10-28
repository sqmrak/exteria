#import "exteria_profile_backdrop_view.h"

@implementation ExteriaProfileBackdropView

@synthesize centerColor = _centerColor;
@synthesize edgeColor = _edgeColor;
@synthesize focus = _focus;
@synthesize patternImage = _patternImage;
@synthesize patternColor = _patternColor;
@synthesize photoRadius = _photoRadius;

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
    [_patternImage release];
    [_patternColor release];
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

- (void)setPatternImage:(UIImage *)image {
    if (image == _patternImage) return;
    [_patternImage release];
    _patternImage = [image retain];
    [self setNeedsDisplay];
}

- (void)setPatternColor:(UIColor *)color {
    if (color == _patternColor) return;
    [_patternColor release];
    _patternColor = [color retain];
    [self setNeedsDisplay];
}

- (void)setPhotoRadius:(CGFloat)radius {
    if (radius == _photoRadius) return;
    _photoRadius = radius;
    [self setNeedsDisplay];
}

/* three rings of the emoji round the photo, each farther, smaller and fainter than the one inside it; the angles are fixed, so a header looks the same every time it is drawn */
- (void)drawPatternInContext:(CGContextRef)context {
    if (!_patternImage.CGImage || !_patternColor || _photoRadius <= 0) return;
    static const int counts[3] = {6, 9, 12};
    static const CGFloat radii[3] = {1.55f, 2.25f, 2.95f};
    static const CGFloat sizes[3] = {0.40f, 0.34f, 0.28f};
    static const CGFloat alphas[3] = {0.55f, 0.38f, 0.22f};
    CGRect bounds = self.bounds;
    for (int ring = 0; ring < 3; ++ring) {
        CGFloat side = _photoRadius * sizes[ring];
        for (int i = 0; i < counts[ring]; ++i) {
            CGFloat jitter = (CGFloat)((i * 37 + ring * 11) % 13) / 13.0f * 0.22f;
            CGFloat angle = (CGFloat)(2 * M_PI) * ((CGFloat)i / counts[ring] + ring * 0.06f + jitter / counts[ring]);
            CGFloat distance = _photoRadius * radii[ring] * (1 + jitter * 0.4f);
            CGRect box = CGRectMake(_focus.x + cos(angle) * distance - side / 2, _focus.y + sin(angle) * distance - side / 2, side, side);
            if (!CGRectIntersectsRect(box, bounds)) continue;
            CGContextSaveGState(context);
            CGContextTranslateCTM(context, box.origin.x, box.origin.y + side);
            CGContextScaleCTM(context, 1, -1);
            CGContextClipToMask(context, CGRectMake(0, 0, side, side), _patternImage.CGImage);
            CGContextSetFillColorWithColor(context, [_patternColor colorWithAlphaComponent:alphas[ring]].CGColor);
            CGContextFillRect(context, CGRectMake(0, 0, side, side));
            CGContextRestoreGState(context);
        }
    }
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
    [self drawPatternInContext:context];
}

@end
