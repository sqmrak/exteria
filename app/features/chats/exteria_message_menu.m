#import "exteria_message_menu.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_dismiss_pan.h"
#import "exteria_blur.h"
#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#include "exteria_reaction_layout.h"

#define CARD_WIDTH 250.0
#define ROW_HEIGHT 48.0
#define HEADER_HEIGHT 44.0
#define BAND_HEIGHT 7.0
#define ICON_ROW_HEIGHT 56.0
#define PILL_HEIGHT 52.0
#define PILL_ITEM 42.0
#define PILL_PAD 7.0
#define GAP 8.0
#define EDGE 10.0
/* how many text rows show before the rest go behind "More" */
#define ROWS_SHOWN 3
#define REACTIONS_SHOWN 7
#define MORE_TAG 0xFFFFu

@implementation ExteriaMenuItem

@synthesize title = _title;
@synthesize symbol = _symbol;
@synthesize tag = _tag;
@synthesize destructive = _destructive;

+ (ExteriaMenuItem *)itemWithTitle:(NSString *)title symbol:(ExteriaSymbol)symbol tag:(NSUInteger)tag destructive:(BOOL)destructive {
    ExteriaMenuItem *item = [[[ExteriaMenuItem alloc] init] autorelease];
    item.title = title;
    item.symbol = symbol;
    item.tag = tag;
    item.destructive = destructive;
    return item;
}

- (void)dealloc {
    [_title release];
    [super dealloc];
}

@end

@interface ExteriaMessageMenu () {
    NSArray *_rows;
    NSArray *_icons;
    NSArray *_reactions;
    NSString *_headerText;
    BOOL _headerRead;
    BOOL _expanded;
    BOOL _closing;
    UIControl *_dim;
    UIView *_litClip;
    UIImageView *_lit;
    CGRect _litOriginalFrame;
    UIView *_pill;
    UIView *_card;
    /* the parts of the header that a late answer changes in place, so the card does not have to be built again while it is still coming in */
    UIImageView *_headerMark;
    UILabel *_headerLabel;
    UIView *_headerView;
    BOOL _shown;
    CGRect _bubble;
    BOOL _outgoing;
    void (^_pickHandler)(NSUInteger tag);
    void (^_reactionHandler)(ExteriaReaction *reaction);
    void (^_moreReactionsHandler)(void);
    void (^_dismissHandler)(void);
    void (^_headerHandler)(void);
}
@end

@implementation ExteriaMessageMenu

@synthesize rows = _rows;
@synthesize icons = _icons;
@synthesize pickHandler = _pickHandler;
@synthesize reactionHandler = _reactionHandler;
@synthesize moreReactionsHandler = _moreReactionsHandler;
@synthesize dismissHandler = _dismissHandler;
@synthesize headerHandler = _headerHandler;

- (void)dealloc {
    [_rows release];
    [_icons release];
    [_reactions release];
    [_headerText release];
    [_dim release];
    [_lit release];
    [_litClip release];
    [_pill release];
    [_card release];
    [_headerMark release];
    [_headerLabel release];
    [_headerView release];
    [_pickHandler release];
    [_reactionHandler release];
    [_moreReactionsHandler release];
    [_dismissHandler release];
    [_headerHandler release];
    [super dealloc];
}

#pragma mark skin

static BOOL ExteriaMenuClassic(void) { return ExteriaThemeIsClassic(); }

/* the classic plate is charcoal on the dark tone, and a pale glossy one on the white tone, where a black plate sat on the light list like a hole */
static BOOL ExteriaMenuCharcoal(void) { return ExteriaMenuClassic() && ExteriaThemeIsDark(); }

