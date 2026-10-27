#import "exteria_welcome_toast.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define CARD_RADIUS 22.0
#define CARD_PAD 14.0
#define STICKER_SIDE 84.0
#define BUTTON_HEIGHT 38.0
#define CARD_MAX_WIDTH 440.0
#define SIDE_MARGIN 12.0
#define DROP_KEY @"welcome.toast.drop"

@interface ExteriaWelcomeToast () {
    UIView *_sticker;
    NSString *_titleText;
    NSString *_messageText;
    NSString *_primaryTitle;
    NSString *_secondaryTitle;
    NSString *_busyTitle;
    void (^_primaryHandler)(void);
    void (^_secondaryHandler)(void);
    void (^_dismissHandler)(void);
    NSTimeInterval _lifetime;
    UIView *_host;
    CGFloat _inset;
    UILabel *_title;
    UILabel *_message;
    UIButton *_primary;
    UIButton *_secondary;
    BOOL _shown;
    BOOL _leaving;
    CGFloat _drag;
}
@end

@implementation ExteriaWelcomeToast

@synthesize sticker = _sticker;
@synthesize titleText = _titleText;
@synthesize messageText = _messageText;
@synthesize primaryTitle = _primaryTitle;
@synthesize secondaryTitle = _secondaryTitle;
@synthesize busyTitle = _busyTitle;
@synthesize primaryHandler = _primaryHandler;
@synthesize secondaryHandler = _secondaryHandler;
@synthesize dismissHandler = _dismissHandler;
@synthesize lifetime = _lifetime;
@synthesize isShown = _shown;
@synthesize inset = _inset;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = CARD_RADIUS;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.22f;
    self.layer.shadowRadius = 14;
    self.layer.shadowOffset = CGSizeMake(0, 6);
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = ExteriaColorTitle();
    _title.font = ExteriaFontBold(17);
    /* a long title wraps onto as many lines as it needs, rather than ending in dots */
    _title.numberOfLines = 0;
    [self addSubview:_title];
    _message = [[UILabel alloc] init];
    _message.backgroundColor = [UIColor clearColor];
    _message.textColor = ExteriaColorMessage();
    _message.font = ExteriaFontRegular(14);
    _message.numberOfLines = 0;
    [self addSubview:_message];
    _primary = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _primary.titleLabel.font = ExteriaFontBold(15);
    _primary.layer.cornerRadius = BUTTON_HEIGHT / 2;
    _primary.backgroundColor = ExteriaColorAccent();
    [_primary setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_primary setTitleColor:[UIColor colorWithWhite:1 alpha:0.7] forState:UIControlStateDisabled];
    [_primary addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_primary];
    _secondary = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _secondary.titleLabel.font = ExteriaFontMedium(15);
    [_secondary setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_secondary addTarget:self action:@selector(secondaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_secondary];
    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)] autorelease];
    [self addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)] autorelease];
    /* ios 5 would otherwise hold the touch back from the buttons while it waits to see whether this is a tap */
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_sticker release];
    [_titleText release];
    [_messageText release];
    [_primaryTitle release];
    [_secondaryTitle release];
    [_busyTitle release];
    [_primaryHandler release];
    [_secondaryHandler release];
    [_dismissHandler release];
    [_title release];
    [_message release];
    [_primary release];
    [_secondary release];
    [super dealloc];
}

- (void)setSticker:(UIView *)sticker {
    if (sticker == _sticker) return;
    [_sticker removeFromSuperview];
    [_sticker release];
    _sticker = [sticker retain];
    if (_sticker) [self addSubview:_sticker];
}

#pragma mark layout

- (CGFloat)cardWidth {
    return MIN(_host.bounds.size.width - 2 * SIDE_MARGIN, CARD_MAX_WIDTH);
}

/* fits texts and buttons to the width and returns the height of the card; frames inside it are set here too */
- (CGFloat)fit {
    CGFloat width = [self cardWidth];
    CGFloat textX = CARD_PAD + (_sticker ? STICKER_SIDE + 12 : 0);
    CGFloat textWidth = width - textX - CARD_PAD;
    _title.text = _titleText;
    _message.text = _messageText;
    CGSize title = [_title sizeThatFits:CGSizeMake(textWidth, 400)];
    CGSize message = [_message sizeThatFits:CGSizeMake(textWidth, 400)];
    _title.frame = CGRectMake(textX, CARD_PAD, textWidth, ceil(title.height));
    _message.frame = CGRectMake(textX, CGRectGetMaxY(_title.frame) + 3, textWidth, ceil(message.height));
    CGFloat top = MAX(CGRectGetMaxY(_message.frame), CARD_PAD + (_sticker ? STICKER_SIDE : 0));
    _sticker.frame = CGRectMake(CARD_PAD, CARD_PAD, STICKER_SIDE, STICKER_SIDE);
    BOOL primary = _primaryTitle.length > 0, secondary = _secondaryTitle.length > 0;
    _primary.hidden = !primary;
    _secondary.hidden = !secondary;
    CGFloat y = top;
    if (primary || secondary) {
        y += 10;
        CGFloat secondaryWidth = secondary ? MIN(ceil(ExteriaStringSize(_secondaryTitle, _secondary.titleLabel.font).width) + 28, width / 2.5) : 0;
        CGFloat primaryWidth = width - 2 * CARD_PAD - (secondary ? secondaryWidth + 6 : 0);
        NSString *shown = _busyTitle.length ? _busyTitle : _primaryTitle;
        [_primary setTitle:shown forState:UIControlStateNormal];
        _primary.enabled = _busyTitle.length == 0;
        _primary.frame = CGRectMake(CARD_PAD, y, primaryWidth, BUTTON_HEIGHT);
        [_secondary setTitle:_secondaryTitle forState:UIControlStateNormal];
        _secondary.frame = CGRectMake(width - CARD_PAD - secondaryWidth, y, secondaryWidth, BUTTON_HEIGHT);
        if (!primary) _secondary.frame = CGRectMake(CARD_PAD, y, width - 2 * CARD_PAD, BUTTON_HEIGHT);
        y += BUTTON_HEIGHT;
    }
    return ceil(y + CARD_PAD);
}

