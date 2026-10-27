#import "exteria_device_sheet.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_settings_kit.h"
#import "exteria_sheet.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"
#import "exteria_time.h"

#define CARD_RADIUS 24.0
#define SIDE 16.0
#define ICON 84.0
#define ITEM_ICON 24.0
#define TEXT_LEFT 64.0
#define SLIDE_SECONDS 0.28
#define DISMISS_DISTANCE 90.0

@interface ExteriaDeviceSheet () <UIGestureRecognizerDelegate> {
    ExteriaDeviceSession *_device;
    void (^_secretChats)(BOOL);
    void (^_calls)(BOOL);
    void (^_end)(void);
    UIView *_dim;
    UIView *_card;
    UIScrollView *_scroll;
    ExteriaLottieView *_lottie;
    UIView *_disc;
    UIImageView *_picture;
    BOOL _closing;
}
@end

@implementation ExteriaDeviceSheet

+ (void)presentInView:(UIView *)host device:(ExteriaDeviceSession *)device
         secretChats:(void (^)(BOOL))secretChats calls:(void (^)(BOOL))calls end:(void (^)(void))end {
    ExteriaDeviceSheet *sheet = [[[ExteriaDeviceSheet alloc] initWithFrame:host.bounds device:device secretChats:secretChats calls:calls end:end] autorelease];
    sheet.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:sheet];
    [sheet rise];
}

static UILabel *ExteriaSheetLabel(UIFont *font, UIColor *color, NSInteger alignment) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

