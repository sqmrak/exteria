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

/* the track runs the full width and the thumb travels inside it by its own radius: with the track inset to the thumb's centre the filled part has no
   width at value 0, and the stretched cap image shows there as a thin bar as tall as the slider */
- (CGRect)trackRectForBounds:(CGRect)bounds {
    if (ExteriaThemeIsClassic()) return [super trackRectForBounds:bounds];
    return CGRectMake(0, (bounds.size.height - 4) / 2, bounds.size.width, 4);
}

- (CGRect)thumbRectForBounds:(CGRect)bounds trackRect:(CGRect)rect value:(float)value {
    if (ExteriaThemeIsClassic()) return [super thumbRectForBounds:bounds trackRect:rect value:value];
    CGFloat side = 28;
    CGFloat travel = MAX(0, rect.size.width - side);
    float span = self.maximumValue - self.minimumValue;
    CGFloat fraction = span > 0 ? (value - self.minimumValue) / span : 0;
    return CGRectMake(rect.origin.x + travel * MIN(1, MAX(0, fraction)), (bounds.size.height - side) / 2, side, side);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (ExteriaThemeIsClassic()) return [super pointInside:point withEvent:event];
    return CGRectContainsPoint(CGRectInset(self.bounds, 0, -MAX(0, (44 - self.bounds.size.height) / 2)), point);
}
@end
