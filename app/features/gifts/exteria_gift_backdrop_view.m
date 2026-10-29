#import "exteria_gift_backdrop_view.h"

#import "exteria_lottie.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define SYMBOL_SIDE 48
#define RING_COUNT 2

UIColor *ExteriaGiftRgb(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1];
}

/* radius as a share of the bounds, how many symbols, the turn of the first one in turns, symbol size as a share of
   the short side and the opacity */
static const struct { CGFloat radius; int count; CGFloat phase; CGFloat size; CGFloat alpha; } ExteriaRings[RING_COUNT] = {
    {0.42, 6, 0.08, 0.15, 0.30},
    {0.74, 10, 0.0, 0.13, 0.20}
};

void ExteriaGiftLoadPatternSymbol(ExteriaMediaCache *media, ExteriaMedia *pattern, uint32_t color, void (^completion)(UIImage *symbol)) {
    static NSCache *kept;
    if (!kept) {
        kept = [[NSCache alloc] init];
        kept.countLimit = 24;
    }
    ExteriaRemoteFile *file = pattern.file;
    if (!file || pattern.stickerFormat != EXTERIA_STICKER_ANIMATED) {
        completion(nil);
        return;
    }
    NSString *key = [NSString stringWithFormat:@"%@/%06x", file.key, (unsigned)color];
    UIImage *ready = [kept objectForKey:key];
    if (ready) {
        completion(ready);
        return;
    }
    void (^done)(UIImage *) = [completion copy];
    [media loadDataForFile:file completion:^(NSData *data) {
        ExteriaLottie *animation = data ? [ExteriaLottie animationWithPackedData:data key:file.key] : nil;
        if (!animation) {
            NSLog(@"exteria: gift pattern %@ could not be had", file.key);
            done(nil);
            [done release];
            return;
        }
        [animation renderStillAtSide:SYMBOL_SIDE completion:^(CGImageRef frame) {
            UIImage *symbol = nil;
            if (frame) {
                /* the frame's alpha is the shape; the pattern color fills it */
                CGSize size = CGSizeMake(SYMBOL_SIDE, SYMBOL_SIDE);
                UIGraphicsBeginImageContextWithOptions(size, NO, 1);
                CGContextRef context = UIGraphicsGetCurrentContext();
                CGRect box = CGRectMake(0, 0, size.width, size.height);
                CGContextTranslateCTM(context, 0, size.height);
                CGContextScaleCTM(context, 1, -1);
                /* a color frame is no clipping mask, so the shape is drawn and then filled through its own alpha */
                CGContextDrawImage(context, box, frame);
                CGContextSetBlendMode(context, kCGBlendModeSourceIn);
                [ExteriaGiftRgb(color) setFill];
                CGContextFillRect(context, box);
                symbol = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            }
            if (symbol) [kept setObject:symbol forKey:key];
            else NSLog(@"exteria: gift pattern %@ did not render", file.key);
            done(symbol);
            [done release];
        }];
    }];
}

@interface ExteriaGiftBackdropView () {
    uint32_t _centerColor;
    uint32_t _edgeColor;
    uint32_t _patternColor;
    UIImage *_symbol;
    BOOL _expressive;
    CGPoint _focus;
}
@end

@implementation ExteriaGiftBackdropView

@synthesize centerColor = _centerColor;
@synthesize edgeColor = _edgeColor;
@synthesize patternColor = _patternColor;
@synthesize symbol = _symbol;
@synthesize expressive = _expressive;
@synthesize focus = _focus;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    _focus = CGPointMake(0.5, 0.5);
    return self;
}

- (void)dealloc {
    [_symbol release];
    [super dealloc];
}

- (void)setCenterColor:(uint32_t)color { _centerColor = color; [self setNeedsDisplay]; }
- (void)setEdgeColor:(uint32_t)color { _edgeColor = color; [self setNeedsDisplay]; }
- (void)setPatternColor:(uint32_t)color { _patternColor = color; [self setNeedsDisplay]; }
- (void)setFocus:(CGPoint)focus { _focus = focus; [self setNeedsDisplay]; }
- (void)setExpressive:(BOOL)expressive { _expressive = expressive; [self setNeedsDisplay]; }

- (void)setSymbol:(UIImage *)symbol {
    if (symbol == _symbol) return;
    [_symbol release];
    _symbol = [symbol retain];
    [self setNeedsDisplay];
}

