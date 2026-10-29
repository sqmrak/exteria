#import "exteria_gift_card.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_gift_backdrop_view.h"
#import "exteria_lite_mode.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define CARD_RADIUS 14.0
#define STICKER_SIDE 110.0
#define BUTTON_HEIGHT 30.0
#define ROW_GAP 6.0

static UIColor *ExteriaGiftCardInk(ExteriaStarGift *gift) {
    return gift.unique && gift.hasBackdropColors ? ExteriaGiftRgb(gift.backdropText) : [UIColor colorWithWhite:1 alpha:0.6];
}

static NSString *ExteriaGiftNumberRibbon(int32_t number) {
    return number > 0 ? [NSString stringWithFormat:@"#%d", (int)number] : nil;
}

@implementation ExteriaGiftCardLayout

@synthesize gift = _gift;
@synthesize size = _size;
@synthesize stickerFrame = _stickerFrame;
@synthesize buttonFrame = _buttonFrame;
@synthesize title = _title;
@synthesize subtitle = _subtitle;
@synthesize note = _note;
@synthesize button = _button;
@synthesize titleOrigin = _titleOrigin;
@synthesize subtitleOrigin = _subtitleOrigin;
@synthesize noteOrigin = _noteOrigin;
@synthesize buttonTextOrigin = _buttonTextOrigin;
@synthesize rowNames = _rowNames;
@synthesize rowValues = _rowValues;
@synthesize rowNameOrigins = _rowNameOrigins;
@synthesize rowValueOrigins = _rowValueOrigins;

- (void)dealloc {
    [_gift release];
    [_title release];
    [_subtitle release];
    [_note release];
    [_button release];
    [_rowNames release];
    [_rowValues release];
    [_rowNameOrigins release];
    [_rowValueOrigins release];
    [super dealloc];
}

+ (ExteriaGiftCardLayout *)layoutForGift:(ExteriaStarGift *)gift title:(NSString *)title subtitle:(NSString *)subtitle note:(NSString *)note
                                    width:(CGFloat)width {
    ExteriaGiftCardLayout *card = [[[ExteriaGiftCardLayout alloc] init] autorelease];
    card->_gift = [gift retain];
    UIColor *white = [UIColor whiteColor], *ink = ExteriaGiftCardInk(gift);
    CGFloat inner = width - 24;
    CGFloat y = 10;
    card->_stickerFrame = CGRectMake(floor((width - STICKER_SIDE) / 2), y, STICKER_SIDE, STICKER_SIDE);
    y += STICKER_SIDE + 9;
    card->_title = [[ExteriaTextLayout layoutForName:title font:ExteriaFontBold(14) color:white width:inner] retain];
    card->_titleOrigin = CGPointMake(floor((width - card->_title.size.width) / 2), y);
    y += ceil(card->_title.size.height) + 3;
    card->_subtitle = [[ExteriaTextLayout layoutForName:subtitle font:ExteriaFontRegular(12) color:ink width:inner] retain];
    card->_subtitleOrigin = CGPointMake(floor((width - card->_subtitle.size.width) / 2), y);
    y += ceil(card->_subtitle.size.height) + 11;
    if (note.length) {
        y += 4;
        card->_note = [[ExteriaTextLayout layoutForText:note entities:nil font:ExteriaFontRegular(13) color:white linkColor:white width:inner
                                                maxLines:4 flush:0.5] retain];
        card->_noteOrigin = CGPointMake(floor((width - card->_note.size.width) / 2), y);
        y += ceil(card->_note.size.height) + 3;
    } else if (gift.unique && gift.model.length) {
        NSMutableArray *names = [NSMutableArray array], *values = [NSMutableArray array];
        NSString *keys[3] = {@"gifts.row.model", @"gifts.row.backdrop", @"gifts.row.pattern"};
        NSString *texts[3] = {gift.model, gift.backdrop, gift.pattern};
        CGFloat nameWidth = 0, valueWidth = 0;
        for (int i = 0; i < 3; ++i) {
            if (!texts[i].length) continue;
            [names addObject:[ExteriaTextLayout layoutForName:NSLocalizedString(keys[i], nil) font:ExteriaFontRegular(12) color:ink width:inner * 0.5]];
            [values addObject:[ExteriaTextLayout layoutForName:texts[i] font:ExteriaFontBold(12) color:white width:inner * 0.5]];
            nameWidth = MAX(nameWidth, [[names lastObject] size].width);
            valueWidth = MAX(valueWidth, [[values lastObject] size].width);
        }
        NSMutableArray *nameOrigins = [NSMutableArray array], *valueOrigins = [NSMutableArray array];
        CGFloat left = width / 2 - (nameWidth + 9 + valueWidth) / 2;
        for (NSUInteger i = 0; i < names.count; ++i) {
            ExteriaTextLayout *name = [names objectAtIndex:i], *value = [values objectAtIndex:i];
            [nameOrigins addObject:[NSValue valueWithCGPoint:CGPointMake(floor(left + nameWidth - name.size.width), y)]];
            [valueOrigins addObject:[NSValue valueWithCGPoint:CGPointMake(floor(left + nameWidth + 9), y)]];
            y += ceil(MAX(name.size.height, value.size.height)) + (i + 1 < names.count ? ROW_GAP : 0);
        }
        card->_rowNames = [names retain];
        card->_rowValues = [values retain];
        card->_rowNameOrigins = [nameOrigins retain];
        card->_rowValueOrigins = [valueOrigins retain];
    }
    y += 11.66;
    card->_button = [[ExteriaTextLayout layoutForName:NSLocalizedString(@"gifts.card.view", nil) font:ExteriaFontBold(14) color:white width:inner - 30] retain];
    CGFloat buttonWidth = ceil(card->_button.size.width) + 30;
    card->_buttonFrame = CGRectMake(floor((width - buttonWidth) / 2), y, buttonWidth, BUTTON_HEIGHT);
    card->_buttonTextOrigin = CGPointMake(card->_buttonFrame.origin.x + 15, y + (BUTTON_HEIGHT - ceil(card->_button.size.height)) / 2);
    y += BUTTON_HEIGHT + 11;
    card->_size = CGSizeMake(width, y);
    return card;
}

