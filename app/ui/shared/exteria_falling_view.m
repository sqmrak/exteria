#import "exteria_falling_view.h"
#import "exteria_window.h"
#import "exteria_animation.h"

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
    CGFloat age, lifetime;
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
    /* after a shake the pictures drop, bounce off the floor and the walls and each other, and lie there for a while, as the icons of Gravity Board do; the time since the shake */
    BOOL _gravity;
    CFTimeInterval _gravityTime;
}
@end

/* snowflake geometry adapted from telegram for android, copyright nikolai kudashov, gpl v2 or later */
static UIImage *ExteriaSnowSprite(void) {
    static UIImage *sprite;
    if (sprite) return sprite;
    const CGFloat side = 10.0f;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, ExteriaScreenScale());
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetRGBStrokeColor(context, 1, 1, 1, 1);
    CGContextSetLineWidth(context, 0.5f);
    CGContextSetLineCap(context, kCGLineCapRound);
    for (int i = 0; i < 6; ++i) {
        CGFloat angle = -(CGFloat)M_PI / 2 + (CGFloat)i * (CGFloat)M_PI / 3;
        CGFloat x = cosf(angle) * 4, y = sinf(angle) * 4;
        CGFloat branch = angle - (CGFloat)M_PI / 2;
        CGContextMoveToPoint(context, 5, 5);
        CGContextAddLineToPoint(context, 5 + x, 5 + y);
        for (int sign = -1; sign <= 1; sign += 2) {
            CGFloat px = sign * -1.14f, py = 3.10f;
            CGContextMoveToPoint(context, 5 + x * 0.66f, 5 + y * 0.66f);
            CGContextAddLineToPoint(context, 5 + cosf(branch) * px - sinf(branch) * py,
                                    5 + sinf(branch) * px + cosf(branch) * py);
        }
    }
    CGContextStrokePath(context);
    sprite = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return sprite;
}

static UIImage *ExteriaSnowDot(void) {
    static UIImage *dot;
    if (dot) return dot;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(10, 10), NO, ExteriaScreenScale());
    [[UIColor whiteColor] setFill];
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(4.25f, 4.25f, 1.5f, 1.5f)];
    [circle fill];
    dot = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return dot;
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
        f->layer.contents = (id)(arc4random_uniform(2) ? ExteriaSnowSprite().CGImage : ExteriaSnowDot().CGImage);
        f->scale = ExteriaSnowRandom(0.3f, 1.2f);
        f->alpha = 0;
        CGFloat angle = ExteriaSnowRandom(70, 110) * (CGFloat)M_PI / 180;
        CGFloat speed = ExteriaSnowRandom(40, 48);
        f->vx = cosf(angle) * speed;
        f->vy = sinf(angle) * speed;
        f->sway = 0;
        f->spin = 0;
        f->rotation = 0;
        f->age = scatter ? ExteriaSnowRandom(0, 3) : 0;
        f->lifetime = ExteriaSnowRandom(3, 5);
    }
    f->phase = ExteriaSnowRandom(0.0f, 6.2832f);
    f->vphase = ExteriaSnowRandom(0.6f, 1.6f);
    f->size = _base * f->scale;
    f->width = _sprite && _sprite.size.height > 1 ? f->size * (_sprite.size.width / _sprite.size.height) : f->size;
    f->x = ExteriaSnowRandom(24, MAX(25, width - 24));
    f->y = _sprite ? (scatter ? ExteriaSnowRandom(-20, height) : ExteriaSnowRandom(-(_base + 40.0f), -36.0f)) : ExteriaSnowRandom(0, height);
    f->layer.bounds = CGRectMake(0, 0, f->width, f->size);
    f->layer.position = CGPointMake(f->x, f->y);
    f->layer.opacity = (float)f->alpha;
    f->layer.affineTransform = CGAffineTransformMakeRotation(f->rotation);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (CGSizeEqualToSize(_laid, self.bounds.size) || self.bounds.size.width <= 1 || self.bounds.size.height <= 1) return;
    BOOL first = _laid.width <= 1 || _laid.height <= 1;
    _laid = self.bounds.size;
    if (first || !_sprite) {
        for (int i = 0; i < _count; ++i) [self resetFlake:&_flakes[i] scatter:YES];
        return;
    }
    /* a re-scatter on every resize (the classic list changes height when edit mode swaps the bars) makes the opaque pictures jump, only snow hides it by fading */
    CGFloat width = self.bounds.size.width;
    for (int i = 0; i < _count; ++i) {
        snow_flake *f = &_flakes[i];
        CGFloat r = f->size * 0.36f;
        if (f->x > width - r) f->x = MAX(r, width - r);
        if (f->y > self.bounds.size.height + f->size) f->y = -f->size;
    }
}

