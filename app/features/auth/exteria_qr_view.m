#import "exteria_qr_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#include "exteria_qr.h"

/* the time one module takes to pop in, and how long the wave takes to reach the corners */
#define POP_SECONDS 0.32
#define WAVE_SECONDS 0.62
#define FADE_SECONDS 0.3
/* the logo's disc covers this share of the code's side */
#define LOGO_SHARE 0.24
#define QUIET 1.0

static CGFloat ExteriaEaseOutBack(CGFloat t) {
    CGFloat c1 = 1.9, c3 = c1 + 1;
    CGFloat u = t - 1;
    return 1 + c3 * u * u * u + c1 * u * u;
}

/* the face of the disc in a chrome rim: a brushed metal gradient on the outside, a darker bevel before the face,
   an inner shadow where the face sits low and a soft gloss over the upper half */
static UIImage *ExteriaMetalDisc(UIImage *face, CGFloat side) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat rim = side * 0.1;
    CGRect outer = CGRectMake(0.5, 0.5, side - 1, side - 1);
    CGRect bevel = CGRectInset(outer, rim * 0.8, rim * 0.8);
    CGRect inner = CGRectInset(outer, rim, rim);
    CGPoint topLeft = CGPointMake(0, 0), bottomRight = CGPointMake(side, side);

    static const CGFloat chrome[] = {0.96, 0.96, 0.97, 1,  0.72, 0.73, 0.76, 1,  0.43, 0.44, 0.48, 1,  0.82, 0.83, 0.86, 1,
                                     0.55, 0.56, 0.60, 1,  0.94, 0.95, 0.96, 1};
    static const CGFloat chromeAt[] = {0, 0.22, 0.45, 0.62, 0.82, 1};
    CGGradientRef metal = CGGradientCreateWithColorComponents(space, chrome, chromeAt, 6);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, outer);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, metal, topLeft, bottomRight, 0);
    CGContextRestoreGState(context);
    CGGradientRelease(metal);

    /* the bevel runs the other way, so the rim looks turned in towards the face */
    static const CGFloat turned[] = {0.35, 0.36, 0.40, 1,  0.93, 0.94, 0.96, 1};
    CGGradientRef bevelGradient = CGGradientCreateWithColorComponents(space, turned, NULL, 2);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, bevel);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, bevelGradient, topLeft, bottomRight, 0);
    CGContextRestoreGState(context);
    CGGradientRelease(bevelGradient);

    CGContextSetRGBStrokeColor(context, 0.25, 0.26, 0.30, 0.85);
    CGContextSetLineWidth(context, 1);
    CGContextStrokeEllipseInRect(context, outer);

    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, inner);
    CGContextClip(context);
    if (face) {
        CGFloat scale = MAX(inner.size.width / face.size.width, inner.size.height / face.size.height);
        CGSize drawn = CGSizeMake(face.size.width * scale, face.size.height * scale);
        [face drawInRect:CGRectMake(CGRectGetMidX(inner) - drawn.width / 2, CGRectGetMidY(inner) - drawn.height / 2, drawn.width, drawn.height)];
    }
    /* a soft shadow on the upper edge of the face, where the rim stands over it */
    static const CGFloat shade[] = {0, 0, 0, 0.35,  0, 0, 0, 0};
    CGGradientRef shadow = CGGradientCreateWithColorComponents(space, shade, NULL, 2);
    CGContextDrawLinearGradient(context, shadow, CGPointMake(0, inner.origin.y), CGPointMake(0, inner.origin.y + inner.size.height * 0.28), 0);
    CGGradientRelease(shadow);
    CGContextRestoreGState(context);
    CGContextSetRGBStrokeColor(context, 0.12, 0.12, 0.16, 0.7);
    CGContextStrokeEllipseInRect(context, inner);

    /* the gloss: white fading out over the upper half of the whole disc */
    static const CGFloat gloss[] = {1, 1, 1, 0.34,  1, 1, 1, 0};
    CGGradientRef shine = CGGradientCreateWithColorComponents(space, gloss, NULL, 2);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, CGRectMake(side * 0.06, side * 0.02, side * 0.88, side * 0.55));
    CGContextClip(context);
    CGContextDrawLinearGradient(context, shine, CGPointMake(0, side * 0.02), CGPointMake(0, side * 0.57), 0);
    CGContextRestoreGState(context);
    CGGradientRelease(shine);
    CGColorSpaceRelease(space);
    UIImage *disc = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return disc;
}

