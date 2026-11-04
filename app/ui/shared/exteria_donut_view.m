#import "exteria_donut_view.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_animation.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define MAX_SEGMENTS 8
#define SLIDE_SECONDS 0.3
/* the gap between two arcs, and how far the rounded corners of an arc reach into its own area */
#define ARC_GAP 3.0
#define ARC_CORNER 2.5
#define RING_SHARE 0.44
/* an arc narrower than this share of the ring has no room for its number */
#define LABEL_MIN_SHARE 0.05

@interface ExteriaDonutView () {
    CGFloat _shown[MAX_SEGMENTS];
    CGFloat _from[MAX_SEGMENTS];
    CGFloat _to[MAX_SEGMENTS];
    NSUInteger _count;
    NSArray *_colors;
    NSString *_amount;
    NSString *_unit;
    CADisplayLink *_link;
    CFTimeInterval _began;
}
@end

@implementation ExteriaDonutView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.isAccessibilityElement = YES;
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_colors release];
    [_amount release];
    [_unit release];
    [super dealloc];
}

- (void)stopSliding {
    [_link invalidate];
    _link = nil;
}

- (void)setValues:(NSArray *)values colors:(NSArray *)colors amount:(NSString *)amount unit:(NSString *)unit animated:(BOOL)animated {
    NSUInteger count = MIN(MIN(values.count, colors.count), (NSUInteger)MAX_SEGMENTS);
    /* a count that changed means other arcs, so the old sizes say nothing about the new ones */
    BOOL sameArcs = count == _count;
    for (NSUInteger i = 0; i < MAX_SEGMENTS; ++i) {
        _from[i] = sameArcs ? _shown[i] : 0;
        _to[i] = i < count ? (CGFloat)[[values objectAtIndex:i] doubleValue] : 0;
        if (!sameArcs) _shown[i] = 0;
    }
    _count = count;
    [_colors release];
    _colors = [colors copy];
    [_amount release];
    _amount = [amount copy];
    [_unit release];
    _unit = [unit copy];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", amount ? amount : @"", unit ? unit : @""];
    [self stopSliding];
    if (animated && self.window && !ExteriaReduceMotionEnabled()) {
        _began = CACurrentMediaTime();
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(slide:)];
        ExteriaSetFrameRate(_link, 60);
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } else {
        for (NSUInteger i = 0; i < MAX_SEGMENTS; ++i) _shown[i] = _to[i];
    }
    [self setNeedsDisplay];
}

- (void)slide:(CADisplayLink *)link {
    (void)link;
    CGFloat t = (CGFloat)((CACurrentMediaTime() - _began) / SLIDE_SECONDS);
    if (t >= 1) {
        for (NSUInteger i = 0; i < MAX_SEGMENTS; ++i) _shown[i] = _to[i];
        [self stopSliding];
    } else {
        CGFloat eased = 1 - (1 - t) * (1 - t) * (1 - t);
        for (NSUInteger i = 0; i < MAX_SEGMENTS; ++i) _shown[i] = _from[i] + (_to[i] - _from[i]) * eased;
    }
    [self setNeedsDisplay];
}

- (void)willMoveToWindow:(UIWindow *)window {
    [super willMoveToWindow:window];
    if (window) return;
    /* a link that outlives the screen would keep this view alive and draw it for nobody */
    [self stopSliding];
    for (NSUInteger i = 0; i < MAX_SEGMENTS; ++i) _shown[i] = _to[i];
}

- (void)drawArc:(CGContextRef)context from:(CGFloat)start to:(CGFloat)end center:(CGPoint)center outer:(CGFloat)outer inner:(CGFloat)inner color:(UIColor *)color {
    CGFloat sweep = end - start;
    CGFloat corner = MIN(ARC_CORNER, inner * sweep / 6);
    CGFloat gap = MIN(ARC_GAP, inner * sweep / 3);
    CGFloat ro = outer - corner, ri = inner + corner;
    /* the same linear gap at both edges of the arc, so the arcs stay parallel instead of leaving a wedge */
    CGFloat margin = gap / 2 + corner;
    CGFloat a0o = start + margin / ro, a1o = end - margin / ro, a0i = start + margin / ri, a1i = end - margin / ri;
    if (a1o <= a0o || a1i <= a0i) return;
    CGContextBeginPath(context);
    CGContextAddArc(context, center.x, center.y, ro, a0o, a1o, 0);
    CGContextAddLineToPoint(context, center.x + ri * cos(a1i), center.y + ri * sin(a1i));
    CGContextAddArc(context, center.x, center.y, ri, a1i, a0i, 1);
    CGContextClosePath(context);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, 2 * corner);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextDrawPath(context, kCGPathFillStroke);
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat outer = side / 2, inner = outer * (1 - RING_SHARE), middle = (outer + inner) / 2;
    CGFloat sum = 0;
    NSUInteger drawn = 0;
    for (NSUInteger i = 0; i < _count; ++i) {
        sum += _shown[i];
        if (_shown[i] > 0) ++drawn;
    }
    if (sum <= 0) {
        /* nothing stored: a quiet ring, so the screen still has its shape */
        CGContextSetStrokeColorWithColor(context, ExteriaColorHairline().CGColor);
        CGContextSetLineWidth(context, outer - inner);
        CGContextAddArc(context, center.x, center.y, middle, 0, 2 * M_PI, 0);
        CGContextStrokePath(context);
    }
    CGFloat angle = -M_PI / 2;
    for (NSUInteger i = 0; i < _count && sum > 0; ++i) {
        if (_shown[i] <= 0) continue;
        CGFloat share = _shown[i] / sum, sweep = 2 * M_PI * share;
        UIColor *color = [_colors objectAtIndex:i];
        if (drawn == 1) {
            CGFloat ro = outer, ri = inner;
            CGContextBeginPath(context);
            CGContextAddEllipseInRect(context, CGRectMake(center.x - ro, center.y - ro, 2 * ro, 2 * ro));
            CGContextAddEllipseInRect(context, CGRectMake(center.x - ri, center.y - ri, 2 * ri, 2 * ri));
            CGContextSetFillColorWithColor(context, color.CGColor);
            CGContextEOFillPath(context);
        } else {
            [self drawArc:context from:angle to:angle + sweep center:center outer:outer inner:inner color:color];
        }
        if (share >= LABEL_MIN_SHARE) {
            NSString *text = [NSString stringWithFormat:@"%d%%", (int)floor(share * 100 + 0.5)];
            UIFont *font = ExteriaFontBold(side * 0.095);
            CGSize size = [text sizeWithFont:font];
            CGFloat mid = angle + sweep / 2;
            [[UIColor whiteColor] set];
            [text drawAtPoint:CGPointMake(center.x + middle * cos(mid) - size.width / 2, center.y + middle * sin(mid) - size.height / 2) withFont:font];
        }
        angle += sweep;
    }
    if (!_amount.length) return;
    UIFont *big = ExteriaFontBold(side * 0.165), *small = ExteriaFontSemibold(side * 0.07);
    CGSize bigSize = [_amount sizeWithFont:big], smallSize = [_unit sizeWithFont:small];
    CGFloat top = center.y - (bigSize.height + smallSize.height) / 2 + side * 0.015;
    [ExteriaColorTitle() set];
    [_amount drawAtPoint:CGPointMake(center.x - bigSize.width / 2, top) withFont:big];
    [ExteriaColorSecondary() set];
    [_unit drawAtPoint:CGPointMake(center.x - smallSize.width / 2, top + bigSize.height - side * 0.02) withFont:small];
}

@end
