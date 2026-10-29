#import "exteria_pill_tabs_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define TABS_HEIGHT 40.0

@interface ExteriaPillTabsView () {
    NSMutableArray *_labels;
    UIScrollView *_scroll;
    UIView *_chosen;
    NSUInteger _selectedIndex;
    void (^_changeHandler)(NSUInteger);
}
@end

@implementation ExteriaPillTabsView

@synthesize changeHandler = _changeHandler;
@synthesize selectedIndex = _selectedIndex;

- (id)initWithTitles:(NSArray *)titles {
    self = [super initWithFrame:CGRectMake(0, 0, 320, TABS_HEIGHT)];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = TABS_HEIGHT / 2;
    _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_scroll];
    _chosen = [[UIView alloc] init];
    _chosen.backgroundColor = ExteriaColorField();
    _chosen.layer.cornerRadius = (TABS_HEIGHT - 8) / 2;
    [_scroll addSubview:_chosen];
    _labels = [[NSMutableArray alloc] init];
    for (NSString *title in titles) {
        UILabel *label = [[[UILabel alloc] init] autorelease];
        label.backgroundColor = [UIColor clearColor];
        label.textAlignment = ExteriaTextAlignmentCenter;
        label.font = ExteriaFontMedium(15);
        label.adjustsFontSizeToFitWidth = NO;
        label.text = title;
        label.isAccessibilityElement = YES;
        label.accessibilityTraits = UIAccessibilityTraitButton;
        [_scroll addSubview:label];
        [_labels addObject:label];
    }
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    [_scroll addGestureRecognizer:tap];
    [self refresh];
    return self;
}

- (void)dealloc {
    [_labels release];
    [_scroll release];
    [_chosen release];
    [_changeHandler release];
    [super dealloc];
}

- (void)refresh {
    for (NSUInteger i = 0; i < _labels.count; ++i) {
        UILabel *label = [_labels objectAtIndex:i];
        label.textColor = i == _selectedIndex ? ExteriaColorAccent() : ExteriaColorSecondary();
    }
    [self setNeedsLayout];
}

- (void)setSelectedIndex:(NSUInteger)index {
    if (index >= _labels.count) return;
    _selectedIndex = index;
    [self refresh];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat natural = 0;
    for (UILabel *label in _labels) natural += ceil(ExteriaStringSize(label.text, label.font).width) + 28;
    CGFloat extra = _labels.count && natural < width ? (width - natural) / _labels.count : 0;
    CGFloat x = 0;
    for (NSUInteger i = 0; i < _labels.count; ++i) {
        UILabel *label = [_labels objectAtIndex:i];
        CGFloat item = ceil(ExteriaStringSize(label.text, label.font).width) + 28 + extra;
        label.frame = CGRectMake(x + 4, 0, MAX(0, item - 8), height);
        if (i == _selectedIndex) _chosen.frame = CGRectMake(x + 4, 4, MAX(0, item - 8), height - 8);
        x += item;
    }
    _scroll.contentSize = CGSizeMake(MAX(width, x), height);
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (!_labels.count || self.bounds.size.width <= 0) return;
    CGPoint point = [tap locationInView:_scroll];
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < _labels.count; ++i) {
        UILabel *label = [_labels objectAtIndex:i];
        if (CGRectContainsPoint(CGRectInset(label.frame, -4, 0), point)) { index = i; break; }
    }
    if (index >= _labels.count || index == _selectedIndex) return;
    [self layoutIfNeeded];
    CGPoint from = _chosen.layer.presentationLayer ? [(CALayer *)_chosen.layer.presentationLayer position] : _chosen.center;
    self.selectedIndex = index;
    [self layoutIfNeeded];
    CGPoint target = _chosen.center;
    _chosen.center = from;
    ExteriaAnimatePosition(_chosen, target, EXTERIA_MOTION_ENTER);
    [_scroll scrollRectToVisible:CGRectInset([[_labels objectAtIndex:index] frame], -4, 0) animated:YES];
    if (_changeHandler) _changeHandler(index);
}

@end
