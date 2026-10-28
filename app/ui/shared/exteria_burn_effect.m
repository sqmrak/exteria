#import <QuartzCore/QuartzCore.h>
#import "exteria_burn_effect.h"

#import "exteria_platform.h"

/* how long the emitter keeps making sparks; the rest of the duration is for the last ones to fade */
#define BURST_SECONDS 0.35
#define SPARK_SIDE 8.0

static CGImageRef ExteriaSparkImage(void) {
    static CGImageRef spark;
    if (spark) return spark;
    CGFloat scale = ExteriaScreenScale();
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(SPARK_SIDE, SPARK_SIDE), NO, scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat colors[8] = {1, 1, 1, 1, 1, 1, 1, 0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
    CGContextDrawRadialGradient(context, gradient, CGPointMake(SPARK_SIDE / 2, SPARK_SIDE / 2), 0, CGPointMake(SPARK_SIDE / 2, SPARK_SIDE / 2), SPARK_SIDE / 2, 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    spark = CGImageRetain(UIGraphicsGetImageFromCurrentImageContext().CGImage);
    UIGraphicsEndImageContext();
    return spark;
}

@interface ExteriaBurnTarget : NSObject
+ (void)finish:(NSDictionary *)state;
@end

@implementation ExteriaBurnTarget
+ (void)finish:(NSDictionary *)state {
    CALayer *layer = [state objectForKey:@"layer"];
    void (^completion)(void) = [state objectForKey:@"completion"];
    [layer removeFromSuperlayer];
    if (completion) completion();
}
@end

@implementation ExteriaBurnEffect

+ (void)burnRect:(CGRect)rect inView:(UIView *)view duration:(NSTimeInterval)duration completion:(void (^)(void))completion {
    CGImageRef image = ExteriaSparkImage();
    if (!view || CGRectIsEmpty(rect) || !image || duration <= BURST_SECONDS) {
        if (completion) completion();
        return;
    }
    CAEmitterLayer *emitter = [CAEmitterLayer layer];
    emitter.frame = rect;
    emitter.emitterPosition = CGPointMake(CGRectGetWidth(rect) / 2, CGRectGetHeight(rect) / 2);
    emitter.emitterSize = rect.size;
    emitter.emitterShape = kCAEmitterLayerRectangle;
    emitter.emitterMode = kCAEmitterLayerOutline;
    emitter.renderMode = kCAEmitterLayerAdditive;
    NSMutableArray *cells = [NSMutableArray array];
    /* embers: warm sparks that rise a little and shrink, and ash: pale ones that drift down */
    CGFloat tints[2][3] = {{1.0f, 0.62f, 0.18f}, {0.85f, 0.85f, 0.9f}};
    for (int i = 0; i < 2; ++i) {
        CAEmitterCell *cell = [CAEmitterCell emitterCell];
        cell.contents = (id)image;
        cell.color = [UIColor colorWithRed:tints[i][0] green:tints[i][1] blue:tints[i][2] alpha:1].CGColor;
        cell.birthRate = i == 0 ? 220 : 120;
        cell.lifetime = (float)(duration - BURST_SECONDS);
        cell.lifetimeRange = (float)((duration - BURST_SECONDS) * 0.4);
        cell.velocity = i == 0 ? 46 : 24;
        cell.velocityRange = 28;
        cell.emissionRange = (CGFloat)(2 * M_PI);
        cell.yAcceleration = i == 0 ? -38 : 52;
        cell.scale = 0.9f;
        cell.scaleRange = 0.5f;
        cell.scaleSpeed = -0.6f;
        cell.alphaSpeed = (float)(-1.0 / (duration - BURST_SECONDS));
        [cells addObject:cell];
    }
    emitter.emitterCells = cells;
    [view.layer addSublayer:emitter];
    /* the emitter stops making sparks after the burst, so the area empties from the middle of the animation on */
    CAKeyframeAnimation *rate = [CAKeyframeAnimation animationWithKeyPath:@"birthRate"];
    rate.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:1], [NSNumber numberWithFloat:1], [NSNumber numberWithFloat:0], nil];
    rate.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:BURST_SECONDS / duration], [NSNumber numberWithDouble:BURST_SECONDS / duration + 0.001], nil];
    rate.duration = duration;
    rate.removedOnCompletion = NO;
    rate.fillMode = kCAFillModeForwards;
    [emitter addAnimation:rate forKey:@"burst"];
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithObject:emitter forKey:@"layer"];
    if (completion) [state setObject:[[completion copy] autorelease] forKey:@"completion"];
    [[ExteriaBurnTarget class] performSelector:@selector(finish:) withObject:state afterDelay:duration];
}

@end
