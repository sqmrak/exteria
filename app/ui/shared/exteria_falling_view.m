#import "exteria_falling_view.h"

#import <QuartzCore/QuartzCore.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

#import "exteria_lite_mode.h"
#import "exteria_platform.h"

#define SNOW_MAX 48

typedef struct {
    CGFloat x, y, vx, vy;
    CGFloat scale, alpha, size, width;
    CGFloat phase, vphase, sway;
    CGFloat rotation, spin;
    CALayer *layer;
} snow_flake;

@interface ExteriaFallingView () {
    snow_flake _flakes[SNOW_MAX];
    int _count;
    CADisplayLink *_link;
    BOOL _running;
    CGSize _laid;
    CFTimeInterval _last;
    /* a picture falling instead of snow: the picture, and how tall it is at scale one */
    UIImage *_sprite;
    CGFloat _base;
    BOOL _pad;
}
@end

/* a soft white dot with a faint blue edge, so a flake still shows on a light screen */
static UIImage *ExteriaSnowSprite(void) {
    static UIImage *sprite;
    if (sprite) return sprite;
    const CGFloat side = 32.0f;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 1.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[8] = {1, 1, 1, 1, 1, 1, 1, 0};
    CGFloat locations[2] = {0.35f, 1.0f};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, locations, 2);
    CGContextSetShadowWithColor(context, CGSizeZero, 2.0f, [UIColor colorWithRed:0.45f green:0.58f blue:0.78f alpha:0.55f].CGColor);
    CGPoint center = CGPointMake(side / 2, side / 2);
    CGContextDrawRadialGradient(context, gradient, center, 0, center, side / 2 - 3.0f, 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    sprite = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return sprite;
}

/* the picture is scaled once, with the soft shadow of senko, so a flake never decodes the png */
static UIImage *ExteriaFallingSprite(NSString *name, BOOL pad) {
    static NSMutableDictionary *cache;
    NSString *key = [name stringByAppendingString:pad ? @"~pad" : @"~phone"];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    UIImage *source = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!source || source.size.width < 1.0f || source.size.height < 1.0f) return nil;
    CGFloat side = pad ? 180.0f : 112.0f;
    CGFloat scale = side / MAX(source.size.width, source.size.height);
    CGSize size = CGSizeMake(source.size.width * scale + 10, source.size.height * scale + 10);
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    CGContextSetShadowWithColor(UIGraphicsGetCurrentContext(), CGSizeMake(0, 1.5f), pad ? 3.0f : 2.0f, [UIColor colorWithRed:0.55f green:0.12f blue:0.35f alpha:0.35f].CGColor);
    [source drawInRect:CGRectMake(5, 5, source.size.width * scale, source.size.height * scale)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!out) return nil;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    [cache setObject:out forKey:key];
    return out;
}

static CGFloat ExteriaSnowRandom(CGFloat low, CGFloat high) {
    return low + ((CGFloat)(arc4random() % 10000) / 10000.0f) * (high - low);
}

@implementation ExteriaFallingView

- (id)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame spriteNamed:nil];
}

- (id)initWithFrame:(CGRect)frame spriteNamed:(NSString *)name {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = YES;
    self.opaque = NO;
    BOOL pad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    _pad = pad;
    BOOL low = ExteriaLiteClass() == EXTERIA_LITE_CLASS_LOW;
    /* an old phone moves fewer of them: every flake is a layer that is placed thirty times a second */
    UIImage *sprite = name.length ? ExteriaFallingSprite(name, pad) : nil;
    if (name.length && !sprite) NSLog(@"exteria: the picture %@ for the falling field is missing", name);
    _sprite = [sprite retain];
    _count = sprite ? (pad ? 18 : (low ? 7 : 12)) : (pad ? 40 : (low ? 14 : 26));
    _base = sprite ? (pad ? 110.0f : 70.0f) : 12.0f;
    if (!sprite) sprite = ExteriaSnowSprite();
    memset(_flakes, 0, sizeof(_flakes));
    for (int i = 0; i < _count; ++i) {
        CALayer *layer = [CALayer layer];
        layer.contents = (id)sprite.CGImage;
        layer.contentsGravity = kCAGravityResizeAspect;
        layer.opaque = NO;
        /* a flake moves by hand every frame, so the implicit animations of its layer are off */
        layer.actions = [NSDictionary dictionaryWithObjectsAndKeys:[NSNull null], @"position", [NSNull null], @"bounds", [NSNull null], @"opacity", [NSNull null], @"transform", nil];
        [self.layer addSublayer:layer];
        _flakes[i].layer = layer;
        [self resetFlake:&_flakes[i] scatter:YES];
    }
    return self;
}