@interface ExteriaQrView () {
    BOOL _metallic;
    CGFloat _discSide;
    NSData *_modules;
    NSInteger _side;
    NSData *_previous;
    NSInteger _previousSide;
    CADisplayLink *_link;
    CFTimeInterval _start;
    UIImageView *_logo;
    BOOL _logoStale;
    UIImage *_centerImage;
    UIColor *_paperColor;
    BOOL _still;
    BOOL _animating;
    CGFloat _ink[2][3];
}
@end

@implementation ExteriaQrView

@synthesize stillMode = _still;
@synthesize centerImage = _centerImage;
@synthesize metallic = _metallic;
@synthesize paperColor = _paperColor;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _paperColor = [[UIColor whiteColor] retain];
    self.backgroundColor = _paperColor;
    self.opaque = YES;
    self.contentMode = UIViewContentModeRedraw;
    [self setModuleTopColor:nil bottomColor:nil];
    _logo = [[UIImageView alloc] init];
    _logo.contentMode = UIViewContentModeScaleAspectFill;
    _logo.layer.masksToBounds = YES;
    _logo.userInteractionEnabled = NO;
    _logoStale = YES;
    [self addSubview:_logo];
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_modules release];
    [_previous release];
    [_logo release];
    [_centerImage release];
    [_paperColor release];
    [super dealloc];
}

#pragma mark logo

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = floor(self.bounds.size.width * LOGO_SHARE);
    /* the layer is the same size at rest, so it can scale from its middle */
    _logo.bounds = CGRectMake(0, 0, side, side);
    _logo.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    /* the logo and a photo in its place are both round */
    _logo.layer.cornerRadius = side / 2;
    if (_metallic && side != _discSide) _logoStale = YES;
    if (!_logoStale) return;
    _logoStale = NO;
    _discSide = side;
    UIImage *face = _centerImage ? _centerImage : [UIImage imageNamed:@"qr_logo"];
    if (!face) NSLog(@"exteria: qr_logo.png is missing from the bundle");
    _logo.image = _metallic ? ExteriaMetalDisc(face, side) : face;
}

#pragma mark modules

- (void)setModuleTopColor:(UIColor *)top bottomColor:(UIColor *)bottom {
    UIColor *colors[2] = {top ? top : [UIColor colorWithRed:0.11 green:0.07 blue:0.19 alpha:1], bottom ? bottom : (top ? top : [UIColor colorWithRed:0.11 green:0.07 blue:0.19 alpha:1])};
    for (int i = 0; i < 2; ++i) {
        CGFloat alpha;
        if (![colors[i] getRed:&_ink[i][0] green:&_ink[i][1] blue:&_ink[i][2] alpha:&alpha]) {
            CGFloat white = 0;
            [colors[i] getWhite:&white alpha:&alpha];
            _ink[i][0] = _ink[i][1] = _ink[i][2] = white;
        }
    }
    [self setNeedsDisplay];
}

/* the ink at a height in the code, 0 at the top edge and 1 at the bottom */
- (void)setInkAt:(CGFloat)t alpha:(CGFloat)alpha context:(CGContextRef)context {
    CGContextSetRGBFillColor(context, _ink[0][0] + (_ink[1][0] - _ink[0][0]) * t, _ink[0][1] + (_ink[1][1] - _ink[0][1]) * t,
                             _ink[0][2] + (_ink[1][2] - _ink[0][2]) * t, alpha);
}

- (void)setPaperColor:(UIColor *)color {
    UIColor *paper = color ? color : [UIColor whiteColor];
    if ([paper isEqual:_paperColor]) return;
    [_paperColor release];
    _paperColor = [paper retain];
    self.backgroundColor = _paperColor;
    [self setNeedsDisplay];
}

- (void)setMetallic:(BOOL)metallic {
    if (metallic == _metallic) return;
    _metallic = metallic;
    _logoStale = YES;
    [self setNeedsLayout];
}

- (void)setCenterImage:(UIImage *)image {
    if (image == _centerImage) return;
    [_centerImage release];
    _centerImage = [image retain];
    _logoStale = YES;
    [self setNeedsLayout];
}

