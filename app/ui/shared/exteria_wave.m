#import "exteria_wave.h"

#import <math.h>

#define EXTERIA_WAVE_STEPS 96

void ExteriaAddWaveEdge(CGMutablePathRef path, CGPoint from, CGPoint control, CGPoint to,
                        CGFloat amplitude, CGFloat ripples) {
    for (int i = 1; i <= EXTERIA_WAVE_STEPS; ++i) {
        CGFloat t = (CGFloat)i / EXTERIA_WAVE_STEPS;
        CGFloat u = 1 - t;
        CGFloat x = u * u * from.x + 2 * u * t * control.x + t * t * to.x;
        CGFloat y = u * u * from.y + 2 * u * t * control.y + t * t * to.y;
        CGFloat dx = 2 * u * (control.x - from.x) + 2 * t * (to.x - control.x);
        CGFloat dy = 2 * u * (control.y - from.y) + 2 * t * (to.y - control.y);
        CGFloat length = sqrt(dx * dx + dy * dy);
        CGFloat offset = amplitude * sin(2 * M_PI * ripples * t) * sin(M_PI * t);
        if (length > 0) {
            x += -dy / length * offset;
            y += dx / length * offset;
        }
        CGPathAddLineToPoint(path, NULL, x, y);
    }
}

/* colors are rgba quadruples spread evenly along the line */
void ExteriaFillGradient(CGContextRef context, CGPoint from, CGPoint to,
                         const CGFloat *colors, size_t count) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, count);
    if (gradient) {
        CGContextDrawLinearGradient(context, gradient, from, to,
                                    kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient);
    }
    CGColorSpaceRelease(space);
}