static UIColor *ExteriaMenuText(void) { return ExteriaMenuCharcoal() ? [UIColor whiteColor] : ExteriaColorTitle(); }
static UIColor *ExteriaMenuRed(void) { return ExteriaMenuCharcoal() ? [UIColor colorWithRed:1 green:0.45 blue:0.40 alpha:1] : ExteriaColorBadgeRed(); }
static UIColor *ExteriaMenuBand(void) {
    if (ExteriaMenuCharcoal()) return [UIColor colorWithWhite:0 alpha:0.35];
    return ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.07] : [UIColor colorWithWhite:0 alpha:0.06];
}

/* the plate behind the rows: a flat card in the modern style, a glossy charcoal plate with a lit edge in the classic one */
static void ExteriaMenuSkin(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = ExteriaMenuCharcoal() ? 0.6 : (ExteriaMenuClassic() ? 0.35 : (ExteriaThemeIsDark() ? 0.5 : 0.22));
    view.layer.shadowRadius = ExteriaMenuClassic() ? 10 : 14;
    view.layer.shadowOffset = CGSizeMake(0, ExteriaMenuClassic() ? 4 : 5);
    if (ExteriaMenuClassic()) {
        CAGradientLayer *gloss = [CAGradientLayer layer];
        if (ExteriaMenuCharcoal()) {
            gloss.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:0.30 alpha:1].CGColor, (id)[UIColor colorWithWhite:0.15 alpha:1].CGColor,
                            (id)[UIColor colorWithWhite:0.10 alpha:1].CGColor, nil];
        } else {
            gloss.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:1.0 alpha:1].CGColor, (id)[UIColor colorWithWhite:0.95 alpha:1].CGColor,
                            (id)[UIColor colorWithWhite:0.90 alpha:1].CGColor, nil];
        }
        gloss.locations = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.5], [NSNumber numberWithFloat:1], nil];
        gloss.cornerRadius = radius;
        gloss.borderColor = [UIColor colorWithWhite:ExteriaMenuCharcoal() ? 0.52 : 0.68 alpha:1].CGColor;
        gloss.borderWidth = 1;
        gloss.name = @"plate";
        gloss.frame = view.bounds;
        [view.layer insertSublayer:gloss atIndex:0];
    } else {
        view.backgroundColor = ExteriaColorCard();
    }
}

#pragma mark content

- (void)setHeaderText:(NSString *)text read:(BOOL)read {
    BOOL hadHeader = _headerText.length > 0;
    [_headerText release];
    _headerText = [text copy];
    _headerRead = read;
    if (!_card) return;
    /* the same line with other words keeps the card as it is; only a header that appears or goes needs the rows moved */
    if (hadHeader && _headerText.length && _headerLabel) {
        _headerLabel.text = _headerText;
        _headerMark.image = ExteriaCheckImage(_headerRead, 18, ExteriaMenuText());
        if (_headerHandler && _headerView.subviews.count < 3) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.frame = _headerView.bounds;
            button.accessibilityLabel = _headerText;
            [button addTarget:self action:@selector(headerTapped) forControlEvents:UIControlEventTouchUpInside];
            [_headerView addSubview:button];
        }
        return;
    }
    [self rebuildAnimated:NO];
}

- (void)setReactions:(NSArray *)reactions {
    [_reactions release];
    _reactions = [reactions copy];
    if (!_card) return;
    if (!_shown) {
        [self rebuildAnimated:NO];
        return;
    }
    /* the answer came after the menu was up: the pill grows in beside the card, and the card stays where it is drawn */
    [_pill removeFromSuperview];
    [_pill release];
    _pill = _reactions.count ? [[self buildPill] retain] : nil;
    if (!_pill) return;
    [self addSubview:_pill];
    _pill.alpha = 0;
    _pill.transform = CGAffineTransformMakeScale(0.92, 0.92);
    [self layoutStack];
    ExteriaAnimateView(_pill, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
}

/* the rows that show now: all of them, or the first few and the entry that opens the rest */
- (NSArray *)visibleRows {
    if (_expanded || _rows.count <= ROWS_SHOWN + 1) return _rows;
    NSMutableArray *shown = [NSMutableArray arrayWithArray:[_rows subarrayWithRange:NSMakeRange(0, ROWS_SHOWN)]];
    [shown addObject:[ExteriaMenuItem itemWithTitle:NSLocalizedString(@"chat.msg.more", nil) symbol:ExteriaSymbolEllipsis tag:MORE_TAG destructive:NO]];
    return shown;
}

- (UIView *)bandOfWidth:(CGFloat)width {
    UIView *band = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, BAND_HEIGHT)] autorelease];
    band.backgroundColor = ExteriaMenuBand();
    return band;
}

