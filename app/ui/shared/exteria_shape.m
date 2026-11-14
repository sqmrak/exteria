#import "exteria_shape.h"

#import <QuartzCore/QuartzCore.h>

#define OUTLINE_POINTS 240

static const CGFloat ExteriaPi = (CGFloat)M_PI;

BOOL ExteriaShapeIsOutline(ExteriaShape shape) {
    return shape != ExteriaShapeRounded && shape != ExteriaShapeCircle && (NSUInteger)shape < ExteriaShapeCount;
}

/* the distance of the outline from the middle at an angle, for the shapes that follow a wave; the lobes reach in from the unit circle, and the radius is scaled so the
   farthest point is on it */
static CGFloat ExteriaLobeRadius(ExteriaShape shape, CGFloat angle) {
    switch (shape) {
    case ExteriaShapeCookie: return (1 + 0.06f * cosf(9 * angle)) / 1.06f;
    case ExteriaShapeSunny: return (1 + 0.12f * cosf(8 * angle)) / 1.12f;
    case ExteriaShapeClover: return (1 + 0.24f * cosf(4 * angle)) / 1.24f;
    case ExteriaShapeFlower: return (1 + 0.2f * cosf(6 * angle)) / 1.2f;
    /* sharp tips with rounded valleys: ten of them */
    case ExteriaShapeBurst: return 1 - 0.18f * fabsf(sinf(5 * angle));
    default: return 1;
    }
}

/* a regular polygon with rounded corners, the first vertex at the top, as points in the unit square: the corners are arcs of the radius fraction rc of the apothem */
static void ExteriaRoundedPolygon(NSMutableArray *points, int sides, CGFloat rc, CGFloat turn) {
    CGFloat apothem = cosf(ExteriaPi / sides);
    CGFloat radius = rc * apothem;
    /* the center of a corner arc lies on the line to the vertex, where the circle of that radius touches both edges */
    CGFloat centerDistance = 1 - radius / apothem;
    CGFloat sweep = 2 * ExteriaPi / sides;
    for (int i = 0; i < sides; ++i) {
        CGFloat direction = -ExteriaPi / 2 + turn + sweep * i;
        CGPoint center = CGPointMake(centerDistance * cosf(direction), centerDistance * sinf(direction));
        for (int step = 0; step <= 12; ++step) {
            CGFloat angle = direction - sweep / 2 + sweep * step / 12;
            [points addObject:[NSValue valueWithCGPoint:CGPointMake(center.x + radius * cosf(angle), center.y + radius * sinf(angle))]];
        }
    }
}

/* the outline of a shape in the square from -1 to 1, kept for the next call */
static NSArray *ExteriaUnitOutline(ExteriaShape shape) {
    static NSArray *kept[ExteriaShapeCount];
    @synchronized (@"exteria.shape.outline") {
        if (kept[shape]) return kept[shape];
        NSMutableArray *points = [NSMutableArray arrayWithCapacity:OUTLINE_POINTS];
        switch (shape) {
        case ExteriaShapePentagon: ExteriaRoundedPolygon(points, 5, 0.34f, 0); break;
        /* the gem is a square stood on a corner, with its corners rounded */
        case ExteriaShapeGem: ExteriaRoundedPolygon(points, 4, 0.34f, 0); break;
        default:
            for (int i = 0; i < OUTLINE_POINTS; ++i) {
                CGFloat angle = 2 * ExteriaPi * i / OUTLINE_POINTS - ExteriaPi / 2;
                CGFloat radius = ExteriaLobeRadius(shape, angle);
                [points addObject:[NSValue valueWithCGPoint:CGPointMake(radius * cosf(angle), radius * sinf(angle))]];
            }
        }
        kept[shape] = [points copy];
        return kept[shape];
    }
}

UIBezierPath *ExteriaShapePath(ExteriaShape shape, CGRect box, NSInteger cornerPercent) {
    CGFloat side = MIN(box.size.width, box.size.height);
    CGRect square = CGRectMake(CGRectGetMidX(box) - side / 2, CGRectGetMidY(box) - side / 2, side, side);
    if (!ExteriaShapeIsOutline(shape)) {
        CGFloat percent = shape == ExteriaShapeCircle ? 100 : (CGFloat)MAX(0, MIN(100, cornerPercent));
        return [UIBezierPath bezierPathWithRoundedRect:square cornerRadius:side * percent / 200];
    }
    NSArray *points = ExteriaUnitOutline(shape);
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat half = side / 2;
    for (NSUInteger i = 0; i < points.count; ++i) {
        CGPoint unit = [[points objectAtIndex:i] CGPointValue];
        CGPoint point = CGPointMake(CGRectGetMidX(square) + unit.x * half, CGRectGetMidY(square) + unit.y * half);
        if (i == 0) [path moveToPoint:point];
        else [path addLineToPoint:point];
    }
    [path closePath];
    return path;
}

CGFloat ExteriaShapePathLength(ExteriaShape shape, CGRect box) {
    CGFloat side = MIN(box.size.width, box.size.height);
    if (!ExteriaShapeIsOutline(shape)) return shape == ExteriaShapeCircle ? ExteriaPi * side : 4 * side;
    NSArray *points = ExteriaUnitOutline(shape);
    CGFloat length = 0;
    for (NSUInteger i = 0; i < points.count; ++i) {
        CGPoint a = [[points objectAtIndex:i] CGPointValue], b = [[points objectAtIndex:(i + 1) % points.count] CGPointValue];
        length += hypotf(b.x - a.x, b.y - a.y);
    }
    return length * side / 2;
}

void ExteriaApplyShapeToLayer(CALayer *layer, ExteriaShape shape, CGFloat side, NSInteger cornerPercent) {
    if (ExteriaShapeIsOutline(shape)) {
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.path = ExteriaShapePath(shape, CGRectMake(0, 0, side, side), 0).CGPath;
        layer.mask = mask;
        layer.cornerRadius = 0;
        return;
    }
    layer.mask = nil;
    layer.cornerRadius = side * (shape == ExteriaShapeCircle ? 100 : MAX(0, MIN(100, cornerPercent))) / 200;
}
