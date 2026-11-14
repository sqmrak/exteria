#import "exteria_tab_bar.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_animation.h"
#import "exteria_platform.h"
#import "exteria_pill_label.h"
#import "exteria_chat_settings.h"
#import "exteria_shape.h"
#import "exteria_theme.h"
#import "exteria_imported_theme.h"

#define TAB_BAR_HEIGHT 49.0
#define TAB_ICON_SIZE 26.0
#define TAB_BADGE_HEIGHT 18.0

/* the bar is opaque white, so the selected tab takes the accent and idle ones a quiet blue lilac */
static UIColor *ExteriaTabIdleColor(void) {
    if (ExteriaThemeIsClassic()) return ExteriaColorSecondary();
    UIColor *imported = ExteriaImportedThemeColor("root.tabBar.icon");
    if (imported) return imported;
    return ExteriaThemeTinted(ExteriaThemeIsDark() ? [UIColor colorWithRed:0.52 green:0.49 blue:0.68 alpha:1] : [UIColor colorWithRed:0.58 green:0.55 blue:0.75 alpha:1]);
}
static UIColor *ExteriaTabActiveColor(void) { return ExteriaImportedThemeColor("root.tabBar.selectedIcon") ?: ExteriaColorAccent(); }

@interface ExteriaTabItem : UIControl {
    UIImageView *_icon;
    UILabel *_caption;
    UILabel *_badge;
    UIImage *_idleImage;
    UIImage *_activeImage;
    ExteriaSymbol _symbol;
    ExteriaAvatarView *_avatar;
    UIView *_ring;
    CAShapeLayer *_ringStroke;
    /* the pill of the Material navigation bar behind the icon of the selected tab, when the customization asks for it */
    UIView *_pill;
    BOOL _active;
}
/* a nil symbol makes the avatar item */
- (id)initWithTitle:(NSString *)title symbol:(NSNumber *)symbol;
- (void)setAvatarInitials:(NSString *)initials seed:(NSUInteger)seed photo:(ExteriaPhoto *)photo cache:(ExteriaAvatarCache *)cache;
- (void)setActive:(BOOL)active;
- (void)setBadge:(NSInteger)count;
- (void)setTitle:(NSString *)title symbol:(NSNumber *)symbol;
@end

@implementation ExteriaTabItem

- (id)initWithTitle:(NSString *)title symbol:(NSNumber *)symbolNumber {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = title;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    if (symbolNumber) {
        _pill = [[UIView alloc] init];
        _pill.backgroundColor = [ExteriaTabActiveColor() colorWithAlphaComponent:0.2f];
        _pill.userInteractionEnabled = NO;
        _pill.alpha = 0;
        [self addSubview:_pill];
        _symbol = (ExteriaSymbol)[symbolNumber intValue];
        _idleImage = [ExteriaSymbolImage(_symbol, TAB_ICON_SIZE, ExteriaTabIdleColor()) retain];
        _activeImage = [ExteriaSymbolImage(_symbol, TAB_ICON_SIZE, ExteriaTabActiveColor()) retain];
        _icon = [[UIImageView alloc] initWithImage:_idleImage];
        _icon.contentMode = UIViewContentModeCenter;
        _icon.userInteractionEnabled = NO;
        [self addSubview:_icon];
    } else {
        /* the ring marks the selected tab, the avatar sits inside it */
        _ring = [[UIView alloc] init];
        _ring.userInteractionEnabled = NO;
        /* the mark of the selected tab is a stroke along the shape of the avatars, so it follows the shape the person chose */
        _ringStroke = [[CAShapeLayer layer] retain];
        _ringStroke.fillColor = nil;
        _ringStroke.strokeColor = ExteriaTabActiveColor().CGColor;
        _ringStroke.lineWidth = 2;
        _ringStroke.opacity = 0;
        [_ring.layer addSublayer:_ringStroke];
        [self addSubview:_ring];
        _avatar = [[ExteriaAvatarView alloc] init];
        _avatar.circular = YES;
        [_ring addSubview:_avatar];
    }
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.text = title;
    _caption.font = ExteriaFontMedium(10);
    _caption.textColor = ExteriaImportedThemeColor("root.tabBar.text") ?: ExteriaTabIdleColor();
    _caption.textAlignment = ExteriaTextAlignmentCenter;
    [self addSubview:_caption];
    _badge = [[ExteriaPillLabel alloc] init];
    _badge.backgroundColor = ExteriaImportedThemeColor("root.tabBar.badgeBackground") ?: ExteriaColorAccent();
    _badge.textColor = ExteriaImportedThemeColor("root.tabBar.badgeText") ?: [UIColor whiteColor];
    _badge.font = ExteriaFontSemibold(11);
    _badge.textAlignment = ExteriaTextAlignmentCenter;
    _badge.layer.cornerRadius = TAB_BADGE_HEIGHT / 2;
    _badge.layer.masksToBounds = YES;
    _badge.hidden = YES;
    [self addSubview:_badge];
    ExteriaAttachBounce(self, 0.035f);
    return self;
}