- (UIButton *)rowForItem:(ExteriaMenuItem *)item width:(CGFloat)width {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, 0, width, ROW_HEIGHT);
    row.tag = (NSInteger)item.tag;
    row.accessibilityLabel = item.title;
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    [row addTarget:self action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown];
    [row addTarget:self action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    UIColor *color = item.destructive ? ExteriaMenuRed() : ExteriaMenuText();
    UIImageView *icon = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(item.symbol, 24, color)] autorelease];
    icon.contentMode = UIViewContentModeCenter;
    icon.frame = CGRectMake(14, (ROW_HEIGHT - 28) / 2, 30, 28);
    icon.userInteractionEnabled = NO;
    [row addSubview:icon];
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(58, 0, width - 70, ROW_HEIGHT)] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = ExteriaMenuClassic() ? [UIFont boldSystemFontOfSize:16] : ExteriaFontMedium(16.5);
    label.textColor = color;
    label.text = item.title;
    label.userInteractionEnabled = NO;
    if (ExteriaMenuCharcoal()) {
        label.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
        label.shadowOffset = CGSizeMake(0, -1);
    } else if (ExteriaMenuClassic()) {
        label.shadowColor = [UIColor colorWithWhite:1 alpha:0.8];
        label.shadowOffset = CGSizeMake(0, 1);
    }
    [row addSubview:label];
    return row;
}

- (void)rowDown:(UIButton *)row {
    row.backgroundColor = ExteriaMenuCharcoal() ? [UIColor colorWithWhite:1 alpha:0.14] : (ExteriaMenuClassic() ? [UIColor colorWithWhite:0 alpha:0.08] : ExteriaColorField());
}

- (void)rowUp:(UIButton *)row { row.backgroundColor = [UIColor clearColor]; }

