#import "exteria_popup_menu.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define ROW_HEIGHT 48.0
/* a long menu on a short screen gets rows down to this height before it scrolls */
#define ROW_HEIGHT_MIN 38.0
#define EDGE_MARGIN 10.0
#define CARD_WIDTH 232.0
#define ICON_SIDE 22.0

@interface ExteriaPopupMenu () {
    NSArray *_titles;
    ExteriaSymbol *_symbols;
    void (^_handler)(NSUInteger);
    UIView *_card;
    CGFloat _rowHeight;
    CGPoint _anchor;
    CGFloat _bottomInset;
    BOOL _closing;
}
@end

@implementation ExteriaPopupMenu

@synthesize bottomInset = _bottomInset;

- (id)initWithTitles:(NSArray *)titles symbols:(const ExteriaSymbol *)symbols handler:(void (^)(NSUInteger))handler {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _titles = [titles copy];
    _symbols = malloc(sizeof(ExteriaSymbol) * (titles.count ? titles.count : 1));
    memcpy(_symbols, symbols, sizeof(ExteriaSymbol) * titles.count);
    _handler = [handler copy];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease];
    [self addGestureRecognizer:tap];
    return self;
}

- (void)dealloc {
    free(_symbols);
    [_titles release];
    [_handler release];
    [_card release];
    [super dealloc];
}

/* the card always fits the screen: the rows shrink a little first, and a menu that is still too tall scrolls inside its card */
- (void)buildCardWithin:(CGFloat)room {
    NSUInteger count = _titles.count ? _titles.count : 1;
    _rowHeight = ROW_HEIGHT;
    if (_rowHeight * (CGFloat)count > room) _rowHeight = MAX(ROW_HEIGHT_MIN, floor(room / (CGFloat)count));
    CGFloat content = _rowHeight * (CGFloat)_titles.count;
    CGFloat height = MIN(content, room);
    _card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CARD_WIDTH, height)];
    UIView *rows = _card;
    if (content > height) {
        UIScrollView *scroll = [[[UIScrollView alloc] initWithFrame:_card.bounds] autorelease];
        scroll.contentSize = CGSizeMake(CARD_WIDTH, content);
        scroll.layer.cornerRadius = 14;
        scroll.clipsToBounds = YES;
        scroll.showsVerticalScrollIndicator = NO;
        [_card addSubview:scroll];
        rows = scroll;
    }
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = 14;
    _card.layer.shadowColor = [UIColor blackColor].CGColor;
    _card.layer.shadowOpacity = ExteriaThemeIsDark() ? 0.5 : 0.22;
    _card.layer.shadowRadius = 12;
    _card.layer.shadowOffset = CGSizeMake(0, 4);
    for (NSUInteger i = 0; i < _titles.count; ++i) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0, _rowHeight * (CGFloat)i, CARD_WIDTH, _rowHeight);
        row.tag = (NSInteger)i;
        [row addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
        [row addTarget:self action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown];
        [row addTarget:self action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        UIImageView *icon = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(_symbols[i], ICON_SIDE, ExteriaColorSecondary())] autorelease];
        icon.contentMode = UIViewContentModeCenter;
        icon.frame = CGRectMake(16, (_rowHeight - ICON_SIDE) / 2, ICON_SIDE + 4, ICON_SIDE);
        icon.userInteractionEnabled = NO;
        [row addSubview:icon];
        UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(56, 0, CARD_WIDTH - 70, _rowHeight)] autorelease];
        label.backgroundColor = [UIColor clearColor];
        label.font = ExteriaFontMedium(16);
        label.textColor = ExteriaColorTitle();
        label.text = [_titles objectAtIndex:i];
        label.userInteractionEnabled = NO;
        [row addSubview:label];
        [rows addSubview:row];
    }
    [self addSubview:_card];
}

- (void)rowDown:(UIButton *)row {
    row.backgroundColor = ExteriaColorField();
}

- (void)rowUp:(UIButton *)row {
    row.backgroundColor = [UIColor clearColor];
}

- (void)showInView:(UIView *)host anchor:(CGPoint)anchor {
    if (self.superview) return;
    /* the classic navigation bar lies outside the host and keeps taking taps while a card is open, so a second tap on its button would stack another card; it closes the open one instead */
    for (UIView *open in host.subviews) {
        if (![open isKindOfClass:[ExteriaPopupMenu class]]) continue;
        [(ExteriaPopupMenu *)open dismiss];
        return;
    }
    _closing = NO;
    self.userInteractionEnabled = YES;
    [_card removeFromSuperview];
    [_card release];
    _card = nil;
    self.frame = host.bounds;
    _anchor = anchor;
    CGFloat bottom = MAX(EDGE_MARGIN + ROW_HEIGHT_MIN, host.bounds.size.height - MAX(0, _bottomInset) - EDGE_MARGIN);
    CGFloat start = MAX(EDGE_MARGIN, MIN(anchor.y, bottom - ROW_HEIGHT_MIN));
    [self buildCardWithin:bottom - start];
    CGFloat x = MIN(MAX(8, anchor.x - CARD_WIDTH), host.bounds.size.width - CARD_WIDTH - 8);
    /* it hangs from the anchor when there is room under it, and slides up just far enough to end above the bottom edge when there is not */
    CGFloat height = _card.frame.size.height;
    CGFloat top = MAX(EDGE_MARGIN, MIN(anchor.y, bottom - height));
    _card.frame = CGRectMake(x, top, CARD_WIDTH, height);
    [host addSubview:self];
    _card.layer.anchorPoint = CGPointMake(1, 0);
    _card.layer.position = CGPointMake(x + CARD_WIDTH, top);
    _card.transform = CGAffineTransformMakeScale(0.8, 0.8);
    _card.alpha = 0;
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
}

- (void)leaveThen:(void (^)(void))after {
    if (_closing) return;
    _closing = YES;
    void (^next)(void) = [after copy];
    self.userInteractionEnabled = NO;
    ExteriaAnimateView(_card, CGAffineTransformMakeScale(0.8, 0.8), 0, EXTERIA_MOTION_EXIT, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (next) next();
        [next release];
    });
}

- (void)dismiss {
    [self leaveThen:nil];
}

- (void)picked:(UIButton *)row {
    if (_closing) return;
    NSUInteger index = (NSUInteger)row.tag;
    void (^handler)(NSUInteger) = [_handler retain];
    [self retain];
    [self leaveThen:^{
        handler(index);
        [handler release];
        [self release];
    }];
}

@end