- (void)dealloc {
    [_pill release];
    [_ringStroke release];
    [_ring release];
    [_avatar release];
    [_icon release];
    [_caption release];
    [_badge release];
    [_idleImage release];
    [_activeImage release];
    [super dealloc];
}

- (void)setAvatarInitials:(NSString *)initials seed:(NSUInteger)seed photo:(ExteriaPhoto *)photo cache:(ExteriaAvatarCache *)cache {
    _avatar.initials = initials;
    _avatar.seed = seed;
    [_avatar setPhoto:photo cache:cache];
}

- (void)setActive:(BOOL)active {
    BOOL changed = active != _active;
    _active = active;
    if (changed && active && self.window) {
        UIView *icon = _icon ? (UIView *)_icon : _ring;
        icon.transform = CGAffineTransformMakeScale(0.86, 0.86);
        ExteriaAnimateView(icon, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
    }
    if (_icon) _icon.image = active ? _activeImage : _idleImage;
    BOOL pill = active && _pill && !ExteriaThemeIsClassic() && ExteriaTabIndicatorOn();
    if (changed && self.window) [UIView animateWithDuration:0.2 animations:^{ _pill.alpha = pill ? 1 : 0; }];
    else _pill.alpha = pill ? 1 : 0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ringStroke.opacity = active ? 1 : 0;
    [CATransaction commit];
    _caption.textColor = active ? (ExteriaImportedThemeColor("root.tabBar.selectedText") ?: ExteriaTabActiveColor()) : (ExteriaImportedThemeColor("root.tabBar.text") ?: ExteriaTabIdleColor());
    self.accessibilityTraits = active ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

- (void)setTitle:(NSString *)title symbol:(NSNumber *)symbol {
    _caption.text = title;
    self.accessibilityLabel = title;
    if (!_icon || !symbol) return;
    _symbol = (ExteriaSymbol)[symbol intValue];
    [_idleImage release];
    [_activeImage release];
    _idleImage = [ExteriaSymbolImage(_symbol, TAB_ICON_SIZE, ExteriaTabIdleColor()) retain];
    _activeImage = [ExteriaSymbolImage(_symbol, TAB_ICON_SIZE, ExteriaTabActiveColor()) retain];
    _icon.image = _active ? _activeImage : _idleImage;
}

- (void)setBadge:(NSInteger)count {
    _badge.hidden = count <= 0;
    _badge.text = count > 999 ? @"999+" : [NSString stringWithFormat:@"%ld", (long)count];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _icon.frame = CGRectMake((width - TAB_ICON_SIZE * 1.4) / 2, 5, TAB_ICON_SIZE * 1.4, TAB_ICON_SIZE);
    CGFloat pillHeight = TAB_ICON_SIZE + 2;
    _pill.frame = CGRectMake((width - 56) / 2, 5 + (TAB_ICON_SIZE - pillHeight) / 2, 56, pillHeight);
    _pill.layer.cornerRadius = pillHeight / 2;
    /* the ring keeps its place whether or not it is drawn, so the avatar does not jump on selection */
    CGFloat ringSide = TAB_ICON_SIZE + 4;
    _ring.frame = CGRectMake((width - ringSide) / 2, 3, ringSide, ringSide);
    _avatar.frame = CGRectInset(_ring.bounds, 3, 3);
    if (_ringStroke) {
        ExteriaShape shape = ExteriaThemeIsClassic() ? ExteriaShapeCircle : (ExteriaShape)ExteriaAvatarShapeStored();
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _ringStroke.frame = _ring.bounds;
        _ringStroke.path = ExteriaShapePath(shape, CGRectInset(_ring.bounds, 1, 1), shape == ExteriaShapeCircle ? 100 : ExteriaAvatarCornerPercent()).CGPath;
        [CATransaction commit];
    }
    _caption.frame = CGRectMake(0, 5 + TAB_ICON_SIZE + 1, width, 13);
    [_badge sizeToFit];
    CGFloat badgeWidth = MAX(TAB_BADGE_HEIGHT, _badge.frame.size.width + 10);
    _badge.frame = CGRectMake(width / 2 + 2, 1, badgeWidth, TAB_BADGE_HEIGHT);
}

@end

@interface ExteriaTabBar () {
    NSMutableArray *_items;
    UIView *_hairline;
}
@end

@implementation ExteriaTabBar

@synthesize delegate = _delegate;
@synthesize selectedIndex = _selectedIndex;
@synthesize itemArea = _itemArea;

+ (CGFloat)barHeight {
    return TAB_BAR_HEIGHT;
}

- (id)initWithTitles:(NSArray *)titles symbols:(NSArray *)symbols {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = ExteriaImportedThemeColor("root.tabBar.background") ?: ExteriaColorBar();
    _itemArea = CGRectNull;
    /* the plate under the selected tab, a little lower than the middle of the bar */
    _items = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < [titles count]; ++i) {
        id symbol = [symbols objectAtIndex:i];
        ExteriaTabItem *item = [[[ExteriaTabItem alloc] initWithTitle:[titles objectAtIndex:i]
                                                               symbol:symbol == [NSNull null] ? nil : symbol] autorelease];
        [item addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *hold = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(itemHeld:)] autorelease];
        hold.minimumPressDuration = 0.45;
        [item addGestureRecognizer:hold];
        [_items addObject:item];
        [self addSubview:item];
    }
    _hairline = [[UIView alloc] init];
    _hairline.backgroundColor = ExteriaImportedThemeColor("root.tabBar.separator") ?: ExteriaColorHairline();
    [self addSubview:_hairline];
    [self setSelectedIndex:0];
    return self;
}