/* the card: header, rows and glyph row, with a band between each part, built again whenever its content or the open "More" changes */
- (UIView *)buildCardWithMaxHeight:(CGFloat)maxHeight {
    CGFloat width = MIN(CARD_WIDTH, self.bounds.size.width - 2 * EDGE);
    UIView *content = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 0)] autorelease];
    CGFloat y = 0;
    [_headerMark release];
    [_headerLabel release];
    [_headerView release];
    _headerMark = nil;
    _headerLabel = nil;
    _headerView = nil;
    if (_headerText.length) {
        UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, y, width, HEADER_HEIGHT)] autorelease];
        _headerView = [header retain];
        UIImageView *mark = [[[UIImageView alloc] initWithImage:ExteriaCheckImage(_headerRead, 18, ExteriaMenuText())] autorelease];
        mark.frame = CGRectMake(16, (HEADER_HEIGHT - mark.image.size.height) / 2, mark.image.size.width, mark.image.size.height);
        _headerMark = [mark retain];
        [header addSubview:mark];
        CGFloat textX = CGRectGetMaxX(mark.frame) + 10;
        UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(textX, 0, width - textX - 12, HEADER_HEIGHT)] autorelease];
        label.backgroundColor = [UIColor clearColor];
        label.font = ExteriaMenuClassic() ? [UIFont boldSystemFontOfSize:15] : ExteriaFontMedium(15.5);
        label.textColor = ExteriaMenuText();
        label.text = _headerText;
        label.adjustsFontSizeToFitWidth = YES;
        _headerLabel = [label retain];
        [header addSubview:label];
        if (_headerHandler) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.frame = header.bounds;
            button.accessibilityLabel = _headerText;
            [button addTarget:self action:@selector(headerTapped) forControlEvents:UIControlEventTouchUpInside];
            [header addSubview:button];
        }
        [content addSubview:header];
        y += HEADER_HEIGHT;
        UIView *band = [self bandOfWidth:width];
        band.frame = CGRectMake(0, y, width, BAND_HEIGHT);
        [content addSubview:band];
        y += BAND_HEIGHT;
    }
    NSArray *visible = [self visibleRows];
    for (NSUInteger i = 0; i < visible.count; ++i) {
        UIButton *row = [self rowForItem:[visible objectAtIndex:i] width:width];
        row.frame = CGRectMake(0, y, width, ROW_HEIGHT);
        [content addSubview:row];
        y += ROW_HEIGHT;
    }
    if (visible.count && _icons.count) {
        UIView *band = [self bandOfWidth:width];
        band.frame = CGRectMake(0, y, width, BAND_HEIGHT);
        [content addSubview:band];
        y += BAND_HEIGHT;
    }
    if (_icons.count) {
        CGFloat each = width / (CGFloat)_icons.count;
        for (NSUInteger i = 0; i < _icons.count; ++i) {
            ExteriaMenuItem *item = [_icons objectAtIndex:i];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.frame = CGRectMake(each * (CGFloat)i, y, each, ICON_ROW_HEIGHT);
            button.tag = (NSInteger)item.tag;
            button.accessibilityLabel = item.title;
            [button setImage:ExteriaSymbolImage(item.symbol, 26, item.destructive ? ExteriaMenuRed() : ExteriaMenuText()) forState:UIControlStateNormal];
            [button addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
            [button addTarget:self action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown];
            [button addTarget:self action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            [content addSubview:button];
        }
        y += ICON_ROW_HEIGHT;
    }
    content.frame = CGRectMake(0, 0, width, y);
    UIView *card = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, MIN(y, maxHeight))] autorelease];
    ExteriaMenuSkin(card, ExteriaMenuClassic() ? 10 : 18);
    UIScrollView *clip = [[[UIScrollView alloc] initWithFrame:card.bounds] autorelease];
    clip.contentSize = content.bounds.size;
    clip.layer.cornerRadius = card.layer.cornerRadius;
    clip.clipsToBounds = YES;
    clip.showsVerticalScrollIndicator = NO;
    clip.bounces = y > maxHeight;
    [clip addSubview:content];
    [card addSubview:clip];
    return card;
}