/* one row of the sheet: the glyph in grey at the left, the value over its description, and a switch when the row takes one */
- (UIView *)itemWithSymbol:(ExteriaSymbol)symbol value:(NSString *)value description:(NSString *)description width:(CGFloat)width
                    switchOn:(NSNumber *)switchOn toggle:(void (^)(BOOL))toggle tap:(void (^)(void))tap top:(CGFloat)top {
    CGFloat right = switchOn ? 76 : SIDE;
    UIControl *item = [[[UIControl alloc] init] autorelease];
    UIImageView *icon = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(symbol, ITEM_ICON, ExteriaColorSecondary())] autorelease];
    icon.frame = CGRectMake(SIDE + 2, 0, ITEM_ICON, ITEM_ICON);
    [item addSubview:icon];
    UILabel *valueLabel = ExteriaSheetLabel(ExteriaFontRegular(16), ExteriaColorTitle(), ExteriaTextAlignmentLeft);
    valueLabel.text = value;
    UILabel *descriptionLabel = ExteriaSheetLabel(ExteriaFontRegular(13), ExteriaColorSecondary(), ExteriaTextAlignmentLeft);
    descriptionLabel.text = description;
    descriptionLabel.numberOfLines = 0;
    CGFloat textWidth = width - TEXT_LEFT - right;
    CGFloat valueHeight = MAX(20, ceil(ExteriaStringSizeIn(value, valueLabel.font, CGSizeMake(textWidth, 200)).height));
    CGFloat descriptionHeight = ceil(ExteriaStringSizeIn(description, descriptionLabel.font, CGSizeMake(textWidth, 200)).height);
    valueLabel.numberOfLines = 0;
    valueLabel.frame = CGRectMake(TEXT_LEFT, 8, textWidth, valueHeight);
    descriptionLabel.frame = CGRectMake(TEXT_LEFT, 8 + valueHeight + 4, textWidth, descriptionHeight);
    [item addSubview:valueLabel];
    [item addSubview:descriptionLabel];
    CGFloat height = 8 + valueHeight + 4 + descriptionHeight + 10;
    icon.frame = CGRectMake(SIDE + 2, (height - ITEM_ICON) / 2, ITEM_ICON, ITEM_ICON);
    item.frame = CGRectMake(0, top, width, height);
    if (switchOn) {
        UISwitch *toggleView = [[[UISwitch alloc] init] autorelease];
        toggleView.on = switchOn.boolValue;
        CGSize size = toggleView.frame.size;
        toggleView.frame = CGRectMake(width - SIDE - size.width, (height - size.height) / 2, size.width, size.height);
        void (^handler)(BOOL) = [toggle copy];
        objc_setAssociatedObject(toggleView, "handler", handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [handler release];
        [toggleView addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [item addSubview:toggleView];
        /* a tap anywhere on the row turns the switch sheet */
        item.tag = 1;
        [item addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    } else if (tap) {
        void (^handler)(void) = [tap copy];
        objc_setAssociatedObject(item, "tap", handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [handler release];
        [item addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    return item;
}

- (void)switchChanged:(UISwitch *)toggle {
    void (^handler)(BOOL) = objc_getAssociatedObject(toggle, "handler");
    if (handler) handler(toggle.on);
}

- (void)rowTapped:(UIControl *)row {
    if (row.tag == 1) {
        for (UIView *view in row.subviews) {
            if ([view isKindOfClass:[UISwitch class]]) {
                UISwitch *toggle = (UISwitch *)view;
                [toggle setOn:!toggle.on animated:YES];
                [self switchChanged:toggle];
            }
        }
        return;
    }
    void (^tap)(void) = objc_getAssociatedObject(row, "tap");
    if (tap) tap();
}

- (id)initWithFrame:(CGRect)frame device:(ExteriaDeviceSession *)device secretChats:(void (^)(BOOL))secretChats calls:(void (^)(BOOL))calls end:(void (^)(void))end {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _device = [device retain];
    _secretChats = [secretChats copy];
    _calls = [calls copy];
    _end = [end copy];
    _dim = [[UIView alloc] initWithFrame:self.bounds];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    [self addSubview:_dim];
    [self buildCard];
    return self;
}

- (void)dealloc {
    [_device release];
    [_secretChats release];
    [_calls release];
    [_end release];
    [_dim release];
    [_card release];
    [_scroll release];
    [_lottie release];
    [_disc release];
    [_picture release];
    [super dealloc];
}

- (NSString *)timeLine {
    return _device.current ? NSLocalizedString(@"devices.online", nil)
                           : [NSString stringWithFormat:NSLocalizedString(@"devices.last", nil), ExteriaMediaTimeText(_device.dateActive)];
}

- (void)buildCard {
    CGFloat width = MIN(self.bounds.size.width, 520);
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = CARD_RADIUS;
    [self addSubview:_card];
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.bounces = NO;
    [_card addSubview:_scroll];

    CGFloat y = 18;
    /* the circle takes the flat color of the device; the animation is drawn over it, or the picture when the kind has none */
    exteria_session_kind kind = _device.kind;
    _disc = [[UIView alloc] initWithFrame:CGRectMake((width - ICON) / 2, y, ICON, ICON)];
    _disc.backgroundColor = ExteriaDeviceColor(kind);
    _disc.layer.cornerRadius = ICON / 2;
    [_scroll addSubview:_disc];
    NSString *animation = ExteriaDeviceAnimationName(kind);
    if (animation) {
        _lottie = [[ExteriaLottieView alloc] initWithAnimationNamed:animation];
        _lottie.frame = _disc.bounds;
        _lottie.userInteractionEnabled = NO;
        [_disc addSubview:_lottie];
    } else {
        _picture = [[UIImageView alloc] initWithImage:ExteriaDeviceIconImage(kind, ICON)];
        _picture.frame = _disc.bounds;
        [_disc addSubview:_picture];
    }
    [_disc addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replay)] autorelease]];
    _disc.userInteractionEnabled = YES;
    y += ICON + 16;

    UILabel *name = ExteriaSheetLabel(ExteriaFontSemibold(21), ExteriaColorTitle(), ExteriaTextAlignmentCenter);
    name.text = _device.title;
    name.numberOfLines = 2;
    CGFloat nameHeight = ceil(ExteriaStringSizeIn(name.text, name.font, CGSizeMake(width - 2 * SIDE - 8, 100)).height);
    name.frame = CGRectMake(SIDE + 4, y, width - 2 * SIDE - 8, nameHeight);
    [_scroll addSubview:name];
    y += nameHeight + 6;
    UILabel *time = ExteriaSheetLabel(ExteriaFontRegular(14), ExteriaColorSecondary(), ExteriaTextAlignmentCenter);
    time.text = [self timeLine];
    time.frame = CGRectMake(SIDE, y, width - 2 * SIDE, 18);
    [_scroll addSubview:time];
    y += 18 + 22;

    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[self itemWithSymbol:ExteriaSymbolAppDevices value:_device.appLine description:NSLocalizedString(@"devices.application", nil)
                                    width:width switchOn:nil toggle:nil tap:nil top:0]];
    if (_device.place.length) {
        NSString *place = _device.place;
        [items addObject:[self itemWithSymbol:ExteriaSymbolMapPin value:place description:NSLocalizedString(@"devices.location", nil) width:width
                                      switchOn:nil toggle:nil tap:^{ [self copyText:place]; } top:0]];
    }
    if (_device.ip.length) {
        NSString *ip = _device.ip;
        [items addObject:[self itemWithSymbol:ExteriaSymbolGlobe value:ip description:NSLocalizedString(@"devices.ip", nil) width:width switchOn:nil toggle:nil
                                         tap:^{ [self copyText:ip]; } top:0]];
    }
    if (_device.takesSecretChatsSetting) {
        [items addObject:[self itemWithSymbol:ExteriaSymbolLock value:NSLocalizedString(@"devices.secret", nil) description:NSLocalizedString(@"devices.secret.info", nil)
                                        width:width switchOn:[NSNumber numberWithBool:_device.secretChatsOn] toggle:_secretChats tap:nil top:0]];
    }
    if (_device.takesCallsSetting) {
        [items addObject:[self itemWithSymbol:ExteriaSymbolPhone value:NSLocalizedString(@"devices.calls", nil) description:NSLocalizedString(@"devices.calls.info", nil)
                                        width:width switchOn:[NSNumber numberWithBool:_device.callsOn] toggle:_calls tap:nil top:0]];
    }
    for (NSUInteger i = 0; i < items.count; ++i) {
        UIView *item = [items objectAtIndex:i];
        CGRect frame = item.frame;
        frame.origin.y = y;
        item.frame = frame;
        [_scroll addSubview:item];
        y += frame.size.height;
        if (i + 1 < items.count) {
            UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(TEXT_LEFT, y - 0.5, width - TEXT_LEFT, 1.0 / ExteriaScreenScale())] autorelease];
            line.backgroundColor = ExteriaColorHairline();
            [_scroll addSubview:line];
        }
    }
    y += 6;
    if (!_device.current) {
        UIButton *end = [UIButton buttonWithType:UIButtonTypeCustom];
        end.frame = CGRectMake(SIDE, y + 8, width - 2 * SIDE, 48);
        end.backgroundColor = ExteriaColorBadgeRed();
        end.layer.cornerRadius = 24;
        end.titleLabel.font = ExteriaFontSemibold(15);
        [end setTitle:NSLocalizedString(@"devices.end", nil) forState:UIControlStateNormal];
        [end setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [end addTarget:self action:@selector(endTapped) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:end];
        y += 8 + 48 + 8;
    }
    y += 12;
    _scroll.contentSize = CGSizeMake(width, y);
    _scroll.frame = CGRectMake(0, 0, width, MIN(y, self.bounds.size.height * 0.88));
    CGFloat cardHeight = _scroll.frame.size.height;
    _card.frame = CGRectMake((self.bounds.size.width - width) / 2, self.bounds.size.height, width, cardHeight + CARD_RADIUS);
    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)] autorelease];
    pan.delegate = self;
    [_card addGestureRecognizer:pan];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_closing && _card.frame.origin.y < self.bounds.size.height) {
        CGRect frame = _card.frame;
        frame.origin.x = (self.bounds.size.width - frame.size.width) / 2;
        frame.origin.y = self.bounds.size.height - _card.frame.size.height + CARD_RADIUS;
        _card.frame = frame;
    }
}