- (void)dealloc {
    [_items release];
    [_hairline release];
    [super dealloc];
}

- (void)setSelectedIndex:(NSInteger)index {
    _selectedIndex = index;
    for (NSUInteger i = 0; i < [_items count]; ++i) [[_items objectAtIndex:i] setActive:(NSInteger)i == index];
}

- (void)setBadge:(NSInteger)count forIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_items count]) return;
    [[_items objectAtIndex:index] setBadge:count];
}

- (void)setTitle:(NSString *)title symbol:(NSNumber *)symbol forIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_items count]) return;
    [[_items objectAtIndex:index] setTitle:title symbol:symbol];
}

- (void)setAvatarInitials:(NSString *)initials seed:(NSUInteger)seed photo:(ExteriaPhoto *)photo cache:(ExteriaAvatarCache *)cache
                 forIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_items count]) return;
    [[_items objectAtIndex:index] setAvatarInitials:initials seed:seed photo:photo cache:cache];
}

- (void)itemTapped:(ExteriaTabItem *)item {
    NSInteger index = (NSInteger)[_items indexOfObject:item];
    if (index == _selectedIndex) {
        if ([_delegate respondsToSelector:@selector(tabBar:didReselectIndex:)]) [_delegate tabBar:self didReselectIndex:index];
        return;
    }
    [self setSelectedIndex:index];
    [_delegate tabBar:self didSelectIndex:index];
}

- (void)itemHeld:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    NSInteger index = (NSInteger)[_items indexOfObject:hold.view];
    if (index == NSNotFound || ![_delegate respondsToSelector:@selector(tabBar:didLongPressIndex:frame:)]) return;
    [_delegate tabBar:self didLongPressIndex:index frame:hold.view.frame];
}

- (void)setItemArea:(CGRect)area {
    if (CGRectEqualToRect(area, _itemArea) || (CGRectIsNull(area) && CGRectIsNull(_itemArea))) return;
    _itemArea = area;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGRect area = CGRectIsNull(_itemArea) ? self.bounds : _itemArea;
    CGFloat each = [_items count] ? area.size.width / (CGFloat)[_items count] : 0;
    for (NSUInteger i = 0; i < [_items count]; ++i) {
        [[_items objectAtIndex:i] setFrame:CGRectMake(area.origin.x + each * (CGFloat)i, 0, each, TAB_BAR_HEIGHT)];
    }
    _hairline.frame = CGRectMake(0, 0, width, 1.0 / ExteriaScreenScale());
}

@end