/* the pill of reactions: the first of them and an arrow that opens the whole list */
- (UIView *)buildPill {
    NSUInteger shown = MIN(_reactions.count, (NSUInteger)REACTIONS_SHOWN);
    CGFloat arrow = 36;
    CGFloat room = self.bounds.size.width - 2 * EDGE - 2 * PILL_PAD - arrow - 6;
    shown = MIN(shown, (NSUInteger)floor(room / PILL_ITEM));
    CGFloat width = 2 * PILL_PAD + (CGFloat)shown * PILL_ITEM + 6 + arrow;
    UIView *pill = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, PILL_HEIGHT)] autorelease];
    ExteriaMenuSkin(pill, PILL_HEIGHT / 2);
    for (NSUInteger i = 0; i < shown; ++i) {
        ExteriaReaction *reaction = [_reactions objectAtIndex:i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(PILL_PAD + (CGFloat)i * PILL_ITEM, (PILL_HEIGHT - PILL_ITEM) / 2, PILL_ITEM, PILL_ITEM);
        button.tag = (NSInteger)i;
        button.layer.cornerRadius = PILL_ITEM / 2;
        if (reaction.chosen) button.backgroundColor = [ExteriaColorAccent() colorWithAlphaComponent:0.35];
        button.accessibilityLabel = reaction.displayText;
        [button addTarget:self action:@selector(reactionTapped:) forControlEvents:UIControlEventTouchUpInside];
        ExteriaEmojiLabel *label = [[[ExteriaEmojiLabel alloc] init] autorelease];
        label.text = reaction.displayText;
        label.entities = reaction.displayEntities;
        label.font = ExteriaFontRegular(27);
        label.textAlignment = ExteriaTextAlignmentCenter;
        label.frame = button.bounds;
        label.userInteractionEnabled = NO;
        [button addSubview:label];
        [pill addSubview:button];
    }
    UIButton *more = [UIButton buttonWithType:UIButtonTypeCustom];
    more.frame = CGRectMake(width - PILL_PAD - arrow, (PILL_HEIGHT - arrow) / 2, arrow, arrow);
    more.layer.cornerRadius = arrow / 2;
    more.backgroundColor = ExteriaMenuCharcoal() ? [UIColor colorWithWhite:1 alpha:0.18] : (ExteriaMenuClassic() ? [UIColor colorWithWhite:0 alpha:0.1] : [UIColor colorWithWhite:0.5 alpha:0.3]);
    /* the arrow is the chevron of the lists turned a quarter */
    [more setImage:ExteriaSymbolImage(ExteriaSymbolChevronRight, 18, ExteriaMenuText()) forState:UIControlStateNormal];
    more.imageView.transform = CGAffineTransformMakeRotation(M_PI_2);
    more.accessibilityLabel = NSLocalizedString(@"chat.reactions", nil);
    [more addTarget:self action:@selector(moreReactionsTapped) forControlEvents:UIControlEventTouchUpInside];
    [pill addSubview:more];
    return pill;
}

#pragma mark layout

/* the reaction pill sits above the visible message and the card below it */
- (void)layoutStack {
    CGSize size = self.bounds.size;
    CGFloat top = EDGE + (ExteriaThemeIsClassic() ? 0 : 20), bottom = size.height - EDGE;
    CGFloat pillHeight = _pill ? _pill.frame.size.height : 0;
    CGFloat cardHeight = _card.frame.size.height;
    CGFloat cardY = MIN(CGRectGetMaxY(_bubble) + GAP, bottom - cardHeight);
    CGFloat pillY = top;
    double calculatedPill = 0, calculatedCard = 0, shift = 0;
    if (_pill && exteria_reaction_menu_stack(top, bottom, CGRectGetMinY(_bubble), CGRectGetMaxY(_bubble), pillHeight, cardHeight, GAP,
                                             &calculatedPill, &calculatedCard, &shift) == EXTERIA_OK) {
        pillY = (CGFloat)calculatedPill;
        cardY = (CGFloat)calculatedCard;
    }
    if (_lit) _lit.frame = CGRectOffset(_litOriginalFrame, 0, (CGFloat)shift);
    CGFloat cardX = _outgoing ? CGRectGetMaxX(_bubble) - _card.frame.size.width : CGRectGetMinX(_bubble);
    cardX = MIN(MAX(EDGE, cardX), size.width - EDGE - _card.frame.size.width);
    _card.frame = CGRectMake(cardX, cardY, _card.frame.size.width, cardHeight);
    if (_pill) {
        CGFloat pillX = _outgoing ? CGRectGetMaxX(_bubble) - _pill.frame.size.width : CGRectGetMinX(_bubble);
        pillX = MIN(MAX(EDGE, pillX), size.width - EDGE - _pill.frame.size.width);
        _pill.frame = CGRectMake(pillX, pillY, _pill.frame.size.width, pillHeight);
    }
}

- (void)rebuildAnimated:(BOOL)animated {
    CGFloat available = self.bounds.size.height - 2 * EDGE - 24 - (_reactions.count ? PILL_HEIGHT + GAP : 0);
    [_card removeFromSuperview];
    [_card release];
    _card = [[self buildCardWithMaxHeight:MAX(120, available)] retain];
    [_pill removeFromSuperview];
    [_pill release];
    _pill = _reactions.count ? [[self buildPill] retain] : nil;
    [self addSubview:_card];
    ExteriaAddDismissPan(_card, self, @selector(dismiss));
    if (_pill) [self addSubview:_pill];
    [self layoutStack];
    if (animated) {
        _card.alpha = 0;
        [UIView animateWithDuration:0.16 animations:^{ _card.alpha = 1; }];
    }
}