- (void)dealloc {
    [self stop];
    for (int i = 0; i < _count; ++i) [_flakes[i].layer removeFromSuperlayer];
    [_sprite release];
    [super dealloc];
}

- (void)resetFlake:(snow_flake *)f scatter:(BOOL)scatter {
    CGFloat width = self.bounds.size.width > 1 ? self.bounds.size.width : 320;
    CGFloat height = self.bounds.size.height > 1 ? self.bounds.size.height : 480;
    if (_sprite) {
        f->scale = _pad ? ExteriaSnowRandom(0.85f, 1.45f) : ExteriaSnowRandom(0.70f, 1.20f);
        f->alpha = ExteriaSnowRandom(0.84f, 1.0f);
        f->vy = _pad ? ExteriaSnowRandom(52.0f, 78.0f) : ExteriaSnowRandom(44.0f, 64.0f);
        f->vx = ExteriaSnowRandom(-8.0f, 8.0f);
        f->sway = 0;
        f->spin = ExteriaSnowRandom(-0.28f, 0.28f);
        f->rotation = ExteriaSnowRandom(-0.18f, 0.18f);
    } else {
        f->scale = ExteriaSnowRandom(0.45f, 1.5f);
        f->alpha = ExteriaSnowRandom(0.55f, 1.0f);
        /* small flakes fall slower than big ones, which reads as depth */
        f->vy = ExteriaSnowRandom(26.0f, 40.0f) + 22.0f * f->scale;
        f->vx = ExteriaSnowRandom(-5.0f, 5.0f);
        f->sway = ExteriaSnowRandom(6.0f, 18.0f);
        f->spin = 0;
        f->rotation = 0;
    }
    f->phase = ExteriaSnowRandom(0.0f, 6.2832f);
    f->vphase = ExteriaSnowRandom(0.6f, 1.6f);
    f->size = _base * f->scale;
    f->width = _sprite && _sprite.size.height > 1 ? f->size * (_sprite.size.width / _sprite.size.height) : f->size;
    f->x = ExteriaSnowRandom(24, MAX(25, width - 24));
    f->y = scatter ? ExteriaSnowRandom(-20, height) : ExteriaSnowRandom(-(_base + 40.0f), -36.0f);
    f->layer.bounds = CGRectMake(0, 0, f->width, f->size);
    f->layer.position = CGPointMake(f->x, f->y);
    f->layer.opacity = (float)f->alpha;
    f->layer.affineTransform = CGAffineTransformMakeRotation(f->rotation);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (CGSizeEqualToSize(_laid, self.bounds.size) || self.bounds.size.width <= 1 || self.bounds.size.height <= 1) return;
    _laid = self.bounds.size;
    for (int i = 0; i < _count; ++i) [self resetFlake:&_flakes[i] scatter:YES];
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    CGFloat dt = _last > 0 ? (CGFloat)(now - _last) : 1.0f / 30.0f;
    _last = now;
    if (dt < 1.0f / 90.0f) dt = 1.0f / 90.0f;
    if (dt > 1.0f / 20.0f) dt = 1.0f / 30.0f;
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    for (int i = 0; i < _count; ++i) {
        snow_flake *f = &_flakes[i];
        f->phase += f->vphase * dt;
        f->y += f->vy * dt;
        f->x += (f->vx + sinf(f->phase) * f->sway) * dt;
        f->rotation += f->spin * dt;
        if (f->y > height + f->size || f->x < -f->width || f->x > width + f->width) {
            [self resetFlake:f scatter:NO];
            continue;
        }
        f->layer.position = CGPointMake(f->x, f->y);
        if (f->spin != 0) f->layer.affineTransform = CGAffineTransformMakeRotation(f->rotation);
    }
}

- (void)start {
    /* reduced motion and the power saver keep the screen still */
    if (_running || ExteriaReduceMotionEnabled() || !ExteriaLiteEnabled(EXTERIA_LITE_PARTICLES)) return;
    _running = YES;
    _last = 0;
    self.hidden = NO;
    _link = [[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];
    if ([_link respondsToSelector:@selector(setFrameInterval:)]) _link.frameInterval = 2;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop {
    _running = NO;
    _last = 0;
    [_link invalidate];
    [_link release];
    _link = nil;
    self.hidden = YES;
}

- (BOOL)isRunning {
    return _running;
}

@end