@end

/* the words and the button, above the animation */
@interface ExteriaGiftCardTextView : UIView {
    ExteriaGiftCardLayout *_card;
    CAEmitterLayer *_sparkles;
}
@property (nonatomic, retain) ExteriaGiftCardLayout *card;
- (void)setSparkling:(BOOL)sparkling;
@end

@implementation ExteriaGiftCardTextView

@synthesize card = _card;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)dealloc {
    [_card release];
    [_sparkles release];
    [super dealloc];
}

/* a four point star, white; the emitter tints and fades it */
static UIImage *ExteriaSparkleImage(void) {
    static UIImage *image;
    if (image) return image;
    CGFloat side = 16;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat m = side / 2, k = side * 0.12;
    CGContextMoveToPoint(context, m, 0);
    CGContextAddQuadCurveToPoint(context, m + k, m - k, side, m);
    CGContextAddQuadCurveToPoint(context, m + k, m + k, m, side);
    CGContextAddQuadCurveToPoint(context, m - k, m + k, 0, m);
    CGContextAddQuadCurveToPoint(context, m - k, m - k, m, 0);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillPath(context);
    image = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return image;
}

/* the stars drift around the button, a little wider than it */
- (void)placeSparkles {
    if (!_sparkles || !_card) return;
    _sparkles.frame = CGRectInset(_card.buttonFrame, -26, -10);
    _sparkles.emitterPosition = CGPointMake(CGRectGetMidX(_sparkles.bounds), CGRectGetMidY(_sparkles.bounds));
    _sparkles.emitterSize = _sparkles.bounds.size;
}

- (void)setCard:(ExteriaGiftCardLayout *)card {
    if (card == _card) return;
    [_card release];
    _card = [card retain];
    [self placeSparkles];
    [self setNeedsDisplay];
}

- (void)setSparkling:(BOOL)sparkling {
    if (sparkling && !_sparkles && _card) {
        CAEmitterCell *star = [CAEmitterCell emitterCell];
        star.contents = (id)ExteriaSparkleImage().CGImage;
        star.birthRate = 5;
        star.lifetime = 1.5;
        star.lifetimeRange = 0.6;
        star.velocity = 3;
        star.velocityRange = 3;
        star.emissionRange = (CGFloat)(2 * M_PI);
        star.scale = 0.55;
        star.scaleRange = 0.35;
        star.alphaSpeed = -0.6;
        star.color = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
        _sparkles = [[CAEmitterLayer alloc] init];
        _sparkles.emitterShape = kCAEmitterLayerRectangle;
        _sparkles.emitterCells = [NSArray arrayWithObject:star];
        [self.layer addSublayer:_sparkles];
        [self placeSparkles];
    }
    _sparkles.birthRate = sparkling ? 1 : 0;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    ExteriaGiftCardLayout *card = _card;
    if (!card) return;
    [card.title drawAtPoint:card.titleOrigin];
    [card.subtitle drawAtPoint:card.subtitleOrigin];
    if (card.note) [card.note drawAtPoint:card.noteOrigin];
    for (NSUInteger i = 0; i < card.rowNames.count; ++i) {
        [[card.rowNames objectAtIndex:i] drawAtPoint:[[card.rowNameOrigins objectAtIndex:i] CGPointValue]];
        [[card.rowValues objectAtIndex:i] drawAtPoint:[[card.rowValueOrigins objectAtIndex:i] CGPointValue]];
    }
    CGRect button = card.buttonFrame;
    [[UIColor colorWithWhite:0 alpha:0.13] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:button cornerRadius:button.size.height / 2] fill];
    [card.button drawAtPoint:card.buttonTextOrigin];
}