- (void)setModules:(NSData *)modules side:(NSInteger)side animated:(BOOL)animated {
    if (side <= 0 || side > EXTERIA_QR_MAX_SIDE || modules.length < (NSUInteger)side * (NSUInteger)side) return;
    /* the same code again (the login flow reports its token more than once) is not a new code: starting the wave over made the picture blink without end */
    if (_modules && side == _side && [modules isEqualToData:_modules]) return;
    BOOL had = _modules != nil;
    if (had && animated) {
        [_previous release];
        _previous = [_modules retain];
        _previousSide = _side;
    } else {
        [_previous release];
        _previous = nil;
    }
    [_modules release];
    _modules = [modules copy];
    _side = side;
    _logo.hidden = NO;
    if (_still || ExteriaReduceMotionEnabled() || !animated || !self.window || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        [_previous release];
        _previous = nil;
        _animating = NO;
        [self stopLink];
        [_logo.layer removeAllAnimations];
        _logo.alpha = 1;
        _logo.transform = CGAffineTransformIdentity;
        [self setNeedsDisplay];
        _logo.hidden = NO;
        return;
    }
    _animating = YES;
    _start = CACurrentMediaTime();
    [self startLink];
    [self bounceLogo];
    [self setNeedsDisplay];
}

- (void)clear {
    [_modules release];
    _modules = nil;
    [_previous release];
    _previous = nil;
    _side = 0;
    _logo.hidden = YES;
    _animating = NO;
    [self stopLink];
    [self setNeedsDisplay];
}

- (void)startLink {
    if (_link) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
    /* the pop is a short wave, so a frame in two keeps an old phone smooth */
    if ([_link respondsToSelector:@selector(setFrameInterval:)]) _link.frameInterval = 2;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopLink {
    [_link invalidate];
    _link = nil;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) return;
    /* a detached code must stop redrawing and release its display link's hold on the view */
    _animating = NO;
    [_previous release];
    _previous = nil;
    [self stopLink];
    [_logo.layer removeAllAnimations];
    _logo.alpha = 1;
    _logo.transform = CGAffineTransformIdentity;
    [self setNeedsDisplay];
}

- (void)step:(CADisplayLink *)link {
    (void)link;
    if (CACurrentMediaTime() - _start > WAVE_SECONDS + POP_SECONDS + 0.05) {
        _animating = NO;
        [_previous release];
        _previous = nil;
        [self stopLink];
    }
    [self setNeedsDisplay];
}

/* the logo drops in a little after the modules and settles with a bounce */
- (void)bounceLogo {
    _logo.transform = CGAffineTransformMakeScale(0.2, 0.2);
    _logo.alpha = 0;
    [UIView animateWithDuration:0.18 delay:0.12 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _logo.alpha = 1;
        _logo.transform = CGAffineTransformMakeScale(1.18, 1.18);
    } completion:^(BOOL finished) {
        (void)finished;
        [UIView animateWithDuration:0.14 animations:^{ _logo.transform = CGAffineTransformIdentity; }];
    }];
}

#pragma mark drawing

static void ExteriaAddRounded(CGContextRef context, CGRect rect, CGFloat radius) {
    CGFloat x0 = CGRectGetMinX(rect), y0 = CGRectGetMinY(rect), x1 = CGRectGetMaxX(rect), y1 = CGRectGetMaxY(rect);
    CGContextMoveToPoint(context, x0 + radius, y0);
    CGContextAddArcToPoint(context, x1, y0, x1, y1, radius);
    CGContextAddArcToPoint(context, x1, y1, x0, y1, radius);
    CGContextAddArcToPoint(context, x0, y1, x0, y0, radius);
    CGContextAddArcToPoint(context, x0, y0, x1, y0, radius);
    CGContextClosePath(context);
}

/* whether the module at (x, y) belongs to one of the three finder patterns, which are drawn as nested rounded squares */
static BOOL ExteriaIsFinder(NSInteger x, NSInteger y, NSInteger side) {
    BOOL left = x < 7, right = x >= side - 7, top = y < 7, bottom = y >= side - 7;
    return (left && top) || (right && top) || (left && bottom);
}