#pragma mark show and close

- (void)showInView:(UIView *)host bubble:(CGRect)bubble outgoing:(BOOL)outgoing snapshot:(UIImage *)snapshot snapshotFrame:(CGRect)snapshotFrame clip:(CGRect)clip {
    if (self.superview) return;
    self.frame = host.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _bubble = bubble;
    _outgoing = outgoing;
    _dim = [[UIControl alloc] initWithFrame:self.bounds];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_dim addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_dim];
    /* taken before the menu joins the host, so the picture holds the chat and nothing of the menu; it fades in with the dim */
    UIView *blur = ExteriaBlurBackdrop(host, self.bounds);
    if (blur) {
        blur.userInteractionEnabled = NO;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];
        [_dim insertSubview:blur atIndex:0];
    }
    if (snapshot) {
        /* only the part of the row that shows in the list stays lit, so it never reaches over the bar above or the field below */
        _litClip = [[UIView alloc] initWithFrame:clip];
        _litClip.clipsToBounds = YES;
        _litClip.userInteractionEnabled = NO;
        _lit = [[UIImageView alloc] initWithImage:snapshot];
        _lit.frame = CGRectOffset(snapshotFrame, -clip.origin.x, -clip.origin.y);
        _litOriginalFrame = _lit.frame;
        [_litClip addSubview:_lit];
        [self addSubview:_litClip];
    }
    [self rebuildAnimated:NO];
    [host addSubview:self];
    _shown = YES;
    _dim.alpha = 0;
    _card.alpha = 0;
    _card.transform = CGAffineTransformMakeScale(0.92, 0.92);
    _pill.alpha = 0;
    _pill.transform = CGAffineTransformMakeScale(0.92, 0.92);
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER, nil);
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
    if (_pill) ExteriaAnimateView(_pill, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
}

- (void)leaveThen:(void (^)(void))after {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    void (^next)(void) = [after copy];
    [self retain];
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0, EXTERIA_MOTION_EXIT, nil);
    if (_pill) ExteriaAnimateView(_pill, CGAffineTransformMakeScale(0.92, 0.92), 0, EXTERIA_MOTION_EXIT, nil);
    ExteriaAnimateView(_card, CGAffineTransformMakeScale(0.92, 0.92), 0, EXTERIA_MOTION_EXIT, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (next) next();
        [next release];
        [self release];
    });
}

- (void)dismiss {
    [self leaveThen:^{ if (_dismissHandler) _dismissHandler(); }];
}

- (void)rowTapped:(UIButton *)button {
    NSUInteger tag = (NSUInteger)button.tag;
    if (tag == MORE_TAG) {
        _expanded = YES;
        [self rebuildAnimated:YES];
        return;
    }
    void (^handler)(NSUInteger) = [_pickHandler retain];
    [self leaveThen:^{
        if (handler) handler(tag);
        [handler release];
    }];
}

- (void)headerTapped {
    void (^handler)(void) = [_headerHandler retain];
    [self leaveThen:^{ if (handler) handler(); [handler release]; }];
}

- (void)reactionTapped:(UIButton *)button {
    if ((NSUInteger)button.tag >= _reactions.count) return;
    ExteriaReaction *reaction = [[_reactions objectAtIndex:(NSUInteger)button.tag] retain];
    void (^handler)(ExteriaReaction *) = [_reactionHandler retain];
    [self leaveThen:^{
        if (handler) handler(reaction);
        [handler release];
        [reaction release];
    }];
}

- (void)moreReactionsTapped {
    void (^handler)(void) = [_moreReactionsHandler retain];
    [self leaveThen:^{
        if (handler) handler();
        [handler release];
    }];
}

@end
