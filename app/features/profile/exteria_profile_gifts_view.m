#import "exteria_profile_gifts_view.h"

#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

#import "exteria_gift_backdrop_view.h"
#import "exteria_platform.h"
#import "exteria_star_gift.h"

#define SLOT_COUNT 6
#define GIFT_SIDE 34.0
#define GLOW_SIDE 66.0

/* offsets from the center of the photo, left side first, for a photo of 96 points */
static const CGPoint ExteriaGiftSlots[SLOT_COUNT] = {
    {-72, -57}, {-148, -3}, {-95, 52}, {92, -47}, {149, -2}, {109, 55}
};

/* the soft light behind a gift: the color of its backdrop at the middle, fading to nothing at the edge, with three small sparkles round it */
@interface ExteriaGiftGlowView : UIView {
    UIColor *_color;
}
@property (nonatomic, retain) UIColor *color;
@end

@implementation ExteriaGiftGlowView

@synthesize color = _color;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    return self;
}

- (void)dealloc {
    [_color release];
    [super dealloc];
}

- (void)setColor:(UIColor *)color {
    if (color == _color) return;
    [_color release];
    _color = [color retain];
    [self setNeedsDisplay];
}

static void ExteriaDrawSparkle(CGContextRef context, CGPoint center, CGFloat radius) {
    CGContextMoveToPoint(context, center.x, center.y - radius);
    CGContextAddQuadCurveToPoint(context, center.x, center.y, center.x + radius, center.y);
    CGContextAddQuadCurveToPoint(context, center.x, center.y, center.x, center.y + radius);
    CGContextAddQuadCurveToPoint(context, center.x, center.y, center.x - radius, center.y);
    CGContextAddQuadCurveToPoint(context, center.x, center.y, center.x, center.y - radius);
    CGContextFillPath(context);
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_color) return;
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [_color getRed:&red green:&green blue:&blue alpha:&alpha];
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat components[8] = {red, green, blue, 0.62, red, green, blue, 0};
    CGFloat locations[2] = {0, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, locations, 2);
    CGPoint middle = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    CGContextDrawRadialGradient(context, gradient, middle, 0, middle, self.bounds.size.width / 2, 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 1, 1, 1, 0.8);
    CGFloat unit = self.bounds.size.width / 66.0;
    ExteriaDrawSparkle(context, CGPointMake(middle.x + 22 * unit, middle.y - 24 * unit), 3.2 * unit);
    ExteriaDrawSparkle(context, CGPointMake(middle.x - 24 * unit, middle.y + 18 * unit), 2.6 * unit);
    ExteriaDrawSparkle(context, CGPointMake(middle.x - 16 * unit, middle.y - 26 * unit), 1.8 * unit);
}

@end

@interface ExteriaProfileGiftsView () {
    ExteriaMediaCache *_media;
    ExteriaGiftGlowView *_glows[SLOT_COUNT];
    UIImageView *_pictures[SLOT_COUNT];
    NSUInteger _count;
    NSUInteger _token;
    CGPoint _focus;
}
@end

@implementation ExteriaProfileGiftsView

@synthesize focus = _focus;

+ (NSUInteger)capacity { return SLOT_COUNT; }

- (id)initWithMedia:(ExteriaMediaCache *)media {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _media = [media retain];
    self.userInteractionEnabled = NO;
    for (NSUInteger i = 0; i < SLOT_COUNT; ++i) {
        _glows[i] = [[ExteriaGiftGlowView alloc] init];
        _glows[i].hidden = YES;
        [self addSubview:_glows[i]];
        _pictures[i] = [[UIImageView alloc] init];
        _pictures[i].contentMode = UIViewContentModeScaleAspectFit;
        _pictures[i].hidden = YES;
        [self addSubview:_pictures[i]];
    }
    return self;
}

- (void)dealloc {
    for (NSUInteger i = 0; i < SLOT_COUNT; ++i) {
        [_glows[i] release];
        [_pictures[i] release];
    }
    [_media release];
    [super dealloc];
}

