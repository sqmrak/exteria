#import "exteria_filter_bar.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_pill_label.h"
#import "exteria_emoji_label.h"
#import "exteria_theme.h"
#import "exteria_animation.h"
#import "exteria_classic_chrome.h"
#import "exteria_folder_icon.h"

#define CHIP_HEIGHT 32.0
#define CHIP_GAP 8.0
#define CHIP_PADDING 14.0
#define CHIP_BADGE_HEIGHT 20.0
#define CHIP_ICON_SIDE 20.0
/* the icon beside a name, and the narrower padding of a tab that is only an icon */
#define CHIP_ICON_GAP 6.0
#define CHIP_ICON_ONLY_PADDING 11.0

@interface ExteriaChip : UIControl {
    ExteriaEmojiLabel *_title;
    UILabel *_badge;
    BOOL _active;
    UIImageView *_plate;
    UIImageView *_icon;
    NSString *_iconName;
    ExteriaFolderTabStyle _style;
}
- (id)initWithTitle:(NSString *)title;
- (void)setActive:(BOOL)active;
- (void)setCount:(NSInteger)count;
- (CGFloat)fittingWidth;
- (void)setEntities:(NSArray *)entities;
- (void)redrawTitle;
- (void)setIconName:(NSString *)name;
- (void)setStyle:(ExteriaFolderTabStyle)style;
@end

@implementation ExteriaChip

- (id)initWithTitle:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    if (ExteriaThemeIsClassic()) {
        _plate = [[UIImageView alloc] init];
        _plate.userInteractionEnabled = NO;
        [self addSubview:_plate];
    }
    self.layer.cornerRadius = CHIP_HEIGHT / 2;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = title;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.text = title;
    _title.font = ExteriaFontMedium(15);
    [self addSubview:_title];
    _icon = [[UIImageView alloc] init];
    _icon.userInteractionEnabled = NO;
    _icon.alpha = 0;
    [self addSubview:_icon];
    _badge = [[ExteriaPillLabel alloc] init];
    _badge.font = ExteriaFontSemibold(13);
    _badge.textAlignment = ExteriaTextAlignmentCenter;
    _badge.textColor = [UIColor whiteColor];
    _badge.layer.cornerRadius = CHIP_BADGE_HEIGHT / 2;
    _badge.layer.masksToBounds = YES;
    _badge.hidden = YES;
    [self addSubview:_badge];
    [self setActive:NO];
    return self;
}

- (void)dealloc {
    [_plate release];
    [_icon release];
    [_iconName release];
    [_title release];
    [_badge release];
    [super dealloc];
}

- (void)setActive:(BOOL)active {
    _active = active;
    self.backgroundColor = active ? ExteriaColorAccent() : ExteriaColorField();
    _title.textColor = active ? [UIColor whiteColor] : ExteriaColorSecondary();
    if (_plate) {
        self.backgroundColor = [UIColor clearColor];
        _plate.image = ExteriaClassicGlossButtonImage(ExteriaClassicGlossSlate, active);
        _title.textColor = [UIColor whiteColor];
        _title.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
        _title.shadowOffset = CGSizeMake(0, -1);
    }
    /* on the filled chip the count turns white on a lighter plate so it stays readable */
    _badge.backgroundColor = active ? [UIColor colorWithWhite:1 alpha:0.28] : ExteriaColorAccent();
    self.accessibilityTraits = active ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
    [self refreshIcon];
}

/* a tab with no picture for its folder keeps its name, so an icons only bar never has an empty tab */
- (BOOL)showsIcon {
    return _iconName.length && _style != ExteriaFolderTabsNames;
}

- (BOOL)showsTitle {
    return _style != ExteriaFolderTabsIcons || !_iconName.length;
}

- (void)refreshIcon {
    UIColor *ink = _plate || _active ? [UIColor whiteColor] : ExteriaColorSecondary();
    _icon.image = _iconName.length ? ExteriaFolderIconImage(_iconName, CHIP_ICON_SIDE, ink) : nil;
}

- (void)setIconName:(NSString *)name {
    if (name == _iconName || [name isEqualToString:_iconName]) return;
    [_iconName release];
    _iconName = [name copy];
    [self refreshIcon];
    _icon.alpha = [self showsIcon] ? 1 : 0;
    _title.alpha = [self showsTitle] ? 1 : 0;
    [self setNeedsLayout];
}

- (void)setStyle:(ExteriaFolderTabStyle)style {
    _style = style;
    _icon.alpha = [self showsIcon] ? 1 : 0;
    _title.alpha = [self showsTitle] ? 1 : 0;
    [self setNeedsLayout];
}

- (void)setCount:(NSInteger)count {
    _badge.hidden = count <= 0;
    _badge.text = count > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)count];
    [self setNeedsLayout];
}

- (CGFloat)badgeWidth {
    if (_badge.hidden) return 0;
    [_badge sizeToFit];
    return MAX(CHIP_BADGE_HEIGHT, _badge.frame.size.width + 10);
}

- (CGFloat)fittingWidth {
    CGSize titleSize = [_title sizeThatFits:CGSizeMake(2048, CHIP_HEIGHT)];
    CGFloat badge = [self badgeWidth];
    BOOL icon = [self showsIcon], title = [self showsTitle];
    CGFloat padding = icon && !title ? CHIP_ICON_ONLY_PADDING : CHIP_PADDING;
    CGFloat content = (icon ? CHIP_ICON_SIDE : 0) + (icon && title ? CHIP_ICON_GAP : 0) + (title ? ceil(titleSize.width) : 0);
    return padding * 2 + content + (badge > 0 ? 6 + badge : 0);
}

