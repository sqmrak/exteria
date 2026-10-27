#import <CoreGraphics/CoreGraphics.h>

/* continues a path with a rippled quadratic curve; the ripple fades out at both ends */
void ExteriaAddWaveEdge(CGMutablePathRef path, CGPoint from, CGPoint control, CGPoint to,
                        CGFloat amplitude, CGFloat ripples);

void ExteriaFillGradient(CGContextRef context, CGPoint from, CGPoint to,
                         const CGFloat *colors, size_t count);
