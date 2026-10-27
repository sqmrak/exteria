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
    NSString *_ribbon;
    CGPoint _focus;
}
@end

@implementation ExteriaGiftBackdropView

@synthesize centerColor = _centerColor;
@synthesize edgeColor = _edgeColor;
@synthesize patternColor = _patternColor;
@synthesize symbol = _symbol;
@synthesize ribbon = _ribbon;
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
    [_ribbon release];
    [super dealloc];
}

- (void)setCenterColor:(uint32_t)color { _centerColor = color; [self setNeedsDisplay]; }
- (void)setEdgeColor:(uint32_t)color { _edgeColor = color; [self setNeedsDisplay]; }
- (void)setPatternColor:(uint32_t)color { _patternColor = color; [self setNeedsDisplay]; }
- (void)setFocus:(CGPoint)focus { _focus = focus; [self setNeedsDisplay]; }

- (void)setSymbol:(UIImage *)symbol {
    if (symbol == _symbol) return;
    [_symbol release];
    _symbol = [symbol retain];
    [self setNeedsDisplay];
}

- (void)setRibbon:(NSString *)ribbon {
    if (ribbon == _ribbon || [ribbon isEqualToString:_ribbon]) return;
    [_ribbon release];
    _ribbon = [ribbon copy];
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
    if (_symbol) [self drawPatternAround:center size:size];
    if (_ribbon.length) [self drawRibbon:size];
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

/* a band across the top right corner, darker than the backdrop, with the line set along it */
- (void)drawRibbon:(CGSize)size {
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
    ExteriaDrawStringIn(_ribbon, font, CGRectMake(-w * 0.4, -height / 2, w * 0.8, height), ExteriaStringTailTruncate, ExteriaTextAlignmentCenter);
    CGContextRestoreGState(context);
}

@end