@end

@interface ExteriaGiftCardView () {
    ExteriaGiftCardLayout *_layout;
    ExteriaGiftBackdropView *_backdrop;
    UIImageView *_poster;
    ExteriaLottieView *_lottie;
    ExteriaGiftCardTextView *_text;
    NSUInteger _token;
    BOOL _active;
    BOOL _played;
}
@end

@implementation ExteriaGiftCardView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.layer.cornerRadius = CARD_RADIUS;
    self.layer.masksToBounds = YES;
    _backdrop = [[ExteriaGiftBackdropView alloc] init];
    [self addSubview:_backdrop];
    _poster = [[UIImageView alloc] init];
    _poster.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_poster];
    _text = [[ExteriaGiftCardTextView alloc] init];
    [self addSubview:_text];
    return self;
}

- (void)dealloc {
    [self discard];
    [_backdrop release];
    [_poster release];
    [_text release];
    [super dealloc];
}

- (BOOL)animationAllowed {
    return !ExteriaReduceMotionEnabled() && ExteriaLiteEnabled(EXTERIA_LITE_STICKERS_CHAT);
}

- (void)discard {
    ++_token;
    [_lottie removeFromSuperview];
    [_lottie setPlaying:NO];
    [_lottie release];
    _lottie = nil;
    _poster.image = nil;
    _poster.hidden = NO;
    [_layout release];
    _layout = nil;
    _played = NO;
    [_text setSparkling:NO];
}

- (void)configureWithLayout:(ExteriaGiftCardLayout *)layout media:(ExteriaMediaCache *)media {
    if (layout == _layout) return;
    [self discard];
    _layout = [layout retain];
    ExteriaStarGift *gift = layout.gift;
    NSUInteger token = _token;
    self.bounds = CGRectMake(0, 0, layout.size.width, layout.size.height);
    CGRect all = self.bounds;
    BOOL themed = gift.unique && gift.hasBackdropColors;
    self.backgroundColor = themed ? ExteriaGiftRgb(gift.backdropEdge) : ExteriaColorBubbleCapsule();
    _backdrop.frame = all;
    _backdrop.hidden = !themed;
    _backdrop.symbol = nil;
    if (themed) {
        _backdrop.centerColor = gift.backdropCenter;
        _backdrop.edgeColor = gift.backdropEdge;
        _backdrop.patternColor = gift.backdropPattern;
        _backdrop.ribbon = ExteriaGiftNumberRibbon(gift.number);
        _backdrop.focus = CGPointMake(0.5, CGRectGetMidY(layout.stickerFrame) / all.size.height);
        if (gift.patternSticker) {
            ExteriaGiftLoadPatternSymbol(media, gift.patternSticker, gift.backdropPattern, ^(UIImage *symbol) {
                if (token == _token) _backdrop.symbol = symbol;
            });
        }
    }
    _poster.frame = layout.stickerFrame;
    _text.frame = all;
    _text.card = layout;
    [self loadAnimationOf:gift.sticker media:media token:token];
    [_text setSparkling:_active && [self animationAllowed]];
}

- (void)loadAnimationOf:(ExteriaMedia *)sticker media:(ExteriaMediaCache *)media token:(NSUInteger)token {
    if (!sticker || !sticker.file) return;
    CGFloat pixels = STICKER_SIDE * ExteriaScreenScale();
    ExteriaRemoteFile *preview = sticker.previewFile;
    if (preview) {
        UIImage *ready = [media cachedImageForFile:preview maxSide:pixels];
        if (ready) _poster.image = ready;
        else [media loadImageForFile:preview maxSide:pixels completion:^(UIImage *image) {
            if (token == _token && image && !_lottie) _poster.image = image;
        }];
    }
    ExteriaRemoteFile *file = sticker.file;
    [media loadDataForFile:file completion:^(NSData *data) {
        if (token != _token || !data || _lottie) return;
        _lottie = [[ExteriaLottieView alloc] initWithPackedData:data key:file.key];
        _lottie.frame = _layout.stickerFrame;
        _lottie.firstFrameHandler = ^{
            if (token == _token) _poster.hidden = YES;
        };
        [_lottie setLoaded:YES];
        [self insertSubview:_lottie aboveSubview:_poster];
        [self playIfDue];
    }];
}

/* the animation plays once, the first time the card is on screen; scrolling back does not run it again */
- (void)playIfDue {
    if (!_active || _played || !_lottie || ![self animationAllowed]) return;
    _played = YES;
    [_lottie playOnce];
}

- (void)setActive:(BOOL)active {
    _active = active;
    [_text setSparkling:active && [self animationAllowed]];
    [self playIfDue];
}

@end
