#import <CoreGraphics/CoreGraphics.h>

#import "exteria_welcome.h"

static inline CGRect ExteriaCGRect(exteria_rect rect) {
    return CGRectMake((CGFloat)rect.x, (CGFloat)rect.y, (CGFloat)rect.width, (CGFloat)rect.height);
}

static inline CGRect ExteriaCGRectOffset(exteria_rect rect, CGFloat dx, CGFloat dy) {
    return CGRectMake((CGFloat)rect.x + dx, (CGFloat)rect.y + dy, (CGFloat)rect.width, (CGFloat)rect.height);
}
