#import "exteria_filter_bar.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_pill_label.h"
#import "exteria_emoji_label.h"
#import "exteria_theme.h"
#import "exteria_animation.h"
#import "exteria_classic_chrome.h"

#define CHIP_HEIGHT 32.0
#define CHIP_GAP 8.0
#define CHIP_PADDING 14.0
#define CHIP_BADGE_HEIGHT 20.0

@interface ExteriaChip : UIControl {
    ExteriaEmojiLabel *_title;
    UILabel *_badge;
    BOOL _active;
    UIImageView *_plate;
}
- (id)initWithTitle:(NSString *)title;
- (void)setActive:(BOOL)active;
- (void)setCount:(NSInteger)count;
- (CGFloat)fittingWidth;
- (void)setEntities:(NSArray *)entities;
- (void)redrawTitle;
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
    return CHIP_PADDING * 2 + ceil(titleSize.width) + (badge > 0 ? 6 + badge : 0);
}

- (void)setEntities:(NSArray *)entities { _title.entities = entities; }
- (void)redrawTitle { [_title setNeedsDisplay]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    _plate.frame = self.bounds;
    CGSize titleSize = [_title sizeThatFits:CGSizeMake(2048, CHIP_HEIGHT)];
    CGFloat badge = [self badgeWidth];
    _title.frame = CGRectMake(CHIP_PADDING, (CHIP_HEIGHT - titleSize.height) / 2, ceil(titleSize.width), titleSize.height);
    _badge.frame = CGRectMake(CGRectGetMaxX(_title.frame) + 6, (CHIP_HEIGHT - CHIP_BADGE_HEIGHT) / 2, badge, CHIP_BADGE_HEIGHT);
}

@end

@interface ExteriaFilterBar () {
    UIScrollView *_scroll;
    NSMutableArray *_chips;
    BOOL _revealSelection;
}
@end

@implementation ExteriaFilterBar

@synthesize delegate = _delegate;
@synthesize selectedIndex = _selectedIndex;

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
    for (NSString *title in titles) {
        ExteriaChip *chip = [[[ExteriaChip alloc] initWithTitle:title] autorelease];
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
