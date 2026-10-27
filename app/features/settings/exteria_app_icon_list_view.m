#import "exteria_app_icon_list_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_app_icon.h"
#import "exteria_theme.h"

#define ICON_SIDE 64.0
#define ITEM_WIDTH 84.0
#define LABEL_HEIGHT 20.0
#define PAD 14.0
#define RING 3.0
/* the scrolling area stops this far from the edges of the rounded list, so an icon that slides out is cut inside the corner and never shows beside it */
#define EDGE 8.0

@interface ExteriaAppIconItem : UIControl {
    NSString *_iconName;
}
- (id)initWithName:(NSString *)name;
@property (nonatomic, readonly) NSString *iconName;
- (void)showSelected:(BOOL)selected;
@end

@implementation ExteriaAppIconItem

@synthesize iconName = _iconName;

- (id)initWithName:(NSString *)name {
    self = [super initWithFrame:CGRectMake(0, 0, ITEM_WIDTH, PAD + ICON_SIDE + 8 + LABEL_HEIGHT)];
    if (!self) return nil;
    _iconName = [name copy];
    UIImageView *picture = [[[UIImageView alloc] initWithFrame:CGRectMake((ITEM_WIDTH - ICON_SIDE) / 2, 0, ICON_SIDE, ICON_SIDE)] autorelease];
    picture.tag = 1;
    picture.contentMode = UIViewContentModeScaleAspectFill;
    picture.layer.cornerRadius = ICON_SIDE * 0.225;
    picture.layer.masksToBounds = YES;
    /* the picture of an icon never changes, so it is clipped once and moves with the list as a texture */
    picture.layer.shouldRasterize = YES;
    picture.layer.rasterizationScale = [UIScreen mainScreen].scale;
    picture.userInteractionEnabled = NO;
    NSString *file = name ? [NSString stringWithFormat:@"%@-60@3x", name] : @"Icon-60@3x";
    picture.image = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:file ofType:@"png"]];
    [self addSubview:picture];
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(0, ICON_SIDE + 6, ITEM_WIDTH, LABEL_HEIGHT)] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.font = ExteriaFontMedium(12);
    label.tag = 2;
    label.adjustsFontSizeToFitWidth = YES;
    label.text = name ? name : @"Exteria";
    [self addSubview:label];
    self.accessibilityLabel = label.text;
    return self;
}

- (void)dealloc {
    [_iconName release];
    [super dealloc];
}

- (void)showSelected:(BOOL)selected {
    UIView *picture = [self viewWithTag:1];
    picture.layer.borderWidth = selected ? RING : 0;
    picture.layer.borderColor = ExteriaColorAccent().CGColor;
    ((UILabel *)[self viewWithTag:2]).textColor = selected ? ExteriaColorAccent() : ExteriaColorSecondary();
    self.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.7 : 1;
}

@end

@interface ExteriaAppIconListView () {
    UIScrollView *_scroll;
    NSMutableArray *_items;
    void (^_chooseHandler)(NSString *name);
}
@end

@implementation ExteriaAppIconListView

@synthesize chooseHandler = _chooseHandler;

- (BOOL)enabled { return self.userInteractionEnabled; }

- (void)setEnabled:(BOOL)enabled {
    self.userInteractionEnabled = enabled;
    self.alpha = enabled ? 1 : 0.4f;
}

+ (CGFloat)height {
    return PAD + ICON_SIDE + 8 + LABEL_HEIGHT + PAD;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    /* the list scrolls, and a clip to rounded corners over scrolling content is drawn again at every frame; the icons stop short of the corners instead */
    self.layer.cornerRadius = 22;
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsHorizontalScrollIndicator = NO;
    [self addSubview:_scroll];
    _items = [[NSMutableArray alloc] init];
    NSMutableArray *names = [NSMutableArray arrayWithObject:[NSNull null]];
    [names addObjectsFromArray:ExteriaAlternateIconNames()];
    for (id name in names) {
        ExteriaAppIconItem *item = [[[ExteriaAppIconItem alloc] initWithName:name == [NSNull null] ? nil : name] autorelease];
        [item addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:item];
        [_items addObject:item];
    }
    [self refreshSelection];
    return self;
}

- (void)dealloc {
    [_scroll release];
    [_items release];
    [_chooseHandler release];
    [super dealloc];
}

- (void)refreshSelection {
    NSString *current = ExteriaAlternateIconName();
    for (ExteriaAppIconItem *item in _items) [item showSelected:(item.iconName == nil && current == nil) || [item.iconName isEqualToString:current]];
}

- (void)tapped:(ExteriaAppIconItem *)item {
    NSString *current = ExteriaAlternateIconName();
    if ((item.iconName == nil && current == nil) || [item.iconName isEqualToString:current]) return;
    if (_chooseHandler) _chooseHandler(item.iconName);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = CGRectInset(self.bounds, EDGE, 0);
    CGFloat x = PAD - EDGE;
    for (ExteriaAppIconItem *item in _items) {
        item.frame = CGRectMake(x, PAD, ITEM_WIDTH, ICON_SIDE + 8 + LABEL_HEIGHT);
        x += ITEM_WIDTH;
    }
    _scroll.contentSize = CGSizeMake(x + PAD - EDGE, self.bounds.size.height);
}

@end
