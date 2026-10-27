#import "exteria_music_style.h"

#include <math.h>

#import "exteria_platform.h"
#import "exteria_theme.h"

static NSString *const ExteriaMusicRadiusKey = @"music.radius";

/* a quick rise past the target and a settle back, the spring of the Material expressive motion scheme */
CAMediaTimingFunction *ExteriaMusicSpring(void) {
    return [CAMediaTimingFunction functionWithControlPoints:0.34f:1.45f:0.64f:1.0f];
}

static BOOL ExteriaMusicComponents(UIColor *color, CGFloat out[4]) {
    CGColorRef ref = color.CGColor;
    size_t count = CGColorGetNumberOfComponents(ref);
    const CGFloat *c = CGColorGetComponents(ref);
    if (count == 4) {
        for (int i = 0; i < 4; ++i) out[i] = c[i];
        return YES;
    }
    if (count == 2) {
        out[0] = out[1] = out[2] = c[0];
        out[3] = c[1];
        return YES;
    }
    return NO;
}

/* the tone a share of over lies at on top of base, how the tonal surfaces of the scheme are made from one accent */
static UIColor *ExteriaMusicBlend(UIColor *base, UIColor *over, CGFloat share) {
    CGFloat a[4], b[4];
    if (!ExteriaMusicComponents(base, a) || !ExteriaMusicComponents(over, b)) return over;
    return [UIColor colorWithRed:a[0] + (b[0] - a[0]) * share green:a[1] + (b[1] - a[1]) * share blue:a[2] + (b[2] - a[2]) * share alpha:1];
}

UIColor *ExteriaMusicSurfaceColor(void) { return ExteriaMusicBlend(ExteriaColorCard(), ExteriaColorAccent(), ExteriaThemeIsDark() ? 0.1f : 0.07f); }
UIColor *ExteriaMusicTonalColor(void) { return ExteriaMusicBlend(ExteriaColorCard(), ExteriaColorAccent(), ExteriaThemeIsDark() ? 0.34f : 0.2f); }

@implementation ExteriaMusicKey

- (void)morphToRadius:(CGFloat)radius duration:(CFTimeInterval)duration timing:(CAMediaTimingFunction *)timing {
    CALayer *shown = [self.layer presentationLayer];
    CGFloat from = (shown ? shown : self.layer).cornerRadius;
    [self.layer removeAnimationForKey:ExteriaMusicRadiusKey];
    self.layer.cornerRadius = radius;
    if (from == radius || self.window == nil || ExteriaReduceMotionEnabled()) return;
    CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
    morph.fromValue = [NSNumber numberWithFloat:(float)from];
    morph.toValue = [NSNumber numberWithFloat:(float)radius];
    morph.duration = duration;
    morph.timingFunction = timing;
    [self.layer addAnimation:morph forKey:ExteriaMusicRadiusKey];
}

- (void)setRestRadius:(CGFloat)radius animated:(BOOL)animated {
    _restRadius = radius;
    if (animated) [self morphToRadius:radius duration:0.5 timing:ExteriaMusicSpring()];
    else {
        [self.layer removeAnimationForKey:ExteriaMusicRadiusKey];
        self.layer.cornerRadius = radius;
    }
}

- (void)setHighlighted:(BOOL)highlighted {
    BOOL was = self.highlighted;
    [super setHighlighted:highlighted];
    if (was == highlighted) return;
    if (highlighted) [self morphToRadius:MIN(_restRadius, 12) duration:0.12 timing:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    else [self morphToRadius:_restRadius duration:0.45 timing:ExteriaMusicSpring()];
}

@end

