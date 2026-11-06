#import "exteria_round_glow.h"

/* the light the other clients use for the front camera: white leaning to yellow */
#define GLOW_RED 1.0
#define GLOW_GREEN 0.965
#define GLOW_BLUE 0.78

@implementation ExteriaRoundGlow {
    CGFloat _savedBrightness;
    BOOL _brightnessHeld;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.alpha = 0;
    self.userInteractionEnabled = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)dealloc {
    [self restoreBrightness];
    [super dealloc];
}

- (void)restoreBrightness {
    if (!_brightnessHeld) return;
    _brightnessHeld = NO;
    [UIScreen mainScreen].brightness = _savedBrightness;
}

- (void)setLit:(BOOL)lit {
    if (lit && !_brightnessHeld) {
        _savedBrightness = [UIScreen mainScreen].brightness;
        _brightnessHeld = YES;
        [UIScreen mainScreen].brightness = 1;
    }
    if (!lit) [self restoreBrightness];
    [UIView animateWithDuration:lit ? 0.32 : 0.24 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.alpha = lit ? 1 : 0;
    } completion:nil];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[8] = {GLOW_RED, GLOW_GREEN, GLOW_BLUE, 0, GLOW_RED, GLOW_GREEN, GLOW_BLUE, 1};
    CGFloat stops[2] = {0.22, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, stops, 2);
    CGPoint center = CGPointMake(width / 2, height * 0.4);
    CGFloat radius = MIN(width, height) / 2 * 1.35;
    CGContextDrawRadialGradient(context, gradient, center, 0, center, radius, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

@end
