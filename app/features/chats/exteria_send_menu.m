#import "exteria_send_menu.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_session.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define EFFECT_SIDE 44.0
#define EFFECT_COLUMNS 6
#define ROW_HEIGHT 48.0
#define CARD_PADDING 8.0
#define CARD_WIDTH 300.0

@interface ExteriaSendMenu () {
    UIView *_card;
    void (^_handler)(ExteriaSendMenuChoice, long long);
    NSMutableArray *_effectIds;
}
@end

@implementation ExteriaSendMenu

+ (void)presentAboveRect:(CGRect)anchor inView:(UIView *)host effects:(NSArray *)effects handler:(void (^)(ExteriaSendMenuChoice, long long))handler {
    if (!host) return;
    ExteriaSendMenu *menu = [[[ExteriaSendMenu alloc] initWithFrame:host.bounds] autorelease];
    menu.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [menu buildWithAnchor:anchor effects:effects handler:handler];
    menu.alpha = 0;
    [host addSubview:menu];
    menu->_card.transform = CGAffineTransformMakeScale(0.9, 0.9);
    [UIView animateWithDuration:0.2 animations:^{
        menu.alpha = 1;
        menu->_card.transform = CGAffineTransformIdentity;
    }];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
    [self addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    _effectIds = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [_card release];
    [_handler release];
    [_effectIds release];
    [super dealloc];
}

- (UIButton *)rowWithTitle:(NSString *)title symbol:(ExteriaSymbol)symbol tag:(NSInteger)tag y:(CGFloat)y width:(CGFloat)width {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, y, width, ROW_HEIGHT);
    row.tag = tag;
    row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    row.contentEdgeInsets = UIEdgeInsetsMake(0, 52, 0, 12);
    [row setTitle:title forState:UIControlStateNormal];
    [row setTitleColor:ExteriaColorTitle() forState:UIControlStateNormal];
    row.titleLabel.font = ExteriaFontRegular(17);
    UIImageView *icon = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(symbol, 22, ExteriaColorTitle())] autorelease];
    icon.frame = CGRectMake(16, (ROW_HEIGHT - 22) / 2, 22, 22);
    icon.userInteractionEnabled = NO;
    [row addSubview:icon];
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    return row;
}

- (void)buildWithAnchor:(CGRect)anchor effects:(NSArray *)effects handler:(void (^)(ExteriaSendMenuChoice, long long))handler {
    _handler = [handler copy];
    CGFloat width = MIN(CARD_WIDTH, self.bounds.size.width - 24);
    NSUInteger rows = (effects.count + EFFECT_COLUMNS - 1) / EFFECT_COLUMNS;
    CGFloat effectsHeight = effects.count ? rows * EFFECT_SIDE + CARD_PADDING * 2 + 22 : 0;
    CGFloat height = effectsHeight + 2 * ROW_HEIGHT;
    CGFloat x = MIN(self.bounds.size.width - width - 12, MAX(12, CGRectGetMaxX(anchor) - width));
    CGFloat y = MAX(12, CGRectGetMinY(anchor) - 10 - height);
    _card = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
    _card.backgroundColor = ExteriaColorBar();
    _card.layer.cornerRadius = 18;
    _card.layer.masksToBounds = YES;
    [self addSubview:_card];
    CGFloat at = 0;
    if (effects.count) {
        UILabel *head = [[[UILabel alloc] initWithFrame:CGRectMake(16, 10, width - 32, 18)] autorelease];
        head.backgroundColor = [UIColor clearColor];
        head.font = ExteriaFontSemibold(13);
        head.textColor = ExteriaColorSecondary();
        head.text = NSLocalizedString(@"chat.send.effect", nil);
        [_card addSubview:head];
        CGFloat gridWidth = EFFECT_COLUMNS * EFFECT_SIDE;
        CGFloat left = (width - gridWidth) / 2;
        for (NSUInteger i = 0; i < effects.count; ++i) {
            ExteriaMessageEffect *effect = [effects objectAtIndex:i];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.frame = CGRectMake(left + (i % EFFECT_COLUMNS) * EFFECT_SIDE, 30 + (i / EFFECT_COLUMNS) * EFFECT_SIDE, EFFECT_SIDE, EFFECT_SIDE);
            button.tag = (NSInteger)i;
            ExteriaEmojiLabel *label = [[[ExteriaEmojiLabel alloc] init] autorelease];
            label.backgroundColor = [UIColor clearColor];
            label.text = effect.emoticon;
            label.font = ExteriaFontRegular(26);
            label.textAlignment = ExteriaTextAlignmentCenter;
            label.userInteractionEnabled = NO;
            label.frame = CGRectMake(0, 4, EFFECT_SIDE, EFFECT_SIDE - 8);
            [button addSubview:label];
            [button addTarget:self action:@selector(effectTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_card addSubview:button];
            [_effectIds addObject:[NSNumber numberWithLongLong:effect.effectId]];
        }
        at = effectsHeight;
        UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(0, at - 1.0 / ExteriaScreenScale(), width, 1.0 / ExteriaScreenScale())] autorelease];
        line.backgroundColor = ExteriaColorHairline();
        [_card addSubview:line];
    }
    [_card addSubview:[self rowWithTitle:NSLocalizedString(@"chat.send.silent", nil) symbol:ExteriaSymbolBellMuted tag:ExteriaSendMenuSilent y:at width:width]];
    [_card addSubview:[self rowWithTitle:NSLocalizedString(@"chat.send.later", nil) symbol:ExteriaSymbolClock tag:ExteriaSendMenuLater y:at + ROW_HEIGHT width:width]];
}

/* the choice is told after the card is gone, so what it opens (a sheet for the time) does not stand over it */
- (void)finish:(ExteriaSendMenuChoice)choice effect:(long long)effectId {
    void (^handler)(ExteriaSendMenuChoice, long long) = [_handler retain];
    [UIView animateWithDuration:0.12 animations:^{ self.alpha = 0; } completion:^(BOOL done) {
        (void)done;
        [self removeFromSuperview];
        if (handler) handler(choice, effectId);
        [handler release];
    }];
}

- (void)rowTapped:(UIButton *)row {
    [self finish:(ExteriaSendMenuChoice)row.tag effect:0];
}

- (void)effectTapped:(UIButton *)button {
    if ((NSUInteger)button.tag >= _effectIds.count) return;
    [self finish:ExteriaSendMenuEffect effect:[[_effectIds objectAtIndex:(NSUInteger)button.tag] longLongValue]];
}

- (void)dismiss {
    [UIView animateWithDuration:0.12 animations:^{ self.alpha = 0; } completion:^(BOOL done) {
        (void)done;
        [self removeFromSuperview];
    }];
}

@end