/* draws one code at the given module size and corner; reveal in [0, 1] says how far the wave has come, fade scales the whole code */
- (void)drawModules:(NSData *)modules side:(NSInteger)side origin:(CGPoint)origin unit:(CGFloat)unit elapsed:(CFTimeInterval)elapsed
              reveal:(BOOL)reveal alpha:(CGFloat)alpha context:(CGContextRef)context {
    const uint8_t *bytes = modules.bytes;
    CGFloat mid = (CGFloat)(side - 1) / 2;
    CGFloat farthest = sqrt(2) * mid;
    CGFloat clear = side * LOGO_SHARE / 2 + 1.2;
    for (NSInteger y = 0; y < side; ++y) {
        [self setInkAt:((CGFloat)y + 0.5) / (CGFloat)side alpha:alpha context:context];
        for (NSInteger x = 0; x < side; ++x) {
            if (!bytes[y * side + x] || ExteriaIsFinder(x, y, side)) continue;
            CGFloat dx = (CGFloat)x - mid, dy = (CGFloat)y - mid;
            CGFloat distance = sqrt(dx * dx + dy * dy);
            if (distance < clear) continue;
            CGFloat scale = 1;
            if (reveal) {
                CGFloat t = (CGFloat)((elapsed - (distance / farthest) * WAVE_SECONDS) / POP_SECONDS);
                if (t <= 0) continue;
                t = MIN(1, t);
                scale = ExteriaEaseOutBack(t);
            }
            CGFloat size = unit * scale * 0.92;
            CGRect cell = CGRectMake(origin.x + ((CGFloat)x + 0.5) * unit - size / 2, origin.y + ((CGFloat)y + 0.5) * unit - size / 2, size, size);
            ExteriaAddRounded(context, cell, size * 0.36);
            CGContextFillPath(context);
        }
    }
    /* the finder patterns: a ring and a heart, with the same pop, a little ahead of the modules */
    CGPoint corners[3] = {CGPointMake(0, 0), CGPointMake((CGFloat)side - 7, 0), CGPointMake(0, (CGFloat)side - 7)};
    for (int i = 0; i < 3; ++i) {
        CGFloat scale = 1;
        if (reveal) {
            CGFloat t = (CGFloat)((elapsed - 0.04 * i) / (POP_SECONDS + 0.1));
            if (t <= 0) continue;
            scale = ExteriaEaseOutBack(MIN(1, t));
        }
        [self setInkAt:(corners[i].y + 3.5) / (CGFloat)side alpha:alpha context:context];
        CGFloat cx = origin.x + (corners[i].x + 3.5) * unit, cy = origin.y + (corners[i].y + 3.5) * unit;
        CGFloat outer = 7 * unit * scale;
        CGRect ring = CGRectMake(cx - outer / 2, cy - outer / 2, outer, outer);
        ExteriaAddRounded(context, ring, outer * 0.3);
        CGRect hole = CGRectInset(ring, unit * scale, unit * scale);
        ExteriaAddRounded(context, hole, hole.size.width * 0.24);
        CGContextEOFillPath(context);
        CGFloat inner = 3 * unit * scale;
        CGRect heart = CGRectMake(cx - inner / 2, cy - inner / 2, inner, inner);
        ExteriaAddRounded(context, heart, inner * 0.34);
        CGContextFillPath(context);
    }
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    [_paperColor setFill];
    CGContextFillRect(context, self.bounds);
    if (!_modules) return;
    CGFloat width = self.bounds.size.width;
    CFTimeInterval elapsed = _animating ? CACurrentMediaTime() - _start : 1000;
    if (_previous && _animating) {
        CGFloat fade = 1 - MIN(1, (CGFloat)(elapsed / FADE_SECONDS));
        CGFloat unit = width / ((CGFloat)_previousSide + 2 * QUIET);
        [self drawModules:_previous side:_previousSide origin:CGPointMake(QUIET * unit, QUIET * unit) unit:unit elapsed:0 reveal:NO alpha:fade context:context];
    }
    CGFloat unit = width / ((CGFloat)_side + 2 * QUIET);
    [self drawModules:_modules side:_side origin:CGPointMake(QUIET * unit, QUIET * unit) unit:unit elapsed:elapsed reveal:_animating alpha:1 context:context];
}

@end