- (void)rise {
    _dim.alpha = 0;
    CGRect frame = _card.frame;
    frame.origin.y = self.bounds.size.height - frame.size.height + CARD_RADIUS;
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : SLIDE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _dim.alpha = 1;
        _card.frame = frame;
    } completion:^(BOOL finished) {
        (void)finished;
        [_lottie playOnce];
    }];
}

- (void)replay {
    [_lottie rewind];
    [_lottie playOnce];
}

- (void)dismissAnimated:(BOOL)animated then:(void (^)(void))then {
    if (_closing) return;
    _closing = YES;
    void (^after)(void) = [then copy];
    [self retain];
    [UIView animateWithDuration:animated && !ExteriaReduceMotionEnabled() ? 0.22 : 0 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        _dim.alpha = 0;
        CGRect frame = _card.frame;
        frame.origin.y = self.bounds.size.height;
        _card.frame = frame;
    } completion:^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (after) after();
        [after release];
        [self release];
    }];
}

- (void)dismiss {
    [self dismissAnimated:YES then:nil];
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    CGFloat rest = self.bounds.size.height - _card.frame.size.height + CARD_RADIUS;
    CGFloat pull = MAX(0, [pan translationInView:self].y);
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGRect frame = _card.frame;
        frame.origin.y = rest + pull;
        _card.frame = frame;
        _dim.alpha = MAX(0, 1 - pull / 300);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (pull > DISMISS_DISTANCE || [pan velocityInView:self].y > 900) {
            [self dismiss];
            return;
        }
        [UIView animateWithDuration:0.2 animations:^{
            CGRect frame = _card.frame;
            frame.origin.y = rest;
            _card.frame = frame;
            _dim.alpha = 1;
        }];
    }
}

/* a pull on the card only closes the sheet when the list inside it is at its top */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (![recognizer isKindOfClass:[UIPanGestureRecognizer class]]) return YES;
    CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:self];
    return fabs(velocity.y) > fabs(velocity.x) && velocity.y > 0 && _scroll.contentOffset.y <= 0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)recognizer;
    (void)other;
    return YES;
}

- (void)copyText:(NSString *)text {
    NSString *copy = [text copy];
    [ExteriaSheet presentInView:self title:nil message:nil options:[NSArray arrayWithObject:NSLocalizedString(@"devices.copy", nil)] destructive:nil
                    cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        (void)index;
        [UIPasteboard generalPasteboard].string = copy;
    }];
    [copy release];
}

- (void)endTapped {
    void (^end)(void) = [_end copy];
    [self retain];
    [ExteriaSheet presentInView:self title:nil message:NSLocalizedString(@"devices.end.confirm", nil)
                        options:[NSArray arrayWithObject:NSLocalizedString(@"devices.terminate", nil)] destructive:[NSIndexSet indexSetWithIndex:0]
                    cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        (void)index;
        [self dismissAnimated:YES then:end];
    }];
    [end release];
    [self release];
}

@end
