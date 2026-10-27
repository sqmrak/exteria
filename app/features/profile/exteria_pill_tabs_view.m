#import "exteria_pill_tabs_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_theme.h"

#define TABS_HEIGHT 40.0

@interface ExteriaPillTabsView () {
    NSMutableArray *_labels;
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
    _chosen = [[UIView alloc] init];
    _chosen.backgroundColor = ExteriaColorField();
    _chosen.layer.cornerRadius = (TABS_HEIGHT - 8) / 2;
    [self addSubview:_chosen];
    _labels = [[NSMutableArray alloc] init];
    for (NSString *title in titles) {
        UILabel *label = [[[UILabel alloc] init] autorelease];
        label.backgroundColor = [UIColor clearColor];
        label.textAlignment = ExteriaTextAlignmentCenter;
        label.font = ExteriaFontMedium(15);
        label.adjustsFontSizeToFitWidth = YES;
        label.text = title;
        label.isAccessibilityElement = YES;
        label.accessibilityTraits = UIAccessibilityTraitButton;
        [self addSubview:label];
        [_labels addObject:label];
    }
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    [self addGestureRecognizer:tap];
    [self refresh];
    return self;
}

- (void)dealloc {
    [_labels release];
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
    CGFloat each = _labels.count ? width / _labels.count : width;
    for (NSUInteger i = 0; i < _labels.count; ++i) [[_labels objectAtIndex:i] setFrame:CGRectMake(each * i + 4, 0, each - 8, height)];
    _chosen.frame = CGRectMake(each * _selectedIndex + 4, 4, each - 8, height - 8);
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (!_labels.count || self.bounds.size.width <= 0) return;
    NSUInteger index = (NSUInteger)([tap locationInView:self].x / (self.bounds.size.width / _labels.count));
    if (index >= _labels.count || index == _selectedIndex) return;
    [self layoutIfNeeded];
    CGPoint from = _chosen.layer.presentationLayer ? [(CALayer *)_chosen.layer.presentationLayer position] : _chosen.center;
    self.selectedIndex = index;
    [self layoutIfNeeded];
    CGPoint target = _chosen.center;
    _chosen.center = from;
    ExteriaAnimatePosition(_chosen, target, EXTERIA_MOTION_ENTER);
    if (_changeHandler) _changeHandler(index);
}

@end