static void ExteriaBlend(uint32_t from, uint32_t to, CGFloat amount, CGFloat out[4]) {
    for (int i = 0; i < 3; ++i) {
        CGFloat a = ((from >> (16 - 8 * i)) & 0xff) / 255.0, b = ((to >> (16 - 8 * i)) & 0xff) / 255.0;
        out[i] = a + (b - a) * amount;
    }
    out[3] = 1;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGSize size = self.bounds.size;
    CGPoint center = CGPointMake(size.width * _focus.x, size.height * _focus.y);
    CGFloat colors[8];
    ExteriaBlend(_centerColor, _centerColor, 0, colors);
    ExteriaBlend(_edgeColor, _edgeColor, 0, colors + 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
    CGFloat reach = MAX(MAX(center.x, size.width - center.x), MAX(center.y, size.height - center.y)) * 1.35;
    CGContextDrawRadialGradient(context, gradient, center, 0, center, reach, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    if (_expressive) [self drawShapesAround:center size:size];
    else if (_symbol) [self drawPatternAround:center size:size];
}

- (void)drawPatternAround:(CGPoint)center size:(CGSize)size {
    CGFloat shortSide = MIN(size.width, size.height);
    for (int ring = 0; ring < RING_COUNT; ++ring) {
        CGFloat side = shortSide * ExteriaRings[ring].size;
        for (int i = 0; i < ExteriaRings[ring].count; ++i) {
            CGFloat turn = (ExteriaRings[ring].phase + (CGFloat)i / ExteriaRings[ring].count) * 2 * (CGFloat)M_PI;
            CGFloat x = center.x + cos(turn) * size.width * ExteriaRings[ring].radius;
            CGFloat y = center.y + sin(turn) * size.height * ExteriaRings[ring].radius;
            [_symbol drawInRect:CGRectMake(x - side / 2, y - side / 2, side, side) blendMode:kCGBlendModeNormal alpha:ExteriaRings[ring].alpha];
        }
    }
}

typedef enum { ShapeCookie, ShapeFlower, ShapeClover, ShapeBurst, ShapeSquircle, ShapePill, ShapeCircle, ShapeKinds } ExpressiveShape;

/* a closed curve r(t) = 1 + depth * cos(lobes * t) around a point: the cookie, the flower, the clover and the burst of the expressive shape set are this with other
   lobes and depths, which keeps them soft without a table of control points */
static UIBezierPath *ExteriaLobedShape(CGPoint center, CGFloat radius, int lobes, CGFloat depth, CGFloat turn) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    const int steps = 72;
    for (int i = 0; i <= steps; ++i) {
        CGFloat t = (CGFloat)i / steps * 2 * (CGFloat)M_PI;
        CGFloat r = radius * (1 + depth * cos(lobes * t)) / (1 + depth);
        CGPoint point = CGPointMake(center.x + r * cos(t + turn), center.y + r * sin(t + turn));
        if (i == 0) [path moveToPoint:point];
        else [path addLineToPoint:point];
    }
    [path closePath];
    return path;
}

/* |x|^4 + |y|^4 = r^4: the rounded square of the expressive set */
static UIBezierPath *ExteriaSquircle(CGPoint center, CGFloat radius, CGFloat turn) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    const int steps = 72;
    for (int i = 0; i <= steps; ++i) {
        CGFloat t = (CGFloat)i / steps * 2 * (CGFloat)M_PI;
        CGFloat c = cos(t), s = sin(t);
        CGFloat x = radius * (c < 0 ? -1 : 1) * sqrt(fabs(c)), y = radius * (s < 0 ? -1 : 1) * sqrt(fabs(s));
        CGPoint point = CGPointMake(center.x + x * cos(turn) - y * sin(turn), center.y + x * sin(turn) + y * cos(turn));
        if (i == 0) [path moveToPoint:point];
        else [path addLineToPoint:point];
    }
    [path closePath];
    return path;
}

static UIBezierPath *ExteriaExpressiveShape(ExpressiveShape kind, CGPoint center, CGFloat radius, CGFloat turn) {
    switch (kind) {
    case ShapeCookie: return ExteriaLobedShape(center, radius, 9, 0.07, turn);
    case ShapeFlower: return ExteriaLobedShape(center, radius, 5, 0.22, turn);
    case ShapeClover: return ExteriaLobedShape(center, radius, 4, 0.30, turn);
    case ShapeBurst: return ExteriaLobedShape(center, radius, 12, 0.10, turn);
    case ShapeSquircle: return ExteriaSquircle(center, radius * 0.92, turn);
    case ShapePill: {
        CGAffineTransform move = CGAffineTransformMakeTranslation(center.x, center.y);
        move = CGAffineTransformRotate(move, turn);
        UIBezierPath *pill = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(-radius, -radius * 0.5, radius * 2, radius) cornerRadius:radius * 0.5];
        [pill applyTransform:move];
        return pill;
    }
    default: return [UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - radius * 0.9, center.y - radius * 0.9, radius * 1.8, radius * 1.8)];
    }
}

