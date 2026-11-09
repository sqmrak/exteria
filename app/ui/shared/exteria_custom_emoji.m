#import "exteria_custom_emoji.h"

#import "exteria_platform.h"
#import "exteria_image_decoder.h"
#import "exteria_animation.h"
#import <QuartzCore/QuartzCore.h>

#define PICTURE_POINTS 24.0
#define BADGE_POINTS 48.0
#define PICTURE_COUNT_MAX 400

NSString *const ExteriaCustomEmojiDidLoadNotification = @"ExteriaCustomEmojiDidLoad";

static NSCache *ExteriaCustomPictures(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = PICTURE_COUNT_MAX;
        cache.totalCostLimit = 16 * 1024 * 1024;
    });
    return cache;
}

static NSMutableSet *ExteriaCustomSet(NSMutableSet **slot) {
    if (!*slot) *slot = [[NSMutableSet alloc] init];
    return *slot;
}

static NSMutableSet *ExteriaLoading;
/* the documents that did not come, with the time they failed: a lost packet, a flood wait or a dead connection looks the same as a document the server does not have,
   and a failure that stayed for the whole run left emoji blank until the app was restarted */
static NSMutableDictionary *ExteriaFailed;
#define FAILED_RETRY_SECONDS 60.0

static UIImage *ExteriaTelegramVerifiedImage(void) {
    static UIImage *image;
    if (image) return image;
    CGFloat side = PICTURE_POINTS, center = side / 2;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, ExteriaScreenScale());
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextMoveToPoint(context, center, center - side * 0.46);
    for (int i = 1; i <= 24; ++i) {
        CGFloat angle = -M_PI_2 + (CGFloat)i * (CGFloat)M_PI / 12;
        CGFloat radius = side * (i % 2 ? 0.40 : 0.46);
        CGContextAddLineToPoint(context, center + cos(angle) * radius, center + sin(angle) * radius);
    }
    CGContextClosePath(context);
    CGContextSetRGBFillColor(context, 0.20, 0.65, 0.91, 1);
    CGContextFillPath(context);
    CGContextSetRGBStrokeColor(context, 1, 1, 1, 1);
    CGContextSetLineWidth(context, side * 0.10);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextMoveToPoint(context, side * 0.29, side * 0.50);
    CGContextAddLineToPoint(context, side * 0.43, side * 0.64);
    CGContextAddLineToPoint(context, side * 0.71, side * 0.36);
    CGContextStrokePath(context);
    image = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return image;
}

/* the Premium star of Telegram for Android (the white shape of its list star), filled with the blue to violet of the Premium mark and drawn once at the size the pictures use */
static UIImage *ExteriaPremiumStarImage(void) {
    static UIImage *star;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"badge_premium_star" ofType:@"png"];
        UIImage *shape = path ? [UIImage imageWithContentsOfFile:path] : nil;
        if (!shape) {
            NSLog(@"exteria: the premium star picture is missing from the bundle");
            return;
        }
        CGFloat side = PICTURE_POINTS;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, ExteriaScreenScale());
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        /* the shape goes down first, and the gradient is drawn over it where it already has paint */
        CGFloat width = side * 0.86, height = width * shape.size.height / shape.size.width;
        [shape drawInRect:CGRectMake((side - width) / 2, (side - height) / 2, width, height)];
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
    CGFloat side = BADGE_POINTS;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, ExteriaScreenScale());
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [source drawInRect:CGRectMake(0, 0, side, side)];
    *slot = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return *slot;
}

#pragma mark animation

#define ANIMATION_COST_LIMIT (12 * 1024 * 1024)
#define ANIMATION_FPS 15

@interface ExteriaEmojiFrames : NSObject {
@public
    NSArray *frames;
    NSTimeInterval duration;
}
@end

@implementation ExteriaEmojiFrames
- (void)dealloc {
    [frames release];
    [super dealloc];
}
@end

static NSCache *ExteriaAnimations(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.totalCostLimit = ANIMATION_COST_LIMIT;
    });
    return cache;
}

static NSUInteger sAnimatedDraws;

NSUInteger ExteriaCustomEmojiAnimatedDraws(void) { return sAnimatedDraws; }

