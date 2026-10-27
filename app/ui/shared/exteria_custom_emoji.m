#import "exteria_custom_emoji.h"

#import "exteria_platform.h"
#import "exteria_image_decoder.h"

#define PICTURE_POINTS 24.0
#define PICTURE_COUNT_MAX 400

NSString *const ExteriaCustomEmojiDidLoadNotification = @"ExteriaCustomEmojiDidLoad";

static NSCache *ExteriaCustomPictures(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = PICTURE_COUNT_MAX;
    });
    return cache;
}

static NSMutableSet *ExteriaCustomSet(NSMutableSet **slot) {
    if (!*slot) *slot = [[NSMutableSet alloc] init];
    return *slot;
}

static NSMutableSet *ExteriaLoading;
static NSMutableSet *ExteriaFailed;

/* a five pointed star with rounded corners in the blue to violet of the Premium mark, drawn once at the size the pictures use */
static UIImage *ExteriaPremiumStarImage(void) {
    static UIImage *star;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGFloat side = PICTURE_POINTS;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, ExteriaScreenScale());
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGFloat radius = side * 0.40, inner = radius * 0.50, round = side * 0.05;
        CGMutablePathRef path = CGPathCreateMutable();
        for (int i = 0; i < 10; ++i) {
            CGFloat angle = -M_PI_2 + (CGFloat)i * M_PI / 5;
            CGFloat r = (i % 2 ? inner : radius) - round;
            CGPoint point = CGPointMake(side / 2 + cos(angle) * r, side / 2 + sin(angle) * r + side * 0.02);
            if (i) CGPathAddLineToPoint(path, NULL, point.x, point.y);
            else CGPathMoveToPoint(path, NULL, point.x, point.y);
        }
        CGPathCloseSubpath(path);
        /* the shape goes down in white, and the gradient is drawn over it where it already has paint */
        CGContextSetLineJoin(context, kCGLineJoinRound);
        CGContextSetLineWidth(context, round * 2);
        CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextAddPath(context, path);
        CGContextDrawPath(context, kCGPathFillStroke);
        CGPathRelease(path);
        CGContextSetBlendMode(context, kCGBlendModeSourceIn);
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat colors[8] = {0.33, 0.62, 1.0, 1.0, 0.74, 0.36, 1.0, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
        CGContextDrawLinearGradient(context, gradient, CGPointMake(side * 0.2, 0), CGPointMake(side * 0.8, side), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        star = [UIGraphicsGetImageFromCurrentImageContext() retain];
        UIGraphicsEndImageContext();
    });
    return star;
}

/* a bundled badge drawn once at the size the pictures use; the file is larger than any screen needs, so the
   context does the scaling */
static UIImage *ExteriaBundledBadge(NSString *name, UIImage **slot) {
    if (*slot) return *slot;
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    UIImage *source = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!source) {
        NSLog(@"exteria: the badge picture %@ is missing from the bundle", name);
        return nil;
    }
    CGFloat side = PICTURE_POINTS;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, ExteriaScreenScale());
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [source drawInRect:CGRectMake(0, 0, side, side)];
    *slot = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return *slot;
}

@implementation ExteriaCustomEmoji

+ (UIImage *)imageForDocument:(long long)document {
    if (document == EXTERIA_PREMIUM_STAR_DOCUMENT) return ExteriaPremiumStarImage();
    static UIImage *hammer, *fox, *net, *hammers, *caution, *promotion;
    if (document == EXTERIA_PROMOTION_DOCUMENT) return ExteriaBundledBadge(@"badge_promotion", &promotion);
    if (document == EXTERIA_CAUTION_DOCUMENT) {
        if (!caution) {
            NSString *path = [[NSBundle mainBundle] pathForResource:@"badge_caution" ofType:@"png"];
            if (path) caution = [ExteriaDecodeImageAtURL([NSURL fileURLWithPath:path],
                PICTURE_POINTS * EXTERIA_CAUTION_BADGE_RATIO * ExteriaScreenScale()) retain];
            if (!caution) NSLog(@"exteria: the caution badge picture could not be decoded");
        }
        return caution;
    }
    if (document == EXTERIA_DEVELOPER_DOCUMENT) return ExteriaBundledBadge(@"badge_developer", &hammer);
    if (document == EXTERIA_LEAD_DOCUMENT) return ExteriaBundledBadge(@"badge_lead", &hammers);
    if (document == EXTERIA_TESTER_DOCUMENT) return ExteriaBundledBadge(@"badge_tester", &net);
    if (document == EXTERIA_SENKO_DOCUMENT) return ExteriaBundledBadge(@"badge_senko", &fox);
    return [ExteriaCustomPictures() objectForKey:[NSNumber numberWithLongLong:document]];
}

+ (BOOL)needsLoad:(long long)document {
    NSNumber *key = [NSNumber numberWithLongLong:document];
    return ![ExteriaCustomPictures() objectForKey:key] && ![ExteriaCustomSet(&ExteriaLoading) containsObject:key] &&
           ![ExteriaCustomSet(&ExteriaFailed) containsObject:key];
}

+ (void)beginLoad:(long long)document {
    [ExteriaCustomSet(&ExteriaLoading) addObject:[NSNumber numberWithLongLong:document]];
}

+ (void)finishLoad:(long long)document image:(UIImage *)image {
    NSNumber *key = [NSNumber numberWithLongLong:document];
    [ExteriaCustomSet(&ExteriaLoading) removeObject:key];
    /* custom documents have unrelated transparent canvas margins */
    if (image) {
        [ExteriaCustomPictures() setObject:ExteriaFitEmojiImage(image) forKey:key];
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaCustomEmojiDidLoadNotification object:key];
    }
    else [ExteriaCustomSet(&ExteriaFailed) addObject:key];
}

+ (CGFloat)pictureSide {
    return PICTURE_POINTS * ExteriaScreenScale();
}

@end