/* big soft shapes in the corners and a ring of smaller ones round the gift, each of another kind, turned and sized a little differently; the same every time, since
   nothing here is random */
- (void)drawShapesAround:(CGPoint)center size:(CGSize)size {
    CGFloat shortSide = MIN(size.width, size.height);
    [[ExteriaGiftRgb(_patternColor) colorWithAlphaComponent:0.12] setFill];
    [ExteriaExpressiveShape(ShapeCookie, CGPointMake(size.width * 0.02, size.height * 0.06), shortSide * 0.42, 0.3) fill];
    [ExteriaExpressiveShape(ShapeFlower, CGPointMake(size.width * 0.98, size.height * 0.94), shortSide * 0.46, 0.9) fill];
    [ExteriaExpressiveShape(ShapeSquircle, CGPointMake(size.width * 0.96, size.height * 0.04), shortSide * 0.22, 0.5) fill];
    static const struct { CGFloat radius; int count; CGFloat phase; CGFloat size; CGFloat alpha; } rings[2] = {
        {0.40, 7, 0.04, 0.085, 0.26},
        {0.72, 11, 0.0, 0.07, 0.17}
    };
    for (int ring = 0; ring < 2; ++ring) {
        for (int i = 0; i < rings[ring].count; ++i) {
            CGFloat turn = (rings[ring].phase + (CGFloat)i / rings[ring].count) * 2 * (CGFloat)M_PI;
            CGPoint at = CGPointMake(center.x + cos(turn) * size.width * rings[ring].radius, center.y + sin(turn) * size.height * rings[ring].radius);
            CGFloat radius = shortSide * rings[ring].size * (0.8 + 0.2 * (CGFloat)((i + ring) % 3));
            ExpressiveShape kind = (ExpressiveShape)((i * 3 + ring * 2) % ShapeKinds);
            [[ExteriaGiftRgb(_patternColor) colorWithAlphaComponent:rings[ring].alpha] setFill];
            [ExteriaExpressiveShape(kind, at, radius, turn * 1.7 + i) fill];
        }
    }
}

@end

@interface ExteriaGiftRibbonView () {
    uint32_t _edgeColor;
    NSString *_text;
}
@end

@implementation ExteriaGiftRibbonView

@synthesize edgeColor = _edgeColor;
@synthesize text = _text;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    return self;
}

- (void)dealloc {
    [_text release];
    [super dealloc];
}

- (void)setEdgeColor:(uint32_t)color { _edgeColor = color; [self setNeedsDisplay]; }

- (void)setText:(NSString *)text {
    if (text == _text || [text isEqualToString:_text]) return;
    [_text release];
    _text = [text copy];
    [self setNeedsDisplay];
}

/* a band across the top right corner, darker than the backdrop, with the line set along it */
- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_text.length) return;
    CGSize size = self.bounds.size;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat w = size.width, reach = w * 0.64, thick = w * 0.27;
    CGFloat c0 = w - reach, c1 = c0 + thick;
    CGFloat shade[4];
    ExteriaBlend(_edgeColor, 0x000000, 0.28, shade);
    CGContextSaveGState(context);
    CGContextSetRGBFillColor(context, shade[0], shade[1], shade[2], 0.92);
    CGContextMoveToPoint(context, c0, 0);
    CGContextAddLineToPoint(context, c1, 0);
    CGContextAddLineToPoint(context, w, w - c1);
    CGContextAddLineToPoint(context, w, w - c0);
    CGContextClosePath(context);
    CGContextFillPath(context);
    CGFloat mid = (c0 + c1) / 2;
    CGContextTranslateCTM(context, (mid + w) / 2, (w - mid) / 2);
    CGContextRotateCTM(context, (CGFloat)(M_PI / 4));
    UIFont *font = ExteriaFontBold(MAX(11, w * 0.1));
    [[UIColor whiteColor] setFill];
    CGFloat height = font.lineHeight;
    ExteriaDrawStringIn(_text, font, CGRectMake(-w * 0.4, -height / 2, w * 0.8, height), ExteriaStringTailTruncate, ExteriaTextAlignmentCenter);
    CGContextRestoreGState(context);
}


@end