- (void)setEntities:(NSArray *)entities { _title.entities = entities; }
- (void)redrawTitle { [_title setNeedsDisplay]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    _plate.frame = self.bounds;
    CGSize titleSize = [_title sizeThatFits:CGSizeMake(2048, CHIP_HEIGHT)];
    CGFloat badge = [self badgeWidth];
    BOOL icon = [self showsIcon], title = [self showsTitle];
    CGFloat x = icon && !title ? CHIP_ICON_ONLY_PADDING : CHIP_PADDING;
    _icon.frame = CGRectMake(x, (CHIP_HEIGHT - CHIP_ICON_SIDE) / 2, CHIP_ICON_SIDE, CHIP_ICON_SIDE);
    if (icon) x += CHIP_ICON_SIDE + (title ? CHIP_ICON_GAP : 0);
    _title.frame = CGRectMake(x, (CHIP_HEIGHT - titleSize.height) / 2, ceil(titleSize.width), titleSize.height);
    CGFloat contentEnd = title ? CGRectGetMaxX(_title.frame) : x;
    _badge.frame = CGRectMake(contentEnd + 6, (CHIP_HEIGHT - CHIP_BADGE_HEIGHT) / 2, badge, CHIP_BADGE_HEIGHT);
}

@end

@interface ExteriaFilterBar () {
    UIScrollView *_scroll;
    NSMutableArray *_chips;
    BOOL _revealSelection;
    ExteriaFolderTabStyle _tabStyle;
}
@end

@implementation ExteriaFilterBar

@synthesize delegate = _delegate;
@synthesize selectedIndex = _selectedIndex;
@synthesize tabStyle = _tabStyle;

- (id)initWithTitles:(NSArray *)titles {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.scrollsToTop = NO;
    [self addSubview:_scroll];
    _chips = [[NSMutableArray alloc] init];
    _tabStyle = ExteriaFolderTabStyleStored();
    for (NSString *title in titles) {
        ExteriaChip *chip = [[[ExteriaChip alloc] initWithTitle:title] autorelease];
        [chip setStyle:_tabStyle];
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_chips addObject:chip];
        [_scroll addSubview:chip];
    }
    [self setSelectedIndex:0];
    return self;
}

- (void)dealloc {
    [_scroll release];
    [_chips release];
    [super dealloc];
}

- (void)setSelectedIndex:(NSInteger)index {
    _selectedIndex = index;
    for (NSUInteger i = 0; i < [_chips count]; ++i) [[_chips objectAtIndex:i] setActive:(NSInteger)i == index];
    _revealSelection = YES;
    [self setNeedsLayout];
}

- (void)setCount:(NSInteger)count forIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_chips count]) return;
    [[_chips objectAtIndex:index] setCount:count];
    [self setNeedsLayout];
}

- (void)setIconName:(NSString *)name forIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_chips.count) return;
    [[_chips objectAtIndex:(NSUInteger)index] setIconName:name];
    [self setNeedsLayout];
}

- (void)setTabStyle:(ExteriaFolderTabStyle)style {
    [self setTabStyle:style animated:NO];
}

- (void)setTabStyle:(ExteriaFolderTabStyle)style animated:(BOOL)animated {
    if (style == _tabStyle) return;
    _tabStyle = style;
    void (^change)(void) = ^{
        for (ExteriaChip *chip in _chips) [chip setStyle:style];
        [self setNeedsLayout];
        [self layoutIfNeeded];
    };
    if (!animated || !self.window) {
        change();
        return;
    }
    /* the tabs slide to their new widths while the name and the icon cross-fade, which a layout pass inside the animation does for the frames */
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:change completion:nil];
    _revealSelection = YES;
}

- (void)setEntities:(NSArray *)entities forIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_chips.count) return;
    [[_chips objectAtIndex:(NSUInteger)index] setEntities:entities];
    [self setNeedsLayout];
}

- (void)redrawTitles {
    for (ExteriaChip *chip in _chips) [chip redrawTitle];
}

- (void)chipTapped:(ExteriaChip *)chip {
    NSInteger index = (NSInteger)[_chips indexOfObject:chip];
    if (index == _selectedIndex) return;
    [self setSelectedIndex:index];
    chip.transform = CGAffineTransformMakeScale(0.94, 0.94);
    ExteriaAnimateView(chip, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
    [_delegate filterBar:self didSelectIndex:index];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = self.bounds;
    CGFloat x = 16;
    CGFloat y = (self.bounds.size.height - CHIP_HEIGHT) / 2;
    for (ExteriaChip *chip in _chips) {
        CGFloat width = [chip fittingWidth];
        chip.frame = CGRectMake(x, y, width, CHIP_HEIGHT);
        x += width + CHIP_GAP;
    }
    _scroll.contentSize = CGSizeMake(x - CHIP_GAP + 16, self.bounds.size.height);
    if (_revealSelection && self.bounds.size.width > 0 && _selectedIndex >= 0 && (NSUInteger)_selectedIndex < _chips.count) {
        _revealSelection = NO;
        UIView *selected = [_chips objectAtIndex:(NSUInteger)_selectedIndex];
        [_scroll scrollRectToVisible:CGRectInset(selected.frame, -16, 0) animated:self.window != nil];
    }
}

@end