/* one display link for every animated emoji on screen: it runs while views are waiting for a tick and stops when none is */
@interface ExteriaEmojiClock : NSObject {
    CADisplayLink *_link;
    NSMutableSet *_views;
}
+ (ExteriaEmojiClock *)shared;
- (void)keep:(UIView *)view;
@end

@implementation ExteriaEmojiClock

+ (ExteriaEmojiClock *)shared {
    static ExteriaEmojiClock *clock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ clock = [[ExteriaEmojiClock alloc] init]; });
    return clock;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _views = [[NSMutableSet alloc] init];
    return self;
}

- (void)keep:(UIView *)view {
    [_views addObject:view];
    if (_link) return;
    _link = [[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];
    ExteriaSetFrameRate(_link, ANIMATION_FPS);
    /* not in the common modes: while a finger drags or a list decelerates the run loop is in the tracking mode, and every row with an animated emoji drawing again fifteen times a second
       is what an iPhone 5 could not keep up with while scrolling the chat list; the emoji stand still for the scroll and go on after it */
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    NSSet *waiting = [[_views copy] autorelease];
    [_views removeAllObjects];
    for (UIView *view in waiting) {
        if (view.window && !view.hidden && view.alpha > 0.01) [view setNeedsDisplay];
    }
    /* a view that drew an emoji again has put itself back by now only if it was drawn, which happens after this tick; the link stays for the next one and ends when nobody came back */
    if (!waiting.count) {
        [_link invalidate];
        [_link release];
        _link = nil;
    }
}

@end

@implementation ExteriaCustomEmoji

+ (void)setAnimationFrames:(NSArray *)frames duration:(NSTimeInterval)duration forDocument:(long long)document {
    if (frames.count < 2 || duration <= 0) return;
    ExteriaEmojiFrames *holder = [[[ExteriaEmojiFrames alloc] init] autorelease];
    holder->frames = [frames copy];
    holder->duration = duration;
    NSUInteger cost = 0;
    for (UIImage *frame in frames) cost += CGImageGetBytesPerRow(frame.CGImage) * CGImageGetHeight(frame.CGImage);
    [ExteriaAnimations() setObject:holder forKey:[NSNumber numberWithLongLong:document] cost:cost];
}

+ (BOOL)hasAnimationForDocument:(long long)document {
    return [ExteriaAnimations() objectForKey:[NSNumber numberWithLongLong:document]] != nil;
}

+ (void)keepAnimatingView:(UIView *)view {
    [[ExteriaEmojiClock shared] keep:view];
}

+ (UIImage *)imageForDocument:(long long)document {
    if (document == EXTERIA_TELEGRAM_VERIFIED_DOCUMENT) return ExteriaTelegramVerifiedImage();
    if (document == EXTERIA_PREMIUM_STAR_DOCUMENT) return ExteriaPremiumStarImage();
    static UIImage *hammer, *fox, *net, *hammers, *promotion, *bugHunter, *officialTester, *manager, *videoFix, *flawSeer;
    if (document == EXTERIA_BUG_HUNTER_DOCUMENT) {
        if (!bugHunter) {
            NSString *path = [[NSBundle mainBundle] pathForResource:@"badge_bug_hunter" ofType:@"png"];
            if (path) bugHunter = [ExteriaDecodeImageAtURL([NSURL fileURLWithPath:path], BADGE_POINTS * ExteriaScreenScale()) retain];
            if (!bugHunter) NSLog(@"exteria: the bug hunter badge picture could not be decoded");
        }
        return bugHunter;
    }
    if (document == EXTERIA_OFFICIAL_TESTER_DOCUMENT) return ExteriaBundledBadge(@"badge_official_tester", &officialTester);
    if (document == EXTERIA_FLAW_SEER_DOCUMENT) return ExteriaBundledBadge(@"badge_flaw_seer", &flawSeer);
    if (document == EXTERIA_MANAGER_DOCUMENT) return ExteriaBundledBadge(@"badge_manager", &manager);
    if (document == EXTERIA_VIDEO_FIX_DOCUMENT) return ExteriaBundledBadge(@"badge_videofix", &videoFix);
    if (document == EXTERIA_PROMOTION_DOCUMENT) return ExteriaBundledBadge(@"badge_promotion", &promotion);
    if (document == EXTERIA_DEVELOPER_DOCUMENT) return ExteriaBundledBadge(@"badge_developer", &hammer);
    if (document == EXTERIA_LEAD_DOCUMENT) return ExteriaBundledBadge(@"badge_lead", &hammers);
    if (document == EXTERIA_TESTER_DOCUMENT) return ExteriaBundledBadge(@"badge_tester", &net);
    if (document == EXTERIA_SENKO_DOCUMENT) return ExteriaBundledBadge(@"badge_senko", &fox);
    ExteriaEmojiFrames *animated = [ExteriaAnimations() objectForKey:[NSNumber numberWithLongLong:document]];
    if (animated && !ExteriaReduceMotionEnabled()) {
        /* every emoji of a document shows the same frame at the same moment, which is what the clock of the process gives */
        double phase = fmod(CACurrentMediaTime(), animated->duration) / animated->duration;
        NSUInteger index = MIN(animated->frames.count - 1, (NSUInteger)(phase * (double)animated->frames.count));
        ++sAnimatedDraws;
        return [animated->frames objectAtIndex:index];
    }
    return [ExteriaCustomPictures() objectForKey:[NSNumber numberWithLongLong:document]];
}

+ (UIImage *)stillImageForDocument:(long long)document {
    UIImage *still = [ExteriaCustomPictures() objectForKey:[NSNumber numberWithLongLong:document]];
    return still ? still : [self imageForDocument:document];
}

+ (void)replaceStillImage:(UIImage *)image forDocument:(long long)document {
    CGImageRef bitmap = image.CGImage;
    if (!bitmap) return;
    NSUInteger cost = CGImageGetBytesPerRow(bitmap) * CGImageGetHeight(bitmap);
    [ExteriaCustomPictures() setObject:image forKey:[NSNumber numberWithLongLong:document] cost:cost];
}

+ (BOOL)needsLoad:(long long)document {
    NSNumber *key = [NSNumber numberWithLongLong:document];
    if ([ExteriaCustomPictures() objectForKey:key] || [ExteriaCustomSet(&ExteriaLoading) containsObject:key]) return NO;
    NSDate *failed = [ExteriaFailed objectForKey:key];
    if (!failed) return YES;
    if (-[failed timeIntervalSinceNow] < FAILED_RETRY_SECONDS) return NO;
    [ExteriaFailed removeObjectForKey:key];
    return YES;
}

+ (void)abandonLoad:(long long)document {
    [ExteriaCustomSet(&ExteriaLoading) removeObject:[NSNumber numberWithLongLong:document]];
}

+ (void)beginLoad:(long long)document {
    [ExteriaCustomSet(&ExteriaLoading) addObject:[NSNumber numberWithLongLong:document]];
}

+ (void)finishLoad:(long long)document image:(UIImage *)image {
    NSNumber *key = [NSNumber numberWithLongLong:document];
    [ExteriaCustomSet(&ExteriaLoading) removeObject:key];
    /* custom documents have unrelated transparent canvas margins */
    if (image) {
        UIImage *fitted = ExteriaFitEmojiImage(image);
        CGImageRef bitmap = fitted.CGImage;
        NSUInteger cost = bitmap ? CGImageGetBytesPerRow(bitmap) * CGImageGetHeight(bitmap) : 0;
        [ExteriaCustomPictures() setObject:fitted forKey:key cost:cost];
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaCustomEmojiDidLoadNotification object:key];
    }
    else {
        if (!ExteriaFailed) ExteriaFailed = [[NSMutableDictionary alloc] init];
        [ExteriaFailed setObject:[NSDate date] forKey:key];
    }
}

+ (CGFloat)pictureSide {
    /* ExteriaFitEmojiImage trims the empty margin and enlarges what is left, up to a third, and a topic icon is drawn 48 points wide: the extra decoded
       pixels are what that enlargement and the row use */
    return 64.0 * ExteriaScreenScale();
}

@end