- (void)setGifts:(NSArray *)gifts {
    NSUInteger token = ++_token;
    NSUInteger slot = 0;
    for (ExteriaSavedGift *saved in gifts) {
        if (slot >= SLOT_COUNT) break;
        if (!saved.pinned || !saved.gift.unique || !saved.gift.sticker) continue;
        [self showGift:saved.gift inSlot:slot token:token];
        ++slot;
    }
    _count = slot;
    for (NSUInteger i = slot; i < SLOT_COUNT; ++i) {
        _glows[i].hidden = YES;
        _pictures[i].hidden = YES;
        _pictures[i].image = nil;
    }
    [self setNeedsLayout];
}

- (void)showGift:(ExteriaStarGift *)gift inSlot:(NSUInteger)slot token:(NSUInteger)token {
    /* the light shows with the picture, so a gift that has not loaded does not leave an empty disc */
    _glows[slot].hidden = YES;
    _glows[slot].color = gift.hasBackdropColors ? ExteriaGiftRgb(gift.backdropCenter) : nil;
    _pictures[slot].hidden = NO;
    _pictures[slot].image = nil;
    ExteriaMedia *sticker = gift.sticker;
    /* an animated sticker is shown by its thumbnail, the file of a static one is its picture */
    BOOL still = sticker.stickerFormat == EXTERIA_STICKER_STATIC;
    ExteriaRemoteFile *file = still ? sticker.file : sticker.previewFile;
    if (!file) {
        NSLog(@"exteria: pinned gift %lld has no picture to show round the photo", gift.giftId);
        return;
    }
    CGFloat pixels = GIFT_SIDE * ExteriaScreenScale();
    UIImage *ready = [_media cachedImageForFile:file maxSide:pixels];
    BOOL glows = gift.hasBackdropColors;
    if (ready) {
        _pictures[slot].image = ready;
        _glows[slot].hidden = !glows;
        return;
    }
    [_media loadImageForFile:file maxSide:pixels completion:^(UIImage *image) {
        if (token != _token || !image) return;
        _pictures[slot].image = image;
        _glows[slot].hidden = !glows;
    }];
}

/* each gift rises and sinks a couple of points on its own beat, the light and the picture together; a layer animation, so it costs no layout and stops with the window */
- (void)startLevitating {
    BOOL motion = self.window && !ExteriaReduceMotionEnabled();
    for (NSUInteger i = 0; i < SLOT_COUNT; ++i) {
        for (UIView *view in [NSArray arrayWithObjects:_glows[i], _pictures[i], nil]) {
            [view.layer removeAnimationForKey:@"exteria.levitate"];
            if (!motion) continue;
            CABasicAnimation *drift = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
            drift.fromValue = [NSNumber numberWithDouble:-1.8];
            drift.toValue = [NSNumber numberWithDouble:1.8];
            drift.duration = 2.4 + 0.35 * (double)i;
            drift.autoreverses = YES;
            drift.repeatCount = HUGE_VALF;
            drift.timeOffset = 0.5 * (double)i;
            drift.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [view.layer addAnimation:drift forKey:@"exteria.levitate"];
        }
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self startLevitating];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat room = self.bounds.size.width / 2 - 8;
    for (NSUInteger i = 0; i < SLOT_COUNT; ++i) {
        CGPoint offset = ExteriaGiftSlots[i];
        /* a narrow screen pulls the outer gifts in so none leaves the head */
        CGFloat limit = room - GLOW_SIDE / 2;
        if (fabs(offset.x) > limit) offset.x = offset.x < 0 ? -limit : limit;
        CGPoint center = CGPointMake(_focus.x + offset.x, _focus.y + offset.y);
        _glows[i].frame = CGRectMake(center.x - GLOW_SIDE / 2, center.y - GLOW_SIDE / 2, GLOW_SIDE, GLOW_SIDE);
        _pictures[i].frame = CGRectMake(center.x - GIFT_SIDE / 2, center.y - GIFT_SIDE / 2, GIFT_SIDE, GIFT_SIDE);
    }
}

@end