- (CGRect)restFrame {
    CGFloat width = [self cardWidth];
    CGFloat height = [self fit];
    return CGRectMake(floor((_host.bounds.size.width - width) / 2), _inset + 8, width, height);
}

- (void)refresh {
    if (!_host) return;
    CGRect frame = [self restFrame];
    self.frame = CGRectMake(frame.origin.x, self.frame.origin.y, frame.size.width, frame.size.height);
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:CARD_RADIUS].CGPath;
}

#pragma mark showing

- (void)showInView:(UIView *)host inset:(CGFloat)inset {
    if (_shown) return;
    _shown = YES;
    _leaving = NO;
    _host = host;
    _inset = inset;
    self.frame = [self restFrame];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:CARD_RADIUS].CGPath;
    [host addSubview:self];
    if ([_sticker respondsToSelector:@selector(setLoaded:)]) [(id<ExteriaToastSticker>)_sticker setLoaded:YES];
    if ([_sticker respondsToSelector:@selector(setPlaying:)]) [(id<ExteriaToastSticker>)_sticker setPlaying:YES];
    if (!ExteriaReduceMotionEnabled()) {
        /* it drops past its place and settles back, as the cards of the platform do */
        CGFloat from = -(self.frame.origin.y + self.frame.size.height + 24);
        CAKeyframeAnimation *drop = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
        drop.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:(float)from], [NSNumber numberWithFloat:8], [NSNumber numberWithFloat:-3], [NSNumber numberWithFloat:0], nil];
        drop.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.55f], [NSNumber numberWithFloat:0.8f], [NSNumber numberWithFloat:1], nil];
        drop.timingFunctions = [NSArray arrayWithObjects:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
                                [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut], nil];
        drop.duration = 0.6;
        [self.layer addAnimation:drop forKey:DROP_KEY];
    }
    if (_lifetime > 0) [self performSelector:@selector(dismiss) withObject:nil afterDelay:_lifetime];
}

- (void)finishLeaving {
    [self removeFromSuperview];
    _shown = NO;
    _host = nil;
    if ([_sticker respondsToSelector:@selector(setPlaying:)]) [(id<ExteriaToastSticker>)_sticker setPlaying:NO];
    void (^handler)(void) = [[_dismissHandler copy] autorelease];
    /* the handler may build the next card, so it runs after this one is out of the way */
    if (handler) handler();
}

- (void)dismiss {
    if (!_shown || _leaving) return;
    _leaving = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dismiss) object:nil];
    [self retain];
    CGFloat distance = self.frame.origin.y + self.frame.size.height + 24;
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.28 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.transform = CGAffineTransformMakeTranslation(0, -distance + _drag);
        self.alpha = 0;
    } completion:^(BOOL finished) {
        (void)finished;
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1;
        [self finishLeaving];
        [self autorelease];
    }];
}

#pragma mark touches

- (void)primaryTapped {
    if (_primaryHandler) _primaryHandler();
}

- (void)secondaryTapped {
    if (_secondaryHandler) _secondaryHandler();
    else [self dismiss];
}

/* a card with no buttons has nothing else to press, so a tap on it sends it away */
- (void)tapped {
    if (_primaryTitle.length || _secondaryTitle.length) return;
    [self dismiss];
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    if (_leaving) return;
    CGFloat up = MIN(0, [pan translationInView:self.superview].y);
    if (pan.state == UIGestureRecognizerStateChanged) {
        _drag = up;
        self.transform = CGAffineTransformMakeTranslation(0, up);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat speed = [pan velocityInView:self.superview].y;
        if (pan.state == UIGestureRecognizerStateEnded && (up < -40 || speed < -500)) {
            [self dismiss];
            return;
        }
        _drag = 0;
        [UIView animateWithDuration:0.2 animations:^{ self.transform = CGAffineTransformIdentity; }];
    }
}

@end
