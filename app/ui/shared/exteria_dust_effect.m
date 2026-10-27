#import "exteria_dust_effect.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_lite_mode.h"
#import "exteria_platform.h"

/* match the exteraless Thanos shader's motion in points */
#define TIME_SCALE 1.15
#define WAVE_WIDTH 0.6
#define RAMP 0.2
#define SPEED_MIN 26.0
#define SPEED_SPREAD 26.0
#define PUSH_UP 65.0
#define PUSH_SIDE 19.0
#define PUSH_FADE 0.35
#define LIFE_MIN 0.7
#define LIFE_SPREAD 0.8
#define LIFE_DRAIN 1.2
#define FADE_AT 0.55
/* nothing is left after this much shader time: the last column starts at 0.5, ramps for 0.2 and its longest life drains in about a second */
#define END_TIME 2.4

typedef struct {
    CGFloat x, y, vx, vy, life, wave;
    CALayer *layer;
} ExteriaDustSquare;

@interface ExteriaDustPlayer : NSObject {
    CALayer *_container;
    ExteriaDustSquare *_squares;
    NSUInteger _count;
    CADisplayLink *_link;
    CFTimeInterval _last;
    double _time;
}
- (id)initWithContainer:(CALayer *)container squares:(ExteriaDustSquare *)squares count:(NSUInteger)count;
- (void)start;
@end

@implementation ExteriaDustPlayer

- (id)initWithContainer:(CALayer *)container squares:(ExteriaDustSquare *)squares count:(NSUInteger)count {
    self = [super init];
    if (!self) return nil;
    _container = [container retain];
    _squares = squares;
    _count = count;
    return self;
}

- (void)dealloc {
    [_container release];
    free(_squares);
    [super dealloc];
}

- (void)start {
    /* the display link keeps its target, which is what keeps the player alive until it ends */
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)finish {
    [_link invalidate];
    _link = nil;
    [_container removeFromSuperlayer];
}

- (void)step:(CADisplayLink *)link {
    CFTimeInterval real = _last > 0 ? link.timestamp - _last : 1.0 / 60;
    _last = link.timestamp;
    /* a frame that was held up is stepped as an ordinary one, so the squares never jump */
    if (real > 1.0 / 20) real = 1.0 / 30;
    double delta = real * TIME_SCALE;
    _time += delta;
    double effect = MAX(0, MIN(PUSH_FADE, _time)) / PUSH_FADE;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _count; ++i) {
        ExteriaDustSquare *q = &_squares[i];
        double fraction = MAX(0, MIN(RAMP, 0.1 + _time - q->wave * WAVE_WIDTH)) / RAMP;
        if (fraction > 0) {
            q->x += q->vx * delta * fraction;
            q->y += q->vy * delta * fraction;
            q->vx += PUSH_SIDE * (q->vx > 0 ? 1 : -1) * (1 - effect) * delta * fraction;
            q->vy -= PUSH_UP * delta * fraction;
            q->life = MAX(0, q->life - LIFE_DRAIN * delta * fraction);
            q->layer.position = CGPointMake(q->x, q->y);
            q->layer.opacity = (float)(MIN(FADE_AT, q->life) / FADE_AT);
        }
    }
    [CATransaction commit];
    if (_time > END_TIME) [self finish];
}

@end

UIImage *ExteriaDustSnapshot(UIView *view) {
    CGSize size = view.bounds.size;
    if (size.width < 1 || size.height < 1) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *picture = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return picture;
}

static CGFloat ExteriaDustRandom(void) {
    return (CGFloat)arc4random_uniform(10001) / 10000.0f;
}

static NSUInteger ExteriaDustSquareLimit(void) {
    switch (ExteriaLiteClass()) {
    case EXTERIA_LITE_CLASS_LOW: return 70;
    case EXTERIA_LITE_CLASS_AVERAGE: return 140;
    default: return 240;
    }
}

void ExteriaDustDisperse(UIImage *picture, CGRect frame, UIView *host) {
    if (!picture || !host.window || ![UIView areAnimationsEnabled] || ExteriaReduceMotionEnabled()) return;
    CGImageRef image = picture.CGImage;
    if (!image || frame.size.width < 1 || frame.size.height < 1) return;
    CGFloat side = MAX(4, ceil(sqrt(frame.size.width * frame.size.height / (CGFloat)ExteriaDustSquareLimit())));
    NSUInteger columns = (NSUInteger)ceil(frame.size.width / side), rows = (NSUInteger)ceil(frame.size.height / side);
    ExteriaDustSquare *squares = calloc(columns * rows, sizeof(*squares));
    if (!squares) return;
    CALayer *container = [CALayer layer];
    container.frame = frame;
    container.masksToBounds = NO;
    NSUInteger count = 0;
    for (NSUInteger row = 0; row < rows; ++row) {
        for (NSUInteger column = 0; column < columns; ++column) {
            CGFloat x = column * side, y = row * side;
            CGFloat width = MIN(side, frame.size.width - x), height = MIN(side, frame.size.height - y);
            CALayer *square = [CALayer layer];
            square.bounds = CGRectMake(0, 0, width, height);
            square.position = CGPointMake(x + width / 2, y + height / 2);
            square.contents = (id)image;
            square.contentsScale = picture.scale;
            square.contentsRect = CGRectMake(x / frame.size.width, y / frame.size.height, width / frame.size.width, height / frame.size.height);
            /* a square moves by its own steps, and an implicit animation on each would trail behind the display link */
            square.actions = [NSDictionary dictionaryWithObjectsAndKeys:[NSNull null], @"position", [NSNull null], @"opacity", nil];
            [container addSublayer:square];
            CGFloat direction = ExteriaDustRandom() * (CGFloat)(2 * M_PI);
            CGFloat speed = SPEED_MIN + SPEED_SPREAD * ExteriaDustRandom();
            ExteriaDustSquare *q = &squares[count++];
            q->x = square.position.x;
            q->y = square.position.y;
            q->vx = cos(direction) * speed;
            q->vy = sin(direction) * speed;
            q->life = (LIFE_MIN + LIFE_SPREAD * ExteriaDustRandom()) / TIME_SCALE;
            q->wave = (x + width / 2) / frame.size.width;
            q->layer = square;
        }
    }
    [host.layer addSublayer:container];
    ExteriaDustPlayer *player = [[[ExteriaDustPlayer alloc] initWithContainer:container squares:squares count:count] autorelease];
    [player start];
}
