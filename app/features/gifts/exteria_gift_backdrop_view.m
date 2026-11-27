#import "exteria_gift_backdrop_view.h"

#import "exteria_lottie.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define SYMBOL_SIDE 64

UIColor *ExteriaGiftRgb(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1];
}

/* the symbols of a pattern as the official clients place them (StarGiftPatterns): x and y in points from the middle of the gift, the side and the opacity of each. points
   and not shares of the bounds, since the view of the header is far taller than what shows of it, and shares of that height put all but two symbols out of sight */
static const CGFloat ExteriaPatternHeader[] = {
    83.33f, 24, 27.33f, .22f,  68.66f, 75.33f, 25.33f, .21f,  0, 86, 25.33f, .12f,  -68.66f, 75.33f, 25.33f, .21f,  -82.66f, 13.66f, 27.33f, .22f,
    -80, -33.33f, 20, .24f,  -46.5f, -63.16f, 27, .21f,  1, -82.66f, 20, .15f,  46.5f, -63.16f, 27, .21f,  80, -33.33f, 19.33f, .24f,
    115.66f, -63, 20, .15f,  134, -10.66f, 20, .18f,  118.66f, 55.66f, 20, .15f,  124.33f, 98.33f, 20, .11f,
    -128, 98.33f, 20, .11f,  -108, 55.66f, 20, .15f,  -123.33f, -10.66f, 20, .18f,  -116, -63.33f, 20, .15f
};
static const CGFloat ExteriaPatternCard[] = {
    27.33f, -57.66f, 20, .12f,  59, -32, 19.33f, .22f,  77, 4.33f, 22.66f, .2f,  100, 40.33f, 18, .12f,  58.66f, 59, 20, .18f,  73.33f, 100.33f, 22.66f, .15f,
    75, 155, 22, .11f,
    -27.33f, -57.33f, 20, .12f,  -59, -32.33f, 19.33f, .2f,  -77, 4.66f, 23.33f, .2f,  -98.66f, 41, 18.66f, .12f,  -58, 59.33f, 19.33f, .18f,
    -73.33f, 100, 22, .15f,  -75.66f, 155, 22, .11f
};
static const CGFloat ExteriaPatternTile[] = {
    -0.83f, -52.16f, 12.33f, .2f,  26.66f, -40.33f, 16, .2f,  44.16f, -20.5f, 12.33f, .2f,  53, 7.33f, 16, .2f,  31, 23.66f, 14.66f, .2f,  0, 32, 13.33f, .2f,
    -29, 23.66f, 14, .2f,  -53, 7.33f, 16, .2f,  -44.5f, -20.16f, 12.33f, .2f,  -27.33f, -40.33f, 16, .2f,  43.66f, 50, 14.66f, .2f,  -41.66f, 48, 14.66f, .2f
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
    ExteriaGiftPatternLayout _patternLayout;
}
@end

@implementation ExteriaGiftBackdropView

@synthesize centerColor = _centerColor;
@synthesize edgeColor = _edgeColor;
@synthesize patternColor = _patternColor;
@synthesize symbol = _symbol;
@synthesize expressive = _expressive;
@synthesize focus = _focus;
@synthesize patternLayout = _patternLayout;

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
- (void)setPatternLayout:(ExteriaGiftPatternLayout)layout { _patternLayout = layout; [self setNeedsDisplay]; }

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
    (void)size;
    const CGFloat *places = ExteriaPatternHeader;
    size_t count = sizeof(ExteriaPatternHeader) / sizeof(CGFloat);
    if (_patternLayout == ExteriaGiftPatternCard) {
        places = ExteriaPatternCard;
        count = sizeof(ExteriaPatternCard) / sizeof(CGFloat);
    } else if (_patternLayout == ExteriaGiftPatternTile) {
        places = ExteriaPatternTile;
        count = sizeof(ExteriaPatternTile) / sizeof(CGFloat);
    }
    for (size_t i = 0; i + 3 < count; i += 4) {
        CGFloat side = places[i + 2];
        CGRect box = CGRectMake(center.x + places[i] - side / 2, center.y + places[i + 1] - side / 2, side, side);
        [_symbol drawInRect:box blendMode:kCGBlendModeNormal alpha:places[i + 3]];
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
