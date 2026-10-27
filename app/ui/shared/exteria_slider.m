#import "exteria_slider.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

@implementation ExteriaSlider
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self && !ExteriaThemeIsClassic()) [self setTrackColor:ExteriaColorAccent()];
    return self;
}

static UIImage *track_image(UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(8, 4), NO, ExteriaScreenScale());
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 8, 4) cornerRadius:2] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image stretchableImageWithLeftCapWidth:4 topCapHeight:0];
}

static UIImage *thumb_image(UIColor *color, CGFloat side) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(28, 28), NO, ExteriaScreenScale());
    [color setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake((28 - side) / 2, (28 - side) / 2, side, side)] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)setTrackColor:(UIColor *)color {
    if (ExteriaThemeIsClassic()) return;
    [self setMinimumTrackImage:track_image(color) forState:UIControlStateNormal];
    [self setMaximumTrackImage:track_image([color colorWithAlphaComponent:0.22]) forState:UIControlStateNormal];
    [self setThumbImage:thumb_image(color, 12) forState:UIControlStateNormal];
    [self setThumbImage:thumb_image(color, 18) forState:UIControlStateHighlighted];
}

- (CGRect)trackRectForBounds:(CGRect)bounds {
    if (ExteriaThemeIsClassic()) return [super trackRectForBounds:bounds];
    return CGRectMake(14, (bounds.size.height - 4) / 2, MAX(0, bounds.size.width - 28), 4);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (ExteriaThemeIsClassic()) return [super pointInside:point withEvent:event];
    return CGRectContainsPoint(CGRectInset(self.bounds, 0, -MAX(0, (44 - self.bounds.size.height) / 2)), point);
}
@end
