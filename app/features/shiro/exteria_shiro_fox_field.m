#import "exteria_shiro_fox_field.h"

#import <QuartzCore/QuartzCore.h>

#include <string.h>

#import "exteria_platform.h"

#define MAX_FLAKES 16
#define PHONE_FLAKES 10

typedef struct {
    CGFloat x, y, vx, vy, rot, vrot, alpha, w, h;
    CALayer *layer;
} ExteriaShiroFlake;

@interface ExteriaShiroFoxField () {
    ExteriaShiroFlake _flakes[MAX_FLAKES];
    int _count;
    CADisplayLink *_link;
    UIImage *_sprite;
    CGSize _laidSize;
    CFTimeInterval _lastStamp;
    CGFloat _baseHeight;
    BOOL _pad;
}
@end

@implementation ExteriaShiroFoxField

static CGFloat ExteriaShiroRandom(CGFloat low, CGFloat high) {
    return low + ((CGFloat)(arc4random() % 10000) / 10000.0f) * (high - low);
}

/* one scaled copy per idiom, so a flake never decodes the png itself: the file is already small, and the copy keeps a soft shadow under the sprite */
static UIImage *ExteriaShiroSprite(NSString *name, BOOL pad) {
    static NSMutableDictionary *cache;
    NSString *key = [name stringByAppendingString:pad ? @"~pad" : @"~phone"];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    UIImage *source = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!source || source.size.width < 1 || source.size.height < 1) return nil;
    CGFloat side = pad ? 180 : 112;
    CGFloat scale = side / MAX(source.size.width, source.size.height);
    CGSize size = CGSizeMake(source.size.width * scale + 10, source.size.height * scale + 10);
    UIGraphicsBeginImageContextWithOptions(size, NO, 1);
    CGContextSetShadowWithColor(UIGraphicsGetCurrentContext(), CGSizeMake(0, 1.5), pad ? 3 : 2, [UIColor colorWithRed:0.55 green:0.12 blue:0.35 alpha:0.3].CGColor);
    [source drawInRect:CGRectMake(5, 5, source.size.width * scale, source.size.height * scale)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!image) return nil;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    [cache setObject:image forKey:key];
    return image;
}

- (void)place:(ExteriaShiroFlake *)flake {
    flake->layer.bounds = CGRectMake(0, 0, flake->w, flake->h);
    flake->layer.position = CGPointMake(flake->x, flake->y);
    flake->layer.opacity = (float)flake->alpha;
    flake->layer.affineTransform = CGAffineTransformMakeRotation(flake->rot);
}

- (void)reset:(ExteriaShiroFlake *)flake scattered:(BOOL)scattered {
    CGFloat width = self.bounds.size.width > 1 ? self.bounds.size.width : 320;
    CGFloat height = self.bounds.size.height > 1 ? self.bounds.size.height : 480;
    CGFloat scale = _pad ? ExteriaShiroRandom(0.85, 1.45) : ExteriaShiroRandom(0.7, 1.2);
    flake->alpha = _pad ? ExteriaShiroRandom(0.92, 1) : ExteriaShiroRandom(0.84, 1);
    flake->vy = _pad ? ExteriaShiroRandom(52, 78) : ExteriaShiroRandom(44, 64);
    flake->vx = _pad ? ExteriaShiroRandom(-10, 10) : ExteriaShiroRandom(-6, 6);
    flake->x = ExteriaShiroRandom(24, MAX(25, width - 24));
    flake->y = scattered ? ExteriaShiroRandom(-40, height) : ExteriaShiroRandom(-(_baseHeight + 40), -36);
    flake->rot = ExteriaShiroRandom(-0.18, 0.18);
    flake->vrot = ExteriaShiroRandom(-0.28, 0.28);
    flake->h = _baseHeight * scale;
    flake->w = _sprite && _sprite.size.height > 1 ? flake->h * (_sprite.size.width / _sprite.size.height) : flake->h;
    [self place:flake];
}

- (id)initWithFrame:(CGRect)frame spriteName:(NSString *)name {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = YES;
    self.opaque = NO;
    _pad = ExteriaIsPad();
    _count = _pad ? MAX_FLAKES : PHONE_FLAKES;
    _baseHeight = _pad ? 110 : 70;
    _sprite = [ExteriaShiroSprite(name, _pad) retain];
    memset(_flakes, 0, sizeof(_flakes));
    for (int i = 0; i < _count; ++i) {
        CALayer *layer = [CALayer layer];
        if (_sprite) {
            layer.contents = (id)_sprite.CGImage;
            layer.contentsGravity = kCAGravityResizeAspect;
        }
        layer.contentsScale = 1;
        layer.opaque = NO;
        /* a flake moves by its own steps, and an implicit animation on each would trail behind the display link */
        layer.actions = [NSDictionary dictionaryWithObjectsAndKeys:[NSNull null], @"position", [NSNull null], @"transform", [NSNull null], @"bounds",
                         [NSNull null], @"opacity", [NSNull null], @"contents", nil];
        [self.layer addSublayer:layer];
        _flakes[i].layer = layer;
        [self reset:&_flakes[i] scattered:YES];
    }
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_link release];
    for (int i = 0; i < _count; ++i) [_flakes[i].layer removeFromSuperlayer];
    [_sprite release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (CGSizeEqualToSize(_laidSize, self.bounds.size) || self.bounds.size.width <= 1 || self.bounds.size.height <= 1) return;
    _laidSize = self.bounds.size;
    for (int i = 0; i < _count; ++i) [self reset:&_flakes[i] scattered:YES];
}

- (void)step:(CADisplayLink *)link {
    CGFloat dt = _lastStamp > 0 ? (CGFloat)(link.timestamp - _lastStamp) : 1.0f / 30;
    _lastStamp = link.timestamp;
    /* a frame that was held up is stepped as an ordinary one, so the flakes never jump */
    if (dt < 1.0f / 90) dt = 1.0f / 90;
    if (dt > 1.0f / 20) dt = 1.0f / 30;
    CGSize size = self.bounds.size;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < _count; ++i) {
        ExteriaShiroFlake *flake = &_flakes[i];
        flake->y += flake->vy * dt;
        flake->x += flake->vx * dt;
        flake->rot += flake->vrot * dt;
        if (flake->y > size.height + flake->h || flake->x < -flake->w || flake->x > size.width + flake->w) {
            [self reset:flake scattered:NO];
            continue;
        }
        flake->layer.position = CGPointMake(flake->x, flake->y);
        flake->layer.affineTransform = CGAffineTransformMakeRotation(flake->rot);
    }
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    /* the display link keeps its target, so it only lives while the field is on a window */
    [_link invalidate];
    [_link release];
    _link = nil;
    _lastStamp = 0;
    if (!self.window || ExteriaReduceMotionEnabled()) return;
    _link = [[CADisplayLink displayLinkWithTarget:self selector:@selector(step:)] retain];
    if ([_link respondsToSelector:@selector(setFrameInterval:)]) _link.frameInterval = 2;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

@end