#define GRAVITY_SECONDS 7.0
#define GRAVITY_FADE 0.7
#define GRAVITY_BOUNCE 0.42f

/* a shake throws the pictures up and sideways, and gravity takes them down */
- (void)shaken {
    if (!_running || !_sprite || _gravity) return;
    _gravity = YES;
    _gravityTime = 0;
    for (int i = 0; i < _count; ++i) {
        snow_flake *f = &_flakes[i];
        f->vx = ExteriaSnowRandom(-280, 280);
        f->vy = ExteriaSnowRandom(-560, -140);
        f->spin = ExteriaSnowRandom(-4.5f, 4.5f);
        f->layer.opacity = (float)f->alpha;
    }
}

/* the fall of one step: gravity, the floor and the walls, and the pictures against each other (each is a circle, and they have the same weight) */
- (void)stepGravity:(CGFloat)dt {
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat g = _pad ? 2300.0f : 1750.0f;
    for (int i = 0; i < _count; ++i) {
        snow_flake *f = &_flakes[i];
        CGFloat r = f->size * 0.36f;
        f->vy += g * dt;
        f->x += f->vx * dt;
        f->y += f->vy * dt;
        f->rotation += f->spin * dt;
        CGFloat floorY = height - r;
        if (f->y > floorY) {
            f->y = floorY;
            f->vy = -f->vy * GRAVITY_BOUNCE;
            /* what lies on the floor stops sliding and turning */
            f->vx *= 0.84f;
            f->spin *= 0.72f;
            if (fabsf(f->vy) < 45.0f) f->vy = 0;
        }
        if (f->x < r) { f->x = r; f->vx = -f->vx * GRAVITY_BOUNCE; }
        else if (f->x > width - r) { f->x = width - r; f->vx = -f->vx * GRAVITY_BOUNCE; }
    }
    for (int i = 0; i < _count; ++i) {
        for (int j = i + 1; j < _count; ++j) {
            snow_flake *a = &_flakes[i], *b = &_flakes[j];
            CGFloat dx = b->x - a->x, dy = b->y - a->y, reach = (a->size + b->size) * 0.36f;
            CGFloat distance2 = dx * dx + dy * dy;
            if (distance2 >= reach * reach || distance2 < 0.0001f) continue;
            CGFloat distance = sqrtf(distance2), nx = dx / distance, ny = dy / distance, overlap = reach - distance;
            a->x -= nx * overlap / 2; a->y -= ny * overlap / 2;
            b->x += nx * overlap / 2; b->y += ny * overlap / 2;
            CGFloat approach = (b->vx - a->vx) * nx + (b->vy - a->vy) * ny;
            if (approach < 0) {
                CGFloat push = -(1 + GRAVITY_BOUNCE) * approach / 2;
                a->vx -= push * nx; a->vy -= push * ny;
                b->vx += push * nx; b->vy += push * ny;
            }
        }
    }
    CGFloat rest = (CGFloat)(GRAVITY_SECONDS - _gravityTime);
    for (int i = 0; i < _count; ++i) {
        snow_flake *f = &_flakes[i];
        f->layer.position = CGPointMake(f->x, f->y);
        f->layer.affineTransform = CGAffineTransformMakeRotation(f->rotation);
        /* they go out at the end, and the slow fall begins again from the top */
        if (rest < GRAVITY_FADE) f->layer.opacity = (float)(f->alpha * MAX(0, rest / GRAVITY_FADE));
    }
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    CGFloat dt = _last > 0 ? (CGFloat)(now - _last) : 1.0f / 30.0f;
    _last = now;
    if (dt < 1.0f / 90.0f) dt = 1.0f / 90.0f;
    if (dt > 1.0f / 20.0f) dt = 1.0f / 30.0f;
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    if (_gravity) {
        _gravityTime += dt;
        [self stepGravity:dt];
        if (_gravityTime >= GRAVITY_SECONDS) {
            _gravity = NO;
            for (int i = 0; i < _count; ++i) [self resetFlake:&_flakes[i] scatter:NO];
        }
        return;
    }
    for (int i = 0; i < _count; ++i) {
        snow_flake *f = &_flakes[i];
        if (!_sprite) {
            f->age += dt;
            if (f->age >= f->lifetime) { [self resetFlake:f scatter:NO]; continue; }
            CGFloat fade = f->age < 0.2f ? f->age / 0.2f : MIN(1, (f->lifetime - f->age) / 2);
            f->layer.opacity = (float)(f->age < 0.2f ? fade * fade : 1 - (1 - fade) * (1 - fade));
        }
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
    _gravity = NO;
    self.hidden = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shaken) name:ExteriaDeviceDidShakeNotification object:nil];
    _link = [[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];
    ExteriaSetFrameRate(_link, 30);
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaDeviceDidShakeNotification object:nil];
    _running = NO;
    _gravity = NO;
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
